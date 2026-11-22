## Round HUD: currencies, Colony size, the Lead Rat's hits left and the Year
## (top-left), Round timer with the Vigilance word and a thin ink bar under it
## (top-centre; Calm / Wary / Alarmed / Hunting, the bar darkening as it
## rises), District Infection bar (top-right) and
## the end-of-Round panel: this Round's earnings, the reason, the Year change
## and a Continue button (Enter / A / click) that hands the RoundDirector's
## result to Run.finish_round() and opens the Upgrade Tree. R restarts the
## Round only with --dev. Ink-brown text on translucent parchment panels.
## Every value shows "—" while its source is missing (the Run autoload too).
## Bottom-left: the Raid cooldown (once Raid is unlocked) and the time left
## Hidden; bottom-centre: a one-time "Enter a door to Hide" hint per session.
## Both read the Colony (group "colony") by property name.
## M6 Exterminators (group "exterminator", read by property name): a centre
## banner "<title> has come" fades in and out when one appears; while it is
## alive its title and Infection bar sit under the Vigilance meter (red fill,
## a faint ink band for what its self-Cleanse takes back in CLEANSE_SHOWN s);
## on "exterminator_beaten" the end panel says "<title> has fallen" and names
## the District that opens (from Run.district_defs(), by `requires`).
extends CanvasLayer

const INK := Color(0.13, 0.10, 0.08)
const PARCHMENT := Color(0.93, 0.88, 0.76, 0.85)
const RED := Color(0.72, 0.12, 0.10)
const NONE := "—"
const FONT_SIZE := 22
## The door hint shows when the Lead Rat is this close to a door, for this long.
const HINT_RANGE := 3.5
const HINT_TIME := 5.0
## Vigilance tiers: the word for Vigilance below each bound (the last has none).
const VIGILANCE_TIERS := [[0.5, "Calm"], [1.0, "Wary"], [2.0, "Alarmed"], [INF, "Hunting"]]
## Vigilance at which the bar is full (the Spawner's fastest interval).
const VIGILANCE_FULL := 2.0
## Bar fill at Calm; darkens to INK by a full bar.
const VIGILANCE_PALE := Color(0.55, 0.49, 0.41)
## Banner: seconds to fade in, hold and fade out.
const BANNER_TIMES := Vector3(0.6, 2.4, 0.9)
## The boss bar's cleanse band shows this many seconds of self-Cleanse.
const CLEANSE_SHOWN := 3.0
const BOSS_BAR_WIDTH := 280.0
const WAY_OPEN := "The way lies open"
const CITY_YOURS := "The city is yours"

## Once per session (survives scene reloads).
static var _hint_done := false

var _director: RoundDirector
var _pestilence: Label
var _bones: Label
var _timer: Label
var _vigilance_label: Label
var _vigilance_bar: ProgressBar
var _vigilance_fill: StyleBoxFlat
var _infection_label: Label
var _infection_bar: ProgressBar
var _end_panel: PanelContainer
var _end_totals: Label
var _end_title: Label
var _colony_label: Label
var _hits_label: Label
var _hit_marks: HBoxContainer
var _mark_full: StyleBoxFlat
var _mark_empty: StyleBoxFlat
var _year: Label
var _continue: Button
var _end_note: Label
var _continued := false
var _dev := false
var _houses_panel: PanelContainer
var _raid_label: Label
var _hidden_label: Label
var _hint_panel: PanelContainer
var _hint_left := 0.0
var _boss: Node3D
var _bosses_seen := {}        # instance id -> true (one banner each)
var _boss_box: VBoxContainer
var _boss_title: Label
var _boss_bar: ProgressBar
var _boss_cleanse: ColorRect
var _banner: PanelContainer
var _banner_label: Label
var _banner_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dev = OS.get_cmdline_user_args().has("--dev")
	_build()
	_refresh()


func _process(delta: float) -> void:
	if _director == null or not is_instance_valid(_director):
		_find_director()
	_refresh()
	_refresh_houses(delta)
	_refresh_boss()


func _unhandled_input(event: InputEvent) -> void:
	if not _end_panel.visible or not _dev:
		return
	var restart := false
	if event is InputEventKey:
		var k := event as InputEventKey
		restart = k.pressed and not k.echo and k.keycode == KEY_R
	if restart:
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		get_tree().reload_current_scene()


func _find_director() -> void:
	_director = get_tree().get_first_node_in_group("round_director") as RoundDirector
	if _director == null:
		return
	_director.round_ended.connect(_on_round_ended)
	if _director.has_ended():
		_on_round_ended(_director.end_reason)


func _refresh() -> void:
	_refresh_colony()
	var run := _run()
	_year.text = "Year %d" % int(run.get("year")) if run != null else "Year " + NONE
	var d := _director if _director != null and is_instance_valid(_director) else null
	if d == null:
		_pestilence.text = "Pestilence  " + NONE
		_bones.text = "Bones  " + NONE
		_timer.text = NONE
		_vigilance_label.text = "Vigilance  " + NONE
		_vigilance_bar.value = 0.0
		_infection_label.text = "District Infection  " + NONE
		_infection_bar.value = 0.0
		return
	_pestilence.text = "Pestilence  %d" % d.pestilence
	_bones.text = "Bones  %d" % d.bones
	var secs := int(ceilf(d.time_left))
	_timer.text = "%d:%02d" % [secs / 60, secs % 60]
	_refresh_vigilance(d)
	var pct := d.district_infection() * 100.0
	_infection_label.text = "District Infection  %d%%" % roundi(pct)
	_infection_bar.value = pct


## Vigilance word and bar, read by property name ("—" without one).
func _refresh_vigilance(d: Node) -> void:
	var v: Variant = d.get("vigilance")
	if not (v is float or v is int):
		_vigilance_label.text = "Vigilance  " + NONE
		_vigilance_bar.value = 0.0
		return
	_vigilance_label.text = vigilance_word(float(v))
	var t := clampf(float(v) / VIGILANCE_FULL, 0.0, 1.0)
	_vigilance_bar.value = t * 100.0
	_vigilance_fill.bg_color = VIGILANCE_PALE.lerp(INK, t)


static func vigilance_word(v: float) -> String:
	for tier: Array in VIGILANCE_TIERS:
		if v < float(tier[0]):
			return tier[1]
	return VIGILANCE_TIERS[-1][1]


## Colony line and the Lead Rat's hit marks. Read by property name so the HUD
## doesn't depend on the Colony / LeadRat classes.
func _refresh_colony() -> void:
	var colony := get_tree().get_first_node_in_group("colony")
	var adults: Variant = colony.get("adult_count") if colony != null else null
	var pups: Variant = colony.get("pup_count") if colony != null else null
	if adults is int and pups is int:
		_colony_label.text = "Colony  %d (+%d pups)" % [adults, pups]
	elif adults is int:
		_colony_label.text = "Colony  %d" % adults
	else:
		_colony_label.text = "Colony  " + NONE
	var rat := get_tree().get_first_node_in_group("lead_rat")
	var left: Variant = rat.get("hits_left") if rat != null else null
	var most: Variant = rat.get("max_hits") if rat != null else null
	if not (left is int):
		_hits_label.text = "Lead Rat  " + NONE
		_hit_marks.visible = false
		return
	_hits_label.text = "Lead Rat"
	_hit_marks.visible = true
	var n: int = most if most is int and most > 0 else maxi(left, 3)
	while _hit_marks.get_child_count() < n:
		var mark := Panel.new()
		mark.custom_minimum_size = Vector2(16, 16)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hit_marks.add_child(mark)
	for i in _hit_marks.get_child_count():
		var m := _hit_marks.get_child(i) as Panel
		m.visible = i < n
		m.add_theme_stylebox_override("panel", _mark_full if i < left else _mark_empty)


## Raid / Hidden lines and the door hint. A missing Colony or property hides
## the line rather than guessing.
func _refresh_houses(delta: float) -> void:
	var colony := get_tree().get_first_node_in_group("colony")
	var raid_on: Variant = colony.get("raid_unlocked") if colony != null else null
	var hide_on: Variant = colony.get("hide_unlocked") if colony != null else null
	var hidden: Variant = colony.get("is_hidden") if colony != null else null
	_raid_label.visible = raid_on is bool and raid_on
	if _raid_label.visible:
		var cd: Variant = colony.get("raid_cooldown_left")
		var inside: Variant = colony.get("raiders_inside")
		var adults: Variant = colony.get("adult_count")
		var text := "Raid  "
		if not (cd is float or cd is int):
			text += NONE
		elif float(cd) > 0.0:
			text += "%ds" % ceili(float(cd))
		elif hidden is bool and hidden:
			text += "(hidden)"
		elif colony.has_method("raid_followers_available"):
			text += "ready" if int(colony.call("raid_followers_available")) > 0 else "(need followers)"
		elif adults is int and adults <= 1:
			text += "(need followers)"
		else:
			text += "ready"
		if inside is int and inside > 0:
			text += "  ·  %d inside" % inside
		_raid_label.text = text
	_hidden_label.visible = hidden is bool and hidden
	if _hidden_label.visible:
		var left: Variant = colony.get("hidden_time_left")
		_hidden_label.text = "Hidden  %ds" % ceili(float(left)) if (left is float or left is int) else "Hidden  " + NONE
	_houses_panel.visible = _raid_label.visible or _hidden_label.visible
	# One-time hint: Hide unlocked and the Lead Rat standing near a door.
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0 or (hidden is bool and hidden):
			_hint_left = 0.0
	elif not _hint_done and hide_on is bool and hide_on and not (hidden is bool and hidden) and _lead_near_door():
		_hint_done = true
		_hint_left = HINT_TIME
	_hint_panel.visible = _hint_left > 0.0


func _lead_near_door() -> bool:
	var rat := get_tree().get_first_node_in_group("lead_rat") as Node3D
	if rat == null:
		return false
	var p := rat.global_position
	for h: Node in get_tree().get_nodes_in_group("houses"):
		var door: Variant = h.get("door_position")
		if door is Vector3 and Vector2(door.x - p.x, door.z - p.z).length() <= HINT_RANGE:
			return true
	return false


## Finds a new Exterminator (banner once each) and keeps its bar up to date;
## hides the bar while there is none or once it is beaten.
func _refresh_boss() -> void:
	for n: Node in get_tree().get_nodes_in_group("exterminator"):
		var id := n.get_instance_id()
		if not _bosses_seen.has(id) and n is Node3D:
			_bosses_seen[id] = true
			_boss = n as Node3D
			show_banner("%s has come" % boss_title(_boss))
	var b := _boss if _boss != null and is_instance_valid(_boss) else null
	var gone: bool = b == null or b.get("is_beaten") == true
	var inf: Node = b.get_node_or_null("Infection") if b != null else null
	_boss_box.visible = not gone and inf != null
	if not _boss_box.visible:
		return
	var v: Variant = inf.get("value")
	var c: Variant = inf.get("cleanse_rate")
	var value := float(v) if (v is float or v is int) else 0.0
	var cleanse := float(c) if (c is float or c is int) else 0.0
	_boss_title.text = boss_title(b)
	_boss_bar.value = value
	# The faint band: the part of the bar the self-Cleanse would take back.
	var w := _boss_bar.size.x if _boss_bar.size.x > 0.0 else BOSS_BAR_WIDTH
	var lo := clampf(value - cleanse * CLEANSE_SHOWN, 0.0, 100.0)
	_boss_cleanse.visible = cleanse > 0.0 and value > 0.0
	_boss_cleanse.position = Vector2(w * lo / 100.0, 0.0)
	_boss_cleanse.size = Vector2(maxf(2.0, w * (value - lo) / 100.0), _boss_bar.size.y)


## An Exterminator's `title`, or "The Exterminator".
static func boss_title(b: Node) -> String:
	var t: Variant = b.get("title") if b != null and is_instance_valid(b) else null
	return t if t is String and t != "" else "The Exterminator"


## Fades `text` in at the centre of the screen, holds it, and fades it out.
func show_banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = true
	_banner.modulate.a = 0.0
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, BANNER_TIMES.x)
	_banner_tween.tween_interval(BANNER_TIMES.y)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, BANNER_TIMES.z)
	_banner_tween.tween_callback(_banner.hide)


## "<next District> lies open" for the District that requires the current one,
## "The city is yours" if none does, "The way lies open" without the Run data.
func next_district_note() -> String:
	var run := _run()
	if run == null or not run.has_method("district_defs"):
		return WAY_OPEN
	var defs: Variant = run.call("district_defs")
	if not (defs is Array) or (defs as Array).is_empty():
		return WAY_OPEN
	var current: Variant = run.get("current_district")
	var cur: String = current if current is String else ""
	for d: Variant in defs:
		if not (d is Object):
			continue
		var req: Variant = (d as Object).get("requires")
		var id: Variant = (d as Object).get("id")
		if req is String and req == cur and cur != "" and id != cur:
			var title: Variant = (d as Object).get("title")
			return "%s lies open" % (title if title is String and title != "" else str(id))
	return CITY_YOURS


func _run() -> Node:
	return get_node_or_null("/root/Run")


func _on_round_ended(reason: String) -> void:
	_refresh()
	var d := _director
	var died := reason == "lead_rat_died"
	var won := reason == "exterminator_beaten"
	_end_title.text = "The Lead Rat was crushed" if died else "The bells ring: the Round is over"
	if won:
		var b: Node = _boss if _boss != null and is_instance_valid(_boss) else get_tree().get_first_node_in_group("exterminator")
		_end_title.text = "%s has fallen" % boss_title(b)
		_boss_box.visible = false
	_end_totals.text = "Earned  %d Pestilence  ·  %d Bones\nDead  %d of %d\nDistrict Infection  %d%%\n%s" % [
		d.pestilence, d.bones, d.dead_count, d.population, roundi(d.district_infection() * 100.0),
		_colony_label.text]
	var run := _run()
	if won:
		_end_note.text = next_district_note()
	elif died:
		var next := str(int(run.get("year")) + 1) if run != null else NONE
		_end_note.text = "The Colony scatters. Year advances to %s." % next
	else:
		_end_note.text = "The Lead Rat survived with a Colony of %d. The Year holds." % int(d.result.get("colony_size", 0))
	_end_panel.visible = true
	_continue.grab_focus()


## Pays the Round into the Run and opens the Upgrade Tree (once).
func _on_continue() -> void:
	if _continued or _director == null:
		return
	_continued = true
	var run := _run()
	if run == null:
		push_warning("HUD: no Run autoload, restarting the Round instead")
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	run.call("finish_round", _director.result)
	run.call("open_tree")


# ---------------------------------------------------------------------- building
func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-left: currencies and the Year.
	var left := _panel(root, "Currencies")
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	var lbox := VBoxContainer.new()
	left.add_child(lbox)
	_pestilence = _label(lbox, FONT_SIZE)
	_bones = _label(lbox, FONT_SIZE)
	_colony_label = _label(lbox, FONT_SIZE - 2)
	var hits_row := HBoxContainer.new()
	hits_row.add_theme_constant_override("separation", 10)
	lbox.add_child(hits_row)
	_hits_label = _label(hits_row, FONT_SIZE - 2)
	_hit_marks = HBoxContainer.new()
	_hit_marks.add_theme_constant_override("separation", 6)
	_hit_marks.alignment = BoxContainer.ALIGNMENT_CENTER
	hits_row.add_child(_hit_marks)
	_mark_full = _box(INK, 2, 0)
	_mark_full.set_corner_radius_all(8)
	_mark_empty = _box(Color(0, 0, 0, 0), 2, 0)
	_mark_empty.set_corner_radius_all(8)
	_year = _label(lbox, FONT_SIZE - 4)

	# Top-centre: the Round timer.
	var centre := _panel(root, "Timer")
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 2)
	centre.add_child(cbox)
	_timer = _label(cbox, FONT_SIZE + 10)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.custom_minimum_size.x = 130
	_vigilance_label = _label(cbox, FONT_SIZE - 6)
	_vigilance_label.name = "Vigilance"
	_vigilance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vigilance_bar = ProgressBar.new()
	_vigilance_bar.name = "VigilanceBar"
	_vigilance_bar.show_percentage = false
	_vigilance_bar.min_value = 0.0
	_vigilance_bar.max_value = 100.0
	_vigilance_bar.custom_minimum_size = Vector2(130, 6)
	_vigilance_bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0), 1, 0))
	_vigilance_fill = _box(VIGILANCE_PALE, 0, 0)
	_vigilance_bar.add_theme_stylebox_override("fill", _vigilance_fill)
	cbox.add_child(_vigilance_bar)
	_build_boss(cbox)

	# Top-right: District Infection bar.
	var right := _panel(root, "Infection")
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var rbox := VBoxContainer.new()
	right.add_child(rbox)
	_infection_label = _label(rbox, FONT_SIZE)
	_infection_bar = ProgressBar.new()
	_infection_bar.show_percentage = false
	_infection_bar.min_value = 0.0
	_infection_bar.max_value = 100.0
	_infection_bar.custom_minimum_size = Vector2(240, 14)
	_infection_bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0), 2, 0))
	_infection_bar.add_theme_stylebox_override("fill", _box(RED, 0, 0))
	rbox.add_child(_infection_bar)

	# Bottom-left: Raid cooldown and time left Hidden.
	_houses_panel = _panel(root, "Houses")
	_houses_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_houses_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hbox := VBoxContainer.new()
	_houses_panel.add_child(hbox)
	_hidden_label = _label(hbox, FONT_SIZE)
	_raid_label = _label(hbox, FONT_SIZE)
	_houses_panel.visible = false

	# Bottom-centre: the one-time door hint.
	_hint_panel = _panel(root, "DoorHint")
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 48)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hint := _label(_hint_panel, FONT_SIZE)
	hint.text = "Enter a door to Hide"
	_hint_panel.visible = false

	# Centre: the Exterminator's arrival banner, above the middle of the screen.
	_banner = _panel(root, "BossBanner")
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top -= 140.0
	_banner.offset_bottom -= 140.0
	_banner.add_theme_stylebox_override("panel", _box(PARCHMENT, 2, 18))
	_banner_label = _label(_banner, FONT_SIZE + 14)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false

	# Centre: end-of-Round panel, hidden until the Round ends.
	_end_panel = _panel(root, "EndOfRound")
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_panel.add_theme_stylebox_override("panel", _box(PARCHMENT, 2, 24))
	var ebox := VBoxContainer.new()
	ebox.add_theme_constant_override("separation", 12)
	_end_panel.add_child(ebox)
	_end_title = _label(ebox, FONT_SIZE + 12)
	_end_title.text = "The Round is over"
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_totals = _label(ebox, FONT_SIZE)
	_end_totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_note = _label(ebox, FONT_SIZE - 2)
	_end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue = Button.new()
	_continue.name = "Continue"
	_continue.text = "Continue"
	_continue.focus_mode = Control.FOCUS_ALL
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue.add_theme_font_size_override("font_size", FONT_SIZE + 2)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		_continue.add_theme_color_override(c, INK)
	_continue.add_theme_color_override("font_pressed_color", PARCHMENT)
	var normal := _box(Color(PARCHMENT, 1.0), 2, 0)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PARCHMENT.darkened(0.1)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = INK
	var focus := _box(Color(0, 0, 0, 0), 3, 0)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	_continue.add_theme_stylebox_override("normal", normal)
	_continue.add_theme_stylebox_override("hover", hover)
	_continue.add_theme_stylebox_override("pressed", pressed)
	_continue.add_theme_stylebox_override("focus", focus)
	_continue.pressed.connect(_on_continue)
	ebox.add_child(_continue)
	if _dev:
		var again := _label(ebox, FONT_SIZE - 6)
		again.text = "dev: R restarts the Round"
		again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_panel.visible = false


## The boss bar under the Vigilance meter: title, then a red Infection bar with
## the faint ink cleanse band laid over it.
func _build_boss(parent: Control) -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.name = "Boss"
	_boss_box.add_theme_constant_override("separation", 2)
	parent.add_child(_boss_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_boss_box.add_child(gap)
	_boss_title = _label(_boss_box, FONT_SIZE - 4)
	_boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = ProgressBar.new()
	_boss_bar.name = "BossBar"
	_boss_bar.show_percentage = false
	_boss_bar.min_value = 0.0
	_boss_bar.max_value = 100.0
	_boss_bar.custom_minimum_size = Vector2(BOSS_BAR_WIDTH, 14)
	_boss_bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0), 2, 0))
	_boss_bar.add_theme_stylebox_override("fill", _box(RED, 0, 0))
	_boss_box.add_child(_boss_bar)
	_boss_cleanse = ColorRect.new()
	_boss_cleanse.name = "CleanseBand"
	_boss_cleanse.color = Color(INK, 0.35)
	_boss_cleanse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(_boss_cleanse)
	_boss_box.visible = false


func _panel(parent: Control, panel_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = panel_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _box(PARCHMENT, 2, 10))
	parent.add_child(p)
	return p


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


## Flat box with a thin ink border.
func _box(fill: Color, border: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = INK
	s.set_border_width_all(border)
	s.set_content_margin_all(margin)
	return s
