## A townsperson's telegraphed attack. While `enabled` and off cooldown, a rat
## within `weapon.reach` of the host starts an attack: the strike is fixed where
## that rat stood, and an INK telegraph on the ground fills in over the wind-up
## so the player can see when it lands and dodge. What lands depends on
## `weapon.kind` (see WeaponDef):
##   stomp: an ink ring at the point; calls `hit()` on every rat within radius.
##   club:  the same with a wide double ring: a slow, heavy stomp.
##   broom: an ink arc in front of the host; Pups in it get `hit()`, everything
##          else `knockback(from, strength)` (if the rat has the method).
##   torch: an ink landing circle at the rat; on impact a FirePatch (an AMBER
##          emissive disc) burns there and hits rats that stand in it.
## The telegraph and the fire patch are DangerZones (group "danger_zones")
## while they are live, so rats can see them coming.
## Impacts are pooled Vfx bursts (scripts/vfx/vfx.gd): stomp = a ring of dust
## puffs and a crack, club = an ink impact star, dust and a crack, broom = a
## dust arc and straw flecks; every strike also sends a Vfx `disturbance`.
class_name WeaponComponent
extends Node3D

const Props := preload("res://scripts/town_props.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")
## Crows scatter this far from a strike (Vfx.disturbance).
const DISTURB_RADIUS := 4.0
## Segments of the broom arc outline.
const ARC_SEGMENTS := 10
## Broom: rats this close to the wielder are swept whatever the angle.
const BROOM_FEET := 0.4

signal windup_started(point: Vector3)
signal struck(point: Vector3, hits: int)

@export var weapon: WeaponDef
## The host turns attacks on and off (only the FIGHT band attacks).
var enabled := true
## Wind-up length factor (infected people are slower, later Years faster).
var windup_multiplier := 1.0

var _props: Props
var _host: Node3D
var _cooldown_left := 0.0
var _windup_left := 0.0
var _windup_total := 0.0
var _point := Vector3.ZERO
var _origin := Vector3.ZERO   # broom: where the host stood when the wind-up began
var _dir := Vector3.FORWARD   # broom: flat direction of the sweep
var _ring: DangerZone
var _fill: Node3D


func _ready() -> void:
	_host = get_parent() as Node3D
	_props = Props.new(17)


func _physics_process(delta: float) -> void:
	if weapon == null:
		return
	if _windup_left > 0.0:
		_windup_left -= delta
		if _ring != null:
			_ring.danger_time_left = maxf(0.0, _windup_left)
		_update_ring()
		if _windup_left <= 0.0:
			_strike()
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not enabled or _cooldown_left > 0.0:
		return
	var target_pos := _rat_pos_in_reach()
	if target_pos != Vector3.INF:
		_begin(target_pos)


func kind() -> StringName:
	return weapon.kind if weapon != null else &"stomp"


func is_winding_up() -> bool:
	return _windup_left > 0.0


## 0 at the start of the wind-up, 1 at the impact.
func windup_progress() -> float:
	if _windup_total <= 0.0 or _windup_left <= 0.0:
		return 0.0
	return clampf(1.0 - _windup_left / _windup_total, 0.0, 1.0)


func strike_point() -> Vector3:
	return _point


func is_ready() -> bool:
	return weapon != null and _windup_left <= 0.0 and _cooldown_left <= 0.0


## How close the host wants to get to a rat: a torch is thrown from afar.
func preferred_range() -> float:
	if weapon != null and weapon.kind == &"torch":
		return weapon.reach * 0.7
	return 0.6


## Aborts a wind-up without striking (the host broke and ran, or died).
func cancel() -> void:
	if _windup_left <= 0.0:
		return
	_windup_left = 0.0
	_cooldown_left = weapon.cooldown * 0.5 if weapon else 0.0
	_free_ring()


func _colony() -> Colony:
	return get_tree().get_first_node_in_group("colony") as Colony


func _rat_pos_in_reach() -> Vector3:
	var c := _colony()
	if c != null and c.has_method("query_crowd"):
		var q: Dictionary = c.query_crowd(global_position, weapon.reach)
		if int(q["count"]) > 0:
			return q["nearest"] as Vector3
		return Vector3.INF
	var r := _rat_in_reach()
	return r.global_position if r != null else Vector3.INF


func _rat_in_reach() -> Node3D:
	var best: Node3D = null
	var bd := weapon.reach * weapon.reach
	var p := global_position
	for n: Node in get_tree().get_nodes_in_group("rats"):
		var r := n as Node3D
		if r == null or r.is_queued_for_deletion() or not r.has_method("hit"):
			continue
		if weapon.kills_pups_only and r.get("is_pup") != true:
			continue
		var d := r.global_position - p
		d.y = 0.0
		if d.length_squared() <= bd:
			bd = d.length_squared()
			best = r
	return best


func _begin(at: Vector3) -> void:
	_point = Vector3(at.x, 0.0, at.z)
	_origin = Vector3(global_position.x, 0.0, global_position.z)
	_dir = _point - _origin
	_dir = _dir.normalized() if _dir.length_squared() > 0.0001 else (_host.global_basis.z if _host else Vector3.BACK)
	_windup_total = weapon.windup * windup_multiplier
	_windup_left = _windup_total
	_build_ring()
	_update_ring()
	windup_started.emit(_point)


func _strike() -> void:
	_windup_left = 0.0
	_cooldown_left = weapon.cooldown
	_free_ring()
	var hits := 0
	var tree := get_tree()
	match weapon.kind:
		&"broom":
			hits = _sweep()
			Vfx.play(tree, &"broom", _origin, _dir, weapon.radius, weapon.arc_deg)
		&"torch":
			_throw_fire()
		&"club":
			hits = _stomp()
			Vfx.play(tree, &"club", _point, Vector3.ZERO, weapon.radius)
			GameFeel.shake_camera(tree, 0.22)
		_:
			hits = _stomp()
			Vfx.play(tree, &"stomp", _point, Vector3.ZERO, weapon.radius)
			if hits > 0:
				GameFeel.shake_camera(tree, 0.12)
	if weapon.kind != &"torch":
		Vfx.disturb_at(tree, _point, DISTURB_RADIUS)
	struck.emit(_point, hits)


## Every rat (copied first: hit() may free them) as a flat list of live nodes.
func _live_rats() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group("rats").duplicate():
		var r := n as Node3D
		if r == null or not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if weapon.kills_pups_only and r.get("is_pup") != true:
			continue
		out.append(r)
	return out


func _stomp() -> int:
	var c := _colony()
	if c != null and c.has_method("hit_rats_in_circle"):
		return c.hit_rats_in_circle(_point, weapon.radius, weapon.kills_pups_only)
	var hits := 0
	for r in _live_rats():
		if not is_instance_valid(r) or not r.has_method("hit"):
			continue
		if DangerZone.circle_contains(_point, weapon.radius, r.global_position):
			r.call("hit")
			hits += 1
	return hits


## Broom: Pups in the arc die, Adults and the Lead Rat are shoved away.
func _sweep() -> int:
	var half := deg_to_rad(weapon.arc_deg) * 0.5
	var c := _colony()
	if c != null and c.has_method("sweep_rats_in_arc"):
		return c.sweep_rats_in_arc(_origin, _dir, weapon.radius, half, BROOM_FEET, weapon.knockback)
	var hits := 0
	for r in _live_rats():
		if not is_instance_valid(r):
			continue
		if not DangerZone.arc_contains(_origin, _dir, weapon.radius, half, BROOM_FEET, r.global_position):
			continue
		if r.get("is_pup") == true and r.has_method("hit"):
			r.call("hit")
			hits += 1
		elif r.has_method("knockback"):
			r.call("knockback", _origin, weapon.knockback)
			hits += 1
	return hits


func _throw_fire() -> void:
	var patch := FirePatch.new()
	patch.name = "FirePatch"
	patch.setup(_props, weapon.radius, weapon.burn_time, weapon.burn_delay)
	# The patch outlives a wielder who goes indoors or dies: park it in the world.
	var world: Node = _host.get_parent() if _host != null and _host.get_parent() != null else get_tree().current_scene
	if world == null:
		world = get_tree().root
	world.add_child(patch)
	patch.global_position = _point
	patch.set_circle(_point, weapon.radius, -1.0)


# ---------------------------------------------------------------------- telegraph
func _build_ring() -> void:
	_free_ring()
	_ring = DangerZone.new()
	_ring.top_level = true
	add_child(_ring)
	var rad := weapon.radius
	if weapon.kind == &"broom":
		_ring.set_arc(_origin, _dir, rad, deg_to_rad(weapon.arc_deg) * 0.5, BROOM_FEET, _windup_total)
	else:
		_ring.set_circle(_point, rad, _windup_total)
	_ring.activate()
	match weapon.kind:
		&"broom":
			_ring.name = "BroomArc"
			_ring.global_transform = Transform3D(Basis(Vector3.UP, atan2(_dir.x, _dir.z)), _origin)
			_arc_outline(_ring, rad, Props.INK, 0.1)
			_fill = _props.node(_ring, Vector3(0, 0.11, 0))
			var fan := MeshInstance3D.new()
			fan.mesh = _sector_mesh(rad, weapon.arc_deg)
			fan.material_override = _props.mat(Props.TIMBER)
			_fill.add_child(fan)
		&"torch":
			_ring.name = "TorchCircle"
			_ring.global_transform = Transform3D(Basis(), _point)
			_props.part(_ring, _props.torus(rad, 0.09), Props.INK, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
			# Short ink rays around the circle: "fire lands here".
			for i in 8:
				var a := TAU * i / 8.0
				var o := Vector3(sin(a), 0.0, cos(a))
				_props.strip(_ring, o * (rad + 0.15) + Vector3(0, 0.12, 0), o * (rad + 0.5) + Vector3(0, 0.12, 0), 0.08, Props.INK)
			_fill = _props.node(_ring, Vector3(0, 0.11, 0))
			_props.part(_fill, _props.cyl(rad, rad, 0.02, 20), Props.TIMBER, Vector3.ZERO)
		&"club":
			_ring.name = "ClubRing"
			_ring.global_transform = Transform3D(Basis(), _point)
			_props.part(_ring, _props.torus(rad, 0.2), Props.INK, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
			_props.part(_ring, _props.torus(rad * 0.82, 0.07), Props.INK, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
			_fill = _props.node(_ring, Vector3(0, 0.11, 0))
			_props.part(_fill, _props.cyl(rad, rad, 0.02, 28), Props.TIMBER, Vector3.ZERO)
		_:
			_ring.name = "StompRing"
			_ring.global_transform = Transform3D(Basis(), _point)
			# Outer INK ring at the full radius, plus an inner ink disc that grows to meet it.
			_props.part(_ring, _props.torus(rad, 0.1), Props.INK, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
			_fill = _props.node(_ring, Vector3(0, 0.11, 0))
			_props.part(_fill, _props.cyl(rad, rad, 0.02, 24), Props.TIMBER, Vector3.ZERO)


func _update_ring() -> void:
	if _fill == null:
		return
	var t := windup_progress()
	# Eased so the last moments read as "now!".
	var s := lerpf(0.08, 1.0, t * t)
	_fill.scale = Vector3(s, 1.0, s)


func _free_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.retire()
	_ring = null
	_fill = null


## Outline of the broom sector (local +Z forward): the curved edge and both
## straight sides, as raised strips.
func _arc_outline(parent: Node3D, rad: float, color: Color, thick: float) -> void:
	var half := deg_to_rad(weapon.arc_deg) * 0.5
	var y := Vector3(0, 0.12, 0)
	var prev := Vector3.ZERO
	for i in ARC_SEGMENTS + 1:
		var a := lerpf(-half, half, float(i) / ARC_SEGMENTS)
		var p := Vector3(sin(a), 0.0, cos(a)) * rad
		if i > 0:
			_props.strip(parent, prev + y, p + y, thick, color)
		prev = p
	for s: float in [-half, half]:
		_props.strip(parent, y + Vector3(sin(s), 0, cos(s)) * 0.3, y + Vector3(sin(s), 0, cos(s)) * rad, thick, color)


## A flat, upward-facing fan of `deg` degrees around local +Z.
func _sector_mesh(rad: float, deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := deg_to_rad(deg) * 0.5
	for i in ARC_SEGMENTS:
		var a0 := lerpf(-half, half, float(i) / ARC_SEGMENTS)
		var a1 := lerpf(-half, half, float(i + 1) / ARC_SEGMENTS)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0.0, cos(a0)) * rad)
		st.add_vertex(Vector3(sin(a1), 0.0, cos(a1)) * rad)
	return st.commit()


## The torch's fire: an AMBER emissive disc with an ink rim. Flickering amber
## flame tongues and pale smoke rise off it from the Vfx pools (FLAME_RATE /
## SMOKE_RATE a second), and it leaves a scorch mark when it goes out. It burns
## `burn_time` s and calls `hit()` once on every rat that has stood in it for
## more than `burn_delay` s without leaving.
class FirePatch extends DangerZone:
	var radius := 0.75
	var burn_time := 3.0
	var burn_delay := 0.25
	var _props: Props
	var _age := 0.0
	var _inside := {}       # rat instance id -> seconds inside without leaving
	var _burned := {}       # rat instance id -> true once hit
	var _flame_left := 0.0
	var _smoke_left := 0.1
	const FLAME_RATE := 22.0
	const SMOKE_RATE := 4.0

	func setup(props: Props, r: float, time: float, delay: float) -> void:
		_props = props
		radius = r
		burn_time = time
		burn_delay = delay

	func _ready() -> void:
		add_to_group("fire_patches")
		set_circle(global_position, radius, -1.0)
		activate()
		if _props == null:
			_props = Props.new(23)
		_props.part(self, _props.cyl(radius, radius, 0.05, 20), Props.AMBER, Vector3(0, 0.08, 0), Vector3.ZERO,
			Vector3.ONE, 2.5)
		_props.part(self, _props.torus(radius, 0.07), Props.INK, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
		var tw := create_tween()
		scale = Vector3(0.3, 1.0, 0.3)
		tw.tween_property(self, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= burn_time:
			Vfx.mark(get_tree(), &"scorch", global_position, randf() * TAU, radius * 1.1, 14.0)
			retire()
			return
		danger_center = Vector3(global_position.x, 0.0, global_position.z)
		var col := get_tree().get_first_node_in_group("colony") as Colony
		if col != null and col.sim != null and _age >= burn_delay:
			# SwarmSim rats standing in fire die cleanly via spatial query.
			col.sim.hit_circle(danger_center, radius, false)
		var seen := {}
		for n: Node in get_tree().get_nodes_in_group("rats").duplicate():
			var r := n as Node3D
			if r == null or not is_instance_valid(r) or r.is_queued_for_deletion():
				continue
			if not danger_contains(r.global_position):
				continue
			var id := r.get_instance_id()
			seen[id] = true
			_inside[id] = float(_inside.get(id, 0.0)) + delta
			if _inside[id] > burn_delay and not _burned.has(id) and r.has_method("hit"):
				_burned[id] = true
				r.call("hit")
		# Leaving the fire resets the count: running through is safe.
		for id: int in _inside.keys():
			if not seen.has(id):
				_inside.erase(id)

	func _process(delta: float) -> void:
		# Dies down over the last half second.
		var left := burn_time - _age
		var k := clampf(left / 0.5, 0.0, 1.0)
		var tree := get_tree()
		_flame_left -= delta * k
		while _flame_left <= 0.0:
			_flame_left += 1.0 / FLAME_RATE
			var a := randf() * TAU
			var at := global_position + Vector3(sin(a), 0.0, cos(a)) * radius * sqrt(randf()) * 0.85
			Vfx.play(tree, &"flame", at, Vector3.ZERO, lerpf(0.5, 1.0, k))
		_smoke_left -= delta * k
		if _smoke_left <= 0.0:
			_smoke_left += 1.0 / SMOKE_RATE
			Vfx.play(tree, &"smoke", global_position + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)))
		if left < 0.5:
			var s := maxf(0.05, left / 0.5)
			scale = Vector3(s, s, s)
