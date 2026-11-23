## Crows (graphics pass B.4): ink birds perched on roof ridges, fences and
## walls. They hop, peck and turn; when a rat comes within SCARE_RADIUS (on
## the ground plan) or a Vfx `disturbance` lands near them they scatter, fly a
## loop and land somewhere else. Extra crows gather on fallen houses.
## At most CAP crows: two pooled MultiMeshes (bodies, wings), CPU-updated,
## no nodes or allocations per frame.
extends Node3D

const WorldMesh := preload("res://scripts/world/world_mesh.gd")
const Props := preload("res://scripts/town_props.gd")

const CAP := 16
const SCARE_RADIUS := 3.0
const SCARE_CHECK := 0.2
const SCALE := 1.05
const FLY_HEIGHT := 8.0
enum { OFF, PERCHED, FLEE, LOOP, LAND }

## How many crows are about (before the fallen-house extras), and the cap.
var base_count := 9
var max_count := CAP
var reduce_motion := false

var _bodies: MultiMesh
var _wings: MultiMesh
var _rng := RandomNumberGenerator.new()
## Perch slots: {"root": Node3D or null, "local": Vector3, "yaw": float,
## "house": Node or null, "taken": int (crow index or -1), "test": bool}.
var _slots: Array[Dictionary] = []
var _dead_houses: Array[Node] = []
var _state := PackedInt32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _slot := PackedInt32Array()
var _timer := PackedFloat32Array()
var _anim := PackedFloat32Array()       # 0..1 progress of a hop / peck
var _anim_kind := PackedInt32Array()     # 0 none, 1 hop, 2 peck
var _flap := PackedFloat32Array()
var _lock := PackedFloat32Array()        # s until rats can scare it again
var _centre := PackedVector3Array()      # loop centre
var _angle := PackedFloat32Array()       # loop angle, sign = direction
var _check_left := 0.0
var _rats: Array[Node] = []
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))
var _bounds := Rect2(-22, -22, 44, 44)


func setup(kit: Props, bounds: Rect2, seed_value: int) -> void:
	_rng.seed = seed_value
	_bounds = bounds
	var mat := WorldMesh.vc_material()
	_bodies = WorldMesh.multimesh(self, WorldMesh.crow_body_mesh(kit), CAP, mat, false, "CrowBodies").multimesh
	_wings = WorldMesh.multimesh(self, WorldMesh.crow_wing_mesh(kit), CAP * 2, mat, false, "CrowWings").multimesh
	_state.resize(CAP)
	_slot.resize(CAP)
	_anim_kind.resize(CAP)
	_yaw.resize(CAP)
	_timer.resize(CAP)
	_anim.resize(CAP)
	_flap.resize(CAP)
	_lock.resize(CAP)
	_angle.resize(CAP)
	_pos.resize(CAP)
	_vel.resize(CAP)
	_centre.resize(CAP)
	for i in CAP:
		_state[i] = OFF
		_slot[i] = -1
		_bodies.set_instance_transform(i, _hidden)
		_wings.set_instance_transform(i * 2, _hidden)
		_wings.set_instance_transform(i * 2 + 1, _hidden)


## A perch: `local` in `root`'s frame (world if root is null), facing `yaw`.
func add_perch(root: Node3D, local: Vector3, yaw: float, house: Node = null, test := false) -> int:
	_slots.append({"root": root, "local": local, "yaw": yaw, "house": house, "taken": -1, "test": test})
	return _slots.size() - 1


## Seats the starting crows on random perches.
func populate() -> void:
	for i in mini(base_count, max_count):
		var s := _pick_slot(Vector3.INF)
		if s < 0:
			return
		_perch(i, s)


## A house fell: from now on crows like its ridge, and two more come.
func add_dead(house: Node) -> void:
	if not _dead_houses.has(house):
		_dead_houses.append(house)


## Scares every crow within `radius` (+ a margin) of `point` on the ground plan.
func disturb(point: Vector3, radius: float) -> void:
	var r := radius + 2.0
	for i in CAP:
		if _state[i] == PERCHED or _state[i] == LAND:
			if _flat_d2(_pos[i], point) < r * r:
				_scatter(i, point)


## --ambient-test: `n` crows on the ground round `centre`, safe from rats
## until they are scattered by scatter_test().
func test_near(centre: Vector3, n: int) -> void:
	base_count += n
	for k in n:
		var a := TAU * k / n + 0.3
		var p := centre + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.8, 2.4)
		var s := add_perch(null, Vector3(p.x, 0.0, p.z), _rng.randf() * TAU, null, true)
		var i := _free_crow()
		if i < 0:
			i = k
			_release(i)
		_perch(i, s)
		_lock[i] = 999.0


func scatter_test(centre: Vector3) -> int:
	var n := 0
	for i in CAP:
		if _state[i] == PERCHED and _slot[i] >= 0 and _slots[_slot[i]]["test"]:
			_scatter(i, centre)
			n += 1
	return n


func active_count() -> int:
	var n := 0
	for i in CAP:
		if _state[i] != OFF:
			n += 1
	return n


# ---------------------------------------------------------------------- update
func _process(delta: float) -> void:
	if _bodies == null:
		return
	_check_left -= delta
	var check := _check_left <= 0.0
	if check:
		_check_left = SCARE_CHECK
		_top_up()
	if check:
		_rats = get_tree().get_nodes_in_group("rats")
	for i in CAP:
		if _state[i] == OFF:
			continue
		if _state[i] == PERCHED:
			_lock[i] -= delta
			if check:
				_check_perch(i, _rats)
			if _state[i] == PERCHED:
				_update_perched(i, delta)
		else:
			_update_flying(i, delta)
		_draw(i)


func _check_perch(i: int, rats: Array[Node]) -> void:
	var slot: Dictionary = _slots[_slot[i]]
	var root: Node3D = slot["root"]
	if root != null and (not is_instance_valid(root) or root.global_transform.basis.y.length() < 0.9):
		_scatter(i, _pos[i] + Vector3(0, 0, 3))   # its house is being cut away
		return
	if _lock[i] > 0.0:
		return
	for r: Node in rats:
		var n3 := r as Node3D
		if n3 and n3.is_visible_in_tree() and _flat_d2(n3.global_position, _pos[i]) < SCARE_RADIUS * SCARE_RADIUS:
			_scatter(i, n3.global_position)
			return


func _update_perched(i: int, delta: float) -> void:
	_pos[i] = _slot_pos(_slot[i])
	_timer[i] -= delta
	if _anim_kind[i] != 0:
		_anim[i] += delta / (0.35 if _anim_kind[i] == 1 else 0.6)
		if _anim[i] >= 1.0:
			_anim_kind[i] = 0
			_anim[i] = 0.0
	if _timer[i] <= 0.0:
		_timer[i] = _rng.randf_range(1.0, 3.2)
		var roll := _rng.randf()
		if roll < 0.45:
			_anim_kind[i] = 2
		elif roll < 0.75:
			_anim_kind[i] = 1
			_yaw[i] += _rng.randf_range(-1.2, 1.2)
		_anim[i] = 0.0


func _update_flying(i: int, delta: float) -> void:
	_timer[i] -= delta
	var desired := Vector3.ZERO
	match _state[i]:
		FLEE:
			desired = _vel[i]
			if _timer[i] <= 0.0:
				_state[i] = LOOP
				_timer[i] = _rng.randf_range(2.2, 3.8)
		LOOP:
			var dir := signf(_angle[i])
			_angle[i] += dir * delta * 1.5
			var a := absf(_angle[i])
			var goal := _centre[i] + Vector3(cos(a), 0.0, sin(a)) * 3.5
			goal.y = FLY_HEIGHT + sin(a * 2.0) * 0.6
			desired = (goal - _pos[i]) * 2.0
			if _timer[i] <= 0.0:
				var s := _pick_slot(_pos[i])
				if s >= 0:
					_slots[s]["taken"] = i
					_slot[i] = s
					_state[i] = LAND
				else:
					_timer[i] = 1.0
		LAND:
			var target := _slot_pos(_slot[i])
			var to := target - _pos[i]
			var d := to.length()
			if d < 0.15:
				_perch(i, _slot[i])
				return
			# Glide in from above: keep height until close, then drop.
			var flat := Vector3(to.x, 0.0, to.z)
			desired = to.normalized() * minf(6.5, d * 2.2 + 0.8)
			if flat.length() > 3.0 and to.y < -0.5:
				desired.y = maxf(desired.y, -1.0)
	desired = desired.limit_length(7.0)
	_vel[i] = _vel[i].lerp(desired, 1.0 - exp(-3.5 * delta))
	_pos[i] += _vel[i] * delta
	if Vector2(_vel[i].x, _vel[i].z).length() > 0.3:
		_yaw[i] = lerp_angle(_yaw[i], atan2(_vel[i].x, _vel[i].z), 1.0 - exp(-6.0 * delta))
	var landing := _state[i] == LAND and _pos[i].distance_to(_slot_pos(_slot[i])) < 1.5
	_flap[i] += delta * (16.0 if not landing else 22.0) * (0.6 if _vel[i].y < -0.5 and not landing else 1.0)


func _draw(i: int) -> void:
	var b := Basis(Vector3.UP, _yaw[i])
	var p := _pos[i]
	if _state[i] == PERCHED:
		if _anim_kind[i] == 1:
			p.y += sin(PI * _anim[i]) * 0.16
		elif _anim_kind[i] == 2:
			b = b * Basis(Vector3.RIGHT, 0.55 * pow(sin(PI * _anim[i] * 2.0), 2.0))
		_bodies.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * SCALE), p))
		_wings.set_instance_transform(i * 2, _hidden)
		_wings.set_instance_transform(i * 2 + 1, _hidden)
		return
	var pitch := clampf(-_vel[i].y * 0.08, -0.4, 0.4)
	b = b * Basis(Vector3.RIGHT, pitch)
	var body := Transform3D(b.scaled(Vector3.ONE * SCALE), p)
	_bodies.set_instance_transform(i, body)
	var flap := sin(_flap[i]) * 0.85
	var shoulder := Vector3(0.07, 0.25, 0.02)
	var right := Transform3D(Basis(Vector3.BACK, flap), shoulder)
	var left := Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.BACK, flap), Vector3(-shoulder.x, shoulder.y, shoulder.z))
	_wings.set_instance_transform(i * 2, body * right)
	_wings.set_instance_transform(i * 2 + 1, body * left)


# ---------------------------------------------------------------------- states
func _perch(i: int, s: int) -> void:
	_release(i)
	_slots[s]["taken"] = i
	_slot[i] = s
	_state[i] = PERCHED
	_pos[i] = _slot_pos(s)
	_vel[i] = Vector3.ZERO
	var choices := [0.0, PI, PI * 0.5, -PI * 0.5]
	_yaw[i] = float(_slots[s]["yaw"]) + float(choices[_rng.randi() % 4]) + _rng.randf_range(-0.4, 0.4)
	_timer[i] = _rng.randf_range(0.5, 2.5)
	_anim_kind[i] = 0
	_lock[i] = 0.6


func _scatter(i: int, threat: Vector3) -> void:
	if _slot[i] >= 0 and _state[i] == PERCHED:
		_slots[_slot[i]]["taken"] = -1
	elif _slot[i] >= 0 and _state[i] == LAND:
		_slots[_slot[i]]["taken"] = -1
	_slot[i] = -1
	var away := Vector3(_pos[i].x - threat.x, 0.0, _pos[i].z - threat.z)
	if away.length() < 0.05:
		away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
	_state[i] = FLEE
	_timer[i] = _rng.randf_range(0.5, 0.8)
	_vel[i] = away * 4.5 + Vector3(0, 4.0, 0)
	_flap[i] = _rng.randf() * TAU
	var c := _pos[i] + away * 3.0
	c.x = clampf(c.x, _bounds.position.x + 3.0, _bounds.end.x - 3.0)
	c.z = clampf(c.z, _bounds.position.y + 3.0, _bounds.end.y - 3.0)
	_centre[i] = c
	var start := atan2(_pos[i].z - c.z, _pos[i].x - c.x)
	# Loop angle is kept positive; its sign picks the direction.
	_angle[i] = (fposmod(start, TAU) + 0.01) * (1.0 if _rng.randf() < 0.5 else -1.0)


func _release(i: int) -> void:
	if _slot[i] >= 0 and _slots[_slot[i]]["taken"] == i:
		_slots[_slot[i]]["taken"] = -1
	_slot[i] = -1
	_state[i] = OFF


## Brings the flock up to its size (a newcomer flies in from outside the
## District), or sends the surplus away when the cap drops.
func _top_up() -> void:
	var want := mini(base_count + 2 * _dead_houses.size(), max_count)
	var have := active_count()
	if have > want:
		for i in range(CAP - 1, -1, -1):
			if have <= want:
				break
			if _state[i] != OFF:
				_release(i)
				_bodies.set_instance_transform(i, _hidden)
				_wings.set_instance_transform(i * 2, _hidden)
				_wings.set_instance_transform(i * 2 + 1, _hidden)
				have -= 1
	elif have < want:
		var i := _free_crow()
		var s := _pick_slot(Vector3.INF)
		if i < 0 or s < 0:
			return
		var edge := Vector3(_rng.randf_range(_bounds.position.x, _bounds.end.x), FLY_HEIGHT + 2.0, _bounds.position.y - 6.0)
		_pos[i] = edge
		_vel[i] = Vector3(0, 0, 3)
		_slots[s]["taken"] = i
		_slot[i] = s
		_state[i] = LAND
		_flap[i] = 0.0


func _free_crow() -> int:
	for i in mini(max_count, CAP):
		if _state[i] == OFF:
			return i
	return -1


## A free perch (not a test one, its house standing, no rat within 5 u);
## prefers fallen houses' ridges. -1 if none.
func _pick_slot(near: Vector3) -> int:
	var lead := get_tree().get_first_node_in_group("lead_rat") as Node3D
	var dead_first := not _dead_houses.is_empty() and _rng.randf() < 0.65
	for pass_i in 2:
		var start := _rng.randi() % maxi(_slots.size(), 1)
		for k in _slots.size():
			var s := (start + k) % _slots.size()
			var slot: Dictionary = _slots[s]
			if slot["taken"] >= 0 or slot["test"]:
				continue
			if dead_first and pass_i == 0 and not _dead_houses.has(slot["house"]):
				continue
			var root: Node3D = slot["root"]
			if root != null and (not is_instance_valid(root) or root.global_transform.basis.y.length() < 0.95):
				continue
			var p := _slot_pos(s)
			if lead and _flat_d2(lead.global_position, p) < 36.0:
				continue
			if near.is_finite() and _flat_d2(near, p) < 4.0:
				continue
			return s
	return -1


func _slot_pos(s: int) -> Vector3:
	var slot: Dictionary = _slots[s]
	var root: Node3D = slot["root"]
	if root != null and is_instance_valid(root):
		return root.global_transform * (slot["local"] as Vector3)
	return slot["local"]


static func _flat_d2(a: Vector3, b: Vector3) -> float:
	return (a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)
