## The ground area of a telegraphed attack or a lasting hazard (M6b). While it
## is active it is in group "danger_zones" so rats can steer out of it:
##   danger_center     world point on the ground (arc: where the swing starts)
##   danger_radius     bounding radius, for cheap culling
##   danger_time_left  seconds until impact; -1 = persistent (fire, trap)
##   danger_contains() the exact test: a circle, or an arc of `arc_half` rad
##                     either side of `arc_dir` (anything within `arc_feet`
##                     of the centre counts whatever the angle).
## The attacks test hits with the same static helpers, so what the zone says
## and what lands always agree. Owners set `danger_time_left` every frame and
## call `retire()` (out of the group at once, then freed) when it is done.
class_name DangerZone
extends Node3D

const GROUP := &"danger_zones"

var danger_center := Vector3.ZERO
var danger_radius := 1.0
var danger_time_left := -1.0
## 0 = a full circle.
var arc_half := 0.0
var arc_dir := Vector3.FORWARD
var arc_feet := 0.0


func set_circle(center: Vector3, radius: float, time_left: float) -> void:
	danger_center = Vector3(center.x, 0.0, center.z)
	danger_radius = radius
	danger_time_left = time_left
	arc_half = 0.0


func set_arc(origin: Vector3, dir: Vector3, radius: float, half: float, feet: float, time_left: float) -> void:
	danger_center = Vector3(origin.x, 0.0, origin.z)
	danger_radius = radius
	danger_time_left = time_left
	arc_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	arc_half = half
	arc_feet = feet


func activate() -> void:
	add_to_group(GROUP)


func is_active() -> bool:
	return is_in_group(GROUP)


## Leaves the group this very frame (queue_free alone would linger till its end).
func retire() -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	if not is_queued_for_deletion():
		queue_free()


func danger_contains(p: Vector3) -> bool:
	if arc_half <= 0.0:
		return circle_contains(danger_center, danger_radius, p)
	return arc_contains(danger_center, arc_dir, danger_radius, arc_half, arc_feet, p)


static func circle_contains(center: Vector3, radius: float, p: Vector3) -> bool:
	var dx := p.x - center.x
	var dz := p.z - center.z
	return dx * dx + dz * dz <= radius * radius


static func arc_contains(origin: Vector3, dir: Vector3, radius: float, half: float, feet: float, p: Vector3) -> bool:
	var d := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var l2 := d.length_squared()
	if l2 > radius * radius:
		return false
	if l2 <= feet * feet:
		return true
	return absf(dir.signed_angle_to(d, Vector3.UP)) <= half
