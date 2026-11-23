## The settings panel (scenes/ui/settings_panel.tscn), shared by the title
## screen and the pause menu: an ink-dimmed backdrop and a parchment card with
## one row per setting of the Settings autoload.
##
## Rows: Screen shake (slider 0-100%), Damage numbers (toggle), Reduce motion
## (toggle), HUD size (slider 80-140%), Effects (Full / Reduced), Fullscreen
## (toggle), then Back. Every
## change goes through Settings.set_value(); Back, B or Esc emits `closed` and
## frees the panel. Works while the tree is paused (process_mode always) and
## is fully navigable with the d-pad / stick / arrows (left / right move a
## slider). Initial focus is the first row. Without the Settings autoload the
## rows show "—" and do nothing.
extends Control

signal closed

const ROW_W := 460.0

var _settings: Node
var _rows: Array[Control] = []
var _values := {}               # key -> Label showing the value
var _controls := {}             # key -> Range / Button
var _choices := {}              # key -> [label for 0, label for 1] (two-way int settings)
var _back: Button
var _closing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_settings = UiKit.settings()
	_build()
	_sync()
	if _settings != null and _settings.has_signal("changed"):
		_settings.connect("changed", _sync)
	modulate.a = 0.0
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(self, "modulate:a", 1.0, 0.15)
	(func() -> void:
		if not _rows.is_empty():
			_rows[0].grab_focus()).call_deferred()


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel") or (InputMap.has_action("pause") and event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


## Emits `closed` and frees the panel (also what Back does).
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


# ---------------------------------------------------------------------- building
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiKit.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PARCHMENT_LIGHT, 2, 26, 4))
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var title := UiKit.label("Settings", UiKit.SIZE_TITLE, UiKit.INK, 0, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_rule())

	_slider_row(box, "Screen shake", "screen_shake", 0.0, 1.0, 0.05)
	_toggle_row(box, "Damage numbers", "damage_numbers")
	_toggle_row(box, "Reduce motion", "reduce_motion")
	_slider_row(box, "HUD size", "hud_scale", 0.8, 1.4, 0.05)
	_toggle_row(box, "Effects", "effects_level")
	_choices["effects_level"] = ["Reduced", "Full"]
	_toggle_row(box, "Fullscreen", "fullscreen")

	box.add_child(_rule())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 18)
	box.add_child(bottom)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(140, 40)
	_back.pressed.connect(close)
	bottom.add_child(_back)
	_rows.append(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var hint := PromptHint.make("ui_cancel", "Back")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(hint)

	# Up / down walk the rows in order and wrap; left / right stay in the row.
	for i in _rows.size():
		var c := _rows[i]
		c.focus_neighbor_top = c.get_path_to(_rows[posmod(i - 1, _rows.size())])
		c.focus_neighbor_bottom = c.get_path_to(_rows[posmod(i + 1, _rows.size())])
		c.focus_previous = c.focus_neighbor_top
		c.focus_next = c.focus_neighbor_bottom
		if c is Button:
			c.focus_neighbor_left = c.get_path_to(c)
			c.focus_neighbor_right = c.get_path_to(c)


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = ROW_W
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := UiKit.label(text, UiKit.SIZE_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _slider_row(parent: Control, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(190, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	s.add_theme_stylebox_override("focus", _focus_box())
	s.add_theme_icon_override("grabber", _grabber(false))
	s.add_theme_icon_override("grabber_highlight", _grabber(true))
	s.value_changed.connect(_on_slider.bind(key))
	s.mouse_entered.connect(s.grab_focus)
	row.add_child(s)
	var v := UiKit.label("—", UiKit.SIZE_BODY)
	v.custom_minimum_size.x = 58
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	_values[key] = v
	_controls[key] = s
	_rows.append(s)


func _toggle_row(parent: Control, text: String, key: String) -> void:
	var row := _row(parent, text)
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(110, 34)
	b.toggled.connect(_on_toggle.bind(key))
	b.mouse_entered.connect(b.grab_focus)
	row.add_child(b)
	_controls[key] = b
	_rows.append(b)


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(UiKit.INK, 0.6)
	r.custom_minimum_size = Vector2(ROW_W, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _focus_box() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = UiKit.AMBER.darkened(0.25)
	f.set_border_width_all(3)
	f.set_corner_radius_all(5)
	f.expand_margin_left = 6
	f.expand_margin_right = 6
	f.expand_margin_top = 2
	f.expand_margin_bottom = 2
	return f


## An ink disc with a parchment centre (amber ring when highlighted).
func _grabber(hi: bool) -> Texture2D:
	var n := 20
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5 - Vector2(0.5, 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d <= 9.0:
				col = UiKit.AMBER.darkened(0.2) if hi and d > 6.5 else UiKit.INK
				if d <= 4.0:
					col = UiKit.PARCHMENT_LIGHT
				col.a = clampf(9.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------- values
func _value(key: String) -> Variant:
	if _settings == null or not key in _settings:
		return null
	return _settings.get(key)


func _sync() -> void:
	for key: String in _controls:
		var v: Variant = _value(key)
		var c: Control = _controls[key]
		if c is Range:
			var r := c as Range
			r.set_value_no_signal(float(v) if v != null else r.min_value)
			r.editable = v != null
			(_values[key] as Label).text = "%d%%" % roundi(float(v) * 100.0) if v != null else "—"
		elif c is Button:
			var b := c as Button
			b.set_pressed_no_signal(bool(v) if v != null else false)
			b.text = "—" if v == null else ("On" if bool(v) else "Off")
			if v != null and _choices.has(key):
				b.text = str(_choices[key][1 if bool(v) else 0])
			b.disabled = v == null


func _on_slider(v: float, key: String) -> void:
	_apply(key, v)


func _on_toggle(on: bool, key: String) -> void:
	_apply(key, (1 if on else 0) if _choices.has(key) else on)


func _apply(key: String, v: Variant) -> void:
	if _settings == null or not _settings.has_method("set_value"):
		return
	_settings.call("set_value", key, v)
	_sync()
