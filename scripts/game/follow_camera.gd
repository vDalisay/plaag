## Top-down-ish camera that follows the Lead Rat with damping. Looks down at
## `pitch_deg` from `distance` units, and keeps its focus point clamped so the
## view doesn't stray far past the District bounds.
extends Camera3D

## The node to follow; if empty, the first node in group "lead_rat".
@export var target_path: NodePath
@export var pitch_deg := 62.0
@export var distance := 20.0
@export var fov_deg := 45.0
## Follow stiffness (1/s): higher = tighter follow.
@export var damping := 5.0
## District rectangle on the ground (x -> X, y -> Z).
@export var bounds := Rect2(-22.0, -22.0, 44.0, 44.0)
## How far (units) the view may show past the bounds.
@export var overshoot := 3.0

var _target: Node3D
var _focus := Vector3.ZERO


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = fov_deg
	rotation_degrees = Vector3(-pitch_deg, 0.0, 0.0)
	_find_target()
	if _target:
		_focus = _clamp_focus(_flat(_target.global_position))
	_place()


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_find_target()
		if _target == null:
			return
	var goal := _clamp_focus(_flat(_target.global_position))
	_focus = _focus.lerp(goal, 1.0 - exp(-damping * delta))
	_place()


## Snaps the view onto the target at once (after a respawn or teleport).
func snap() -> void:
	if _target:
		_focus = _clamp_focus(_flat(_target.global_position))
		_place()


func _find_target() -> void:
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		_target = get_tree().get_first_node_in_group("lead_rat") as Node3D


func _place() -> void:
	global_position = _focus + global_transform.basis.z * distance


func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


## Clamps the ground focus so the visible ground stays within bounds + overshoot.
## Extents are measured on the ground plane: the half width at the focus
## depth, and how far the top / bottom screen edges reach from the focus.
func _clamp_focus(f: Vector3) -> Vector3:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_v := deg_to_rad(fov_deg) * 0.5
	var pitch := deg_to_rad(pitch_deg)
	var height := distance * sin(pitch)
	var back := distance * cos(pitch)
	var half_w := distance * tan(half_v) * aspect
	var up_reach := height / tan(pitch - half_v) - back
	var down_reach := back - height / tan(minf(pitch + half_v, PI * 0.5 - 0.001))
	var lo_x := bounds.position.x + half_w - overshoot
	var hi_x := bounds.end.x - half_w + overshoot
	var lo_z := bounds.position.y + up_reach - overshoot
	var hi_z := bounds.end.y - down_reach + overshoot
	f.x = clampf(f.x, lo_x, hi_x) if lo_x <= hi_x else bounds.get_center().x
	f.z = clampf(f.z, lo_z, hi_z) if lo_z <= hi_z else bounds.get_center().y
	return f
