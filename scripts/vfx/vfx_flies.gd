## Flies: tiny ink specks on jittery paths round a node, all in one shared
## MultiMesh (cap MAX). Two kinds of attachment:
##   HEAD: 2-4 flies orbit a sick townsperson's head; dropped when it dies.
##   CORPSE: 3-5 flies settle on a corpse, crawl, hop up and land again, and
##           stay while the body is in group "corpses".
## A node that is hidden (indoors) shows none. Freed nodes are dropped.
## Off at Reduced (Settings.effects_level 0).
extends RefCounted

enum Mode { HEAD, CORPSE }

const MAX := 120
const HEAD_Y := 2.25
const CORPSE_Y := 0.42
## Tiny crisp darting ink motes instead of chunky spheres.
const FLY_SIZE := Vector3(0.045, 0.03, 0.07)

var enabled := true
var _mm: MultiMesh
var _time := 0.0
var _nodes: Array[Node3D] = []
var _mode := PackedInt32Array()
var _count := PackedInt32Array()
var _phase := PackedFloat32Array()
var _offset := PackedVector3Array()


func _init(parent: Node3D, material: Material, mesh: Mesh) -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Flies"
	mmi.multimesh = _mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-300, -5, -300), Vector3(600, 20, 600))
	parent.add_child(mmi)


## Attaches (or switches) `node`'s flies to `mode` with `count` flies,
## centred `offset` (world) from the node.
func attach(node: Node3D, mode: int, count: int, offset := Vector3.ZERO) -> void:
	var i := _nodes.find(node)
	if i < 0:
		_nodes.append(node)
		_mode.append(mode)
		_count.append(count)
		_phase.append(randf() * TAU)
		_offset.append(offset)
	else:
		_mode[i] = mode
		_count[i] = maxi(_count[i], count)
		_offset[i] = offset


func detach(node: Node3D) -> void:
	var i := _nodes.find(node)
	if i >= 0:
		_remove(i)


func attached(node: Node3D) -> bool:
	return _nodes.has(node)


func update(dt: float) -> void:
	_time += dt
	var shown := 0
	var i := 0
	while i < _nodes.size():
		var node := _nodes[i]
		if not is_instance_valid(node) or not node.is_inside_tree():
			_remove(i)
			continue
		var mode := _mode[i]
		if mode == Mode.CORPSE and not node.is_in_group("corpses"):
			_remove(i)
			continue
		if mode == Mode.HEAD and node.has_method("is_dead") and bool(node.call("is_dead")):
			_remove(i)
			continue
		i += 1
		if not enabled or not node.is_visible_in_tree():
			continue
		var c := node.global_position + _offset[i - 1]
		var ph := _phase[i - 1]
		for k in _count[i - 1]:
			if shown >= MAX:
				break
			var p := _head_fly(c, ph + k * 2.39, k) if mode == Mode.HEAD else _corpse_fly(c, ph + k * 2.39, k)
			var yaw := _time * 9.0 + ph + k
			_mm.set_instance_transform(shown, Transform3D(Basis(Vector3.UP, yaw).scaled(FLY_SIZE), p))
			shown += 1
	_mm.visible_instance_count = shown


## Orbits the head on a wobbly loop, with a fast buzz on top.
func _head_fly(c: Vector3, ph: float, k: int) -> Vector3:
	var t := _time
	var dir := 1.0 if k % 2 == 0 else -1.0
	var a := t * (3.2 + 0.8 * float(k % 3)) * dir + ph
	var r := 0.22 + 0.08 * sin(t * 5.2 + ph * 1.7)
	var y := HEAD_Y + 0.08 * sin(t * 4.4 + ph * 2.3)
	return c + Vector3(cos(a) * r, y, sin(a) * r)


func _corpse_fly(c: Vector3, ph: float, k: int) -> Vector3:
	var t := _time
	var a := t * (2.6 + 0.6 * float(k % 3)) + ph
	var r := 0.22 + 0.10 * sin(t * 3.1 + ph * 1.9)
	var lift := 0.12 + 0.14 * absf(sin(t * 1.7 + ph))
	return c + Vector3(cos(a) * r, CORPSE_Y + lift, sin(a) * r)


## Attachments (tests).
func count() -> int:
	return _nodes.size()


func _remove(i: int) -> void:
	_nodes.remove_at(i)
	_mode.remove_at(i)
	_count.remove_at(i)
	_phase.remove_at(i)
	_offset.remove_at(i)
