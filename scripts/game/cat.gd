## A town cat (M5): a small solid-ink hunter, larger than a rat, with upright
## ears and its tail held up. It wanders near where it came in, sprints at the
## nearest rat within HUNT_RANGE, kills it on contact (`hit()`) and then sits
## for PAUSE seconds. It runs away whenever CROWD or more rats are within
## CROWD_RANGE, so a big Colony is safe from it and a lone rat is not.
## Cats are not townsfolk: no Infection, not in "townsfolk", not counted in the
## population. Group "cats". Spawned by the Spawner for the type with look "cat".
class_name Cat
extends CharacterBody3D

const Props := preload("res://scripts/town_props.gd")
const SCALE := 1.3
const SPRINT := 7.0
const FLEE_SPEED := 7.0
const HUNT_RANGE := 10.0
const CROWD := 8
const CROWD_RANGE := 5.0
## Touching distance that kills the rat.
const CATCH := 0.6
const PAUSE := 2.0
## Seconds a fleeing cat keeps running once the crowd thins.
const FLEE_MIN := 1.5
## Seconds between rat scans.
const SCAN := 0.15
## Half-size of the patch a cat wanders in when no bounds were given.
const WANDER_HALF := 8.0

enum Mode { WANDER, HUNT, PAUSE, FLEE }

## XZ rectangle it wanders in (x -> X, y -> Z); empty = around its spawn point.
@export var wander_bounds := Rect2()
@export var rng_seed := 0
@export var walk_speed := 1.5

var mode := Mode.WANDER
var kills := 0
## The type given by setup() (may be null).
var def: TownsfolkDef

var _rng := RandomNumberGenerator.new()
var _props: Props
var _visual: Node3D
var _tail: Node3D
var _target: Node3D
var _goal := Vector3.ZERO
var _idle_left := 0.0
var _pause_left := 0.0
var _flee_left := 0.0
var _flee_dir := Vector3.ZERO
var _scan_left := 0.0
var _crowd := 0
var _crowd_centre := Vector3.ZERO
var _gait := 0.0


## Same entry point as Townsperson.setup(): walk speed * the Year's speed.
func setup(type_def: TownsfolkDef, year_entry: YearEntry) -> void:
	def = type_def
	if def != null:
		walk_speed = def.walk_speed * (year_entry.speed_mult if year_entry != null else 1.0)


func _ready() -> void:
	add_to_group("cats")
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_props = Props.new(_rng.randi())
	if wander_bounds.has_area() == false:
		var p := global_position
		wander_bounds = Rect2(p.x - WANDER_HALF, p.z - WANDER_HALF, WANDER_HALF * 2.0, WANDER_HALF * 2.0)
	_build()
	rotation.y = _rng.randf_range(-PI, PI)
	_gait = _rng.randf_range(0.0, 10.0)
	_pick_goal()


## Body, four legs, head with upright ears and a tail curling up, all INK.
func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var root := _props.node(_visual, Vector3.ZERO)
	root.scale = Vector3.ONE * SCALE
	var ink := Props.INK
	_props.part(root, _props.sphere(0.3, 12), ink, Vector3(0, 0.42, -0.02), Vector3.ZERO, Vector3(0.8, 0.72, 1.6))
	_props.part(root, _props.sphere(0.24, 10), ink, Vector3(0, 0.5, 0.3), Vector3.ZERO, Vector3(0.95, 0.9, 1.0))
	for sx: float in [-1.0, 1.0]:
		for z: float in [0.32, -0.34]:
			_props.part(root, _props.cyl(0.045, 0.055, 0.34, 6), ink, Vector3(sx * 0.13, 0.17, z))
	# Head and ears: tall pointed cones, splayed a little.
	_props.part(root, _props.sphere(0.19, 10), ink, Vector3(0, 0.72, 0.56), Vector3.ZERO, Vector3(1.05, 0.9, 0.95))
	_props.part(root, _props.cyl(0.03, 0.08, 0.1, 6), ink, Vector3(0, 0.67, 0.73), Vector3(70, 0, 0))
	for sx: float in [-1.0, 1.0]:
		_props.part(root, _props.cyl(0.0, 0.085, 0.26, 4), ink, Vector3(sx * 0.11, 0.95, 0.53), Vector3(-8, 45, sx * -16.0))
		_props.part(root, _props.sphere(0.03, 6), Props.STONE, Vector3(sx * 0.075, 0.76, 0.72))
	# Tail: up from the rump, curling forward at the top.
	_tail = _props.node(root, Vector3(0, 0.5, -0.46))
	var pts: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0.3, -0.1), Vector3(0, 0.6, -0.08), Vector3(0, 0.8, 0.04),
		Vector3(0, 0.86, 0.17)]
	for i in pts.size() - 1:
		_props.strip(_tail, pts[i], pts[i + 1], 0.075 - i * 0.008, ink)


func _physics_process(delta: float) -> void:
	_pause_left = maxf(0.0, _pause_left - delta)
	_flee_left = maxf(0.0, _flee_left - delta)
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN
		_scan()
	if _crowd >= CROWD:
		mode = Mode.FLEE
		_flee_left = FLEE_MIN
		var away := global_position - _crowd_centre
		away.y = 0.0
		if away.length_squared() > 0.0001:
			_flee_dir = away.normalized()
	elif _flee_left > 0.0:
		mode = Mode.FLEE
	elif _pause_left > 0.0:
		mode = Mode.PAUSE
	elif _target != null:
		mode = Mode.HUNT
	else:
		if mode != Mode.WANDER:
			_pick_goal()
		mode = Mode.WANDER
	match mode:
		Mode.FLEE:
			if _flee_dir == Vector3.ZERO:
				_flee_dir = global_basis.z
			_move(_flee_dir, FLEE_SPEED, delta)
		Mode.HUNT:
			_hunt(delta)
		Mode.PAUSE:
			velocity = Vector3.ZERO
		_:
			_wander(delta)
	_animate(delta)


## Counts the rats within CROWD_RANGE and picks the nearest one to hunt.
func _scan() -> void:
	var here := global_position
	var c2 := CROWD_RANGE * CROWD_RANGE
	var best_d := HUNT_RANGE * HUNT_RANGE
	var best: Node3D = null
	var sum := Vector3.ZERO
	_crowd = 0
	for n: Node in get_tree().get_nodes_in_group("rats"):
		var r := n as Node3D
		if r == null or r.is_queued_for_deletion():
			continue
		var d := r.global_position - here
		d.y = 0.0
		var l2 := d.length_squared()
		if l2 <= c2:
			_crowd += 1
			sum += r.global_position
		if l2 < best_d and r.has_method("hit"):
			best_d = l2
			best = r
	_crowd_centre = sum / float(_crowd) if _crowd > 0 else here
	_target = best


func _hunt(delta: float) -> void:
	if not _target_ok():
		_target = null
		velocity = Vector3.ZERO
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length() <= CATCH:
		_target.call("hit")
		kills += 1
		_target = null
		_pause_left = PAUSE
		velocity = Vector3.ZERO
		_face(to, 1.0)
		return
	_move(to.normalized(), SPRINT, delta)


func _target_ok() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.is_queued_for_deletion() \
		and _target.is_in_group("rats")


func _wander(delta: float) -> void:
	if _idle_left > 0.0:
		_idle_left -= delta
		velocity = Vector3.ZERO
		if _idle_left <= 0.0:
			_pick_goal()
		return
	var to := _goal - global_position
	to.y = 0.0
	if to.length() < 0.3:
		_idle_left = _rng.randf_range(1.0, 4.0)
		velocity = Vector3.ZERO
		return
	_move(to.normalized(), walk_speed, delta)


func _move(dir: Vector3, speed: float, delta: float) -> void:
	velocity = dir * speed
	move_and_slide()
	_face(dir, delta * 10.0)


func _face(dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, weight))


func _pick_goal() -> void:
	var b := wander_bounds.abs()
	_goal = Vector3(_rng.randf_range(b.position.x, b.end.x), 0.0, _rng.randf_range(b.position.y, b.end.y))


## A quick bounding gait at a sprint, a sit while pausing, a slow tail sway.
func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_gait += delta * (2.0 + speed * 2.2)
	var bob := absf(sin(_gait)) * minf(speed, 7.0) * 0.012
	var sit := 1.0 if mode == Mode.PAUSE else 0.0
	_visual.position.y = bob - sit * 0.06
	_visual.rotation.x = -0.18 * sit + (0.06 * sin(_gait * 2.0) if speed > 3.0 else 0.0)
	_tail.rotation.z = sin(_gait * 0.6) * 0.25
	_tail.rotation.x = -0.6 if mode == Mode.FLEE else 0.0   # streams out behind on the run
