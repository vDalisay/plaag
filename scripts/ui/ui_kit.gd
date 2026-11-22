## Shared look for every 2D screen: palette, fonts, sizes, label settings,
## panel boxes, the button theme and input prompts. Static only; every screen
## uses this instead of its own copies so the HUD, Upgrade Tree, Scroll Map,
## title and pause menus read as one manuscript.
##
## Sizes are in the 1280x720 base resolution (project stretch mode
## canvas_items / expand scales them with the window).
##
## Colour rules (same as the world): ink and sepia on parchment. RED is the
## plague only (Infection, Pestilence, plague upgrades). AMBER is "you can act
## on this" (affordable node, ready ability, focus glow), used sparingly.
class_name UiKit
extends RefCounted

const PARCHMENT := Color(0.93, 0.88, 0.76)
const PARCHMENT_LIGHT := Color(0.97, 0.94, 0.86)
const PARCHMENT_DARK := Color(0.84, 0.77, 0.62)
## Translucent panel fill for HUD boxes over the world.
const PANEL_FILL := Color(0.93, 0.88, 0.76, 0.88)
const INK := Color(0.13, 0.10, 0.08)
const SEPIA := Color(0.36, 0.25, 0.15)
const INK_FADED := Color(0.13, 0.10, 0.08, 0.45)
const RED := Color(0.72, 0.12, 0.10)
const RED_DARK := Color(0.48, 0.07, 0.06)
const AMBER := Color(0.85, 0.55, 0.12)
## Text outline: a parchment halo so ink text reads over hatching.
const OUTLINE := Color(0.95, 0.91, 0.80, 0.9)

const SIZE_SMALL := 14
const SIZE_BODY := 18
const SIZE_LARGE := 24
const SIZE_TITLE := 36
const SIZE_HUGE := 56

const BODY_FONTS: Array[String] = ["Georgia", "Garamond", "Times New Roman", "serif"]
const DISPLAY_FONTS: Array[String] = ["Old English Text MT", "UnifrakturMaguntia", "Gabriola", "Georgia", "serif"]

## Gamepad button index -> name (Xbox layout, the Godot default).
const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start",
	7: "LS", 8: "RS", 9: "LB", 10: "RB", 11: "Up", 12: "Down", 13: "Left", 14: "Right"}
## Fallbacks when an action has no event of a kind (or doesn't exist).
const KEY_FALLBACK := {"ui_accept": "Enter", "ui_cancel": "Esc", "pause": "Esc", "raid": "Click"}
const PAD_FALLBACK := {"ui_accept": "A", "ui_cancel": "B", "pause": "Start", "raid": "A"}

static var _body: Font
static var _display: Font


static func body_font() -> Font:
	if _body == null:
		_body = _system_font(BODY_FONTS)
	return _body


static func display_font() -> Font:
	if _display == null:
		_display = _system_font(DISPLAY_FONTS)
	return _display


static func _system_font(names: Array[String]) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


## Label settings: body (or display) font, ink colour, parchment outline.
## outline 0 = none (for text on solid parchment panels).
static func label_settings(size: int = SIZE_BODY, color: Color = INK, outline: int = 0, display := false) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = display_font() if display else body_font()
	s.font_size = size
	s.font_color = color
	if outline > 0:
		s.outline_size = outline
		s.outline_color = OUTLINE
	return s


## A ready-made Label.
static func label(text: String, size: int = SIZE_BODY, color: Color = INK, outline: int = 0, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = label_settings(size, color, outline, display)
	return l


## Parchment panel with an ink border (HUD boxes, tooltips, menus).
static func panel_box(fill: Color = PANEL_FILL, border: int = 2, margin: int = 10, radius: int = 3) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = INK
	b.set_border_width_all(border)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	b.shadow_color = Color(0.13, 0.10, 0.08, 0.18)
	b.shadow_size = 4
	b.shadow_offset = Vector2(2, 3)
	return b


## Theme for every menu: serif font, ink-on-parchment buttons with clear
## hover / pressed / disabled states and a thick focus ring for gamepads.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = SIZE_BODY
	var normal := panel_box(PARCHMENT_LIGHT, 2, 0, 3)
	normal.shadow_size = 0
	_pad(normal, 18, 6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PARCHMENT_DARK.lightened(0.25)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = PARCHMENT_DARK
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(PARCHMENT_LIGHT, 0.5)
	disabled.border_color = INK_FADED
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = AMBER.darkened(0.25)
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(5)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	for type in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_disabled_color", type, INK_FADED)
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "TooltipPanel", panel_box(PARCHMENT_LIGHT, 2, 8))
	t.set_color("font_color", "TooltipLabel", INK)
	var grab := StyleBoxFlat.new()
	grab.bg_color = INK
	grab.set_corner_radius_all(6)
	var slider := StyleBoxFlat.new()
	slider.bg_color = PARCHMENT_DARK
	slider.border_color = INK
	slider.set_border_width_all(1)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	return t


static func _pad(b: StyleBoxFlat, h: int, v: int) -> void:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v


# ---------------------------------------------------------------- settings access
static func settings() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("Settings") if loop != null else null


static func reduce_motion() -> bool:
	var s := settings()
	return s != null and bool(s.get("reduce_motion"))


## Camera shake multiplier (0 = off).
static func shake_scale() -> float:
	var s := settings()
	if s == null:
		return 1.0
	return 0.0 if bool(s.get("reduce_motion")) else float(s.get("screen_shake"))


static func is_gamepad() -> bool:
	var s := settings()
	return s != null and s.has_method("is_gamepad") and bool(s.call("is_gamepad"))


# ---------------------------------------------------------------- input prompts
## The glyph text for `action` on the device the player last used, from the
## InputMap (so rebinding shows up), e.g. "Enter" / "A", "Esc" / "Start".
static func prompt(action: String) -> String:
	var pad := is_gamepad()
	if InputMap.has_action(action):
		for e: InputEvent in InputMap.action_get_events(action):
			if pad and e is InputEventJoypadButton:
				return PAD_NAMES.get(int(e.button_index), "Pad %d" % int(e.button_index))
			if not pad and e is InputEventKey:
				var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
				if e.physical_keycode != 0:
					code = DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
				var k := OS.get_keycode_string(code)
				return {"Escape": "Esc", "Space": "Space", "BackSpace": "Bksp"}.get(k, k)
			if not pad and e is InputEventMouseButton:
				return {MOUSE_BUTTON_LEFT: "Click", MOUSE_BUTTON_RIGHT: "Right-click"}.get(int(e.button_index), "Mouse")
	return str((PAD_FALLBACK if pad else KEY_FALLBACK).get(action, action))


## Plays a small punch-scale on `c` (pivot at its centre). No-op with reduced motion.
static func punch(c: Control, amount := 0.15, time := 0.18) -> void:
	if c == null or not c.is_inside_tree() or reduce_motion():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, time * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
