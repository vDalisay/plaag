## World feedback drawn over the 3D view and under the HUD panels: the HUD adds
## it as its first child, full screen and unscaled, so world points map 1:1
## through camera.unproject_position. Everything is drawn in one _draw:
## * Infection bars: a 30x4 red bar in an ink frame over the head of every
##   living, infected, outdoor, on-screen townsperson (group "townsfolk";
##   Exterminators and their pets excluded, they have the boss bar). It fades
##   in on infection and gets a thin pulsing frame above PULSE_AT %.
## * Bite numbers (Settings.damage_numbers): add_bite() sums each target's
##   Bites over NUMBER_WINDOW s, then "+7" in sepia rises 20 px and fades over
##   0.7 s. At most NUMBER_MAX alive (the oldest is reused).
## * Flying payouts (Nodebuster): add_payout() pops a currency icon at the
##   world point and flies it on a curve to `target_for.call(kind)` (the
##   HUD's wallet counter) in FLY_TIME s, then emits `landed(kind, amount)`.
##   At most FLY_MAX in flight; beyond that the amount joins the newest icon of
##   that kind. With reduced motion it lands at once. pending(kind) is what is
##   still in the air, so the HUD shows the wallet minus that.
## * Off-screen arrow: while a living Exterminator (group "exterminator") is
##   off-screen, an ink arrow with a small skull at the screen edge (inside
##   the safe margin) points at it.
## * Hit vignette: flash_hit() darkens the screen edges with ink for 0.35 s.
## Missing camera / nodes simply draw nothing.
class_name WorldOverlay
extends Control

signal landed(kind: String, amount: int)

const BAR_SIZE := Vector2(30, 4)
## Bar height above a townsperson's feet (u).
const HEAD_HEIGHT := 2.75
const BAR_FADE := 0.3
const PULSE_AT := 80.0
const NUMBER_WINDOW := 0.35
const NUMBER_RISE := 20.0
const NUMBER_TIME := 0.7
const NUMBER_MAX := 24
const NUMBER_HEIGHT := 3.1
const FLY_TIME := 0.6
const FLY_POP := 0.12
const FLY_MAX := 12
const FLY_ICON := 22.0
## Payouts start this high above the person (u).
const FLY_HEIGHT := 1.6
const SAFE_MARGIN := 24.0
const ARROW_INSET := 30.0
const VIGNETTE_TIME := 0.35
const VIGNETTE_DEPTH := 110.0

## kind -> screen position of its wallet counter (set by the HUD).
var target_for: Callable
## The off-screen arrow stays below this y (the HUD's top bar), set by the HUD.
var top_inset := 0.0

var _time := 0.0
var _bar_age := {}          # instance id -> seconds since its bar appeared
var _bites := {}            # instance id -> [sum: float, left: float, node: Node3D]
var _numbers: Array = []    # [world: Vector3, text: String, age: float]
var _flights: Array = []    # [kind: String, amount: int, from: Vector2, age: float, bend: float]
var _vignette := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UiKit.body_font()


func _process(delta: float) -> void:
	_time += delta
	_vignette = maxf(0.0, _vignette - delta)
	# Close the Bite windows into floating numbers.
	for id: int in _bites.keys():
		var b: Array = _bites[id]
		b[1] -= delta
		if b[1] <= 0.0:
			_bites.erase(id)
			var n: Node3D = b[2]
			if is_instance_valid(n) and n.is_inside_tree():
				_spawn_number(n.global_position + Vector3.UP * NUMBER_HEIGHT, b[0])
	var i := 0
	while i < _numbers.size():
		_numbers[i][2] += delta
		if _numbers[i][2] >= NUMBER_TIME:
			_numbers.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _flights.size():
		var f: Array = _flights[i]
		f[3] += delta
		if f[3] >= FLY_TIME:
			_flights.remove_at(i)
			landed.emit(f[0], f[1])
		else:
			i += 1
	queue_redraw()


# ---------------------------------------------------------------------- API
## A Bite of `chunk` Infection landed on `target` (summed per target).
func add_bite(target: Node3D, chunk: float) -> void:
	if target == null or not is_instance_valid(target) or not _numbers_on():
		return
	if not target.is_in_group("townsfolk"):
		return  # indoors: the house shows the Bite
	var id := target.get_instance_id()
	if _bites.has(id):
		_bites[id][0] += chunk
	else:
		_bites[id] = [chunk, NUMBER_WINDOW, target]


## A currency payout earned at `world_pos`: flies an icon to the wallet.
func add_payout(kind: String, amount: int, world_pos: Vector3) -> void:
	if amount <= 0:
		return
	var cam := get_viewport().get_camera_3d()
	var to := _target(kind)
	if UiKit.reduce_motion() or cam == null or to == Vector2.INF:
		landed.emit(kind, amount)
		return
	var at := world_pos + Vector3.UP * FLY_HEIGHT
	if cam.is_position_behind(at):
		landed.emit(kind, amount)
		return
	if _flights.size() >= FLY_MAX:
		for j in range(_flights.size() - 1, -1, -1):
			if _flights[j][0] == kind:
				_flights[j][1] += amount
				return
		landed.emit(kind, amount)
		return
	var from := cam.unproject_position(at)
	_flights.append([kind, amount, from, 0.0, randf_range(0.6, 1.0) * (1.0 if randf() < 0.5 else -1.0)])


## What of `kind` is still flying to the wallet.
func pending(kind: String) -> int:
	var n := 0
	for f: Array in _flights:
		if f[0] == kind:
			n += int(f[1])
	return n


## Lands every icon still in the air (the Round ended).
func land_all() -> void:
	for f: Array in _flights:
		landed.emit(f[0], f[1])
	_flights.clear()


## The ink vignette at the screen edges (the Lead Rat was hit).
func flash_hit() -> void:
	_vignette = VIGNETTE_TIME


func _numbers_on() -> bool:
	var s := UiKit.settings()
	return s == null or bool(s.get("damage_numbers"))


func _spawn_number(world: Vector3, amount: float) -> void:
	if _numbers.size() >= NUMBER_MAX:
		_numbers.remove_at(0)
	_numbers.append([world, "+%d" % maxi(1, roundi(amount)), 0.0])


func _target(kind: String) -> Vector2:
	if not target_for.is_valid():
		return Vector2.INF
	var v: Variant = target_for.call(kind)
	return v if v is Vector2 else Vector2.INF


# ---------------------------------------------------------------------- drawing
func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_draw_bars(cam)
		_draw_numbers(cam)
		_draw_boss_arrow(cam)
	_draw_flights()
	if _vignette > 0.0:
		_draw_vignette(_vignette / VIGNETTE_TIME)


func _draw_bars(cam: Camera3D) -> void:
	var view := Rect2(Vector2.ZERO, size).grow(-4.0)
	var seen := {}
	for n: Node in get_tree().get_nodes_in_group("townsfolk"):
		if n.is_in_group("exterminator") or n.is_in_group("exterminator_pets") or n.is_in_group("terrier"):
			continue
		var body := n as Node3D
		if body == null:
			continue
		var inf := body.get_node_or_null("Infection")
		if inf == null:
			continue
		var v: Variant = inf.get("value")
		if not (v is float) or float(v) <= 0.0 or (inf.has_method("is_dead") and inf.call("is_dead")):
			continue
		var head := body.global_position + Vector3.UP * HEAD_HEIGHT
		if cam.is_position_behind(head):
			continue
		var p := cam.unproject_position(head)
		if not view.has_point(p):
			continue
		var id := body.get_instance_id()
		var age: float = _bar_age.get(id, 0.0)
		seen[id] = age + get_process_delta_time()
		var a := clampf(age / BAR_FADE, 0.0, 1.0)
		var r := Rect2(p - BAR_SIZE * 0.5, BAR_SIZE)
		draw_rect(r.grow(1.0), Color(UiKit.PARCHMENT, 0.8 * a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(float(v) / 100.0, 0.0, 1.0), r.size.y)), Color(UiKit.RED, a))
		draw_rect(r.grow(1.0), Color(UiKit.INK, a), false, 1.0)
		if float(v) >= PULSE_AT:
			var pulse := 0.5 + 0.5 * sin(_time * 9.0 + float(id % 7))
			draw_rect(r.grow(2.5 + pulse * 1.5), Color(UiKit.RED, a * (0.25 + 0.5 * pulse)), false, 1.0)
	_bar_age = seen


func _draw_numbers(cam: Camera3D) -> void:
	var fs := UiKit.SIZE_BODY
	for num: Array in _numbers:
		var w: Vector3 = num[0]
		if cam.is_position_behind(w):
			continue
		var t: float = num[2] / NUMBER_TIME
		var p := cam.unproject_position(w) + Vector2(0, -NUMBER_RISE * t)
		var text: String = num[1]
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := p - Vector2(tw * 0.5, 0)
		var a := 1.0 - t * t
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(UiKit.OUTLINE, UiKit.OUTLINE.a * a))
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.SEPIA, a))


func _draw_flights() -> void:
	for f: Array in _flights:
		var to := _target(f[0])
		if to == Vector2.INF:
			continue
		var from: Vector2 = f[2]
		var age: float = f[3]
		var s := 1.0
		var pos := from
		if age < FLY_POP:
			var k := age / FLY_POP
			s = sin(k * PI * 0.5) * 1.3
		else:
			var k := clampf((age - FLY_POP) / (FLY_TIME - FLY_POP), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			var mid := (from + to) * 0.5
			var side: Vector2 = (to - from).orthogonal().normalized() * f[4] * minf(160.0, from.distance_to(to) * 0.35)
			var ctrl: Vector2 = mid + side + Vector2(0, -60)
			pos = from.lerp(ctrl, k).lerp(ctrl.lerp(to, k), k)
			s = lerpf(1.3, 0.8, k)
		var big: int = f[1]
		var px := FLY_ICON * s * (1.0 + minf(0.6, 0.08 * float(big - 1)))
		draw_circle(pos, px * 0.62, Color(UiKit.PARCHMENT_LIGHT, 0.85))
		UiIcons.draw(self, f[0], pos, px)


## The ink arrow + skull at the screen edge pointing at an off-screen Exterminator.
func _draw_boss_arrow(cam: Camera3D) -> void:
	var boss := _living_boss()
	if boss == null:
		return
	var at := boss.global_position + Vector3.UP * 1.0
	var behind := cam.is_position_behind(at)
	var p := cam.unproject_position(at)
	var inner := Rect2(Vector2.ZERO, size).grow(-SAFE_MARGIN)
	if not behind and inner.has_point(p):
		return
	# The arrow runs round the screen inside the safe margin, below the top bar.
	var edge := Rect2(Vector2.ZERO, size).grow(-(SAFE_MARGIN + ARROW_INSET))
	var top := top_inset + ARROW_INSET
	if top > edge.position.y and top < edge.end.y - 40.0:
		edge = Rect2(edge.position.x, top, edge.size.x, edge.end.y - top)
	var c := edge.get_center()
	var dir := (p - c) if not behind else (c - p)
	if dir.length_squared() < 0.01:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half := edge.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var tip := c + dir * t
	var n := dir.orthogonal()
	var bob := 3.0 * sin(_time * 6.0)
	tip += dir * bob
	var tri := PackedVector2Array([tip + dir * 20.0, tip - dir * 8.0 + n * 15.0, tip - dir * 8.0 - n * 15.0])
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), UiKit.OUTLINE, 5.0, true)
	draw_colored_polygon(tri, UiKit.INK)
	var skull_at := tip - dir * 30.0
	draw_circle(skull_at, 13.0, Color(UiKit.PARCHMENT_LIGHT, 0.9))
	draw_arc(skull_at, 13.0, 0.0, TAU, 24, UiKit.INK, 1.5, true)
	UiIcons.draw(self, "skull", skull_at, 18.0)


func _living_boss() -> Node3D:
	for n: Node in get_tree().get_nodes_in_group("exterminator"):
		var b := n as Node3D
		if b == null or not is_instance_valid(b) or b.get("is_beaten") == true:
			continue
		if b.get("has_arrived") == false and not b.is_inside_tree():
			continue
		return b
	return null


## Ink darkening at the four screen edges, fading inwards.
func _draw_vignette(k: float) -> void:
	var a := 0.55 * k
	var d := VIGNETTE_DEPTH
	var w := size.x
	var h := size.y
	var dark := Color(UiKit.INK, a)
	var clear := Color(UiKit.INK, 0.0)
	var quads := [
		[Vector2(0, 0), Vector2(w, 0), Vector2(w - d, d), Vector2(d, d)],
		[Vector2(w, 0), Vector2(w, h), Vector2(w - d, h - d), Vector2(w - d, d)],
		[Vector2(w, h), Vector2(0, h), Vector2(d, h - d), Vector2(w - d, h - d)],
		[Vector2(0, h), Vector2(0, 0), Vector2(d, d), Vector2(d, h - d)],
	]
	for q: Array in quads:
		draw_polygon(PackedVector2Array(q), PackedColorArray([dark, dark, clear, clear]))
