## Shared base of the Exterminators (M6), the District bosses. An Exterminator
## is a person: it is in "townsfolk" (so rats Bite it) and in "exterminator",
## and has an `Infection` child tuned in its scene (low gain_multiplier, a
## self-Cleanse and a fading Bite bonus, base_rate 0) so only many rats Biting
## at once push it to 100. Fear doesn't apply to it. The RoundDirector leaves it
## out of the population and ends the Round on `beaten`.
## It walks in from the gate for `arrive_time` s (`arrived` fires when it
## starts work), then subclasses run their brain in `_think()`. On `beaten` it
## collapses into a big sepia corpse that stays in the world.
## The base also carries the ink telegraph kit (ring, arc, fill) and a
## wall-aware walk shared by the bosses.
class_name Exterminator
extends CharacterBody3D

const Props := preload("res://scripts/town_props.gd")
## Pooled event effects (subclasses use it too).
const Vfx := preload("res://scripts/vfx/vfx.gd")
## Dark sepia of the corpse (drawn as heavy hatching, like a townsperson's).
const CORPSE_INK := Color(0.34, 0.29, 0.24)
const WORLD_MASK := 1
const ARC_SEGMENTS := 14

signal arrived
signal beaten

@export var title := "The Rat-catcher"
@export var walk_speed := 1.9
## Seconds walking in from the gate before the first attack.
@export var arrive_time := 2.5
@export var rng_seed := 0
## XZ rectangle it stays inside (x -> X, y -> Z); empty = no limit.
@export var wander_bounds := Rect2()

var has_arrived := false
var is_beaten := false

var _rng := RandomNumberGenerator.new()
var _props: Props
var _visual: Node3D            # pivot at the feet; tilted for gait, toppled on death
var _tint: Array[StandardMaterial3D] = []   # cloth that reddens with Infection
var _tint_base: Array[Color] = []
var _sick := Props.RED
var _arrive_left := 0.0
var _gait := 0.0
var _probe := SphereShape3D.new()
var _side := 1.0

@onready var infection: InfectionComponent = $Infection
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("exterminator")
	add_to_group("townsfolk")
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_props = Props.new(_rng.randi())
	_probe.radius = 0.45
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build()
	# Lethality multiplies every base_rate as it enters the tree; a boss never
	# sickens on its own (its scene says 0), only Bites push it up.
	infection.value_changed.connect(_on_infection_changed)
	infection.died.connect(_on_died)
	_arrive_left = arrive_time
	_gait = _rng.randf_range(0.0, 10.0)


## Builds the look under `_visual` (subclasses).
func _build() -> void:
	pass


## The boss's behaviour once it has arrived (subclasses).
func _think(_delta: float) -> void:
	pass


## Called once when the walk-in ends (subclasses: release the terrier, ...).
func _on_arrived() -> void:
	pass


func _physics_process(delta: float) -> void:
	if is_beaten:
		return
	_gait += delta
	if not has_arrived:
		_arrive_left -= delta
		var lead := lead_rat()
		var to := (lead.global_position - global_position) if lead != null else -global_position
		to.y = 0.0
		if to.length() > 2.0:
			walk(to.normalized(), walk_speed, delta)
		else:
			velocity = Vector3.ZERO
		if _arrive_left <= 0.0:
			has_arrived = true
			_on_arrived()
			arrived.emit()
		_animate(delta)
		return
	_think(delta)
	_animate(delta)


## A slow bob while walking (subclasses may override).
func _animate(_delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_visual.position.y = absf(sin(_gait * 7.0)) * 0.05 * minf(speed, 2.0)


# ---------------------------------------------------------------------- queries
## The living Lead Rat out in the street, or null (hidden / dead / missing).
func lead_rat() -> Node3D:
	var r := get_tree().get_first_node_in_group("lead_rat") as Node3D
	if r == null or not is_instance_valid(r) or r.get("is_dead") == true or r.get("is_hidden") == true:
		return null
	return r


## Every living rat in the street (copied: hit() may free them).
func live_rats() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group("rats").duplicate():
		var r := n as Node3D
		if r != null and is_instance_valid(r) and not r.is_queued_for_deletion():
			out.append(r)
	return out


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------- moving
## Walks along `dir`, sliding around walls, and turns to face it.
func walk(dir: Vector3, speed: float, delta: float) -> void:
	var d := dir
	if is_inside_tree() and not _clear(global_position, global_position + d * 1.3):
		d = _slide_dir(d)
	velocity = d * speed
	move_and_slide()
	if wander_bounds.has_area():
		var b := wander_bounds.abs()
		global_position.x = clampf(global_position.x, b.position.x, b.end.x)
		global_position.z = clampf(global_position.z, b.position.y, b.end.y)
	face(d, delta * 6.0)


func face(dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, weight))


func _slide_dir(dir: Vector3) -> Vector3:
	for step in range(1, 7):
		for s: float in [_side, -_side]:
			var d := dir.rotated(Vector3.UP, s * step * PI / 7.0)
			if _clear(global_position, global_position + d * 1.3):
				_side = s
				return d
	return dir


## True when a body-sized sphere can travel from a to b without hitting the world.
func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.collision_mask = WORLD_MASK
	var from := Vector3(a.x, 0.8, a.z)
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = Vector3(b.x, 0.8, b.z) - from
	var hit := get_world_3d().direct_space_state.cast_motion(q)
	return hit.is_empty() or hit[0] >= 1.0


# ---------------------------------------------------------------------- infection
## Registers cloth materials (by colour) that redden as the Infection climbs:
## every mesh under `root` using the Props material of `color` gets a copy.
func tint_color(root: Node3D, color: Color, sick := Props.RED) -> void:
	var shared := _props.mat(color)
	var own := shared.duplicate() as StandardMaterial3D
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == shared:
			mi.material_override = own
	_tint.append(own)
	_tint_base.append(color)
	_sick = sick


func _on_infection_changed(value: float) -> void:
	if is_beaten:
		return
	var t := smoothstep(0.0, 100.0, value) * 0.85
	for i in _tint.size():
		_tint[i].albedo_color = _tint_base[i].lerp(_sick, t)


func _on_died() -> void:
	if is_beaten:
		return
	is_beaten = true
	remove_from_group("townsfolk")
	_on_beaten()
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	for m in _tint:
		m.albedo_color = CORPSE_INK
	# Topples over; the tween keeps playing through the Round-end pause.
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_visual, "rotation", Vector3(0.0, 0.0, side * PI * 0.5), 0.6)
	tw.tween_property(_visual, "position", Vector3(0.0, 0.5, 0.0), 0.6)
	# A big red miasma bloom (the Round ends on this frame; it shows frozen).
	Vfx.play(get_tree(), &"ext_beaten", global_position)
	beaten.emit()


## Subclasses drop telegraphs, free traps, ... when beaten.
func _on_beaten() -> void:
	pass


# ---------------------------------------------------------------------- telegraph kit
## A top-level node in the world at `at` (outlives the boss's own transform).
func world_node(node_name: String, at: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	var world: Node = get_parent() if get_parent() != null else get_tree().root
	world.add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), flat(at))
	return n


## A top-level DangerZone in the world at `at`, already in "danger_zones"
## (callers set its shape with set_circle / set_arc).
func world_zone(node_name: String, at: Vector3, yaw := 0.0) -> DangerZone:
	var n := DangerZone.new()
	n.name = node_name
	var world: Node = get_parent() if get_parent() != null else get_tree().root
	world.add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), flat(at))
	n.activate()
	return n


## An INK ring of `radius` on the ground under `parent`.
func ink_ring(parent: Node3D, radius: float, thick := 0.1, y := 0.13) -> MeshInstance3D:
	return _props.part(parent, _props.torus(radius, thick), Props.INK, Vector3(0, y, 0), Vector3.ZERO, Vector3(1, 0.25, 1))


## A dashed INK circle: `dashes` short strips around `radius`.
func ink_dashes(parent: Node3D, radius: float, dashes := 16, thick := 0.09) -> void:
	for i in dashes:
		var a0 := TAU * float(i) / dashes
		var a1 := a0 + TAU / dashes * 0.55
		var y := Vector3(0, 0.12, 0)
		_props.strip(parent, Vector3(sin(a0), 0, cos(a0)) * radius + y, Vector3(sin(a1), 0, cos(a1)) * radius + y, thick, Props.INK)


## A flat TIMBER disc under `parent` that the wind-up grows (see set_fill).
func fill_disc(parent: Node3D, radius: float) -> Node3D:
	var f := _props.node(parent, Vector3(0, 0.11, 0))
	_props.part(f, _props.cyl(radius, radius, 0.02, 28), Props.TIMBER, Vector3.ZERO)
	return f


## The outline of a sector (local +Z forward) of `radius` and `deg` degrees.
func ink_arc(parent: Node3D, radius: float, deg: float, thick := 0.11) -> void:
	var half := deg_to_rad(deg) * 0.5
	var y := Vector3(0, 0.12, 0)
	var prev := Vector3.ZERO
	for i in ARC_SEGMENTS + 1:
		var a := lerpf(-half, half, float(i) / ARC_SEGMENTS)
		var p := Vector3(sin(a), 0.0, cos(a)) * radius
		if i > 0:
			_props.strip(parent, prev + y, p + y, thick, Props.INK)
		prev = p
	for s: float in [-half, half]:
		_props.strip(parent, y + Vector3(sin(s), 0, cos(s)) * 0.4, y + Vector3(sin(s), 0, cos(s)) * radius, thick, Props.INK)


## A flat TIMBER fan of the sector that the wind-up grows (see set_fill).
func fill_fan(parent: Node3D, radius: float, deg: float) -> Node3D:
	var f := _props.node(parent, Vector3(0, 0.11, 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := deg_to_rad(deg) * 0.5
	for i in ARC_SEGMENTS:
		var a0 := lerpf(-half, half, float(i) / ARC_SEGMENTS)
		var a1 := lerpf(-half, half, float(i + 1) / ARC_SEGMENTS)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0.0, cos(a0)) * radius)
		st.add_vertex(Vector3(sin(a1), 0.0, cos(a1)) * radius)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# Two-sided: the fan's winding must not hide it from the camera.
	var m := _props.mat(Props.TIMBER).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	f.add_child(mi)
	return f


## Grows a fill from a speck to full size as the wind-up `t` goes 0 -> 1.
static func set_fill(fill: Node3D, t: float) -> void:
	if fill == null or not is_instance_valid(fill):
		return
	var s := lerpf(0.08, 1.0, t * t)
	fill.scale = Vector3(s, 1.0, s)


## An alpha INK material for fading flashes.
func fade_mat(color := Props.INK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
