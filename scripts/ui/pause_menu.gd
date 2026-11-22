## The in-Round pause menu (the `pause` action; the HUD opens it, never after
## the Round has ended). Pauses the tree behind an ink-dimmed backdrop.
## Left column: Resume (initial focus), Settings (instances
## res://scenes/ui/settings_panel.tscn when it exists and waits for its
## `closed`), End the Round (confirm, then RoundDirector.end_round("timer"):
## earnings kept, the Year holds) and Quit to Title (confirm: this Round's
## earnings are lost; Transition.go() when that autoload exists, else
## change_scene_to_file). Right column: a Vampire Survivors-style stat sheet
## from Run.stat() and the unlocks, and "This Round" from the RoundDirector.
## `pause` or B / Esc backs out one level: confirm -> menu -> resume.
## Everything is read by duck typing; a missing value shows "—".
class_name PauseMenu
extends Control

signal resumed

const SETTINGS_SCENE := "res://scenes/ui/settings_panel.tscn"
const TITLE_SCENE := "res://scenes/ui/title.tscn"
const NONE := "—"
## Run.stat() rows: key, label, format (%s gets the number).
const STAT_ROWS := [
	["rat_speed", "Lead Rat speed", "%.1f"],
	["bite_range", "Bite range", "%.1f u"],
	["bite_cooldown", "Bite cooldown", "%.2f s"],
	["bite_chunk", "Bite strength", "%.1f"],
	["lethality", "Lethality", "×%.2f"],
	["carry_over", "Carry-over", "pct"],
]
const UNLOCKS := [["unlock_hide", "Hide"], ["unlock_raid", "Raid"], ["unlock_fleas", "Fleas"], ["unlock_contagion", "Contagion"]]

var director: Node

var _menu: VBoxContainer
var _resume: Button
var _settings_btn: Button
var _end_btn: Button
var _quit_btn: Button
var _confirm: PanelContainer
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
var _confirm_action := ""
var _sheet: VBoxContainer
var _settings_panel: Node
var _columns: HBoxContainer
var _last_focus: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	get_tree().paused = true
	_refresh_sheet()
	_show_confirm("")
	visible = true
	modulate.a = 0.0
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	_resume.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_close_settings()
	var ended: bool = director != null and is_instance_valid(director) and director.has_method("has_ended") \
		and bool(director.call("has_ended"))
	if not ended:
		get_tree().paused = false
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	get_viewport().set_input_as_handled()
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return  # the settings panel backs out itself (its `closed`)
	if _confirm.visible:
		_show_confirm("")
		return
	close()


# ---------------------------------------------------------------------- actions
func _on_settings() -> void:
	if not ResourceLoader.exists(SETTINGS_SCENE):
		return
	var scene := load(SETTINGS_SCENE) as PackedScene
	if scene == null:
		return
	_settings_panel = scene.instantiate()
	_settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_settings_panel)
	_columns.visible = false
	if _settings_panel.has_signal("closed"):
		_settings_panel.connect("closed", _close_settings, CONNECT_ONE_SHOT)


func _close_settings() -> void:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
	_settings_panel = null
	_columns.visible = true
	if visible:
		_settings_btn.grab_focus()


## action "" hides the confirm box and shows the menu again.
func _show_confirm(action: String) -> void:
	_confirm_action = action
	_confirm.visible = action != ""
	_menu.visible = action == ""
	match action:
		"end":
			_confirm_text.text = "End the Round now?\nYou keep what you have earned; the Year holds."
			_confirm_yes.text = "End the Round"
			_last_focus = _end_btn
		"quit":
			_confirm_text.text = "Quit to the title?\nThis Round's earnings are lost."
			_confirm_yes.text = "Quit"
			_last_focus = _quit_btn
	if action != "":
		_confirm_no.grab_focus()
	elif _last_focus != null and visible:
		_last_focus.grab_focus()
		_last_focus = null


func _on_confirm_yes() -> void:
	match _confirm_action:
		"end":
			visible = false
			if director != null and is_instance_valid(director) and director.has_method("end_round"):
				director.call("end_round", "timer")
			else:
				get_tree().paused = false
			resumed.emit()
		"quit":
			visible = false
			get_tree().paused = false
			var path := TITLE_SCENE if ResourceLoader.exists(TITLE_SCENE) \
				else str(ProjectSettings.get_setting("application/run/main_scene", ""))
			var t := get_node_or_null("/root/Transition")
			if t != null and t.has_method("go"):
				t.call("go", path)
			elif path != "":
				get_tree().change_scene_to_file(path)


# ---------------------------------------------------------------------- building
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiKit.INK, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 28)
	center.add_child(_columns)

	# Left: title and the buttons (or the confirm box in their place).
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PARCHMENT, 2, 22, 4))
	left.custom_minimum_size = Vector2(320, 0)
	_columns.add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 14)
	left.add_child(lbox)
	var title := UiKit.label("Paused", UiKit.SIZE_TITLE, UiKit.INK, 0, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbox.add_child(title)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	lbox.add_child(_menu)
	_resume = _button(_menu, "Resume", close)
	_settings_btn = _button(_menu, "Settings", _on_settings)
	_settings_btn.disabled = not ResourceLoader.exists(SETTINGS_SCENE)
	if _settings_btn.disabled:
		_settings_btn.tooltip_text = "Not available yet"
	_end_btn = _button(_menu, "End the Round", _show_confirm.bind("end"))
	_quit_btn = _button(_menu, "Quit to Title", _show_confirm.bind("quit"))

	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	lbox.add_child(_confirm)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 10)
	_confirm.add_child(cbox)
	_confirm_text = UiKit.label("", UiKit.SIZE_BODY)
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size.x = 270
	cbox.add_child(_confirm_text)
	_confirm_yes = _button(cbox, "Yes", _on_confirm_yes)
	_confirm_no = _button(cbox, "Back", _show_confirm.bind(""))
	_confirm.visible = false

	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 16)
	lbox.add_child(hints)
	hints.add_child(PromptHint.make("ui_accept", "Choose"))
	hints.add_child(PromptHint.make("ui_cancel", "Back"))

	# Right: the stat sheet.
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PARCHMENT, 2, 22, 4))
	right.custom_minimum_size = Vector2(340, 0)
	_columns.add_child(right)
	_sheet = VBoxContainer.new()
	_sheet.add_theme_constant_override("separation", 4)
	right.add_child(_sheet)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", UiKit.SIZE_BODY)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	parent.add_child(b)
	return b


## Rebuilds the stat sheet from the Run and the RoundDirector.
func _refresh_sheet() -> void:
	for c in _sheet.get_children():
		c.queue_free()
	var run := get_node_or_null("/root/Run")
	_sheet.add_child(_header("The Colony"))
	for row: Array in STAT_ROWS:
		var v: Variant = run.call("stat", row[0]) if run != null and run.has_method("stat") else null
		var text := NONE
		if v is float or v is int:
			text = ("%d%%" % roundi(float(v) * 100.0)) if row[2] == "pct" else (row[2] % float(v))
		_row(row[1], text)
	var unlocked: Array[String] = []
	for u: Array in UNLOCKS:
		if run != null and run.has_method("is_unlocked") and bool(run.call("is_unlocked", u[0])):
			unlocked.append(u[1])
	_row("Abilities", ", ".join(unlocked) if not unlocked.is_empty() else ("none yet" if run != null else NONE))
	_sheet.add_child(_gap())
	_sheet.add_child(_header("This Round"))
	var d := director if director != null and is_instance_valid(director) else null
	var el: Variant = d.get("elapsed") if d != null else null
	if el is float:
		var s := int(el)
		_row("Time", "%d:%02d" % [s / 60, s % 60])
	else:
		_row("Time", NONE)
	_row("Infected", _num(d, "pestilence"))
	_row("Dead", _num(d, "dead_count"))
	_row("Houses fallen", _num(d, "houses_fallen"))


func _num(d: Node, key: String) -> String:
	var v: Variant = d.get(key) if d != null else null
	return str(v) if v is int else NONE


func _header(text: String) -> Label:
	return UiKit.label(text.to_upper(), UiKit.SIZE_SMALL, UiKit.SEPIA)


func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	return c


func _row(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	_sheet.add_child(row)
	var l := UiKit.label(label, UiKit.SIZE_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := UiKit.label(value, UiKit.SIZE_BODY)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
