## Ripples on the well and fountain water (graphics pass B.7): thin blue
## rings that widen and then sink under the surface. A small pooled
## MultiMesh (RINGS per surface), CPU-updated.
extends Node3D

const WorldMesh := preload("res://scripts/world/world_mesh.gd")
const Props := preload("res://scripts/town_props.gd")

const RING := Color(0.30, 0.47, 0.72)
const RINGS := 3
const LIFE := 2.6

var _mm: MultiMesh
var _rng := RandomNumberGenerator.new()
var _centre := PackedVector3Array()     # per surface: water top centre
var _radius := PackedFloat32Array()     # per surface
var _left := PackedFloat32Array()       # per surface: s to the next ring
var _pos := PackedVector3Array()        # per ring
var _age := PackedFloat32Array()        # per ring, < 0 = idle
var _max_r := PackedFloat32Array()      # per ring
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))


## `surfaces`: Array of [centre: Vector3 (the water's top), radius: float].
func setup(kit: Props, surfaces: Array, seed_value: int) -> void:
	_rng.seed = seed_value
	if surfaces.is_empty():
		return
	for s: Array in surfaces:
		_centre.append(s[0])
		_radius.append(s[1])
		_left.append(_rng.randf_range(0.0, 1.0))
	var n := surfaces.size() * RINGS
	_mm = WorldMesh.multimesh(self, kit.torus(1.0, 0.09), n, kit.mat(RING), false, "Ripples").multimesh
	_pos.resize(n)
	_age.resize(n)
	_max_r.resize(n)
	for i in n:
		_age[i] = -1.0
		_mm.set_instance_transform(i, _hidden)


func _process(delta: float) -> void:
	if _mm == null:
		return
	for s in _centre.size():
		_left[s] -= delta
		if _left[s] <= 0.0:
			_left[s] = _rng.randf_range(0.7, 1.4)
			_spawn(s)
	for i in _age.size():
		if _age[i] < 0.0:
			continue
		_age[i] += delta
		var t := _age[i] / LIFE
		if t >= 1.0:
			_age[i] = -1.0
			_mm.set_instance_transform(i, _hidden)
			continue
		var r := lerpf(0.12, _max_r[i], 1.0 - pow(1.0 - t, 2.0))
		# Sinks under the surface over the last third instead of fading.
		var sink := smoothstep(0.65, 1.0, t) * 0.06
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, 0.35, r)), _pos[i] - Vector3(0, sink, 0)))


func _spawn(s: int) -> void:
	var base := s * RINGS
	var pick := base
	for k in RINGS:
		if _age[base + k] < 0.0:
			pick = base + k
			break
		if _age[base + k] > _age[pick]:
			pick = base + k
	var max_r := minf(0.75, _radius[s] * 0.45)
	var off := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, maxf(_radius[s] - max_r - 0.1, 0.0))
	_pos[pick] = _centre[s] + Vector3(off.x, 0.012, off.y)
	_max_r[pick] = max_r * _rng.randf_range(0.75, 1.0)
	_age[pick] = 0.0
