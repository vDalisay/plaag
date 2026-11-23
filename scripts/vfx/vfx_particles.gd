## One CPU-updated particle pool: a MultiMeshInstance3D (one draw call) with
## per-instance colours, `cap` slots, live particles packed in [0, n) and
## swap-removed when they die. When the pool is full the oldest particle (by
## life fraction) is recycled. Particles are opaque meshes, so the parchment
## shader outlines them; they grow in, hold and shrink to nothing (no alpha).
## update(delta) is called by the Vfx node with the scaled delta.
extends RefCounted

## Size over life: PUFF swells in and shrinks from 45%; DROP pops in, holds
## and shrinks from 55%; TICK holds to 50% then shrinks; FLAME is a puff
## whose height flickers.
enum Life { PUFF, DROP, TICK, FLAME }

var mmi: MultiMeshInstance3D
var mm: MultiMesh
var cap := 0
## Effective cap (half at Reduced).
var limit := 0
var n := 0
## True: particles have an orientation (strokes); false: axis-aligned (puffs).
var oriented := false

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _shape := PackedVector3Array()
var _floor := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _curve := PackedByteArray()
var _col := PackedColorArray()
var _basis: Array[Basis] = []


func _init(parent: Node3D, pool_name: String, mesh: Mesh, material: Material, capacity: int, is_oriented: bool) -> void:
	cap = capacity
	limit = capacity
	oriented = is_oriented
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.name = pool_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-300, -20, -300), Vector3(600, 80, 600))
	parent.add_child(mmi)
	_pos.resize(cap)
	_vel.resize(cap)
	_shape.resize(cap)
	_floor.resize(cap)
	_age.resize(cap)
	_life.resize(cap)
	_grav.resize(cap)
	_drag.resize(cap)
	_seed.resize(cap)
	_curve.resize(cap)
	_col.resize(cap)
	_basis.resize(cap)


func set_full(full: bool) -> void:
	limit = cap if full else maxi(1, cap / 2)


func clear() -> void:
	n = 0
	mm.visible_instance_count = 0


## Starts one particle. `shape` is its full-size scale (x, y, z), `axis` the
## direction its local Z points along (oriented pools; ZERO = random),
## `floor_y` where a falling particle comes to rest, `pre` seconds it is
## advanced at once (for effects shown while the world is about to pause).
func emit(pos: Vector3, vel: Vector3, shape: Vector3, life: float, curve: int, color: Color,
		grav := 0.0, drag := 0.0, axis := Vector3.ZERO, floor_y := -INF, pre := 0.0) -> void:
	if limit <= 0 or life <= 0.0:
		return
	var i := n
	if n < limit:
		n += 1
	else:
		i = _oldest()
	_pos[i] = pos
	_vel[i] = vel
	_shape[i] = shape
	_floor[i] = floor_y
	_age[i] = 0.0
	_life[i] = life
	_grav[i] = grav
	_drag[i] = drag
	_seed[i] = randf() * TAU
	_curve[i] = curve
	_col[i] = color
	if oriented:
		var z := axis.normalized() if axis.length_squared() > 0.000001 else Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
		var x := up.cross(z).normalized()
		_basis[i] = Basis(x, z.cross(x), z)
	mm.set_instance_color(i, color)
	if pre > 0.0:
		_step(i, pre)
	_write(i)
	mm.visible_instance_count = n


func update(dt: float) -> void:
	if n == 0:
		if mm.visible_instance_count != 0:
			mm.visible_instance_count = 0
		return
	var i := 0
	while i < n:
		if not _step(i, dt):
			n -= 1
			if i < n:
				_move(n, i)
			continue
		_write(i)
		i += 1
	mm.visible_instance_count = n


## Advances particle i; false once its life is over.
func _step(i: int, dt: float) -> bool:
	var age := _age[i] + dt
	if age >= _life[i]:
		return false
	_age[i] = age
	var v := _vel[i]
	var g := _grav[i]
	v.y -= g * dt
	var d := _drag[i]
	if d > 0.0:
		v *= maxf(0.0, 1.0 - d * dt)
	var p := _pos[i] + v * dt
	if p.y < _floor[i]:
		p.y = _floor[i]
		v = Vector3.ZERO
	_pos[i] = p
	_vel[i] = v
	return true


func _write(i: int) -> void:
	var f := _age[i] / _life[i]
	var s := 1.0
	var sh := _shape[i]
	match _curve[i]:
		Life.PUFF, Life.FLAME:
			var x := minf(f / 0.18, 1.0)
			s = (1.0 - (1.0 - x) * (1.0 - x)) * (1.0 - smoothstep(0.45, 1.0, f)) * lerpf(0.75, 1.15, f)
			if _curve[i] == Life.FLAME:
				sh.y *= 0.7 + 0.45 * absf(sin(_age[i] * 19.0 + _seed[i]))
		Life.DROP:
			s = minf(f / 0.08, 1.0) * (1.0 - smoothstep(0.55, 1.0, f))
		Life.TICK:
			s = minf(f / 0.1, 1.0) * (1.0 if f < 0.5 else (1.0 - f) * 2.0)
	sh *= maxf(s, 0.0001)
	var b: Basis
	if oriented:
		var o := _basis[i]
		b = Basis(o.x * sh.x, o.y * sh.y, o.z * sh.z)
	else:
		b = Basis.from_scale(sh)
	mm.set_instance_transform(i, Transform3D(b, _pos[i]))


## Copies particle `from` into slot `to` (swap-remove).
func _move(from: int, to: int) -> void:
	_pos[to] = _pos[from]
	_vel[to] = _vel[from]
	_shape[to] = _shape[from]
	_floor[to] = _floor[from]
	_age[to] = _age[from]
	_life[to] = _life[from]
	_grav[to] = _grav[from]
	_drag[to] = _drag[from]
	_seed[to] = _seed[from]
	_curve[to] = _curve[from]
	_col[to] = _col[from]
	_basis[to] = _basis[from]
	mm.set_instance_color(to, _col[to])


## The slot nearest the end of its life (recycled when the pool is full).
func _oldest() -> int:
	var best := 0
	var bf := -1.0
	for i in n:
		var f := _age[i] / _life[i]
		if f > bf:
			bf = f
			best = i
	return best
