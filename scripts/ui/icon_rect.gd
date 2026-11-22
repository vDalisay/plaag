## One UiIcons icon as a Control, for use inside containers:
## IconRect.make("bones", 22).
class_name IconRect
extends Control

var kind := "":
	set(v):
		kind = v
		queue_redraw()
var color := UiKit.INK:
	set(v):
		color = v
		queue_redraw()


static func make(p_kind: String, p_size := 22.0, p_color: Color = UiKit.INK) -> IconRect:
	var i := IconRect.new()
	i.kind = p_kind
	i.color = p_color
	i.custom_minimum_size = Vector2(p_size, p_size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	UiIcons.draw(self, kind, size * 0.5, minf(size.x, size.y), color)
