## The title screen (scenes/ui/title.tscn, the project's main scene): the demo
## town (res://scenes/main.tscn) in the parchment look behind a slowly
## drifting camera, "Plaag" in the display font and a menu: Continue (only
## with a save; "Year 1349 · 54 P · 24 B", opens the Upgrade Tree), New
## Plague (asks "Burn the old Run?" first when a save exists, then
## Run.reset() and straight into a Round in the slums), Settings (the shared
## settings panel) and Quit. Initial focus is the first button; B / Esc in
## the confirm or the settings goes back, on the menu it moves to Quit.
##
## The demo town is instanced with its own script swapped for _Backdrop, a
## subclass that builds the same town but skips demo_town.gd's command-line
## handling, so --screenshot here never triggers the demo's own screenshot.
##
## Forwarding (keeps every District debug flag working with the title as the
## main scene): when OS.get_cmdline_user_args() holds any argument other than
## the title's own (--screenshot=, --screenshot-delay=, --title,
## --settings-test), the title goes straight to the District
## (res://scenes/game/district.tscn) without building anything. Launching
## res://scenes/ui/title.tscn explicitly (the path is in
## OS.get_cmdline_args()) or passing --title always shows the title.
##
## Run access is duck typed: Run.has_save() if A added it, else the save file
## (user://plaag_run.cfg) exists. Debug flags (after `--`): --screenshot=<path>
## (saves a frame after --screenshot-delay=<s>, default 1.5 s, and quits),
## --settings-test (opens the settings panel), --title.
extends Control

const DISTRICT_SCENE := "res://scenes/game/district.tscn"
const TREE_SCENE := "res://scenes/ui/upgrade_tree.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_panel.tscn"
const BACKDROP_SCENE := "res://scenes/main.tscn"
const SAVE_FALLBACK := "user://plaag_run.cfg"
const OWN_FLAGS := ["--title", "--settings-test"]
const OWN_PREFIXES := ["--screenshot=", "--screenshot-delay="]


## demo_town.gd without its _ready() argument handling; drifts the camera.
class _Backdrop extends "res://scripts/demo_town.gd":
	## Degrees of slow sway around the look-at point, and its period in s.
	const DRIFT_YAW := 7.0
	const DRIFT_PERIOD := 38.0
	var _t := 0.0

	func _ready() -> void:
		_setup_view()
		_k = Props.new(11)
		_build_town()

	func _process(delta: float) -> void:
		_t += delta
		var a := sin(_t * TAU / DRIFT_PERIOD)
		var yaw := deg_to_rad(DRIFT_YAW * a)
		var pitch := deg_to_rad(camera_pitch_deg + 2.0 * sin(_t * TAU / (DRIFT_PERIOD * 1.7)))
		var b := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
		_camera.basis = b
		_camera.position = look_at_point + Vector3(0.6 * a, 0, 0) + b.z * (camera_distance - 1.5 * cos(_t * TAU / DRIFT_PERIOD))


var _run: Node
var _menu: VBoxContainer
var _buttons: Array[Button] = []
var _continue: Button
var _quit: Button
var _confirm: Control
var _confirm_keep: Button
var _settings_panel: Node
var _focus_before: Control


func _ready() -> void:
	if _should_forward():
		set_process(false)
		(func() -> void: get_tree().change_scene_to_file(DISTRICT_SCENE)).call_deferred()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	_run = get_node_or_null("/root/Run")
	_add_backdrop()
	_build()
	_buttons[0].grab_focus()
	_intro()
	_apply_debug_args()


## True when a user argument is not one of the title's own and the title was
## not asked for explicitly.
static func _should_forward() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--title"):
		return false
	for a in OS.get_cmdline_args():
		if a.ends_with("scenes/ui/title.tscn"):
			return false
	for a in args:
		if a in OWN_FLAGS:
			continue
		var own := false
		for p: String in OWN_PREFIXES:
			if a.begins_with(p):
				own = true
		if not own:
			return true
	return false


# ---------------------------------------------------------------------- Run access
func _has_save() -> bool:
	if _run != null and _run.has_method("has_save"):
		return bool(_run.call("has_save"))
	var path := SAVE_FALLBACK
	if _run != null and _run.get("save_path") != null:
		path = str(_run.get("save_path"))
	return FileAccess.file_exists(path)


func _run_int(key: String) -> String:
	if _run == null or _run.get(key) == null:
		return "—"
	return str(int(_run.get(key)))


# ---------------------------------------------------------------------- actions
func _on_continue() -> void:
	if _run != null and _run.has_method("open_tree"):
		_run.call("open_tree")
	else:
		_go(TREE_SCENE)


func _on_new() -> void:
	if _has_save():
		_open_confirm()
	else:
		_start_new()


func _start_new() -> void:
	if _run != null and _run.has_method("reset"):
		_run.call("reset")
	if _run != null and _run.get("current_district") != null:
		_run.set("current_district", "slums")
	if _run != null and _run.has_method("start_round"):
		_run.call("start_round")
	else:
		_go(DISTRICT_SCENE)


func _on_settings() -> void:
	if _settings_panel != null or not ResourceLoader.exists(SETTINGS_SCENE):
		return
	_focus_before = get_viewport().gui_get_focus_owner()
	_settings_panel = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	add_child(_settings_panel)
	_settings_panel.connect("closed", _on_settings_closed)


func _on_settings_closed() -> void:
	_settings_panel = null
	if _focus_before != null and is_instance_valid(_focus_before):
		_focus_before.grab_focus()
	else:
		_buttons[0].grab_focus()


func _go(path: String) -> void:
	var t := get_node_or_null("/root/Transition")
	if t != null and t.has_method("go"):
		t.call("go", path)
	else:
		get_tree().change_scene_to_file(path)


func _unhandled_input(event: InputEvent) -> void:
	if _settings_panel != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm != null and _confirm.visible:
			_close_confirm()
		elif get_viewport().gui_get_focus_owner() != _quit:
			_quit.grab_focus()


# ---------------------------------------------------------------------- confirm
func _open_confirm() -> void:
	_confirm.visible = true
	_menu.modulate.a = 0.35
	for b in _buttons:
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_keep.grab_focus()


func _close_confirm() -> void:
	_confirm.visible = false
	_menu.modulate.a = 1.0
	for b in _buttons:
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_filter = Control.MOUSE_FILTER_STOP
	_buttons[1 if _continue != null else 0].grab_focus()


# ---------------------------------------------------------------------- building
func _add_backdrop() -> void:
	if not ResourceLoader.exists(BACKDROP_SCENE):
		return
	var town := (load(BACKDROP_SCENE) as PackedScene).instantiate()
	town.set_script(_Backdrop)
	town.name = "Backdrop"
	add_child(town)
	move_child(town, 0)


func _build() -> void:
	# A wash of parchment behind the menu side so the text reads over the town.
	var wash := TextureRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.texture = _side_wash()
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(wash)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_left", 96)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var title := UiKit.label("Plaag", 96, UiKit.INK, 6, true)
	col.add_child(title)
	var sub := UiKit.label("The Black Death, as the rats remember it", UiKit.SIZE_LARGE, UiKit.SEPIA, 5)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 34
	col.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	col.add_child(_menu)
	if _has_save():
		_continue = _menu_button("Continue", _on_continue)
		var details := HBoxContainer.new()
		details.add_theme_constant_override("separation", 6)
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_child(UiKit.label("Year %s  ·" % _run_int("year"), UiKit.SIZE_SMALL, UiKit.SEPIA, 4))
		details.add_child(UiKit.label(_run_int("pestilence"), UiKit.SIZE_SMALL, UiKit.SEPIA, 4))
		details.add_child(IconRect.make("pestilence", 16))
		details.add_child(UiKit.label("·  " + _run_int("bones"), UiKit.SIZE_SMALL, UiKit.SEPIA, 4))
		details.add_child(IconRect.make("bones", 16))
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 8)
		pad.add_theme_constant_override("margin_top", -6)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(details)
		_menu.add_child(pad)
	_menu_button("New Plague", _on_new)
	_menu_button("Settings", _on_settings)
	_quit = _menu_button("Quit", get_tree().quit)
	for i in _buttons.size():
		var b := _buttons[i]
		b.focus_neighbor_top = b.get_path_to(_buttons[posmod(i - 1, _buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(_buttons[posmod(i + 1, _buttons.size())])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)

	# Hints, bottom left inside the safe margin.
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 22)
	hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	hints.offset_left = 96
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_child(PromptHint.make("ui_accept", "Choose", UiKit.SIZE_SMALL, 4))
	# Esc / B on the title moves the focus to Quit (console convention).
	hints.add_child(PromptHint.make("ui_cancel", "Quit", UiKit.SIZE_SMALL, 4))
	add_child(hints)

	_build_confirm()


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 48)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UiKit.SIZE_LARGE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void:
		if b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus())
	b.focus_entered.connect(UiKit.punch.bind(b, 0.04, 0.16))
	_menu.add_child(b)
	_buttons.append(b)
	return b


func _build_confirm() -> void:
	_confirm = CenterContainer.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	add_child(_confirm)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PARCHMENT_LIGHT, 2, 24, 4))
	_confirm.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	var q := UiKit.label("Burn the old Run?", UiKit.SIZE_TITLE, UiKit.INK, 0, true)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	var note := UiKit.label("This cannot be undone. Your Year, wallet and every\nupgrade go into the fire. Settings are kept.", UiKit.SIZE_BODY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_confirm_keep = Button.new()
	_confirm_keep.text = "Keep it"
	_confirm_keep.custom_minimum_size = Vector2(150, 44)
	_confirm_keep.pressed.connect(_close_confirm)
	row.add_child(_confirm_keep)
	var burn := Button.new()
	burn.text = "Burn it"
	burn.custom_minimum_size = Vector2(150, 44)
	burn.pressed.connect(_start_new)
	row.add_child(burn)
	for b: Button in [_confirm_keep, burn]:
		b.mouse_entered.connect(b.grab_focus)
	_confirm_keep.focus_neighbor_left = _confirm_keep.get_path_to(burn)
	_confirm_keep.focus_neighbor_right = _confirm_keep.get_path_to(burn)
	burn.focus_neighbor_left = burn.get_path_to(_confirm_keep)
	burn.focus_neighbor_right = burn.get_path_to(_confirm_keep)
	for b: Button in [_confirm_keep, burn]:
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
	var hint := HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_child(PromptHint.make("ui_cancel", "Keep it"))
	box.add_child(hint)


## Parchment on the left fading to clear on the right (a 256 x 1 gradient).
func _side_wash() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(UiKit.PARCHMENT, 0.82), Color(UiKit.PARCHMENT, 0.6), Color(UiKit.PARCHMENT, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.32, 0.62])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 4
	return t


## The menu fades up.
func _intro() -> void:
	_menu.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(_menu, "modulate:a", 1.0, 0.35)


# ---------------------------------------------------------------------- debug
func _apply_debug_args() -> void:
	var shot := ""
	var delay := 1.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			shot = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-delay="):
			delay = float(arg.trim_prefix("--screenshot-delay="))
		elif arg == "--settings-test":
			_on_settings.call_deferred()
	if not shot.is_empty():
		_screenshot(shot, delay)


func _screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved to ", path)
	get_tree().quit()
