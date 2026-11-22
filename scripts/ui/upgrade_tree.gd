## The Upgrade Tree screen between Rounds: a parchment page with the
## UpgradeNodeDefs from Run.all_nodes() drawn as ink circles joined by ink
## lines (one line per `requires`). Under each circle are its level pips and
## the next level's cost. Hidden nodes aren't drawn, unaffordable ones are
## faded, maxed ones are filled with ink. Red is used only for plague nodes.
##
## Input: click a node to buy it, drag empty parchment (or right/middle-drag
## anywhere) to pan. Arrows / WASD / d-pad / stick move the focus between
## nearby nodes, Enter / A buys the focused one, Space / Start goes on to the
## Scroll Map (M7; "To the Map", Run.open_map()).
##
## Every Run call is guarded (get_node_or_null("/root/Run")) so the scene
## still opens without the autoload; it then shows the tree read-only.
## Debug flags (after `--`): --screenshot=<path> (saves a frame after
## --screenshot-delay=<s>, default 1 s, and quits), --dev-focus=<id>; with
## --dev also --dev-wallet=<p>,<b> (adds to the wallet) and --dev-buy=<id>,...
## (buys those nodes in order, saving the Run).
extends Control

const UPGRADES_DIR := "res://data/upgrades/"
const PARCHMENT := Color(0.93, 0.88, 0.76)
const PARCHMENT_DARK := Color(0.84, 0.77, 0.62)
const INK := Color(0.13, 0.10, 0.08)
const SEPIA := Color(0.36, 0.25, 0.15)
const RED := Color(0.72, 0.12, 0.10)
## Stats that are the plague itself: their nodes are inked in red.
const PLAGUE_STATS := ["lethality", "unlock_fleas", "unlock_contagion"]
## Pixels per tree unit, node circle radius, node hit box size.
const UNIT := 86.0
const RADIUS := 38.0
const NODE_SIZE := Vector2(104, 128)
const FADED_ALPHA := 0.42
const HEADER_HEIGHT := 64.0
## stat key -> [label, format of one value]; "%" formats as a percentage.
const STAT_INFO := {
	"rat_speed": ["Lead Rat speed", "%.1f"],
	"bite_range": ["Bite range", "%.2f"],
	"bite_cooldown": ["Bite cooldown", "%.2f s"],
	"bite_chunk": ["Bite strength", "%.0f"],
	"bite_rate_bonus": ["Bite bonus", "%.2f"],
	"start_adults": ["Starting Adults", "%.0f"],
	"feed_time": ["Feeding time", "%.1f s"],
	"pup_maturity": ["Pup maturity", "%.0f s"],
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

var _run: Node
var _nodes: Array[UpgradeNodeDef] = []
var _buttons := {}          # id -> Button
var _fx := {}               # id -> {"fill": float, "splash": float, "shake": float}
var _shown := {}            # id -> true once drawn (to fade in new nodes)
var _selected: UpgradeNodeDef     # shown in the description panel
var _from_mouse := false          # focus came from hovering: don't pan
var _pan := Vector2.ZERO
var _dragging := false
var _pan_tween: Tween
var _font: Font
var _blot: Texture2D        # soft round stain
var _vignette: Texture2D    # clear centre, dark edges

var _bg: Control
var _board: Control
var _wallet_label: Label
var _year_label: Label
var _begin: Button
var _desc_title: Label
var _desc_text: Label
var _desc_effect: Label
var _desc_status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_run = get_node_or_null("/root/Run")
	_font = _make_font()
	_blot = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], [0.0, 0.55, 1.0])
	_vignette = _radial([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1)], [0.0, 0.75, 1.42])
	theme = _make_theme()
	_nodes = _load_nodes()
	_build()
	if _run != null:
		_run.connect("wallet_changed", _refresh)
		_run.connect("upgrades_changed", _refresh)
	_apply_debug_args()
	_refresh()
	_centre_view(false)
	_focus_start()
	resized.connect(_on_resized)


func _on_resized() -> void:
	_centre_view(false)
	_bg.queue_redraw()


# ---------------------------------------------------------------------- Run access
func _load_nodes() -> Array[UpgradeNodeDef]:
	if _run != null:
		return _run.call("all_nodes")
	var out: Array[UpgradeNodeDef] = []
	if DirAccess.dir_exists_absolute(UPGRADES_DIR):
		for f in DirAccess.get_files_at(UPGRADES_DIR):
			var n := load(UPGRADES_DIR + f.trim_suffix(".remap")) as UpgradeNodeDef
			if n != null:
				out.append(n)
	return out


func _level(n: UpgradeNodeDef) -> int:
	return int(_run.call("level", n.id)) if _run != null else 0


func _cost(n: UpgradeNodeDef) -> Vector2i:
	if _run != null:
		return _run.call("cost_of", n)
	return Vector2i(n.cost_pestilence, n.cost_bones)


func _is_shown(n: UpgradeNodeDef) -> bool:
	return bool(_run.call("is_visible", n)) if _run != null else n.requires.is_empty()


func _can_buy(n: UpgradeNodeDef) -> bool:
	return _run != null and bool(_run.call("can_buy", n))


func _maxed(n: UpgradeNodeDef) -> bool:
	return _level(n) >= n.max_level


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


# ---------------------------------------------------------------------- actions
func _try_buy(n: UpgradeNodeDef) -> void:
	if _can_buy(n) and bool(_run.call("buy", n)):
		_play_buy(n)
	else:
		_play_refuse(n)
	_show_desc(n)


## "To the Map": the Scroll Map (Run.open_map), or straight to the next Round
## with an older Run that has no map.
func _begin_round() -> void:
	if _run == null:
		push_warning("UpgradeTree: no Run autoload, can't leave the Tree")
	elif _run.has_method("open_map"):
		_run.call("open_map")
	else:
		_run.call("start_round")


func _input(event: InputEvent) -> void:
	# Space would also press the focused button (ui_accept): catch it first.
	var begin := false
	if event is InputEventKey:
		var k := event as InputEventKey
		begin = k.pressed and not k.echo and k.keycode == KEY_SPACE
	elif event is InputEventJoypadButton:
		var j := event as InputEventJoypadButton
		begin = j.pressed and j.button_index == JOY_BUTTON_START
	if begin:
		get_viewport().set_input_as_handled()
		_begin_round()
		return
	# Right / middle drag pans anywhere, even over a node.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan_by((event as InputEventMouseMotion).relative)


func _unhandled_input(event: InputEvent) -> void:
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


func _pan_by(delta: Vector2) -> void:
	if _pan_tween != null:
		_pan_tween.kill()
	_set_pan(_pan + delta)


func _set_pan(p: Vector2) -> void:
	_pan = p
	_board.position = _area().get_center() + _pan


## The part of the screen the tree is drawn in (below the header).
func _area() -> Rect2:
	return Rect2(0, HEADER_HEIGHT, size.x, maxf(1.0, size.y - HEADER_HEIGHT))


## Centres the visible nodes in the area.
func _centre_view(animate: bool) -> void:
	var box := Rect2()
	var first := true
	for n in _nodes:
		if not _is_shown(n):
			continue
		var r := Rect2((_buttons[n.id] as Button).get_meta("base_pos"), NODE_SIZE)
		box = r if first else box.merge(r)
		first = false
	var target := -box.get_center()
	if animate:
		_tween_pan(target)
	else:
		_set_pan(target)


func _tween_pan(target: Vector2) -> void:
	if _pan_tween != null:
		_pan_tween.kill()
	_pan_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_method(_set_pan, _pan, target, 0.3)


## Keeps the focused node on screen when the focus moves with keys / pad.
func _on_node_focused(n: UpgradeNodeDef) -> void:
	var b: Button = _buttons[n.id]
	if not b.visible:
		return
	_show_desc(n)
	_redraw_nodes()
	if _from_mouse:
		return
	var rect := Rect2(b.position + _area().get_center() + _pan, b.size)
	var view := _area().grow(-24.0)
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


func _focus_start() -> void:
	var best: UpgradeNodeDef = null
	for n in _nodes:
		if _is_shown(n) and _can_buy(n) and (best == null or n.tree_position.length() < best.tree_position.length()):
			best = n
	if best != null:
		(_buttons[best.id] as Button).grab_focus()
	else:
		_begin.grab_focus()
		var root := _find_root()
		if root != null:
			_show_desc(root)


func _find_root() -> UpgradeNodeDef:
	for n in _nodes:
		if n.requires.is_empty():
			return n
	return null


# ---------------------------------------------------------------------- feedback
## Ink floods the circle, splashes outward, then settles to the node's state.
func _play_buy(n: UpgradeNodeDef) -> void:
	var fx: Dictionary = _fx[n.id]
	var t := create_tween()
	t.tween_method(_set_fx.bind(n.id, "fill"), 0.0, 1.0, 0.18).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(_set_fx.bind(n.id, "splash"), 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_fx.bind(n.id, "fill"), 1.0, 0.0, 0.35).set_delay(0.08)
	t.tween_callback(func() -> void: fx["splash"] = 0.0)
	var b: Button = _buttons[n.id]
	b.pivot_offset = Vector2(NODE_SIZE.x * 0.5, RADIUS + 4.0)
	var pop := create_tween()
	pop.tween_property(b, "scale", Vector2(1.12, 1.12), 0.08)
	pop.tween_property(b, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


## A short sideways shake.
func _play_refuse(n: UpgradeNodeDef) -> void:
	var t := create_tween()
	t.tween_method(_set_fx.bind(n.id, "shake"), 0.0, 1.0, 0.35)
	t.tween_callback(_set_fx.bind(0.0, n.id, "shake"))


func _set_fx(v: float, id: String, key: String) -> void:
	var fx: Dictionary = _fx[id]
	fx[key] = v
	var b: Button = _buttons[id]
	if key == "shake":
		var base: Vector2 = b.get_meta("base_pos")
		b.position = base + Vector2(sin(v * TAU * 3.0) * 7.0 * (1.0 - v), 0)
	b.queue_redraw()


# ---------------------------------------------------------------------- refresh
func _refresh() -> void:
	var w := _wallet()
	_wallet_label.text = "Pestilence  %d     Bones  %d" % [w.x, w.y]
	var year := int(_run.get("year")) if _run != null else 1347
	_year_label.text = "Year of Our Lord %d" % year
	var revealed := false
	for n in _nodes:
		var b: Button = _buttons[n.id]
		var show := _is_shown(n)
		if show and not _shown.has(n.id):
			_shown[n.id] = true
			if is_node_ready():
				revealed = true
				b.modulate.a = 0.0
				create_tween().tween_property(b, "modulate:a", 1.0, 0.4)
		b.visible = show
		b.queue_redraw()
	_board.queue_redraw()
	if revealed:
		_centre_view(true)
	var focus := get_viewport().gui_get_focus_owner()
	if _selected != null:
		_show_desc(_selected)
	elif focus != null and focus.has_meta("node_id"):
		_show_desc(_find(str(focus.get_meta("node_id"))))


func _show_desc(n: UpgradeNodeDef) -> void:
	if n == null:
		return
	_selected = n
	var lv := _level(n)
	_desc_title.text = "%s   %d / %d" % [n.title, lv, n.max_level]
	_desc_text.text = n.description
	_desc_effect.text = _effect_text(n)
	var c := _cost(n)
	var w := _wallet()
	if _maxed(n):
		_desc_status.text = "Mastered."
	elif _run == null:
		_desc_status.text = "Costs %s  (no Run loaded)" % _cost_text(c)
	elif c.x > w.x or c.y > w.y:
		var lack: Array[String] = []
		if c.x > w.x:
			lack.append("%d Pestilence" % (c.x - w.x))
		if c.y > w.y:
			lack.append("%d Bones" % (c.y - w.y))
		_desc_status.text = "Costs %s.  Short of %s." % [_cost_text(c), " and ".join(lack)]
	else:
		_desc_status.text = "Costs %s.  Click or press A to buy." % _cost_text(c)


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
		if maxed:
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


func _cost_text(c: Vector2i) -> String:
	var parts: Array[String] = []
	if c.x > 0:
		parts.append("%d P" % c.x)
	if c.y > 0:
		parts.append("%d B" % c.y)
	return "free" if parts.is_empty() else " · ".join(parts)


static func _is_plague(n: UpgradeNodeDef) -> bool:
	for key: String in PLAGUE_STATS:
		if n.effects.has(key) or n.level_stat == key:
			return true
	return false


# ---------------------------------------------------------------------- drawing
func _draw_bg() -> void:
	var s := _bg.size
	_bg.draw_rect(Rect2(Vector2.ZERO, s), PARCHMENT)
	# Stains and foxing, always in the same places.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1347
	for i in 34:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		var r := rng.randf_range(40.0, 260.0)
		var c := SEPIA
		c.a = rng.randf_range(0.05, 0.14)
		_bg.draw_texture_rect(_blot, Rect2(p - Vector2(r, r * 0.8), Vector2(r, r * 0.8) * 2.0), false, c)
	for i in 60:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		var c := SEPIA
		c.a = rng.randf_range(0.05, 0.14)
		_bg.draw_circle(p, rng.randf_range(0.8, 2.6), c)
	# Darkened edges.
	_bg.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, s), false, Color(SEPIA, 0.55))
	# Double ink rule round the page.
	var ink := INK
	ink.a = 0.8
	_bg.draw_rect(Rect2(Vector2(14, 14), s - Vector2(28, 28)), ink, false, 2.0)
	ink.a = 0.5
	_bg.draw_rect(Rect2(Vector2(20, 20), s - Vector2(40, 40)), ink, false, 1.0)


## Requirement lines between the visible nodes, edge to edge.
func _draw_board() -> void:
	for n in _nodes:
		if not _is_shown(n):
			continue
		for req_id in n.requires:
			var r := _find(req_id)
			if r == null or not _is_shown(r):
				continue
			var a := r.tree_position * UNIT
			var b := n.tree_position * UNIT
			var from := _line_end(a, b)
			var to := _line_end(b, a)
			if from.distance_to(b) <= to.distance_to(b):
				continue
			var c := INK
			c.a = 0.85 if _level(n) > 0 else 0.45
			_wobbly_line(_board, from, to, c, 2.2 if _level(n) > 0 else 1.6, hash(n.id + req_id))


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
	var ph := float(seed_value % 1000) * 0.01
	for i in steps + 1:
		var t := float(i) / float(steps)
		var off := sin(t * 7.0 + ph) * 1.3 + sin(t * 17.0 + ph * 2.0) * 0.6
		pts.append(a.lerp(b, t) + normal * off * sin(t * PI))
	ci.draw_polyline(pts, c, width, true)


func _wobbly_circle(ci: CanvasItem, centre: Vector2, r: float, c: Color, width: float, ph: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := float(i) / 48.0 * TAU
		var rr := r + sin(a * 2.0 + ph) * 0.45 + sin(a * 5.0 + ph * 1.7) * 0.2
		pts.append(centre + Vector2(cos(a), sin(a)) * rr)
	ci.draw_polyline(pts, c, width, true)


func _draw_node(b: Button, n: UpgradeNodeDef) -> void:
	var fx: Dictionary = _fx[n.id]
	var lv := _level(n)
	var maxed := lv >= n.max_level
	var affordable := maxed or _can_buy(n) or _run == null
	var ink := RED if _is_plague(n) else INK
	var c := Vector2(NODE_SIZE.x * 0.5, RADIUS + 4.0)
	var ph := float(hash(n.id) % 100) * 0.1
	var alpha := 1.0 if affordable else FADED_ALPHA
	var line := ink
	line.a = alpha
	var focused := b.has_focus()
	# Splash: droplets thrown out of the circle.
	var splash: float = fx["splash"]
	if splash > 0.0:
		var drop := ink
		drop.a = 1.0 - splash
		for i in 9:
			var ang := float(i) / 9.0 * TAU + ph
			var dist := RADIUS + 6.0 + splash * (18.0 + float((i * 7) % 5) * 5.0)
			b.draw_circle(c + Vector2(cos(ang), sin(ang)) * dist, 4.0 * (1.0 - splash) + 1.0, drop)
		var ring := ink
		ring.a = (1.0 - splash) * 0.6
		_wobbly_circle(b, c, RADIUS + 4.0 + splash * 22.0, ring, 2.0, ph)
	# Body.
	var fill := PARCHMENT.lightened(0.25) if not maxed else ink
	fill.a = alpha if not maxed else 1.0
	b.draw_circle(c, RADIUS, fill)
	if lv > 0 and not maxed:
		# Owned but not maxed: an inner hatch-like ring.
		var inner := ink
		inner.a = 0.35
		b.draw_arc(c, RADIUS - 6.0, 0.0, TAU, 40, inner, 3.0, true)
	var flood: float = fx["fill"]
	if flood > 0.0:
		b.draw_circle(c, RADIUS * flood, ink)
	_wobbly_circle(b, c, RADIUS, line, 3.0 if focused else 2.4, ph)
	var second := line
	second.a *= 0.4
	_wobbly_circle(b, c, RADIUS + 1.5, second, 1.0, ph + 2.0)
	if focused:
		var halo := line
		halo.a *= 0.7
		_dashed_circle(b, c, RADIUS + 9.0, halo)
	# Title inside, one word per line.
	var text_col := PARCHMENT if (maxed or flood > 0.5) else line
	var words := n.title.split(" ")
	var fs := 15 if n.title.length() <= 10 else 14
	var lh := float(fs) + 2.0
	var y0 := c.y - (float(words.size()) * lh) * 0.5 + float(fs) * 0.8
	for i in words.size():
		var wsz := _font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		b.draw_string(_font, Vector2(c.x - wsz.x * 0.5, y0 + float(i) * lh), words[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	# Level pips.
	var pip_y := c.y + RADIUS + 15.0
	var gap := 13.0
	var x0 := c.x - gap * float(n.max_level - 1) * 0.5
	for i in n.max_level:
		var p := Vector2(x0 + gap * float(i), pip_y)
		if i < lv:
			b.draw_circle(p, 4.2, line)
		else:
			b.draw_arc(p, 4.0, 0.0, TAU, 16, line, 1.4, true)
	# Cost.
	var cost_str := "mastered" if maxed else _cost_text(_cost(n))
	var cs := 14
	var csz := _font.get_string_size(cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cs)
	var cost_col := INK
	cost_col.a = alpha
	b.draw_string(_font, Vector2(c.x - csz.x * 0.5, pip_y + 22.0), cost_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, cs, cost_col)


func _dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var dashes := 18
	for i in dashes:
		var a0 := float(i) / float(dashes) * TAU
		ci.draw_arc(c, r, a0, a0 + TAU / float(dashes) * 0.55, 4, col, 1.6, true)


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
		_fx[n.id] = {"fill": 0.0, "splash": 0.0, "shake": 0.0}
		var b := Button.new()
		b.name = "Node_" + n.id
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.size = NODE_SIZE
		b.position = n.tree_position * UNIT - Vector2(NODE_SIZE.x * 0.5, RADIUS + 4.0)
		b.set_meta("base_pos", b.position)
		b.set_meta("node_id", n.id)
		for style in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		b.draw.connect(_draw_node.bind(b, n))
		b.pressed.connect(_try_buy.bind(n))
		b.focus_entered.connect(_on_node_focused.bind(n))
		b.focus_exited.connect(_redraw_nodes)
		b.mouse_entered.connect(_on_hover.bind(n))
		_board.add_child(b)
		_buttons[n.id] = b
		if _is_shown(n):
			_shown[n.id] = true

	# Header: wallet, page title, Year and the To the Map button.
	var header := PanelContainer.new()
	header.name = "Header"
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size.y = HEADER_HEIGHT
	var hs := StyleBoxFlat.new()
	hs.bg_color = PARCHMENT.darkened(0.03)
	hs.border_color = INK
	hs.border_width_bottom = 2
	hs.content_margin_left = 36
	hs.content_margin_right = 30
	hs.content_margin_top = 8
	hs.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", hs)
	add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	header.add_child(row)
	_wallet_label = _label(row, 22)
	_wallet_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := _label(row, 28)
	heading.text = "The Upgrade Tree"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_year_label = _label(row, 20)
	_year_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_begin = Button.new()
	_begin.text = "To the Map"
	_begin.add_theme_font_size_override("font_size", 20)
	_begin.focus_mode = Control.FOCUS_ALL
	_begin.pressed.connect(_begin_round)
	row.add_child(_begin)

	# Top-right: the description of the hovered / focused node.
	var desc := PanelContainer.new()
	desc.name = "Description"
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 30)
	desc.offset_top = HEADER_HEIGHT + 14.0
	desc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	desc.custom_minimum_size = Vector2(330, 0)
	desc.add_theme_stylebox_override("panel", _box(Color(PARCHMENT.lightened(0.15), 0.92), 2, 14))
	add_child(desc)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 6)
	desc.add_child(dbox)
	_desc_title = _label(dbox, 22)
	_desc_text = _label(dbox, 16)
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_text.custom_minimum_size.x = 300
	_desc_effect = _label(dbox, 16)
	_desc_effect.add_theme_color_override("font_color", SEPIA)
	_desc_status = _label(dbox, 15)
	_desc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_status.custom_minimum_size.x = 300

	# Bottom-left: the controls.
	var hint := _label(self, 14)
	hint.name = "Hint"
	hint.text = "Click / A: buy     Drag: pan     Space / Start: To the Map"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 32)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.add_theme_color_override("font_color", SEPIA)


## Hovering a node focuses it, so mouse and pad share one selection.
func _on_hover(n: UpgradeNodeDef) -> void:
	_from_mouse = true
	(_buttons[n.id] as Button).grab_focus()
	_from_mouse = false


func _redraw_nodes() -> void:
	for b: Button in _buttons.values():
		b.queue_redraw()


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _box(fill: Color, border: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = INK
	s.set_border_width_all(border)
	s.set_content_margin_all(margin)
	return s


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


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Georgia", "Garamond", "Times New Roman", "serif"])
	return f


## Ink-on-parchment buttons (the Begin Round button) and the serif font.
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font
	var normal := _box(PARCHMENT.lightened(0.2), 2, 0)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PARCHMENT_DARK
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0, 0, 0, 0)
	focus.set_border_width_all(3)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = INK
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_pressed_color", "Button", PARCHMENT)
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
	for arg in args:
		if arg.begins_with("--dev-focus="):
			var n := _find(arg.trim_prefix("--dev-focus="))
			if n != null and _is_shown(n):
				(func() -> void: (_buttons[n.id] as Button).grab_focus()).call_deferred()
	if not shot.is_empty():
		_screenshot(shot, delay)


func _screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved to ", path)
	get_tree().quit()
