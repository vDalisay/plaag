## One house of the District: its collision body (layer 1), the door the
## townsfolk and rats use, and who lives and who is inside right now.
## The District builds the visual with Props.house() and passes the same
## numbers to setup(), which works out the door point and the roof planes.
## When every resident is dead the house is a dead house: an ink X is drawn
## across its roof (under the visual root, so it squashes with the cutaway).
class_name House
extends StaticBody3D

signal occupants_changed
signal house_died                            # every resident is dead (fires once)

const Props := preload("res://scripts/town_props.gd")
## How far in front of the facade (past the collider) the door point sits.
const DOOR_OUT := 0.55

var door_position: Vector3                   # world point just outside the door, on the ground
var door_normal: Vector3                     # points out of the house
var residents: Array[Node3D] = []            # townsfolk whose home is this house (set at spawn)
var occupants: Array[Node3D] = []            # townsfolk currently inside
## The visual root built by Props.house() (squashed by the cutaway).
var visual: Node3D
## Build order in the District layout (0..n-1), the same every time a layout
## seed is built; Run.best_dead_houses stores these.
var index: int

var _dead := false
var _props: Props
## Roof in the visual's local frame: eave line centre, length, depth, rise.
var _roof_base := Vector3.ZERO
var _roof_length := 0.0
var _roof_depth := 0.0
var _roof_rise := 0.0
var _shiver: Tween


func _ready() -> void:
	add_to_group("houses")


## Same numbers as passed to Props.house(): the door is in bay `door_bay` of
## `n_bays` across the facade (local +Z, at depth / 2); the collider reaches
## `front` (facade plus jetty and margin), so the door point sits DOOR_OUT past it.
func setup(root: Node3D, length: float, depth: float, top: float, jetty: float,
		pitch_deg: float, door_bay: int, n_bays: int, front: float, props: Props) -> void:
	visual = root
	_props = props
	var bw := length / n_bays
	var door_x := -length * 0.5 + (door_bay + 0.5) * bw
	var xf := root.global_transform
	door_position = xf * Vector3(door_x, 0.0, front + DOOR_OUT)
	door_position.y = 0.0
	door_normal = (xf.basis * Vector3(0, 0, 1)).normalized()
	door_normal.y = 0.0
	door_normal = door_normal.normalized()
	_roof_length = length + 0.7
	_roof_depth = depth + jetty + 0.7
	_roof_base = Vector3(0, top, jetty * 0.5)
	_roof_rise = _roof_depth * 0.5 * tan(deg_to_rad(pitch_deg))


# ---------------------------------------------------------------------- people
## Registers a townsperson whose home this is; watches it for death.
func add_resident(person: Node3D) -> void:
	if residents.has(person):
		return
	residents.append(person)
	var inf := person.get_node_or_null("Infection") as InfectionComponent
	if inf and not inf.died.is_connected(_check_dead):
		inf.died.connect(_check_dead)


## Called by Townsperson.go_inside (and start_indoors).
func enter(person: Node3D) -> void:
	if occupants.has(person):
		return
	occupants.append(person)
	occupants_changed.emit()


## Called by Townsperson.come_outside.
func leave(person: Node3D) -> void:
	if not occupants.has(person):
		return
	occupants.erase(person)
	occupants_changed.emit()


## Occupants that are still alive (infected or not).
func living_occupants() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p in occupants:
		if not is_instance_valid(p):
			continue
		var inf := p.get_node_or_null("Infection") as InfectionComponent
		if inf and not inf.is_dead():
			out.append(p)
	return out


## Living occupants not yet infected.
func healthy_occupants() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p in living_occupants():
		var inf := p.get_node("Infection") as InfectionComponent
		if not inf.is_infected():
			out.append(p)
	return out


func is_dead_house() -> bool:
	return _dead


func _check_dead() -> void:
	if _dead or residents.is_empty():
		return
	for p in residents:
		if not is_instance_valid(p):
			continue
		var inf := p.get_node_or_null("Infection") as InfectionComponent
		if inf and not inf.is_dead():
			return
	_dead = true
	_draw_roof_x()
	house_died.emit()


# ---------------------------------------------------------------------- feedback
## A Bite landed inside: a small red mark at the door and a shiver of the house.
func show_bite() -> void:
	if visual == null or _props == null:
		return
	var dot := Node3D.new()
	dot.name = "InsideBite"
	get_parent().add_child(dot)
	var side := door_normal.cross(Vector3.UP)
	dot.global_position = door_position - door_normal * 0.25 + side * randf_range(-0.5, 0.5)
	_props.ground_dot(dot, Vector3.ZERO, 0.16)
	var tw := dot.create_tween()
	tw.tween_property(dot, "scale", Vector3(0.2, 1.0, 0.2), 0.35).set_delay(0.05).set_ease(Tween.EASE_IN)
	tw.tween_callback(dot.queue_free)
	if _shiver and _shiver.is_valid():
		return
	_shiver = visual.create_tween()
	_shiver.tween_property(visual, "scale:x", 1.025, 0.05)
	_shiver.tween_property(visual, "scale:x", 0.99, 0.06)
	_shiver.tween_property(visual, "scale:x", 1.0, 0.06)


## Two hand-drawn ink strokes corner to corner across each roof slope, each
## built from a few jittered, tapering segments that appear one after another.
func _draw_roof_x() -> void:
	if visual == null or _props == null:
		return
	var x_root := Node3D.new()
	x_root.name = "DeadX"
	visual.add_child(x_root)
	var half := _roof_depth * 0.5
	var rh := _roof_rise
	var slope_len := sqrt(half * half + rh * rh)
	var a := _roof_length * 0.5 - 0.35
	var segments: Array[MeshInstance3D] = []
	for s: float in [1.0, -1.0]:
		var nrm := Vector3(0, half, s * rh) / slope_len
		var ridge := _roof_base + Vector3(0, rh, 0) + nrm * 0.14
		var eave := _roof_base + Vector3(0, 0, s * half) + nrm * 0.14
		# Keep the stroke ends a little in from the ridge and the eave.
		var top := ridge.lerp(eave, 0.1)
		var bottom := ridge.lerp(eave, 0.9)
		for d: float in [1.0, -1.0]:
			_stroke(x_root, top + Vector3(-a * d, 0, 0), bottom + Vector3(a * d, 0, 0), nrm, segments)
	for m in segments:
		m.visible = false
	var tw := x_root.create_tween()
	for m in segments:
		tw.tween_callback(m.show)
		tw.tween_interval(0.04)


func _stroke(parent: Node3D, from: Vector3, to: Vector3, nrm: Vector3, out: Array[MeshInstance3D]) -> void:
	var n := 4
	var across := (to - from).normalized().cross(nrm).normalized()
	var pts: Array[Vector3] = []
	for i in n + 1:
		var f := float(i) / n
		var wob := 0.0 if i == 0 or i == n else randf_range(-0.09, 0.09)
		pts.append(from.lerp(to, f) + across * wob)
	for i in n:
		# Thickest in the middle of the stroke, like a quill pressed harder.
		var w := 0.1 + 0.07 * sin(PI * (i + 0.5) / n)
		var seg := _props.strip(parent, pts[i], pts[i + 1] + (pts[i + 1] - pts[i]).normalized() * 0.05, w, Props.INK)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(seg)
