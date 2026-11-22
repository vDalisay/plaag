## An input prompt: a small ink key cap with the glyph for `action` on the
## device the player last used, then the verb ("[Enter] Continue",
## "[A] Continue"). Updates itself when the player switches device.
## Build with PromptHint.make("ui_accept", "Continue").
class_name PromptHint
extends HBoxContainer

var action := ""
var verb := ""
var font_size := UiKit.SIZE_SMALL
var color := UiKit.INK
## > 0: parchment outline on the verb (for hints over the world).
var outline := 0

var _cap: PanelContainer
var _cap_label: Label
var _verb_label: Label


static func make(p_action: String, p_verb: String, p_size: int = UiKit.SIZE_SMALL, p_outline := 0) -> PromptHint:
	var h := PromptHint.new()
	h.action = p_action
	h.verb = p_verb
	h.font_size = p_size
	h.outline = p_outline
	return h


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap = PanelContainer.new()
	var box := UiKit.panel_box(UiKit.PARCHMENT_LIGHT, 1, 0, 4)
	box.shadow_size = 0
	box.content_margin_left = 5
	box.content_margin_right = 5
	box.content_margin_top = 0
	box.content_margin_bottom = 1
	box.border_width_bottom = 2
	_cap.add_theme_stylebox_override("panel", box)
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Keep the key cap one text line tall even in a tall row (next to buttons).
	_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_cap)
	_cap_label = UiKit.label("", font_size, color)
	_cap.add_child(_cap_label)
	_verb_label = UiKit.label(verb, font_size, color, outline)
	add_child(_verb_label)
	refresh()
	var s := UiKit.settings()
	if s != null and s.has_signal("device_changed"):
		s.connect("device_changed", _on_device_changed)


func _on_device_changed(_device: int) -> void:
	refresh()


func set_verb(v: String) -> void:
	verb = v
	if _verb_label != null:
		_verb_label.text = v


func refresh() -> void:
	if _cap_label != null:
		_cap_label.text = UiKit.prompt(action)
	if _verb_label != null:
		_verb_label.text = verb
		_verb_label.visible = verb != ""
