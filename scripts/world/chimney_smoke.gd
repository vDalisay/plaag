## Chimney smoke (graphics pass B.3): pale puffs rise from the chimneys of
## living houses, drift with the wind, swell and shrink away. One pooled,
## CPU-updated MultiMesh (a ring buffer with a hard cap, the oldest puff is
## recycled); opaque, so every puff gets the shader's ink outline.
## A dead house is cold (stop()); a house squashed by the occlusion cutaway
## emits nothing and its puffs shrink away fast.
extends Node3D

const WorldMesh := preload("res://scripts/world/world_mesh.gd")
const Props := preload("res://scripts/town_props.gd")

const SMOKE := Color(0.93, 0.90, 0.83)
const LIFE := 3.6
const RISE := 0.85
const WIND := Vector3(0.34, 0.0, -0.1)
const SIZE_START := 0.14
const SIZE_PEAK := 0.48

## Hard cap of live puffs (Full); Reduced uses half.
var cap := 72
var _mm: MultiMesh
var _pos := PackedVector3Array()
var _age := PackedFloat32Array()
var _size := PackedFloat32Array()
var _src := PackedInt32Array()
var _seed := PackedFloat32Array()
var _ring := 0
var _time := 0.0
## {"root": Node3D, "local": Vector3, "house": Node, "interval": float, "left": float, "on": bool}
var _emitters: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))


func setup(kit: Props, cap_full: int, seed_value: int) -> void:
	_rng.seed = seed_value
	var mmi := WorldMesh.multimesh(self, kit.sphere(1.0, 10), cap_full, kit.mat(SMOKE), false, "Puffs")
	_mm = mmi.multimesh
	_pos.resize(cap_full)
	_age.resize(cap_full)
	_size.resize(cap_full)
	_src.resize(cap_full)
	_seed.resize(cap_full)
	for i in cap_full:
		_age[i] = -1.0
		_mm.set_instance_transform(i, _hidden)
	cap = cap_full


## A chimney: `local` is its cap top in `root`'s frame. `interval` s between puffs.
func add_emitter(root: Node3D, local: Vector3, house: Node, interval: float) -> void:
	_emitters.append({"root": root, "local": local, "house": house, "interval": interval,
		"left": _rng.randf_range(0.0, interval), "on": true})


## Stops the chimneys of `house` (it has died).
func stop(house: Node) -> void:
	for e in _emitters:
		if e["house"] == house:
			e["on"] = false


## Live puffs at most `n` (<= the pool size).
func set_cap(n: int) -> void:
	cap = clampi(n, 1, _age.size())
	for i in range(cap, _age.size()):
		if _age[i] >= 0.0:
			_age[i] = -1.0
			_mm.set_instance_transform(i, _hidden)
	_ring = _ring % cap


func _process(delta: float) -> void:
	if _mm == null:
		return
	_time += delta
	for ei in _emitters.size():
		var e := _emitters[ei]
		if not e["on"]:
			continue
		var root: Node3D = e["root"]
		if not is_instance_valid(root):
			e["on"] = false
			continue
		e["left"] = float(e["left"]) - delta
		if float(e["left"]) > 0.0:
			continue
		e["left"] = float(e["interval"]) * _rng.randf_range(0.75, 1.3)
		if root.global_transform.basis.y.length() < 0.95:
			continue  # squashed by the cutaway
		_emit(root.global_transform * (e["local"] as Vector3), ei)
	for i in cap:
		var age := _age[i]
		if age < 0.0:
			continue
		var src := _src[i]
		var fast := 1.0
		if src >= 0 and src < _emitters.size():
			var root: Node3D = _emitters[src]["root"]
			if is_instance_valid(root) and root.global_transform.basis.y.length() < 0.95:
				fast = 4.0
		age += delta * fast
		if age >= LIFE:
			_age[i] = -1.0
			_mm.set_instance_transform(i, _hidden)
			continue
		_age[i] = age
		var t := age / LIFE
		var sd := _seed[i]
		var drift := WIND * t + Vector3(sin(_time * 1.3 + sd) * 0.12, 0.0, cos(_time * 1.1 + sd) * 0.06)
		_pos[i] += (Vector3(0.0, RISE * (1.0 - t * 0.45), 0.0) + drift) * delta
		var s := lerpf(SIZE_START, SIZE_PEAK, 1.0 - pow(1.0 - minf(t * 1.6, 1.0), 2.0)) * _size[i]
		s *= 1.0 - smoothstep(0.62, 1.0, t)
		var b := Basis(Vector3.UP, sd + t * 0.8).scaled(Vector3(s, s * 0.82, s))
		_mm.set_instance_transform(i, Transform3D(b, _pos[i]))


func _emit(p: Vector3, src: int) -> void:
	var i := _ring
	_ring = (_ring + 1) % cap
	_pos[i] = p + Vector3(_rng.randf_range(-0.08, 0.08), 0.05, _rng.randf_range(-0.08, 0.08))
	_age[i] = 0.0
	_size[i] = _rng.randf_range(0.8, 1.2)
	_src[i] = src
	_seed[i] = _rng.randf() * TAU
