## The Upgrade Tree screen between Rounds (Nodebuster-style): a parchment page
## with the UpgradeNodeDefs from Run.all_nodes() drawn as ink circles joined
## by ink lines (one line per `requires`), on a board you pan and zoom.
##
## Node states, readable at a glance:
## - Teaser: not visible yet, but one of its `requires` is: a dashed circle
##   with "?" and no name or cost, so the tree visibly has more to give.
## - Locked (requirement unmet): some but not all of its `requires` owned:
##   faded, with a tiny lock.
## - Can't afford: normal ink; the lacking currency in the cost line is faded
##   and underlined.
## - Affordable: a soft amber halo that breathes, and a one-time bounce when it
##   becomes affordable (also on entering the tree, for nodes that were not
##   affordable on the last visit).
## - Maxed: filled with ink, parchment text and "MAX" instead of the cost.
## Plague nodes (Lethality, Fleas, Contagion) are inked in red.
##
## Header: the wallet (IconRect icons; the shown numbers roll down after a
## buy), "N upgrades within reach", the Year and "To the Map", which breathes
## amber when nothing is within reach. A tooltip sits beside the hovered
## (0.12 s delay) or focused (instant) node: name, level, description,
## current -> next value, the cost with icons and "(need 3 more Bones)", and
## a Buy prompt. A bottom hint bar of PromptHints lists the controls.
##
## Input: click / A / Enter buys; holding keeps buying (after 0.35 s, one
## level every 0.2 s while affordable). Juice: the node punches, an ink ring
## splashes out, "-4" floats up beside the wallet and the wallet rolls down;
## newly revealed children ink in along their line (0.4 s) then fade in; a
## failed buy shakes the node and flashes the lacking counter. Drag empty
## parchment (or right / middle-drag anywhere, or the right stick) pans; the
## mouse wheel zooms around the cursor, LT / RT (joy axes 4 / 5) and - / =
## around the centre (0.55-1.6). Home / Y recentres on the focused node.
## Arrows / WASD / d-pad / stick move the focus between nearby nodes. Space /
## Start goes on to the Scroll Map (Run.open_map()); Esc / B to the title.
## Zoom and pan persist across visits (static vars).
##
## Every Run call is guarded (get_node_or_null("/root/Run")) so the scene
## still opens without the autoload; it then shows the tree read-only.
## Debug flags (after `--`): --screenshot=<path> (saves a frame after
## --screenshot-delay=<s>, default 1 s, and quits), --dev-focus=<id>,
## --dev-hover=<id> (focuses that node and shows its tooltip), --dev-zoom=<z>;
## with --dev also --dev-wallet=<p>,<b> (adds to the wallet) and
## --dev-buy=<id>,... (buys those nodes in order, saving the Run).
extends Control

enum State { HIDDEN, TEASER, LOCKED, OPEN, MAXED }

const UPGRADES_DIR := "res://data/upgrades/"
const TITLE_SCENE := "res://scenes/ui/title.tscn"
## Stats that are the plague itself: their nodes are inked in red.
const PLAGUE_STATS := ["lethality", "unlock_fleas", "unlock_contagion", "plague_burst_radius"]
## High-impact Keystone nodes get an ornate double wax-seal ring and heavier buy impact.
const KEYSTONE_IDS := ["litters", "frenzy_birth", "plague_burst", "ravenous_cleave", "fleas", "contagion", "old_blood"]
## Pixels per tree unit, node circle radius, node hit box size.
const UNIT := 86.0
const RADIUS := 38.0
const NODE_SIZE := Vector2(104, 128)
const CIRCLE := Vector2(52, 42)        # circle centre inside a node's box
const LOCKED_ALPHA := 0.4
const HEADER_HEIGHT := 72.0
const HINT_HEIGHT := 52.0
const SAFE := 24.0
const ZOOM_MIN := 0.55
const ZOOM_MAX := 1.6
const INITIAL_ZOOM_MIN := 0.9
const HOLD_DELAY := 0.35
const HOLD_STEP := 0.2
const HOVER_DELAY := 0.12
const REVEAL_LINE := 0.4
const REVEAL_FADE := 0.25
const STICK_DEADZONE := 0.22
const STICK_PAN_SPEED := 900.0
## stat key -> [label, format of one value]; "%" formats as a percentage.
const STAT_INFO := {
	"rat_speed": ["Lead Rat speed", "%.1f"],
	"bite_range": ["Bite range", "%.2f"],
	"bite_cooldown": ["Bite cooldown", "%.2f s"],
	"bite_chunk": ["Bite strength", "%.0f"],
	"bite_rate_bonus": ["Bite bonus", "%.2f"],
	"start_adults": ["Starting Adults", "%.0f"],
	"feed_time": ["Feeding time", "%.2f s"],
	"pup_maturity": ["Pup maturity", "%.1f s"],
	"extra_pups_per_feed": ["Extra Pups / Feed", "+%.0f"],
	"corpse_meals": ["Extra Corpse Meals", "+%.0f"],
	"death_pups": ["Pups on Death", "%.0f"],
	"plague_burst_radius": ["Rupture Radius", "%.1f u"],
	"lead_cleave": ["Lead Bite Targets", "%.0f"],
	"lethality": ["Lethality", "x%.2f"],
	"carry_over": ["Carry-over", "%"],
	"round_length": ["Round length", "%.0f s"],
	"unlock_hide": ["Hide", ""],
	"unlock_raid": ["Raid", ""],
	"unlock_fleas": ["Fleas", ""],
	"unlock_contagion": ["Contagion", ""],
	"hide_duration": ["Hide time", "%.0f s"],
	"raid_size": ["Raiders", "%.0f"],
	"raid_duration": ["Raid time", "%.0f s"],
	"raid_cooldown": ["Raid cooldown", "%.1f s"],
}

## Kept across visits: the view, and which nodes were affordable last time.
static var _view_zoom := 0.0
static var _view_pan := Vector2.ZERO
static var _aff_seen := {}
static var _aff_seen_valid := false


## A PromptHint whose key cap is fixed text per device (for inputs that are
## not InputMap actions: drag / wheel / sticks / triggers).
class FixedHint extends PromptHint:
	var key_text := ""
	var pad_text := ""

	static func make_fixed(p_key: String, p_pad: String, p_verb: String) -> FixedHint:
		var h := FixedHint.new()
		h.key_text = p_key
		h.pad_text = p_pad
		h.verb = p_verb
		h.outline = 4
		return h

	func refresh() -> void:
		if _cap_label != null:
			_cap_label.text = pad_text if UiKit.is_gamepad() else key_text
		if _verb_label != null:
			_verb_label.text = verb
			_verb_label.visible = verb != ""


var _run: Node
var _nodes: Array[UpgradeNodeDef] = []
var _buttons := {}          # id -> Button
var _fx := {}               # id -> {"fill": float, "splash": float}
var _state := {}            # id -> State (last refresh)
var _aff := {}              # id -> bool, affordable at the last refresh
var _reveal := {}           # id -> 0..1, the ink line growing towards a new node
var _ready_done := false
var _time := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _shake_amp := 0.0
var _shake_t := 0.0
var _dragging := false
var _pan_tween: Tween
var _font: Font             # MSDF body font: crisp at every zoom
var _blot: Texture2D
var _vignette: Texture2D
var _reach := 0
var _wallet_shown := Vector2.ZERO
var _wallet_tween: Tween

var _hold_id := ""
var _hold_time := 0.0
var _hold_next := 0.0

var _tip_id := ""
var _tip_wait := -1.0       # seconds until the pending tooltip shows; < 0 = none
var _tip_pending := ""
var _quiet_focus := false   # true while _focus_start() places the opening focus
var _from_mouse := false

var _bg: Control
var _board: Control
var _header: PanelContainer
var _pest_label: Label
var _bones_label: Label
var _reach_label: Label
var _year_label: Label
var _begin: Button
var _begin_style: StyleBoxFlat
var _tip: PanelContainer
var _tip_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_run = get_node_or_null("/root/Run")
	var f := (UiKit.body_font() as SystemFont).duplicate() as SystemFont
	f.multichannel_signed_distance_field = true
	_font = f
	_blot = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], [0.0, 0.55, 1.0])
	_vignette = _radial([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1)], [0.0, 0.75, 1.42])
	theme = UiKit.theme()
	_ensure_actions()
	_nodes = _load_nodes()
	_build()
	if _run != null:
		_run.connect("wallet_changed", _refresh)
		_run.connect("upgrades_changed", _refresh)
	_apply_debug_args()
	_refresh()
	_ready_done = true
	_restore_view()
	_greet_affordable()
	_focus_start()
	_apply_view_args()
	resized.connect(_on_resized)


func _exit_tree() -> void:
	_view_zoom = _zoom
	_view_pan = _pan


func _on_resized() -> void:
	_apply_view()
	_bg.queue_redraw()


## Runtime-only actions for the hint bar (never saved to project.godot).
func _ensure_actions() -> void:
	var defs := {"tree_to_map": [KEY_SPACE, JOY_BUTTON_START], "tree_recenter": [KEY_HOME, JOY_BUTTON_Y]}
	for action: String in defs:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var k := InputEventKey.new()
		k.keycode = defs[action][0]
		InputMap.action_add_event(action, k)
		var j := InputEventJoypadButton.new()
		j.button_index = defs[action][1]
		InputMap.action_add_event(action, j)


# ---------------------------------------------------------------------- Run access
func _load_nodes() -> Array[UpgradeNodeDef]:
	if _run != null:
		return _run.call("all_nodes")
	var out: Array[UpgradeNodeDef] = []
	if DirAccess.dir_exists_absolute(UPGRADES_DIR):
		for file in DirAccess.get_files_at(UPGRADES_DIR):
			var n := load(UPGRADES_DIR + file.trim_suffix(".remap")) as UpgradeNodeDef
			if n != null:
				out.append(n)
	return out


func _level(n: UpgradeNodeDef) -> int:
	return int(_run.call("level", n.id)) if _run != null else 0


func _cost(n: UpgradeNodeDef) -> Vector2i:
	if _run != null:
		return _run.call("cost_of", n)
	return Vector2i(n.cost_pestilence, n.cost_bones)


func _is_visible(n: UpgradeNodeDef) -> bool:
	return bool(_run.call("is_visible", n)) if _run != null else n.requires.is_empty()


func _can_buy(n: UpgradeNodeDef) -> bool:
	return _run != null and bool(_run.call("can_buy", n))


func _wallet() -> Vector2i:
	if _run == null:
		return Vector2i.ZERO
	return Vector2i(int(_run.get("pestilence")), int(_run.get("bones")))


func _stat(key: String) -> float:
	if _run != null:
		return float(_run.call("stat", key))
	return 0.0


func _find(id: String) -> UpgradeNodeDef:
	for n in _nodes:
		if n.id == id:
			return n
	return null


## The node's state from the Run (see the header comment).
func _compute_state(n: UpgradeNodeDef) -> State:
	if _is_visible(n):
		return State.MAXED if _level(n) >= n.max_level else State.OPEN
	var owned_any := false
	var visible_any := false
	for id in n.requires:
		var r := _find(id)
		if r == null:
			continue
		if _level(r) >= 1:
			owned_any = true
		if _is_visible(r):
			visible_any = true
	if owned_any:
		return State.LOCKED
	if visible_any:
		return State.TEASER
	return State.HIDDEN


## The state to draw: a node whose reveal line is still inking stays a teaser.
func _draw_state(n: UpgradeNodeDef) -> State:
	var st: State = _state.get(n.id, State.HIDDEN)
	if _reveal.has(n.id) and (st == State.OPEN or st == State.MAXED):
		return State.TEASER
	return st


func _shown(st: State) -> bool:
	return st == State.OPEN or st == State.MAXED


# ---------------------------------------------------------------------- actions
## Buys one level of `n` with all the juice; `from_hold` buys stay quiet when
## they fail (the hold just stops).
func _try_buy(n: UpgradeNodeDef, from_hold := false) -> bool:
	var st: State = _state.get(n.id, State.HIDDEN)
	if st == State.OPEN and _can_buy(n):
		var c := _cost(n)
		if bool(_run.call("buy", n)):
			_play_buy(n, c)
			_update_tip()
			return true
	if not from_hold:
		_play_refuse(n)
	return false


func _start_hold(n: UpgradeNodeDef) -> void:
	_try_buy(n)
	_hold_id = n.id
	_hold_time = 0.0
	_hold_next = HOLD_DELAY


func _stop_hold() -> void:
	_hold_id = ""


func _process_hold(delta: float) -> void:
	if _hold_id.is_empty():
		return
	var n := _find(_hold_id)
	if n == null:
		_stop_hold()
		return
	_hold_time += delta
	while _hold_time >= _hold_next and not _hold_id.is_empty():
		if _can_buy(n):
			_try_buy(n, true)
			_hold_next += HOLD_STEP
		else:
			_stop_hold()


## "To the Map": the Scroll Map (Run.open_map), or straight to the next Round
## with an older Run that has no map.
func _begin_round() -> void:
	if _run == null:
		push_warning("UpgradeTree: no Run autoload, can't leave the Tree")
	elif _run.has_method("open_map"):
		_run.call("open_map")
	else:
		_run.call("start_round")


func _to_title() -> void:
	var t := get_node_or_null("/root/Transition")
	if t != null and t.has_method("go"):
		t.call("go", TITLE_SCENE)
	elif ResourceLoader.exists(TITLE_SCENE):
		get_tree().change_scene_to_file(TITLE_SCENE)


func _busy() -> bool:
	var t := get_node_or_null("/root/Transition")
	return t != null and t.has_method("is_busy") and bool(t.call("is_busy"))


func _focused_node() -> UpgradeNodeDef:
	var f := get_viewport().gui_get_focus_owner()
	if f != null and f.has_meta("node_id"):
		return _find(str(f.get_meta("node_id")))
	return null


func _input(event: InputEvent) -> void:
	if _busy():
		return
	if event.is_action_pressed("tree_to_map", false, true):
		get_viewport().set_input_as_handled()
		_begin_round()
		return
	if event.is_action_pressed("tree_recenter", false, true):
		get_viewport().set_input_as_handled()
		_recenter()
		return
	if event.is_action_pressed("ui_cancel", false, true):
		get_viewport().set_input_as_handled()
		_to_title()
		return
	# Accept on a focused node: buy now, keep buying while held.
	var fn := _focused_node()
	if fn != null and event.is_action("ui_accept", true) and not (event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_start_hold(fn)
		elif not event.is_pressed():
			_stop_hold()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if mb.position.y > HEADER_HEIGHT:
				var k := 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
				_zoom_at(_zoom * pow(k, maxf(1.0, mb.factor)), mb.position)
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_stop_hold()
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_pan_by((event as InputEventMouseMotion).relative)
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			_zoom_at(_zoom * 1.15, _area().get_center())
		elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom_at(_zoom / 1.15, _area().get_center())


func _unhandled_input(event: InputEvent) -> void:
	if _busy():
		return
	# WASD (move_* actions) move the focus like the arrows do.
	var sides := {"move_left": SIDE_LEFT, "move_right": SIDE_RIGHT, "move_up": SIDE_TOP, "move_down": SIDE_BOTTOM}
	for action: String in sides:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			var from := get_viewport().gui_get_focus_owner()
			if from == null:
				_focus_start()
			else:
				var to := from.find_valid_focus_neighbor(sides[action])
				if to != null:
					to.grab_focus()
			get_viewport().set_input_as_handled()
			return


## Left-drag on empty parchment pans.
func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan_by((event as InputEventMouseMotion).relative)


## Mouse on a node: press buys (and holds), release stops.
func _on_node_input(event: InputEvent, n: UpgradeNodeDef) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		(_buttons[n.id] as Button).accept_event()
		if mb.pressed:
			_from_mouse = true
			(_buttons[n.id] as Button).grab_focus()
			_from_mouse = false
			_start_hold(n)
		else:
			_stop_hold()


# ---------------------------------------------------------------------- view
func _area() -> Rect2:
	return Rect2(0, HEADER_HEIGHT, size.x, maxf(1.0, size.y - HEADER_HEIGHT - HINT_HEIGHT))


func _apply_view() -> void:
	_pan = _clamp_pan(_pan)
	_board.scale = Vector2(_zoom, _zoom)
	var shake_off := Vector2.ZERO
	if _shake_amp > 0.05:
		shake_off = Vector2(sin(_shake_t * 62.0), cos(_shake_t * 78.0)) * _shake_amp
	_board.position = _area().get_center() + _pan + shake_off
	_view_zoom = _zoom
	_view_pan = _pan


func _set_pan(p: Vector2) -> void:
	_pan = p
	_apply_view()


func _pan_by(delta: Vector2) -> void:
	if _pan_tween != null:
		_pan_tween.kill()
	_set_pan(_pan + delta)


## Zooms to `z` keeping the board point under the screen point `at` still.
func _zoom_at(z: float, at: Vector2) -> void:
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(z, _zoom):
		return
	if _pan_tween != null:
		_pan_tween.kill()
	var world := (at - _board.position) / _zoom
	_zoom = z
	_pan = at - world * _zoom - _area().get_center()
	_apply_view()


## Board-space box of every drawn node.
func _tree_box() -> Rect2:
	var box := Rect2()
	var first := true
	for n in _nodes:
		if _state.get(n.id, State.HIDDEN) == State.HIDDEN:
			continue
		var r := Rect2((_buttons[n.id] as Button).get_meta("base_pos"), NODE_SIZE)
		box = r if first else box.merge(r)
		first = false
	return box


## Keeps at least part of the tree on screen.
func _clamp_pan(p: Vector2) -> Vector2:
	var box := _tree_box()
	if not box.has_area():
		return p
	var area := _area()
	var keep := 140.0
	var origin := area.get_center() + p
	var lo := origin + box.position * _zoom
	var hi := origin + box.end * _zoom
	if hi.x < area.position.x + keep:
		p.x += area.position.x + keep - hi.x
	if lo.x > area.end.x - keep:
		p.x -= lo.x - (area.end.x - keep)
	if hi.y < area.position.y + keep:
		p.y += area.position.y + keep - hi.y
	if lo.y > area.end.y - keep:
		p.y -= lo.y - (area.end.y - keep)
	return p


## Restores the last visit's zoom and pan; on the first visit fits the tree,
## but never below INITIAL_ZOOM_MIN (node text stays readable; pan for more).
func _restore_view() -> void:
	if _view_zoom > 0.0:
		_zoom = _view_zoom
		_pan = _view_pan
	else:
		var box := _tree_box()
		var area := _area().grow(-40.0)
		_zoom = 1.0
		if box.has_area():
			_zoom = clampf(minf(area.size.x / box.size.x, area.size.y / box.size.y), INITIAL_ZOOM_MIN, 1.0)
			_pan = -box.get_center() * _zoom
			var full := _area()
			if box.size.y * _zoom > full.size.y - 16.0:
				# Too tall: show the top (the newest branches) rather than cut it.
				_pan.y = full.position.y + 12.0 - full.get_center().y - box.position.y * _zoom
	_apply_view()


func _tween_pan(target: Vector2) -> void:
	if _pan_tween != null:
		_pan_tween.kill()
	if UiKit.reduce_motion():
		_set_pan(target)
		return
	_pan_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_method(_set_pan, _pan, target, 0.3)


## Home / Y: the focused node (else the tree) to the centre.
func _recenter() -> void:
	var n := _focused_node()
	if n != null:
		var b: Button = _buttons[n.id]
		var p: Vector2 = (b.get_meta("base_pos") as Vector2) + CIRCLE
		_tween_pan(-p * _zoom)
	else:
		var box := _tree_box()
		_tween_pan(-box.get_center() * _zoom)


## Keeps a node on screen when the focus moves with keys / pad.
func _scroll_into_view(n: UpgradeNodeDef) -> void:
	var b: Button = _buttons[n.id]
	var rect := b.get_global_rect()
	var view := _area().grow(-SAFE)
	if view.size.x <= 0.0 or view.size.y <= 0.0 or view.encloses(rect):
		return
	var shift := Vector2.ZERO
	if rect.position.x < view.position.x:
		shift.x = view.position.x - rect.position.x
	elif rect.end.x > view.end.x:
		shift.x = view.end.x - rect.end.x
	if rect.position.y < view.position.y:
		shift.y = view.position.y - rect.position.y
	elif rect.end.y > view.end.y:
		shift.y = view.end.y - rect.end.y
	_tween_pan(_pan + shift)


func _on_node_focused(n: UpgradeNodeDef) -> void:
	var b: Button = _buttons[n.id]
	if not b.visible:
		return
	if _hold_id != n.id:
		_stop_hold()
	if _from_mouse:
		_queue_tip(n.id, HOVER_DELAY)
	elif _quiet_focus and not UiKit.is_gamepad():
		# The opening focus: a mouse player hasn't pointed at anything yet,
		# so don't cover the tree with a tooltip they didn't ask for.
		pass
	else:
		_scroll_into_view(n)
		_queue_tip(n.id, 0.0)


func _on_node_unfocused(n: UpgradeNodeDef) -> void:
	if _hold_id == n.id:
		_stop_hold()
	if _tip_id == n.id or _tip_pending == n.id:
		_hide_tip()


## Hovering a node focuses it, so mouse and pad share one selection.
func _on_hover(n: UpgradeNodeDef) -> void:
	_from_mouse = true
	var b: Button = _buttons[n.id]
	if b.has_focus():
		_queue_tip(n.id, HOVER_DELAY)
	else:
		b.grab_focus()
	_from_mouse = false


func _on_unhover(n: UpgradeNodeDef) -> void:
	if _hold_id == n.id and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop_hold()
	if _tip_id == n.id or _tip_pending == n.id:
		_hide_tip()


func _focus_start() -> void:
	var best: UpgradeNodeDef = null
	for n in _nodes:
		if _state.get(n.id) == State.OPEN and _can_buy(n) and (best == null or n.tree_position.length() < best.tree_position.length()):
			best = n
	if best == null:
		for n in _nodes:
			if _state.get(n.id) in [State.OPEN, State.MAXED] and (best == null or n.tree_position.length() < best.tree_position.length()):
				best = n
	_quiet_focus = true
	if best != null and _aff.values().has(true):
		(_buttons[best.id] as Button).grab_focus()
	else:
		_begin.grab_focus()
	_quiet_focus = false


func _process(delta: float) -> void:
	_time += delta
	if _shake_amp > 0.01:
		_shake_t += delta
		_shake_amp = maxf(0.0, _shake_amp * exp(-16.0 * delta) - delta * 4.0)
		_apply_view()
	_process_hold(delta)
	# Reveal lines ink in, then the node fades in.
	for id: String in _reveal.keys():
		_reveal[id] = float(_reveal[id]) + delta / REVEAL_LINE
		if float(_reveal[id]) >= 1.0:
			_reveal.erase(id)
			var b: Button = _buttons[id]
			b.modulate.a = 0.0
			create_tween().tween_property(b, "modulate:a", 1.0, REVEAL_FADE)
	# Right stick pans, triggers zoom about the centre.
	if not _busy():
		var stick := Vector2(_axis(JOY_AXIS_RIGHT_X), _axis(JOY_AXIS_RIGHT_Y))
		if stick != Vector2.ZERO:
			_pan_by(-stick * STICK_PAN_SPEED * delta)
		var trig := _axis(JOY_AXIS_TRIGGER_RIGHT) - _axis(JOY_AXIS_TRIGGER_LEFT)
		if trig != 0.0:
			_zoom_at(_zoom * pow(2.2, trig * delta), _area().get_center())
	# Tooltip: delayed show, then follow the node.
	if _tip_wait >= 0.0:
		_tip_wait -= delta
		if _tip_wait < 0.0:
			_show_tip(_tip_pending)
	if _tip.visible:
		_place_tip()
	# The wallet labels show the rolling values.
	_pest_label.text = str(roundi(_wallet_shown.x))
	_bones_label.text = str(roundi(_wallet_shown.y))
	# Nothing within reach: "To the Map" breathes amber.
	if _reach == 0 and _run != null:
		var k := 0.5 + 0.5 * sin(_time * 2.6)
		_begin_style.border_color = UiKit.AMBER.darkened(0.45).lerp(UiKit.AMBER, k)
		_begin_style.bg_color = UiKit.PARCHMENT_LIGHT.lerp(UiKit.AMBER.lightened(0.5), 0.25 + 0.5 * k)
		_begin.add_theme_stylebox_override("normal", _begin_style)
	else:
		_begin.remove_theme_stylebox_override("normal")
	_redraw_nodes()
	_board.queue_redraw()


func _axis(a: JoyAxis) -> float:
	var v := 0.0
	for d in Input.get_connected_joypads():
		var x := Input.get_joy_axis(d, a)
		if absf(x) > absf(v):
			v = x
	if absf(v) < STICK_DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)


# ---------------------------------------------------------------------- feedback
## Heavy wax-seal stamp slam: anticipation dip, punch bounce, board micro-shake,
## radial ink/crimson splatter, and bold stat-upgrade pop above the node.
func _play_buy(n: UpgradeNodeDef, cost: Vector2i) -> void:
	var fx: Dictionary = _fx[n.id]
	var is_key := KEYSTONE_IDS.has(n.id)
	var maxed := _level(n) >= n.max_level
	var heavy := is_key or maxed
	var t := create_tween()
	t.tween_method(_set_fx.bind(n.id, "fill"), 0.0, 1.0, 0.12).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(_set_fx.bind(n.id, "splash"), 0.0, 1.0, 0.55 if heavy else 0.42).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_fx.bind(n.id, "fill"), 1.0, 0.0, 0.28)
	t.tween_callback(func() -> void: fx["splash"] = 0.0)
	_stamp_pop(n.id, 0.30 if heavy else 0.20)
	if not UiKit.reduce_motion():
		_shake_amp = maxf(_shake_amp, 12.0 if heavy else 5.5)
	_float_node_pop(n, "KEYSTONE!" if (is_key and _level(n) == 1) else ("MAXED!" if maxed else n.title + " ↑"))
	if cost.x > 0:
		_float_spent(_pest_label, "−%d" % cost.x)
	if cost.y > 0:
		_float_spent(_bones_label, "−%d" % cost.y)


func _stamp_pop(id: String, amount: float) -> void:
	if UiKit.reduce_motion():
		return
	var b: Button = _buttons[id]
	b.pivot_offset = CIRCLE
	var pop := create_tween()
	pop.tween_property(b, "scale", Vector2.ONE * 0.86, 0.04).set_ease(Tween.EASE_IN)
	pop.tween_property(b, "scale", Vector2.ONE * (1.0 + amount), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(b, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _float_node_pop(n: UpgradeNodeDef, text: String) -> void:
	var b: Button = _buttons[n.id]
	var col := UiKit.RED if (_is_plague(n) or KEYSTONE_IDS.has(n.id)) else UiKit.INK
	var l := UiKit.label(text, UiKit.SIZE_LARGE, col, 5, KEYSTONE_IDS.has(n.id))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var c := b.get_global_transform() * CIRCLE
	var tw := l.get_minimum_size().x
	l.position = Vector2(c.x - tw * 0.5, c.y - RADIUS * _zoom - 26.0)
	var tw_anim := create_tween().set_parallel()
	if not UiKit.reduce_motion():
		tw_anim.tween_property(l, "position:y", l.position.y - 44.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_anim.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw_anim.chain().tween_callback(l.queue_free)


## A short sideways shake, and the lacking wallet counters flash.
func _play_refuse(n: UpgradeNodeDef) -> void:
	var b: Button = _buttons[n.id]
	var base: Vector2 = b.get_meta("base_pos")
	if not UiKit.reduce_motion():
		var t := create_tween()
		t.tween_method(func(v: float) -> void:
			b.position = base + Vector2(sin(v * TAU * 3.0) * 7.0 * (1.0 - v), 0), 0.0, 1.0, 0.32)
		t.tween_callback(func() -> void: b.position = base)
	if _state.get(n.id) != State.OPEN:
		return
	var c := _cost(n)
	var w := _wallet()
	if c.x > w.x:
		_flash(_pest_label)
	if c.y > w.y:
		_flash(_bones_label)


func _pop(id: String, amount: float) -> void:
	if UiKit.reduce_motion():
		return
	var b: Button = _buttons[id]
	b.pivot_offset = CIRCLE
	var pop := create_tween()
	pop.tween_property(b, "scale", Vector2.ONE * (1.0 + amount), 0.07)
	pop.tween_property(b, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash(l: Label) -> void:
	var t := create_tween()
	for i in 2:
		t.tween_property(l, "modulate:a", 0.15, 0.08)
		t.tween_property(l, "modulate:a", 1.0, 0.1)
	UiKit.punch(l, 0.25, 0.25)


## "−4" rising (and fading) from beside a wallet counter.
func _float_spent(beside: Label, text: String) -> void:
	var l := UiKit.label(text, UiKit.SIZE_LARGE, UiKit.SEPIA, 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var r := beside.get_global_rect()
	l.position = Vector2(r.end.x + 8.0, r.position.y)
	var t := create_tween().set_parallel()
	if not UiKit.reduce_motion():
		t.tween_property(l, "position:y", l.position.y + 30.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.15)
	t.chain().tween_callback(l.queue_free)


func _set_fx(v: float, id: String, key: String) -> void:
	var fx: Dictionary = _fx[id]
	fx[key] = v


## Nodes that became affordable since the last visit bounce once on entering.
func _greet_affordable() -> void:
	var k := 0
	for n in _nodes:
		if bool(_aff.get(n.id, false)) and (not _aff_seen_valid or not _aff_seen.has(n.id)):
			var id := n.id
			get_tree().create_timer(0.3 + 0.06 * k).timeout.connect(func() -> void:
				if is_inside_tree():
					_pop(id, 0.18))
			k += 1
	_remember_affordable()


func _remember_affordable() -> void:
	_aff_seen = {}
	for id: String in _aff:
		if bool(_aff[id]):
			_aff_seen[id] = true
	_aff_seen_valid = true


# ---------------------------------------------------------------------- refresh
func _refresh() -> void:
	var w := _wallet()
	if not _ready_done or UiKit.reduce_motion():
		_wallet_shown = Vector2(w)
	elif Vector2(w) != _wallet_shown:
		if _wallet_tween != null:
			_wallet_tween.kill()
		_wallet_tween = create_tween()
		_wallet_tween.tween_property(self, "_wallet_shown", Vector2(w), 0.35).set_ease(Tween.EASE_OUT)
	var year: Variant = _run.get("year") if _run != null else null
	_year_label.text = "Year of Our Lord %s" % (str(int(year)) if year != null else "—")
	_reach = 0
	for n in _nodes:
		var b: Button = _buttons[n.id]
		var prev: State = _state.get(n.id, State.HIDDEN)
		var st := _compute_state(n)
		_state[n.id] = st
		var aff := st == State.OPEN and _can_buy(n)
		if aff:
			_reach += 1
		if _ready_done:
			if _shown(st) and not _shown(prev) and prev != State.HIDDEN:
				_reveal[n.id] = 0.0
			elif prev == State.HIDDEN and st != State.HIDDEN:
				b.modulate.a = 0.0
				var t := create_tween()
				t.tween_interval(REVEAL_LINE)
				t.tween_property(b, "modulate:a", 1.0, REVEAL_FADE)
			if aff and not bool(_aff.get(n.id, false)):
				_pop(n.id, 0.18)
		_aff[n.id] = aff
		b.visible = st != State.HIDDEN
	if _ready_done:
		_remember_affordable()
	_reach_label.text = ("%d upgrade within reach" if _reach == 1 else "%d upgrades within reach") % _reach \
		if _run != null else "—"
	_update_tip()


# ---------------------------------------------------------------------- tooltip
func _queue_tip(id: String, delay: float) -> void:
	if delay <= 0.0:
		_tip_wait = -1.0
		_show_tip(id)
	else:
		if _tip_id != id:
			_tip.visible = false
			_tip_id = ""
		_tip_pending = id
		_tip_wait = delay


func _hide_tip() -> void:
	_tip.visible = false
	_tip_id = ""
	_tip_pending = ""
	_tip_wait = -1.0


func _show_tip(id: String) -> void:
	var n := _find(id)
	if n == null or _state.get(id, State.HIDDEN) == State.HIDDEN:
		_hide_tip()
		return
	_tip_id = id
	_tip_pending = ""
	_fill_tip(n)
	_tip.visible = true
	_place_tip()


func _update_tip() -> void:
	if _tip != null and _tip.visible and not _tip_id.is_empty():
		_fill_tip(_find(_tip_id))
		_place_tip()


func _fill_tip(n: UpgradeNodeDef) -> void:
	for c in _tip_box.get_children():
		_tip_box.remove_child(c)
		c.queue_free()
	if n == null:
		return
	var st := _draw_state(n)
	var lv := _level(n)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_tip_box.add_child(head)
	if st == State.TEASER:
		head.add_child(UiKit.label("Not yet known", UiKit.SIZE_LARGE, UiKit.INK, 0, true))
		var names: Array[String] = []
		for rid in n.requires:
			var r := _find(rid)
			if r != null and _level(r) < 1:
				names.append(r.title)
		var l := UiKit.label("Buy %s to reveal." % " and ".join(names), UiKit.SIZE_BODY - 2, UiKit.SEPIA)
		_tip_box.add_child(l)
		return
	var name_l := UiKit.label(n.title, UiKit.SIZE_LARGE, UiKit.RED_DARK if _is_plague(n) else UiKit.INK, 0, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var lvl := UiKit.label("Level %d / %d" % [lv, n.max_level], UiKit.SIZE_SMALL, UiKit.SEPIA)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lvl)
	var desc := UiKit.label(n.description, UiKit.SIZE_BODY - 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 300
	_tip_box.add_child(desc)
	var eff := _effect_text(n)
	if not eff.is_empty():
		_tip_box.add_child(UiKit.label(eff, UiKit.SIZE_BODY - 2, UiKit.SEPIA))
	if st == State.LOCKED:
		var names: Array[String] = []
		for rid in n.requires:
			var r := _find(rid)
			if r != null and _level(r) < 1:
				names.append(r.title)
		_tip_box.add_child(UiKit.label("Locked: buy %s first." % " and ".join(names), UiKit.SIZE_SMALL, UiKit.SEPIA))
		return
	var rule := ColorRect.new()
	rule.color = Color(UiKit.INK, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	_tip_box.add_child(rule)
	if st == State.MAXED:
		_tip_box.add_child(UiKit.label("MAX: fully learned.", UiKit.SIZE_BODY - 2))
		return
	var c := _cost(n)
	var w := _wallet()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_tip_box.add_child(row)
	row.add_child(UiKit.label("Cost", UiKit.SIZE_BODY - 2, UiKit.SEPIA))
	var lack: Array[String] = []
	for k in 2:
		var amount := c.x if k == 0 else c.y
		if amount <= 0:
			continue
		var have := w.x if k == 0 else w.y
		var short := _run != null and amount > have
		var num := UiKit.label(str(amount), UiKit.SIZE_LARGE, UiKit.INK)
		num.modulate.a = 0.45 if short else 1.0
		row.add_child(num)
		var icon := IconRect.make("pestilence" if k == 0 else "bones", 20)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.modulate.a = 0.45 if short else 1.0
		row.add_child(icon)
		if short:
			lack.append("%d more %s" % [amount - have, "Pestilence" if k == 0 else "Bones"])
	if c == Vector2i.ZERO:
		row.add_child(UiKit.label("free", UiKit.SIZE_BODY - 2))
	if not lack.is_empty():
		var need := UiKit.label("(need %s)" % " and ".join(lack), UiKit.SIZE_SMALL, UiKit.SEPIA)
		need.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(need)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 10)
	_tip_box.add_child(hint)
	hint.add_child(PromptHint.make("ui_accept", "Buy"))
	if n.max_level - lv > 1:
		hint.add_child(UiKit.label("hold to buy more", UiKit.SIZE_SMALL, UiKit.SEPIA))


## Beside the node's circle, on the side facing away from the tree's centre
## (so it covers as little of the tree as possible), kept on screen.
func _place_tip() -> void:
	if _tip_id.is_empty() or not _buttons.has(_tip_id):
		return
	var b: Button = _buttons[_tip_id]
	_tip.reset_size()
	var ts := _tip.size
	var c := b.get_global_transform() * CIRCLE
	var r := (RADIUS + 14.0) * _zoom
	var centre := _board.get_global_transform() * _tree_box().get_center()
	var right := c.x >= centre.x - 4.0
	var x := c.x + r if right else c.x - r - ts.x
	if right and x + ts.x > size.x - SAFE:
		x = c.x - r - ts.x
	elif not right and x < SAFE:
		x = c.x + r
	x = clampf(x, SAFE, maxf(SAFE, size.x - SAFE - ts.x))
	var y := clampf(c.y - ts.y * 0.5, HEADER_HEIGHT + 8.0, maxf(HEADER_HEIGHT + 8.0, size.y - HINT_HEIGHT - 8.0 - ts.y))
	_tip.position = Vector2(x, y).round()


## "Bite cooldown 1.20 s → 1.10 s" for every stat the next level changes.
func _effect_text(n: UpgradeNodeDef) -> String:
	var lines: Array[String] = []
	var lv := _level(n)
	var maxed := lv >= n.max_level
	if n.level_stat != "" and not n.level_values.is_empty():
		var now := _stat(n.level_stat) if _run != null else 0.0
		if maxed:
			lines.append("%s %s" % [_stat_label(n.level_stat), _fmt(n.level_stat, now)])
		else:
			var nxt := n.level_values[mini(lv, n.level_values.size() - 1)]
			lines.append("%s %s  →  %s" % [_stat_label(n.level_stat), _fmt(n.level_stat, now), _fmt(n.level_stat, nxt)])
	for key: String in n.effects:
		var delta := float(n.effects[key])
		if key.begins_with("unlock_"):
			lines.append(("Unlocked: %s" if lv >= 1 else "Unlocks %s") % _stat_label(key))
			continue
		var now := _stat(key)
		if _run == null:
			lines.append("%s %+.2f per level" % [_stat_label(key), delta])
		elif maxed:
			lines.append("%s %s" % [_stat_label(key), _fmt(key, now)])
		else:
			lines.append("%s %s  →  %s" % [_stat_label(key), _fmt(key, now), _fmt(key, now + delta)])
	return "\n".join(lines)


func _stat_label(key: String) -> String:
	return str(STAT_INFO[key][0]) if STAT_INFO.has(key) else key.capitalize()


func _fmt(key: String, v: float) -> String:
	var f := str(STAT_INFO[key][1]) if STAT_INFO.has(key) else "%.2f"
	if f == "%":
		return "%d%%" % roundi(v * 100.0)
	return f % v


static func _is_plague(n: UpgradeNodeDef) -> bool:
	for key: String in PLAGUE_STATS:
		if n.effects.has(key) or n.level_stat == key:
			return true
	return false


# ---------------------------------------------------------------------- drawing
func _draw_bg() -> void:
	var s := _bg.size
	_bg.draw_rect(Rect2(Vector2.ZERO, s), UiKit.PARCHMENT)
	# Stains and foxing, always in the same places.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1347
	for i in 34:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		var r := rng.randf_range(40.0, 260.0)
		var c := UiKit.SEPIA
		c.a = rng.randf_range(0.05, 0.14)
		_bg.draw_texture_rect(_blot, Rect2(p - Vector2(r, r * 0.8), Vector2(r, r * 0.8) * 2.0), false, c)
	for i in 60:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		var c := UiKit.SEPIA
		c.a = rng.randf_range(0.05, 0.14)
		_bg.draw_circle(p, rng.randf_range(0.8, 2.6), c)
	_bg.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, s), false, Color(UiKit.SEPIA, 0.55))
	# Double ink rule round the page.
	_bg.draw_rect(Rect2(Vector2(14, 14), s - Vector2(28, 28)), Color(UiKit.INK, 0.8), false, 2.0)
	_bg.draw_rect(Rect2(Vector2(20, 20), s - Vector2(40, 40)), Color(UiKit.INK, 0.5), false, 1.0)


## Requirement lines, edge to edge: solid to bought / visible nodes (inking
## in while a node is revealed), dashed to teasers, faint to locked ones.
func _draw_board() -> void:
	for n in _nodes:
		var st: State = _state.get(n.id, State.HIDDEN)
		if st == State.HIDDEN:
			continue
		for req_id in n.requires:
			var r := _find(req_id)
			if r == null or not _shown(_draw_state(r)):
				continue
			var a := r.tree_position * UNIT
			var b := n.tree_position * UNIT
			var from := _line_end(a, b)
			var to := _line_end(b, a)
			if from.distance_to(b) <= to.distance_to(b):
				continue
			var seed_value := hash(n.id + req_id)
			var owned := _level(n) > 0
			if st == State.TEASER or (st == State.LOCKED and _level(r) < 1):
				_dashed_line(_board, from, to, Color(UiKit.INK, 0.4), 1.4)
			elif st == State.LOCKED:
				_wobbly_line(_board, from, to, Color(UiKit.INK, 0.3), 1.4, seed_value)
			elif _reveal.has(n.id):
				_dashed_line(_board, from, to, Color(UiKit.INK, 0.4), 1.4)
				var t := ease(clampf(float(_reveal[n.id]), 0.0, 1.0), 0.6)
				_wobbly_line(_board, from, from.lerp(to, t), UiKit.INK, 2.4, seed_value)
				_board.draw_circle(from.lerp(to, t), 3.2, UiKit.INK)
			else:
				_wobbly_line(_board, from, to, Color(UiKit.INK, 0.85 if owned else 0.6), 2.2 if owned else 1.7, seed_value)


## Where a line from node centre `p` towards `q` leaves that node's circle
## and its label (pips and cost below the circle), so it never crosses them.
func _line_end(p: Vector2, q: Vector2) -> Vector2:
	var dir := (q - p).normalized()
	var label := Rect2(p.x - 36.0, p.y + RADIUS + 4.0, 72.0, 44.0)
	var d := RADIUS + 6.0
	while d < p.distance_to(q) and label.has_point(p + dir * d):
		d += 2.0
	return p + dir * d


func _wobbly_line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, width: float, seed_value: int) -> void:
	var pts := PackedVector2Array()
	var steps := maxi(4, int(a.distance_to(b) / 12.0))
	var normal := (b - a).normalized().orthogonal()
	var ph := float(absi(seed_value) % 1000) * 0.01
	for i in steps + 1:
		var t := float(i) / float(steps)
		var off := sin(t * 7.0 + ph) * 1.3 + sin(t * 17.0 + ph * 2.0) * 0.6
		pts.append(a.lerp(b, t) + normal * off * sin(t * PI))
	ci.draw_polyline(pts, c, width, true)


func _dashed_line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, width: float) -> void:
	var dist := a.distance_to(b)
	var t := 0.0
	while t < dist:
		ci.draw_line(a.lerp(b, t / dist), a.lerp(b, minf(t + 6.0, dist) / dist), c, width, true)
		t += 11.0


func _wobbly_circle(ci: CanvasItem, centre: Vector2, r: float, c: Color, width: float, ph: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := float(i) / 48.0 * TAU
		var rr := r + sin(a * 2.0 + ph) * 0.45 + sin(a * 5.0 + ph * 1.7) * 0.2
		pts.append(centre + Vector2(cos(a), sin(a)) * rr)
	ci.draw_polyline(pts, c, width, true)


func _dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, dashes := 18, width := 1.6) -> void:
	for i in dashes:
		var a0 := float(i) / float(dashes) * TAU
		ci.draw_arc(c, r, a0, a0 + TAU / float(dashes) * 0.55, 4, col, width, true)


func _text_c(ci: CanvasItem, at: Vector2, s: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(_font, Vector2(at.x - w * 0.5, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_node(b: Button, n: UpgradeNodeDef) -> void:
	var st := _draw_state(n)
	var c := CIRCLE
	var ph := float(absi(hash(n.id)) % 100) * 0.1
	var focused := b.has_focus()
	if st == State.TEASER:
		_draw_teaser(b, c, focused)
		return
	var fx: Dictionary = _fx[n.id]
	var lv := _level(n)
	var maxed := st == State.MAXED
	var locked := st == State.LOCKED
	var aff := st == State.OPEN and bool(_aff.get(n.id, false))
	var ink := UiKit.RED if _is_plague(n) else UiKit.INK
	var alpha := LOCKED_ALPHA if locked else 1.0
	var line := Color(ink, alpha)
	# Affordable: a soft amber halo that breathes.
	if aff:
		var k := 0.5 + 0.5 * sin(_time * 2.4 + ph)
		b.draw_circle(c, RADIUS + 12.0 + 2.0 * k, Color(UiKit.AMBER, 0.10 + 0.08 * k))
		b.draw_circle(c, RADIUS + 7.0 + 1.5 * k, Color(UiKit.AMBER, 0.16 + 0.08 * k))
		b.draw_arc(c, RADIUS + 5.0 + 1.5 * k, 0.0, TAU, 48, Color(UiKit.AMBER.darkened(0.1), 0.55 + 0.3 * k), 2.5, true)
	# Splash: bold ink/crimson wax-seal burst and radial splatter droplets.
	var splash: float = fx["splash"]
	var is_key := KEYSTONE_IDS.has(n.id)
	if splash > 0.0:
		var drops := 16 if is_key else 12
		for i in drops:
			var ang := float(i) / float(drops) * TAU + ph
			var dist := RADIUS + 8.0 + splash * ((32.0 if is_key else 22.0) + float((i * 7) % 5) * 6.0)
			var dcol := UiKit.AMBER if (is_key and i % 3 == 0) else ink
			b.draw_circle(c + Vector2(cos(ang), sin(ang)) * dist, (5.5 if is_key else 4.2) * (1.0 - splash) + 1.2, Color(dcol, 1.0 - splash))
		_wobbly_circle(b, c, RADIUS + 5.0 + splash * (42.0 if is_key else 30.0), Color(ink, (1.0 - splash) * 0.9), 4.0 * (1.0 - splash) + 1.0, ph)
		if is_key:
			_wobbly_circle(b, c, RADIUS + 12.0 + splash * 56.0, Color(UiKit.AMBER, (1.0 - splash) * 0.8), 2.5 * (1.0 - splash) + 0.5, ph + 1.0)
	# Body (+ ornate outer seal ring for Keystones).
	if is_key:
		var k_col := UiKit.RED if _is_plague(n) else UiKit.AMBER.darkened(0.15)
		_wobbly_circle(b, c, RADIUS + 5.5, Color(k_col, alpha * 0.85), 2.6, ph + 3.0)
	if maxed:
		b.draw_circle(c, RADIUS, ink)
	else:
		b.draw_circle(c, RADIUS, Color(UiKit.PARCHMENT_LIGHT, 0.95 if not locked else 0.6))
		if lv > 0:
			b.draw_arc(c, RADIUS - 6.0, 0.0, TAU, 40, Color(ink, 0.35), 3.0, true)
	var flood: float = fx["fill"]
	if flood > 0.0:
		b.draw_circle(c, RADIUS * flood, ink)
	_wobbly_circle(b, c, RADIUS, line, 3.2 if focused else 2.4, ph)
	_wobbly_circle(b, c, RADIUS + 1.5, Color(line, line.a * 0.4), 1.0, ph + 2.0)
	if focused:
		_dashed_circle(b, c, RADIUS + (17.0 if aff else 9.0), Color(UiKit.INK, 0.8), 22, 2.0)
	# Title inside, one word per line.
	var text_col := UiKit.PARCHMENT_LIGHT if (maxed or flood > 0.5) else line
	var words := n.title.split(" ")
	var fs := 15 if n.title.length() <= 10 else 14
	var lh := float(fs) + 2.0
	var y0 := c.y - (float(words.size()) * lh) * 0.5 + float(fs) * 0.8
	for i in words.size():
		_text_c(b, Vector2(c.x, y0 + float(i) * lh), words[i], fs, text_col)
	if locked:
		_draw_lock(b, c + Vector2(RADIUS * 0.72, -RADIUS * 0.72), Color(UiKit.INK, 0.75))
	# Level pips.
	var pip_y := c.y + RADIUS + 13.0
	var gap := 13.0
	var x0 := c.x - gap * float(n.max_level - 1) * 0.5
	for i in n.max_level:
		var p := Vector2(x0 + gap * float(i), pip_y)
		if i < lv:
			b.draw_circle(p, 4.2, line)
		else:
			b.draw_arc(p, 4.0, 0.0, TAU, 16, line, 1.4, true)
	if locked:
		return
	# Cost line (or MAX).
	var cy := pip_y + 24.0
	if maxed:
		_text_c(b, Vector2(c.x, cy), "MAX", 15, UiKit.INK)
		return
	_draw_cost(b, Vector2(c.x, cy), _cost(n), _wallet())


## "4 (drop) 1 (bones)": the lacking currency faded, with a short underline.
func _draw_cost(ci: CanvasItem, at: Vector2, cost: Vector2i, w: Vector2i) -> void:
	var fs := 15
	var icon := 15.0
	var parts: Array = []
	var total := 0.0
	for k in 2:
		var amount := cost.x if k == 0 else cost.y
		if amount <= 0:
			continue
		var s := str(amount)
		var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var short := _run != null and amount > (w.x if k == 0 else w.y)
		parts.append([s, tw, "pestilence" if k == 0 else "bones", short])
		total += tw + 2.0 + icon
	if parts.is_empty():
		_text_c(ci, at, "free", fs, UiKit.INK)
		return
	total += 8.0 * float(parts.size() - 1)
	var x := at.x - total * 0.5
	for p: Array in parts:
		var short: bool = p[3]
		var a := 0.42 if short else 1.0
		ci.draw_string(_font, Vector2(x, at.y), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.INK, a))
		var ix := x + float(p[1]) + 2.0
		var mod := Color(1, 1, 1, a)
		_icon_faded(ci, str(p[2]), Vector2(ix + icon * 0.5, at.y - fs * 0.33), icon, mod)
		if short:
			ci.draw_line(Vector2(x, at.y + 4.0), Vector2(ix + icon, at.y + 4.0), Color(UiKit.INK, 0.6), 1.4, true)
		x = ix + icon + 8.0


func _icon_faded(ci: CanvasItem, kind: String, c: Vector2, s: float, mod: Color) -> void:
	if mod.a >= 1.0:
		UiIcons.draw(ci, kind, c, s)
		return
	# Faded: draw in a lighter ink (UiIcons keeps its own red for the drop).
	UiIcons.draw(ci, kind, c, s, Color(UiKit.INK, mod.a))
	ci.draw_circle(c, s * 0.62, Color(UiKit.PARCHMENT_LIGHT, 1.0 - mod.a))


func _draw_teaser(b: Button, c: Vector2, focused: bool) -> void:
	b.draw_circle(c, RADIUS * 0.78, Color(UiKit.PARCHMENT_LIGHT, 0.5))
	_dashed_circle(b, c, RADIUS * 0.78, Color(UiKit.INK, 0.6), 16, 2.0)
	var fs := 30
	var f := UiKit.display_font()
	var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	b.draw_string(f, Vector2(c.x - w * 0.5, c.y + fs * 0.33), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.INK, 0.6))
	if focused:
		_dashed_circle(b, c, RADIUS * 0.78 + 8.0, Color(UiKit.INK, 0.8), 22, 2.0)


func _draw_lock(ci: CanvasItem, c: Vector2, col: Color) -> void:
	ci.draw_circle(c, 11.0, UiKit.PARCHMENT_LIGHT)
	ci.draw_arc(c + Vector2(0, -2), 4.5, PI, TAU, 10, col, 2.0, true)
	ci.draw_line(c + Vector2(-4.5, -2), c + Vector2(-4.5, 0), col, 2.0)
	ci.draw_line(c + Vector2(4.5, -2), c + Vector2(4.5, 0), col, 2.0)
	ci.draw_rect(Rect2(c + Vector2(-6.5, 0), Vector2(13, 9)), col)


# ---------------------------------------------------------------------- building
func _build() -> void:
	_bg = Control.new()
	_bg.name = "Parchment"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.draw.connect(_draw_bg)
	_bg.gui_input.connect(_on_bg_input)
	add_child(_bg)

	_board = Control.new()
	_board.name = "Board"
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	add_child(_board)
	for n in _nodes:
		_fx[n.id] = {"fill": 0.0, "splash": 0.0}
		var b := Button.new()
		b.name = "Node_" + n.id
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.size = NODE_SIZE
		b.position = n.tree_position * UNIT - CIRCLE
		b.set_meta("base_pos", b.position)
		b.set_meta("node_id", n.id)
		for style in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		b.draw.connect(_draw_node.bind(b, n))
		b.gui_input.connect(_on_node_input.bind(n))
		b.focus_entered.connect(_on_node_focused.bind(n))
		b.focus_exited.connect(_on_node_unfocused.bind(n))
		b.mouse_entered.connect(_on_hover.bind(n))
		b.mouse_exited.connect(_on_unhover.bind(n))
		_board.add_child(b)
		_buttons[n.id] = b

	_build_header()
	_build_hints()

	_tip = PanelContainer.new()
	_tip.name = "Tooltip"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.add_theme_stylebox_override("panel", UiKit.panel_box(Color(UiKit.PARCHMENT_LIGHT, 0.97), 2, 14, 3))
	add_child(_tip)
	_tip_box = VBoxContainer.new()
	_tip_box.add_theme_constant_override("separation", 6)
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_box)


func _build_header() -> void:
	_header = PanelContainer.new()
	_header.name = "Header"
	_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_header.custom_minimum_size.y = HEADER_HEIGHT
	var hs := StyleBoxFlat.new()
	hs.bg_color = UiKit.PARCHMENT.darkened(0.03)
	hs.border_color = UiKit.INK
	hs.border_width_bottom = 2
	hs.content_margin_left = 36
	hs.content_margin_right = 30
	hs.content_margin_top = 8
	hs.content_margin_bottom = 8
	_header.add_theme_stylebox_override("panel", hs)
	add_child(_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_header.add_child(row)

	var left := HBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(_centered(IconRect.make("pestilence", 28)))
	_pest_label = UiKit.label("—", UiKit.SIZE_LARGE)
	_pest_label.custom_minimum_size.x = 44
	left.add_child(_pest_label)
	left.add_child(_centered(IconRect.make("bones", 28)))
	_bones_label = UiKit.label("—", UiKit.SIZE_LARGE)
	_bones_label.custom_minimum_size.x = 44
	left.add_child(_bones_label)
	_reach_label = UiKit.label("—", UiKit.SIZE_SMALL + 2, UiKit.SEPIA)
	_reach_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(_reach_label)

	var heading := UiKit.label("The Upgrade Tree", UiKit.SIZE_TITLE, UiKit.INK, 0, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(heading)

	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 18)
	row.add_child(right)
	_year_label = UiKit.label("—", UiKit.SIZE_BODY)
	_year_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_year_label)
	_begin = Button.new()
	_begin.text = "To the Map"
	_begin.add_theme_font_size_override("font_size", 20)
	_begin.focus_mode = Control.FOCUS_ALL
	_begin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_begin.pressed.connect(_begin_round)
	right.add_child(_begin)
	_begin_style = UiKit.panel_box(UiKit.PARCHMENT_LIGHT, 3, 0, 3)
	_begin_style.shadow_size = 0
	_begin_style.content_margin_left = 18
	_begin_style.content_margin_right = 18
	_begin_style.content_margin_top = 6
	_begin_style.content_margin_bottom = 6


func _centered(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _build_hints() -> void:
	var foot := PanelContainer.new()
	foot.name = "Footer"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -HINT_HEIGHT
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var fs := StyleBoxFlat.new()
	fs.bg_color = UiKit.PARCHMENT.darkened(0.03)
	fs.border_color = UiKit.INK
	fs.border_width_top = 2
	fs.content_margin_bottom = 4
	foot.add_theme_stylebox_override("panel", fs)
	add_child(foot)
	var bar := HBoxContainer.new()
	bar.name = "Hints"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 26)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(bar)
	bar.add_child(PromptHint.make("ui_accept", "Buy (hold for more)", UiKit.SIZE_SMALL, 4))
	bar.add_child(FixedHint.make_fixed("Drag", "R-stick", "Pan"))
	bar.add_child(FixedHint.make_fixed("Wheel", "LT / RT", "Zoom"))
	bar.add_child(PromptHint.make("tree_recenter", "Recenter", UiKit.SIZE_SMALL, 4))
	bar.add_child(PromptHint.make("tree_to_map", "To the Map", UiKit.SIZE_SMALL, 4))
	bar.add_child(PromptHint.make("ui_cancel", "Title", UiKit.SIZE_SMALL, 4))
	for h: Control in bar.get_children():
		h.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _redraw_nodes() -> void:
	for b: Button in _buttons.values():
		if b.visible:
			b.queue_redraw()


## A radial gradient texture (centre to corner) in white, tinted when drawn.
func _radial(colors: Array[Color], offsets: Array[float]) -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


# ---------------------------------------------------------------------- debug
func _apply_debug_args() -> void:
	var args := OS.get_cmdline_user_args()
	var dev := _run != null and bool(_run.get("dev_mode"))
	var shot := ""
	var delay := 1.0
	for arg in args:
		if arg.begins_with("--screenshot="):
			shot = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-delay="):
			delay = float(arg.trim_prefix("--screenshot-delay="))
		elif dev and arg.begins_with("--dev-wallet="):
			var pb := arg.trim_prefix("--dev-wallet=").split(",")
			if pb.size() == 2:
				_run.set("pestilence", int(_run.get("pestilence")) + int(pb[0]))
				_run.set("bones", int(_run.get("bones")) + int(pb[1]))
				_run.emit_signal("wallet_changed")
		elif dev and arg.begins_with("--dev-buy="):
			for id in arg.trim_prefix("--dev-buy=").split(","):
				var n := _find(id)
				if n == null or not bool(_run.call("buy", n)):
					push_warning("UpgradeTree: --dev-buy could not buy '%s'" % id)
	if not shot.is_empty():
		_screenshot(shot, delay)


## The view / focus flags, once the tree is laid out.
func _apply_view_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dev-zoom="):
			_zoom_at(float(arg.trim_prefix("--dev-zoom=")), _area().get_center())
	for arg in OS.get_cmdline_user_args():
		var focus_id := ""
		if arg.begins_with("--dev-focus="):
			focus_id = arg.trim_prefix("--dev-focus=")
		elif arg.begins_with("--dev-hover="):
			focus_id = arg.trim_prefix("--dev-hover=")
		var n := _find(focus_id)
		if n != null and _state.get(n.id, State.HIDDEN) != State.HIDDEN:
			(func() -> void:
				(_buttons[n.id] as Button).grab_focus()
				if arg.begins_with("--dev-hover="):
					_show_tip(n.id)).call_deferred()


func _screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved to ", path)
	get_tree().quit()
