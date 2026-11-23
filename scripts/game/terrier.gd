## The Rat-catcher's terrier (M6): a wiry, hatched sepia dog with an ink saddle,
## folded ink ears, a pale beard, a short upright tail and an ink collar. Never
## solid ink, so it doesn't read as a cat or rat. It hunts only the Lead Rat at
## `run_speed`; within `lunge_range` it crouches for `windup` s over an INK ring
## at the spot it will spring at, then lunges there. If the Lead Rat is still
## within `catch` it gets `hit()`, and the terrier pauses `pause` s.
## The Colony doesn't scare it. It is bitable and infectable like a person
## (group "townsfolk", child `Infection`, normal gain) and falls over as a
## corpse when it dies; groups "terrier" and "exterminator_pets" keep it out of
## the population and the spawner's counts. The lunge ring is a DangerZone
## ("danger_zones") from the crouch until the terrier lands.
class_name Terrier
extends CharacterBody3D

const Props := preload("res://scripts/town_props.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")
## Run dust: a puff behind it this often while it hunts or lunges.
const DUST_GAP := 0.08
const CORPSE_INK := Color(0.34, 0.29, 0.24)
const SCALE := 1.8
## Coat: a mid sepia the shader hatches, so it reads apart from the solid-ink
## cat and rats and from the bare parchment.
const COAT := Color(0.42, 0.35, 0.27)
const MEALS := 2

enum Mode { HUNT, WINDUP, LUNGE, PAUSE, SNIFF, DEAD }

@export var run_speed := 6.5
@export var lunge_range := 1.8
@export var lunge_speed := 10.0
@export var windup := 0.3
@export var catch := 0.8
@export var pause := 2.5
## Speed factor once infected.
@export var sick_speed := 0.7
@export var rng_seed := 0

var mode := Mode.HUNT
var catches := 0
var meals_left := MEALS
var _dust_left := 0.0

var _rng := RandomNumberGenerator.new()
var _props: Props
var _visual: Node3D
var _tail: Node3D
var _body_mat: StandardMaterial3D
var _mode_left := 0.0
var _lunge_to := Vector3.ZERO
var _telegraph: DangerZone
var _gait := 0.0

@onready var infection: InfectionComponent = $Infection
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("townsfolk")
	add_to_group("terrier")
	add_to_group("exterminator_pets")
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_props = Props.new(_rng.randi())
	_build()
	infection.value_changed.connect(_on_infection_changed)
	infection.died.connect(_on_died)


## Hatched sepia body, ink saddle and paws, square head with a beard, folded ink
## ears, short upright tail, ink collar.
func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var root := _props.node(_visual, Vector3.ZERO)
	root.scale = Vector3.ONE * SCALE
	var pale := COAT
	_props.part(root, _props.box(Vector3(0.34, 0.3, 0.72)), pale, Vector3(0, 0.4, 0))
	# A flat ink saddle marking across the back.
	_props.part(root, _props.box(Vector3(0.36, 0.04, 0.26)), Props.INK, Vector3(0, 0.56, -0.14))
	for sx: float in [-1.0, 1.0]:
		for z: float in [0.26, -0.26]:
			_props.part(root, _props.box(Vector3(0.09, 0.28, 0.09)), pale, Vector3(sx * 0.12, 0.14, z))
			_props.part(root, _props.box(Vector3(0.1, 0.05, 0.13)), Props.INK, Vector3(sx * 0.12, 0.025, z + 0.02))
	# Head: a square skull and muzzle, an ink nose, a pale beard, ink eyes.
	var head := _props.node(root, Vector3(0, 0.62, 0.42))
	_props.part(head, _props.box(Vector3(0.28, 0.26, 0.26)), pale, Vector3.ZERO)
	_props.part(head, _props.box(Vector3(0.2, 0.16, 0.2)), pale, Vector3(0, -0.05, 0.2))
	_props.part(head, _props.sphere(0.05, 6), Props.INK, Vector3(0, -0.01, 0.31))
	_props.part(head, _props.box(Vector3(0.18, 0.1, 0.06)), Props.STONE, Vector3(0, -0.15, 0.25))
	for sx: float in [-1.0, 1.0]:
		_props.part(head, _props.sphere(0.03, 6), Props.INK, Vector3(sx * 0.08, 0.06, 0.13))
		_props.part(head, _props.box(Vector3(0.05, 0.14, 0.12)), Props.INK, Vector3(sx * 0.16, 0.08, -0.02), Vector3(0, 0, sx * -35.0))
	# Collar with a pale tag.
	_props.part(root, _props.torus(0.15, 0.05), Props.INK, Vector3(0, 0.55, 0.3), Vector3(70, 0, 0))
	_props.part(root, _props.cyl(0.04, 0.04, 0.02, 8), Props.STONE, Vector3(0, 0.44, 0.38), Vector3(70, 0, 0))
	# Short tail straight up.
	_tail = _props.node(root, Vector3(0, 0.52, -0.36))
	_props.strip(_tail, Vector3.ZERO, Vector3(0, 0.26, -0.04), 0.06, Props.INK)
	var shared := _props.mat(pale)
	_body_mat = shared.duplicate() as StandardMaterial3D
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == shared:
			mi.material_override = _body_mat


func _physics_process(delta: float) -> void:
	if mode == Mode.DEAD:
		return
	_gait += delta
	_mode_left -= delta
	var slow := sick_speed if infection.is_infected() else 1.0
	var lead := _lead()
	match mode:
		Mode.PAUSE:
			velocity = Vector3.ZERO
			if _mode_left <= 0.0:
				mode = Mode.HUNT
		Mode.WINDUP:
			velocity = Vector3.ZERO
			_face(_lunge_to - global_position, delta * 14.0)
			if _mode_left <= 0.0:
				mode = Mode.LUNGE
				_mode_left = lunge_range * 1.4 / lunge_speed
		Mode.LUNGE:
			_lunge(lead, delta, slow)
		_:
			_hunt(lead, delta, slow)
	_dust_left -= delta
	if _dust_left <= 0.0 and velocity.length_squared() > 4.0:
		_dust_left = DUST_GAP
		Vfx.run_dust_at(get_tree(), global_position, velocity, 1.3)
	_update_zone(slow)
	_animate()


func _hunt(lead: Node3D, delta: float, slow: float) -> void:
	if lead == null:
		mode = Mode.SNIFF
		velocity = Vector3.ZERO
		return
	mode = Mode.HUNT
	var to := lead.global_position - global_position
	to.y = 0.0
	if to.length() <= lunge_range:
		begin_lunge(lead.global_position)
		return
	_move(to.normalized(), run_speed * slow, delta)


## Crouches over an INK ring at `at`, then springs at it.
func begin_lunge(at: Vector3) -> void:
	_lunge_to = Vector3(at.x, 0.0, at.z)
	mode = Mode.WINDUP
	_mode_left = windup
	_free_telegraph()
	_telegraph = DangerZone.new()
	_telegraph.name = "LungeRing"
	var world: Node = get_parent() if get_parent() != null else get_tree().root
	world.add_child(_telegraph)
	_telegraph.global_position = _lunge_to
	_telegraph.set_circle(_lunge_to, catch, windup + _flat_d(global_position, _lunge_to) / lunge_speed)
	_telegraph.activate()
	_props.part(_telegraph, _props.torus(catch, 0.08), Props.INK, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
	# Two short ink claw marks across the ring.
	for s: float in [-1.0, 1.0]:
		_props.strip(_telegraph, Vector3(s * 0.25, 0.12, -0.35), Vector3(s * 0.25, 0.12, 0.35), 0.06, Props.INK)


func _lunge(lead: Node3D, delta: float, slow: float) -> void:
	if lead != null and _flat_d(lead.global_position, global_position) <= catch:
		lead.call("hit")
		catches += 1
		_end_lunge(pause)
		return
	var to := _lunge_to - global_position
	to.y = 0.0
	if to.length() < 0.2 or _mode_left <= 0.0:
		# Landed: one last check at the spot, else a short recovery.
		if lead != null and _flat_d(lead.global_position, _lunge_to) <= catch:
			lead.call("hit")
			catches += 1
			_end_lunge(pause)
		else:
			_end_lunge(0.5)
		return
	_move(to.normalized(), lunge_speed * slow, delta)


func _end_lunge(wait: float) -> void:
	_free_telegraph()
	mode = Mode.PAUSE
	_mode_left = wait
	velocity = Vector3.ZERO


## Seconds until it lands on the ring: the rest of the crouch plus the spring.
func _update_zone(slow: float) -> void:
	if _telegraph == null or not is_instance_valid(_telegraph):
		return
	var travel := _flat_d(global_position, _lunge_to) / maxf(0.1, lunge_speed * slow)
	match mode:
		Mode.WINDUP:
			_telegraph.danger_time_left = maxf(0.0, _mode_left) + travel
		Mode.LUNGE:
			_telegraph.danger_time_left = minf(travel, maxf(0.0, _mode_left))


func _free_telegraph() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.retire()
	_telegraph = null


## The living Lead Rat in the street (never any other rat), or null.
func _lead() -> Node3D:
	var r := get_tree().get_first_node_in_group("lead_rat") as Node3D
	if r == null or not is_instance_valid(r) or r.get("is_dead") == true or r.get("is_hidden") == true:
		return null
	return r


func _move(dir: Vector3, speed: float, delta: float) -> void:
	velocity = dir * speed
	move_and_slide()
	_face(dir, delta * 12.0)


func _face(dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, weight))


static func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A quick scamper; a low crouch over the wind-up; a wagging tail.
func _animate() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var crouch := 1.0 if mode == Mode.WINDUP else 0.0
	_visual.position.y = absf(sin(_gait * 22.0)) * 0.015 * minf(speed, 7.0) - crouch * 0.08
	_visual.rotation.x = 0.15 * crouch - (0.1 if mode == Mode.LUNGE else 0.0)
	_tail.rotation.z = sin(_gait * (20.0 if mode == Mode.PAUSE else 8.0)) * 0.4


func _on_infection_changed(value: float) -> void:
	if mode == Mode.DEAD:
		return
	_body_mat.albedo_color = COAT.lerp(Props.RED, smoothstep(0.0, 60.0, value))


func _on_died() -> void:
	mode = Mode.DEAD
	_free_telegraph()
	remove_from_group("townsfolk")
	add_to_group("corpses")
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	_body_mat.albedo_color = CORPSE_INK
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_visual, "rotation", Vector3(0.0, 0.0, PI * 0.5), 0.35)
	tw.tween_property(_visual, "position", Vector3(0.0, 0.25, 0.0), 0.35)


func is_dead() -> bool:
	return mode == Mode.DEAD


## A rat Feeds on the corpse; false if alive or picked clean.
func take_meal() -> bool:
	if mode != Mode.DEAD or meals_left <= 0:
		return false
	meals_left -= 1
	_visual.scale = Vector3(lerpf(1.0, 0.3, float(MEALS - meals_left) / MEALS), 1.0, 1.0)
	if meals_left == 0:
		remove_from_group("corpses")
	return true
