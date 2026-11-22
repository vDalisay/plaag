## The end-of-Round results screen (replaces the HUD's old end panel), over an
## ink-dimmed backdrop. open(result, info) fills it from the RoundDirector's
## result and tallies it Vampire Survivors style:
## * the title by reason ("The bells toll" / "The Lead Rat is dead" /
##   "<Warden> has fallen");
## * "The Round": time survived, townsfolk infected and dead, houses fallen,
##   peak Colony, Bites and Pups born, counting up one row at a time (ROW_TIME
##   s each);
## * "Earnings": Pestilence +N and Bones +N (the Exterminator bounty on its
##   own line), then the wallet before -> after;
## * a "Best Round" seal when the houses fallen beat the District's best
##   (Run.is_best_round(), checked before Run.finish_round() records it);
## * the Year block: "The Year turns: 1349 -> 1350" with Run.year_preview()
##   when the Lead Rat died, else "The Year holds at 1349"; and the
##   next-District note after a beaten Exterminator.
## Continue (a PromptHint for ui_accept in a focusable button) first skips the
## tally, then hands the result to Run.finish_round() and opens the Upgrade
## Tree (once). Values the Run can't give show "—".
class_name ResultsPanel
extends Control

signal continued

const ROW_TIME := 0.25
const NONE := "—"
const WAY_OPEN := "The way lies open"
const CITY_YOURS := "The city is yours"

var _result := {}
var _steps: Array[Callable] = []
var _t := 0.0
var _running := false
var _done := false
var _continued := false
var _continue: Button
var _seal: Control
var _best := false
var _card: PanelContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _title: Label
var _sub: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	visible = false


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	_apply()


## Fills and shows the screen. info: {title: String (the screen title),
## district_id, district_title, year: int, next_note: String}.
func open(result: Dictionary, info: Dictionary) -> void:
	_result = result
	for c in get_children():
		c.queue_free()
	_steps.clear()
	_build(info)
	visible = true
	modulate.a = 0.0
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	_t = 0.0
	_done = false
	_running = true
	_apply()
	_continue.grab_focus.call_deferred()


## Jumps the tally to the end.
func skip() -> void:
	_t = 1000.0
	_apply()


func is_tallying() -> bool:
	return _running and not _done


func _apply() -> void:
	for i in _steps.size():
		_steps[i].call(clampf((_t - float(i) * ROW_TIME) / ROW_TIME, 0.0, 1.0))
	if _t >= float(_steps.size()) * ROW_TIME and not _done:
		_done = true
		_running = false
		if _best and _seal != null:
			_seal.visible = true
			UiKit.punch(_seal, 0.35, 0.3)


func _on_continue_pressed() -> void:
	if not _done:
		skip()
		return
	if _continued:
		return
	_continued = true
	continued.emit()
	var run := get_node_or_null("/root/Run")
	if run == null:
		push_warning("Results: no Run autoload, restarting the Round instead")
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	run.call("finish_round", _result)
	run.call("open_tree")


# ---------------------------------------------------------------------- building
func _build(info: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiKit.INK, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PARCHMENT, 2, 22, 4))
	_card.custom_minimum_size = Vector2(820, 0)
	center.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_card.add_child(box)

	_title = UiKit.label(str(info.get("title", "The Round is over")), UiKit.SIZE_TITLE, UiKit.INK, 0, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var y: Variant = info.get("year")
	_sub = UiKit.label("%s  ·  Year of Our Lord %s" % [str(info.get("district_title", NONE)), str(y) if y is int else NONE],
		UiKit.SIZE_SMALL, UiKit.SEPIA)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	box.add_child(_rule())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	box.add_child(cols)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 4)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_left)
	var sep := VSeparator.new()
	sep.add_theme_stylebox_override("separator", _vline())
	cols.add_child(sep)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 4)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_right)

	# Left: the Round.
	_left.add_child(_header("The Round"))
	var st: Dictionary = _result.get("stats", {}) if _result.get("stats") is Dictionary else {}
	_count_row(_left, "", "Time survived", st.get("elapsed"), true)
	_count_row(_left, "pestilence", "Townsfolk infected", st.get("infected", _result.get("pestilence")))
	_count_row(_left, "skull", "Townsfolk dead", st.get("dead"))
	_count_row(_left, "house", "Houses fallen", st.get("houses_fallen"))
	_count_row(_left, "rat", "Peak Colony", st.get("peak_colony"))
	_count_row(_left, "", "Bites", st.get("bites"))
	_count_row(_left, "pup", "Pups born", st.get("pups_born"))

	# Right: earnings, wallet, the Year.
	_right.add_child(_header("Earnings"))
	var bounty := int(_result.get("bounty", 0))
	var p := int(_result.get("pestilence", 0))
	var b := int(_result.get("bones", 0))
	_count_row(_right, "pestilence", "Pestilence", p, false, "+")
	_count_row(_right, "bones", "Bones", b - bounty, false, "+")
	if bounty > 0:
		_count_row(_right, "bones", "Bounty", bounty, false, "+")
	_wallet_row(p, b)
	_right.add_child(_spacer(6))
	_year_block(info)

	# Bottom: the Best Round seal and Continue.
	box.add_child(_rule())
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 18)
	box.add_child(bottom)
	_continue = Button.new()
	_continue.name = "Continue"
	_continue.focus_mode = Control.FOCUS_ALL
	_continue.custom_minimum_size = Vector2(180, 40)
	var hint := PromptHint.make("ui_accept", "Continue", UiKit.SIZE_BODY)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_continue.add_child(hint)
	_continue.pressed.connect(_on_continue_pressed)
	bottom.add_child(_continue)
	var run := get_node_or_null("/root/Run")
	if run != null and bool(run.get("dev_mode")):
		bottom.add_child(UiKit.label("dev: R restarts the Round", UiKit.SIZE_SMALL, UiKit.SEPIA))

	_seal = _make_seal()
	_card.add_child(_seal)
	_seal.visible = false
	var did: Variant = info.get("district_id")
	_best = run != null and run.has_method("is_best_round") and did is String \
		and bool(run.call("is_best_round", did, st))


func _header(text: String) -> Label:
	var l := UiKit.label(text.to_upper(), UiKit.SIZE_SMALL, UiKit.SEPIA)
	return l


## A stat row: [icon] label ........ value, counting up from 0 in its step.
func _count_row(parent: Control, icon: String, text: String, value: Variant, as_time := false, prefix := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	if icon != "":
		row.add_child(IconRect.make(icon, 20))
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(20, 20)
		row.add_child(gap)
	var name_l := UiKit.label(text, UiKit.SIZE_BODY)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var val_l := UiKit.label(NONE, UiKit.SIZE_LARGE)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.custom_minimum_size.x = 70
	row.add_child(val_l)
	row.modulate.a = 0.0
	var known := value is int or value is float
	var target := float(value) if known else 0.0
	_steps.append(func(k: float) -> void:
		row.modulate.a = minf(1.0, k * 3.0)
		if not known:
			val_l.text = NONE
		elif as_time:
			var s := int(target * k)
			val_l.text = "%d:%02d" % [s / 60, s % 60]
		else:
			val_l.text = prefix + str(roundi(target * k)))


## Wallet before -> after (the Run's wallet plus this Round's earnings).
func _wallet_row(p: int, b: int) -> void:
	var run := get_node_or_null("/root/Run")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_right.add_child(_spacer(4))
	_right.add_child(row)
	row.add_child(UiKit.label("Wallet", UiKit.SIZE_BODY))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	var wp: Variant = run.get("pestilence") if run != null else null
	var wb: Variant = run.get("bones") if run != null else null
	row.add_child(IconRect.make("pestilence", 18))
	row.add_child(UiKit.label("%s → %s" % [str(wp), str(int(wp) + p)] if wp is int else NONE, UiKit.SIZE_BODY))
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	row.add_child(gap)
	row.add_child(IconRect.make("bones", 18))
	row.add_child(UiKit.label("%s → %s" % [str(wb), str(int(wb) + b)] if wb is int else NONE, UiKit.SIZE_BODY))
	row.modulate.a = 0.0
	_steps.append(func(k: float) -> void: row.modulate.a = k)


## "The Year turns / holds" and what changes, then the next-District note.
func _year_block(info: Dictionary) -> void:
	var run := get_node_or_null("/root/Run")
	var y: Variant = info.get("year")
	var died := str(_result.get("reason", "")) == "lead_rat_died"
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	_right.add_child(block)
	block.add_child(_header("The Year"))
	if not (y is int):
		block.add_child(UiKit.label(NONE, UiKit.SIZE_BODY))
	elif died:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.add_child(IconRect.make("hourglass", 18))
		head.add_child(UiKit.label("The Year turns: %d → %d" % [y, y + 1], UiKit.SIZE_BODY))
		block.add_child(head)
		var lines: Variant = []
		var did: Variant = info.get("district_id")
		if run != null and run.has_method("year_preview") and did is String:
			lines = run.call("year_preview", y, y + 1, did)
		if lines is Array and not (lines as Array).is_empty():
			for line: Variant in lines:
				var l := UiKit.label("·  " + str(line), UiKit.SIZE_SMALL, UiKit.SEPIA)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				block.add_child(l)
		else:
			block.add_child(UiKit.label("·  The town is much as it was", UiKit.SIZE_SMALL, UiKit.SEPIA))
	else:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.add_child(IconRect.make("hourglass", 18))
		head.add_child(UiKit.label("The Year holds at %d" % y, UiKit.SIZE_BODY))
		block.add_child(head)
	var note := str(info.get("next_note", ""))
	if note != "":
		block.add_child(_spacer(4))
		block.add_child(UiKit.label(note, UiKit.SIZE_BODY, UiKit.INK, 0, true))
	block.modulate.a = 0.0
	_steps.append(func(k: float) -> void: block.modulate.a = k)


## "<next District> lies open" for the District that requires `district_id`,
## "The city is yours" if none does, "The way lies open" without the Run data.
static func next_district_note(run: Node, district_id: String) -> String:
	if run == null or not run.has_method("district_defs"):
		return WAY_OPEN
	var defs: Variant = run.call("district_defs")
	if not (defs is Array) or (defs as Array).is_empty():
		return WAY_OPEN
	for d: Variant in defs:
		if not (d is Object):
			continue
		var req: Variant = (d as Object).get("requires")
		var id: Variant = (d as Object).get("id")
		if req is String and req == district_id and district_id != "" and id != district_id:
			var title: Variant = (d as Object).get("title")
			return "%s lies open" % (title if title is String and title != "" else str(id))
	return CITY_YOURS


func _rule() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = UiKit.INK_FADED
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	return s


func _vline() -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = UiKit.INK_FADED
	line.thickness = 1
	line.vertical = true
	return line


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## A round ink stamp "Best Round", tilted, at the card's top-right corner.
func _make_seal() -> Control:
	var s := _Seal.new()
	s.size_flags_horizontal = Control.SIZE_SHRINK_END
	s.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	s.custom_minimum_size = Vector2(96, 96)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


class _Seal extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_set_transform(c, -0.22, Vector2.ONE)
		draw_circle(Vector2.ZERO, r, Color(UiKit.PARCHMENT_LIGHT, 0.85))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, UiKit.INK, 3.0, true)
		draw_arc(Vector2.ZERO, r - 6.0, 0.0, TAU, 40, UiKit.INK, 1.2, true)
		var f := UiKit.display_font()
		for i in 2:
			var word: String = ["Best", "Round"][i]
			var fs := 20
			var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(-w * 0.5, -3.0 + 20.0 * i), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
