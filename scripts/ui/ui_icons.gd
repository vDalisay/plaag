## Small ink icons drawn with CanvasItem calls, shared by every screen so a
## currency or a rat looks the same in the HUD, the Upgrade Tree and the map.
## UiIcons.draw(ci, kind, center, size) from any _draw(); IconRect wraps one
## in a Control for containers.
##
## Kinds: "pestilence" (a red plague drop), "bones" (a crossed pair of
## bones), "rat", "pup", "skull", "house", "eye" (Vigilance), "hourglass"
## (time / Year), "door" (Hide), "raid" (an arrow into a house).
class_name UiIcons
extends RefCounted

const KINDS := ["pestilence", "bones", "rat", "pup", "skull", "house", "eye", "hourglass", "door", "raid"]


## Draws `kind` centred on `c`, fitting a `s` x `s` box. `ink` is the line /
## silhouette colour; plague icons keep their red.
static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, ink: Color = UiKit.INK) -> void:
	var r := s * 0.5
	var w := maxf(1.0, s / 14.0)
	match kind:
		"pestilence":
			var drop := PackedVector2Array()
			drop.append(c + Vector2(0, -r * 0.95))
			for i in 13:
				var a := PI * (-0.18 + 1.36 * float(i) / 12.0)
				drop.append(c + Vector2(cos(a), sin(a)) * r * 0.58 + Vector2(0, r * 0.32))
			ci.draw_colored_polygon(drop, UiKit.RED)
			drop.append(drop[0])
			ci.draw_polyline(drop, Color(ink, 0.9), w, true)
			ci.draw_circle(c + Vector2(-r * 0.2, r * 0.22), r * 0.12, Color(1, 1, 1, 0.35))
		"bones":
			for sgn: float in [-1.0, 1.0]:
				var d := Vector2(r * 0.62, r * 0.62 * sgn)
				ci.draw_line(c - d, c + d, ink, r * 0.26, true)
				for end: Vector2 in [c - d, c + d]:
					var n := d.normalized().orthogonal() * r * 0.13
					var out := (end - c).normalized() * r * 0.06
					ci.draw_circle(end + n + out, r * 0.17, ink)
					ci.draw_circle(end - n + out, r * 0.17, ink)
		"rat", "pup":
			var k := 1.0 if kind == "rat" else 0.72
			var body := c + Vector2(r * 0.12, r * 0.1) * k
			_ellipse(ci, body, Vector2(r * 0.55, r * 0.34) * k, ink)
			ci.draw_circle(body + Vector2(-r * 0.55, -r * 0.08) * k, r * 0.22 * k, ink)
			ci.draw_colored_polygon(PackedVector2Array([
				body + Vector2(-r * 0.95, -r * 0.02) * k,
				body + Vector2(-r * 0.62, -r * 0.2) * k,
				body + Vector2(-r * 0.62, r * 0.08) * k]), ink)
			ci.draw_circle(body + Vector2(-r * 0.5, -r * 0.3) * k, r * 0.1 * k, ink)
			var tail := PackedVector2Array()
			for i in 8:
				var t := float(i) / 7.0
				tail.append(body + Vector2(r * (0.5 + 0.45 * t), r * (0.05 - 0.35 * sin(t * PI))) * k)
			ci.draw_polyline(tail, ink, w, true)
		"skull":
			ci.draw_circle(c + Vector2(0, -r * 0.12), r * 0.62, ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.36, r * 0.2), Vector2(r * 0.72, r * 0.5)), ink)
			var paper := UiKit.PARCHMENT
			ci.draw_circle(c + Vector2(-r * 0.24, -r * 0.1), r * 0.16, paper)
			ci.draw_circle(c + Vector2(r * 0.24, -r * 0.1), r * 0.16, paper)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.08), c + Vector2(-r * 0.08, r * 0.24), c + Vector2(r * 0.08, r * 0.24)]), paper)
			for i in 3:
				var x := -r * 0.2 + r * 0.2 * i
				ci.draw_line(c + Vector2(x, r * 0.45), c + Vector2(x, r * 0.7), paper, w)
		"house":
			var pts := PackedVector2Array([c + Vector2(-r * 0.7, r * 0.75), c + Vector2(-r * 0.7, -r * 0.1),
				c + Vector2(0, -r * 0.8), c + Vector2(r * 0.7, -r * 0.1), c + Vector2(r * 0.7, r * 0.75)])
			pts.append(pts[0])
			ci.draw_polyline(pts, ink, w * 1.4, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.18, r * 0.25), Vector2(r * 0.36, r * 0.5)), ink)
		"door":
			var arch := PackedVector2Array([c + Vector2(-r * 0.5, r * 0.85)])
			for i in 9:
				var a := PI + PI * float(i) / 8.0
				arch.append(c + Vector2(cos(a) * r * 0.5, -r * 0.25 + sin(a) * r * 0.5))
			arch.append(c + Vector2(r * 0.5, r * 0.85))
			ci.draw_colored_polygon(arch, ink)
			ci.draw_circle(c + Vector2(r * 0.25, r * 0.25), r * 0.08, UiKit.PARCHMENT)
		"raid":
			draw(ci, "house", c + Vector2(r * 0.2, 0), s * 0.8, ink)
			ci.draw_line(c + Vector2(-r * 0.95, r * 0.35), c + Vector2(-r * 0.05, r * 0.35), ink, w * 1.6, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, r * 0.35), c + Vector2(-r * 0.3, r * 0.12), c + Vector2(-r * 0.3, r * 0.58)]), ink)
		"eye":
			var lid := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				lid.append(c + Vector2(lerpf(-r * 0.9, r * 0.9, t), -sin(t * PI) * r * 0.5))
			for i in range(15, 0, -1):
				var t := float(i) / 16.0
				lid.append(c + Vector2(lerpf(-r * 0.9, r * 0.9, t), sin(t * PI) * r * 0.5))
			lid.append(lid[0])
			ci.draw_polyline(lid, ink, w * 1.3, true)
			ci.draw_circle(c, r * 0.28, ink)
		"hourglass":
			var top := PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.8), c + Vector2(r * 0.5, -r * 0.8), c])
			var bot := PackedVector2Array([c, c + Vector2(r * 0.5, r * 0.8), c + Vector2(-r * 0.5, r * 0.8)])
			ci.draw_colored_polygon(bot, ink)
			top.append(top[0])
			ci.draw_polyline(top, ink, w * 1.3, true)
			ci.draw_line(c + Vector2(-r * 0.65, -r * 0.85), c + Vector2(r * 0.65, -r * 0.85), ink, w * 1.5)
			ci.draw_line(c + Vector2(-r * 0.65, r * 0.85), c + Vector2(r * 0.65, r * 0.85), ink, w * 1.5)
		_:
			ci.draw_circle(c, r * 0.4, ink)


static func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_colored_polygon(pts, col)
