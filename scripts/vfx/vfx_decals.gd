## Flat ground marks (ink blots, splats, drops, cracks, scorch): thin opaque
## prisms just above the ground, one MultiMesh per shape with per-instance
## colours, each a ring buffer with a hard cap (the oldest is recycled). A
## decal spreads in over `spread` s, lies there and shrinks away over its
## last SHRINK_TIME s. Only decals that are spreading, shrinking or were moved
## are rewritten each frame.
extends RefCounted

const Meshes := preload("res://scripts/vfx/vfx_meshes.gd")
const SHRINK_TIME := 0.8

## Shape name -> cap at Full (about 160 in total).
const CAPS := {&"blob": 56, &"drop": 64, &"crack": 20, &"scorch": 20}

var _layers := {}   # StringName -> Layer


class Layer:
	var mm: MultiMesh
	var cap := 0
	var limit := 0
	var n := 0
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var size := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var spread := PackedFloat32Array()
	var col := PackedColorArray()

	func _init(c: int) -> void:
		cap = c
		limit = c
		pos.resize(c)
		yaw.resize(c)
		size.resize(c)
		age.resize(c)
		life.resize(c)
		spread.resize(c)
		col.resize(c)


func _init(parent: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var meshes := {
		&"blob": Meshes.blob(5),
		&"drop": Meshes.drop(),
		&"crack": Meshes.crack(9),
		&"scorch": Meshes.blob(21, 22, 0.18),
	}
	for k: StringName in CAPS:
		var l := Layer.new(int(CAPS[k]))
		l.mm = MultiMesh.new()
		l.mm.transform_format = MultiMesh.TRANSFORM_3D
		l.mm.use_colors = true
		l.mm.mesh = meshes[k]
		l.mm.instance_count = l.cap
		l.mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Decals_%s" % k
		mmi.multimesh = l.mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-300, -5, -300), Vector3(600, 10, 600))
		parent.add_child(mmi)
		_layers[k] = l


func set_full(full: bool) -> void:
	for l: Layer in _layers.values():
		l.limit = l.cap if full else maxi(1, l.cap / 2)


func has_shape(shape: StringName) -> bool:
	return _layers.has(shape)


## Lays a mark of `shape` at `pos` (y = its base height), turned `rot` around
## Y, `size` across (x) by `size * aspect` (z), for `life` s.
func add(shape: StringName, pos: Vector3, rot: float, size: float, life: float, spread: float, color: Color,
		aspect := 1.0) -> void:
	var l: Layer = _layers.get(shape)
	if l == null or l.limit <= 0:
		return
	var i := l.n
	if l.n < l.limit:
		l.n += 1
	else:
		i = _oldest(l)
	l.pos[i] = pos
	l.yaw[i] = rot
	l.size[i] = Vector3(size, 1.0, size * aspect)
	l.age[i] = 0.0
	l.life[i] = maxf(life, SHRINK_TIME + spread + 0.05)
	l.spread[i] = spread
	l.col[i] = color
	l.mm.set_instance_color(i, color)
	_write(l, i)
	l.mm.visible_instance_count = l.n


func update(dt: float) -> void:
	for l: Layer in _layers.values():
		if l.n == 0:
			continue
		var i := 0
		var moved := false
		while i < l.n:
			var a := l.age[i] + dt
			if a >= l.life[i]:
				l.n -= 1
				if i < l.n:
					_move(l, l.n, i)
					moved = true
				continue
			l.age[i] = a
			if moved or a - dt < l.spread[i] or l.life[i] - a < SHRINK_TIME:
				_write(l, i)
			moved = false
			i += 1
		l.mm.visible_instance_count = l.n


func _write(l: Layer, i: int) -> void:
	var a := l.age[i]
	var s := 1.0
	var sp := l.spread[i]
	if sp > 0.0 and a < sp:
		var x := a / sp
		s = 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)
	var left := l.life[i] - a
	if left < SHRINK_TIME:
		s *= maxf(left / SHRINK_TIME, 0.0)
	s = maxf(s, 0.001)
	var sz := l.size[i]
	var b := Basis(Vector3.UP, l.yaw[i]) * Basis.from_scale(Vector3(sz.x * s, 1.0, sz.z * s))
	l.mm.set_instance_transform(i, Transform3D(b, l.pos[i]))


func _move(l: Layer, from: int, to: int) -> void:
	l.pos[to] = l.pos[from]
	l.yaw[to] = l.yaw[from]
	l.size[to] = l.size[from]
	l.age[to] = l.age[from]
	l.life[to] = l.life[from]
	l.spread[to] = l.spread[from]
	l.col[to] = l.col[from]
	l.mm.set_instance_color(to, l.col[to])


func _oldest(l: Layer) -> int:
	var best := 0
	var bf := -1.0
	for i in l.n:
		var f := l.age[i] / l.life[i]
		if f > bf:
			bf = f
			best = i
	return best


## Live marks (tests).
func count() -> int:
	var c := 0
	for l: Layer in _layers.values():
		c += l.n
	return c
