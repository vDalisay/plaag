## A townsperson of the District: wanders inside wander_bounds, catches the
## plague from Bites (child InfectionComponent "Infection"), reddens, staggers,
## coughs ink and finally falls over as a corpse that stays in the world.
## Rats nearby (child FearComponent "Fear") change what they do: FIGHT walks at
## the nearest rat and stomps (child WeaponComponent "Weapon"), UNEASY keeps its
## distance, FLEE runs away with the arms up for at least FLEE_MIN seconds.
## A corpse holds `meals_left` meals for the Colony and flattens as it is eaten.
## Houses: a person may have a `home` and spends time indoors (hidden, out of
## group "townsfolk", in group "indoors"; the Infection keeps ticking). Now and
## then they walk home, and in FLEE they run into a nearby door. Someone who
## dies indoors stays hidden inside and never joins "corpses".
## M5: the spawner may call setup(def, year_entry) before add_child to give the
## person a TownsfolkDef type (look, weapon, speed, Guards' always_fight) and
## the Year's Hygiene, speed and wind-up. Without it they are a plain stomper.
## M7: with Contagion unlocked, the first person in a scene adds the scene's
## Contagion node (scripts/components/contagion.gd), which spreads the plague
## between outdoor townsfolk.
class_name Townsperson
extends CharacterBody3D

const Props := preload("res://scripts/town_props.gd")
## Cloak colour of a corpse: a dark sepia that the shader draws as heavy hatching,
## so corpses stay distinct from the solid-ink rats Feeding on them.
const CORPSE_INK := Color(0.34, 0.29, 0.24)
const SCALE := 1.1
const FIGHT_SPEED := 2.2
const UNEASY_SPEED := 1.8
const FLEE_SPEED := 3.2
## Seconds a person keeps running once they break.
const FLEE_MIN := 2.0
## Distance an UNEASY person tries to keep from the nearest rat.
const UNEASY_KEEP := 5.0
const INFECTED_SPEED := 0.55
const INFECTED_WINDUP := 1.5
const MEALS := 3
## Routine: seconds outdoors between trips home, and how long a trip home lasts.
const ROUTINE_GAP := Vector2(20.0, 40.0)
const ROUTINE_STAY := Vector2(10.0, 25.0)
## Seconds before someone who spawned indoors comes out.
const START_STAY := Vector2(5.0, 30.0)
## FLEE runs into a door this close, and stays in this long.
const FLEE_DOOR_RANGE := 10.0
const FLEE_STAY := Vector2(8.0, 15.0)
## Giving up on a door that can't be reached.
const DOOR_TIMEOUT := 8.0
## Close enough to the door to step in.
const DOOR_REACH := 0.6
## Distance outside the door a person reappears at.
const DOOR_STEP_OUT := 0.8
## Seconds after coming out before FLEE may send them back in.
const REENTER_COOLDOWN := 4.0
## Physics layer of houses and bounds, used by the door steering.
const WORLD_MASK := 1

enum Mode { WANDER, FIGHT, UNEASY, FLEE }

## XZ rectangle the person wanders in (x -> X, y -> Z). Set by the spawner.
@export var wander_bounds := Rect2(-8.0, -8.0, 16.0, 16.0)
## Seed for the look and the wandering; 0 picks a random one.
@export var rng_seed := 0
@export var walk_speed := 1.6
## Chance of the red-cloaked variant.
@export var red_chance := 0.15

## Cloak variant from the Props kit: "plain" or "red".
var kind := "plain"
## Visual type (TownsfolkDef.look): plain | red | broom | torch | club | guard.
var look := "plain"
## The type given by setup() (null for a plain stomper without data).
var def: TownsfolkDef
## Guards attack whatever their Fear: they never turn UNEASY or FLEE.
var always_fight := false
## The house this person lives in (set by the spawner before add_child; may be null).
var home: House
var is_indoors := false
## The house the person is inside right now (null outdoors).
var current_house: House
## Meals the Colony can still take from this corpse (only meaningful once dead).
var meals_left := MEALS

var _rng := RandomNumberGenerator.new()
var _props: Props
var _visual: Node3D          # pivot at the feet, tilted for gait / toppled on death
var _cloak_mat: StandardMaterial3D
var _cloak_color := Props.COAT
var _sick_color := Props.RED
var _target := Vector3.ZERO
var _idle_left := 0.0
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
var _gait_time := 0.0
var _cough_left := 0.0
var _dead := false
var _mode := Mode.WANDER
var _flee_left := 0.0
var _flee_dir := Vector3.ZERO
var _side := 1.0             # UNEASY sidestep direction
var _side_left := 0.0
var _arm_pivots: Array[Node3D] = []
var _arms_up := 0.0          # 0 hanging .. 1 thrown up (FLEE)
var _slam_left := 0.0        # forward slam after a stomp lands
var _death_tween: Tween
var _start_house: House      # start_indoors() before _ready
var _inside_left := 0.0      # seconds until coming back out
var _routine_left := 0.0     # seconds until the next trip home
var _reenter_left := 0.0
var _flee_scan := 0.0
var _going: House             # house being walked to (null when not)
var _going_flee := false
var _going_stay := 0.0
var _going_time := 0.0
var _waypoint := Vector3.ZERO
var _has_waypoint := false
var _replan_left := 0.0
var _layer := 0              # collision while outdoors (restored on coming out)
var _mask := 0
var _probe := SphereShape3D.new()   # body-sized probe for the door steering
var _year: YearEntry         # from setup(); null without one
var _speed_mult := 1.0       # Year speed factor for every gait
var _windup_base := 1.0      # Year wind-up factor
var _held: Node3D            # broom / torch / club in the right hand

@onready var _infection: InfectionComponent = $Infection
@onready var _fear: FearComponent = $Fear
@onready var _weapon: WeaponComponent = $Weapon
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_props = Props.new(_rng.randi())
	kind = "red" if _rng.randf() < red_chance else "plain"
	# Typed townsfolk never wear red (red means plague) unless their look is
	# "red"; a typed "plain" keeps the usual chance of the red cloak.
	if def != null and look != "plain":
		kind = "red" if look == "red" else "plain"
	else:
		look = kind
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var fig := _props.figure(_visual, Vector3.ZERO, 0.0, kind, SCALE)
	_split_cloak_material()
	_rig_arms(fig)
	_dress(fig)
	_apply_setup()
	rotation.y = _rng.randf_range(-PI, PI)
	_gait_time = _rng.randf_range(0.0, 10.0)
	_idle_left = _rng.randf_range(0.0, 1.5)
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_pick_target()
	_infection.value_changed.connect(_on_infection_changed)
	_infection.infected.connect(_on_infected)
	_infection.died.connect(_on_died)
	_fear.band_changed.connect(_on_band_changed)
	_weapon.struck.connect(_on_struck)
	_probe.radius = 0.35
	_layer = collision_layer
	_mask = collision_mask
	_routine_left = _rng.randf_range(ROUTINE_GAP.x, ROUTINE_GAP.y)
	if _start_house != null:
		var h := _start_house
		_start_house = null
		_enter(h, _rng.randf_range(START_STAY.x, START_STAY.y))
	# M7: townsfolk pass the plague on once Contagion is unlocked.
	Contagion.ensure_for(self)


## Gives the person a type and the Year's numbers. Called by the spawner before
## add_child (safe after it too): look, weapon (null keeps the stomp), walk
## speed * Year speed, always_fight, Infection gain = gain * (1 - Hygiene) and
## the Year's wind-up factor. The look only applies before _ready.
func setup(type_def: TownsfolkDef, year_entry: YearEntry) -> void:
	def = type_def
	_year = year_entry
	if def == null:
		return
	look = def.look
	always_fight = def.always_fight
	_speed_mult = year_entry.speed_mult if year_entry != null else 1.0
	_windup_base = year_entry.windup_mult if year_entry != null else 1.0
	walk_speed = def.walk_speed * _speed_mult
	if is_node_ready():
		_apply_setup()


## Pushes the setup() numbers into the components (once they exist).
func _apply_setup() -> void:
	if def == null:
		return
	if def.weapon != null:
		_weapon.weapon = def.weapon
	var hygiene := _year.hygiene if _year != null else 0.0
	_infection.gain_multiplier = def.gain_multiplier * (1.0 - hygiene)


## Speed factor of every gait (the Year's speed_mult; 1 without setup()).
func speed_multiplier() -> float:
	return _speed_mult


## Adds the look's extras to the figure: a broom, torch or club in the right
## hand, or a Guard's helmet and tabard (holding whatever their weapon is).
func _dress(fig: Node3D) -> void:
	var item := look
	if look == "guard":
		_guard_kit(fig)
		var w := def.weapon if def != null else null
		item = String(w.kind) if w != null else ""
	if _arm_pivots.size() < 2 or not item in ["broom", "torch", "club"]:
		return
	# The right hand, in the right arm pivot's space.
	_held = _props.node(_arm_pivots[1], Vector3(0.06, -0.92, 0.02))
	_held.name = item.capitalize()
	match item:
		"broom":
			# Shaft down and forward; a wide, flat straw head on the ground.
			var top := Vector3(-0.05, 0.55, -0.25)
			var foot := Vector3(0.25, -0.6, 0.95)
			_props.strip(_held, top, foot, 0.07, Props.TIMBER)
			var fwd := Vector3(foot.x - top.x, 0.0, foot.z - top.z).normalized()
			var head := Node3D.new()
			_held.add_child(head)
			head.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), foot + fwd * 0.25 + Vector3(0, -0.04, 0))
			_props.part(head, _props.cyl(0.36, 0.1, 0.55, 8), Props.WOOD, Vector3.ZERO, Vector3(-90, 0, 0),
				Vector3(1.0, 1.0, 0.3))
			_props.part(head, _props.box(Vector3(0.26, 0.14, 0.09)), Props.TIMBER, Vector3(0, 0.02, 0.24))
			for z: float in [0.02, -0.16]:
				var w := lerpf(0.42, 0.62, (0.24 - z) / 0.55)
				_props.strip(head, Vector3(-w * 0.5, 0.06, z), Vector3(w * 0.5, 0.06, z), 0.05, Props.TIMBER)
		"torch":
			# Held out and up at the side, the flame clear of the hat.
			var tip := Vector3(0.38, 1.2, 0.3)
			_props.strip(_held, Vector3(0, -0.12, 0), tip, 0.08, Props.TIMBER)
			_props.part(_held, _props.cyl(0.12, 0.08, 0.16, 8), Props.TIMBER, tip)
			_props.part(_held, _props.sphere(0.22, 10), Props.AMBER, tip + Vector3(0, 0.18, 0), Vector3.ZERO,
				Vector3(1, 1.1, 1), 3.0)
			_props.part(_held, _props.cyl(0.0, 0.17, 0.5, 6), Props.AMBER, tip + Vector3(0, 0.48, 0), Vector3.ZERO,
				Vector3.ONE, 3.0)
		"club":
			# A thick, short cudgel held out to the side, its knob clear of the cloak.
			var grip := Vector3(0, 0.1, -0.06)
			var end := Vector3(0.48, -0.3, 0.55)
			var c := Node3D.new()
			_held.add_child(c)
			c.transform = Transform3D(Basis.looking_at(end - grip, Vector3.UP), (grip + end) * 0.5)
			var length := grip.distance_to(end)
			_props.part(c, _props.cyl(0.08, 0.2, length, 8), Props.INK, Vector3.ZERO, Vector3(90, 0, 0))
			_props.part(c, _props.sphere(0.23, 10), Props.INK, Vector3(0, 0, -length * 0.5))
			for i in 3:
				var a := TAU * i / 3.0
				_props.part(c, _props.cyl(0.0, 0.06, 0.14, 4), Props.INK,
					Vector3(cos(a) * 0.2, sin(a) * 0.2, -length * 0.5), Vector3(0, 0, rad_to_deg(a) - 90.0))


## Guard: the hat swapped for a TIMBER kettle helmet with a pale crest, and a
## pale tabard with an ink cross over the shoulders, front and back.
func _guard_kit(fig: Node3D) -> void:
	for c: Node in fig.get_children():
		var n := c as Node3D
		if n != null and not (n is MeshInstance3D) and n.position.y > 2.2:
			n.free()   # the hat
	var helm := _props.node(fig, Vector3(0, 2.2, 0.0))
	helm.name = "Helmet"
	_props.part(helm, _props.cyl(0.42, 0.44, 0.05, 18), Props.TIMBER, Vector3.ZERO)
	_props.part(helm, _props.sphere(0.25, 12), Props.TIMBER, Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
	_props.strip(helm, Vector3(0, 0.27, -0.24), Vector3(0, 0.27, 0.24), 0.06, Props.STONE)
	var tab := _props.node(fig, Vector3.ZERO)
	tab.name = "Tabard"
	_props.part(tab, _props.box(Vector3(0.78, 0.07, 0.62)), Props.WALL, Vector3(0, 1.86, 0))
	_props.strip(tab, Vector3(-0.39, 1.91, 0), Vector3(0.39, 1.91, 0), 0.07, Props.TIMBER)
	_props.strip(tab, Vector3(0, 1.91, -0.31), Vector3(0, 1.91, 0.31), 0.07, Props.TIMBER)
	for z: float in [-1.0, 1.0]:
		var zz := z * 0.4
		_props.part(tab, _props.box(Vector3(0.5, 1.0, 0.04)), Props.WALL, Vector3(0, 1.32, zz), Vector3(-z * 9.0, 0, 0))
		_props.strip(tab, Vector3(0, 1.75, zz + z * 0.03), Vector3(0, 0.95, zz + z * 0.15), 0.06, Props.TIMBER)
		_props.strip(tab, Vector3(-0.22, 1.5, zz + z * 0.06), Vector3(0.22, 1.5, zz + z * 0.06), 0.06, Props.TIMBER)


## Props caches one material per colour, so give this figure's cloak parts a
## private copy that can be tinted without reddening everybody else.
func _split_cloak_material() -> void:
	if kind == "red":
		_cloak_color = Props.RED
		_sick_color = Props.TAIL   # already red: deepen to dried-blood instead
	var shared := _props.mat(_cloak_color)
	_cloak_mat = shared.duplicate() as StandardMaterial3D
	for n: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == shared:
			mi.material_override = _cloak_mat


## Moves the arm, cuff and hand meshes of the figure under a pivot at each
## shoulder so FLEE can throw the arms up. Props builds them as the only direct
## children of the figure root that far out to the side and below the shoulder.
func _rig_arms(fig: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "ArmL" if s < 0.0 else "ArmR"
		pivot.position = Vector3(s * 0.4, 1.66, 0.04)
		fig.add_child(pivot)
		_arm_pivots.append(pivot)
	for c: Node in fig.get_children():
		var mi := c as MeshInstance3D
		if mi == null or absf(mi.position.x) < 0.38 or mi.position.y > 1.5:
			continue
		var pivot := _arm_pivots[0] if mi.position.x < 0.0 else _arm_pivots[1]
		fig.remove_child(mi)
		pivot.add_child(mi)
		mi.position -= pivot.position


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if is_indoors:
		_inside_left -= delta
		if _inside_left <= 0.0:
			come_outside()
		return
	var sick := _infection.is_infected()
	var slow := INFECTED_SPEED if sick else 1.0
	_weapon.windup_multiplier = _windup_base * (INFECTED_WINDUP if sick else 1.0)
	_flee_left = maxf(0.0, _flee_left - delta)
	_slam_left = maxf(0.0, _slam_left - delta)
	_reenter_left = maxf(0.0, _reenter_left - delta)
	var prev := _mode
	if always_fight:
		_mode = Mode.FIGHT if _fear.rats_near > 0 else Mode.WANDER
	elif _fear.band == FearComponent.Band.FLEE or _flee_left > 0.0:
		_mode = Mode.FLEE
	elif _fear.rats_near > 0 and _fear.band == FearComponent.Band.UNEASY:
		_mode = Mode.UNEASY
	elif _fear.rats_near > 0:
		_mode = Mode.FIGHT
	else:
		_mode = Mode.WANDER
	_weapon.enabled = _mode == Mode.FIGHT
	if _mode != Mode.FIGHT and _weapon.is_winding_up():
		_weapon.cancel()
	if prev != Mode.WANDER and _mode == Mode.WANDER:
		_pick_target()
		_idle_left = 0.0
	var gait_rate := 1.0
	if _mode == Mode.FLEE:
		gait_rate = 1.8
	elif _mode == Mode.FIGHT:
		gait_rate = 1.25
	_gait_time += delta * (2.2 if sick else 1.0) * gait_rate
	_plan_house(delta)
	if _going != null:
		var speed := (FLEE_SPEED * slow * _speed_mult) if _going_flee else walk_speed * slow
		_walk_to_door(delta, speed, sick)
		if is_indoors:
			return
	else:
		_act(delta, slow, sick)
	if sick:
		_cough_left -= delta
		if _cough_left <= 0.0:
			_cough()
			_cough_left = _rng.randf_range(1.5, 4.0)


## Starts, keeps or drops a walk to a door: FLEE runs into a nearby house, the
## routine sends a calm person home, and rats nearby call a routine walk off.
func _plan_house(delta: float) -> void:
	if _going != null:
		if not _going_flee and _mode != Mode.WANDER:
			_cancel_going()
			_routine_left = _rng.randf_range(ROUTINE_GAP.x, ROUTINE_GAP.y) * 0.5
		return
	if _mode == Mode.FLEE:
		_flee_scan -= delta
		if _flee_scan <= 0.0 and _reenter_left <= 0.0:
			_flee_scan = 0.5
			var h := _flee_house()
			if h != null:
				go_inside(h, _rng.randf_range(FLEE_STAY.x, FLEE_STAY.y), true)
		return
	_flee_scan = 0.0
	if _mode == Mode.WANDER and home != null and is_instance_valid(home):
		_routine_left -= delta
		if _routine_left <= 0.0:
			go_inside(home, _rng.randf_range(ROUTINE_STAY.x, ROUTINE_STAY.y))


func _act(delta: float, slow: float, sick: bool) -> void:
	match _mode:
		Mode.FIGHT:
			_fight(delta, slow, sick)
		Mode.UNEASY:
			_uneasy(delta, slow, sick)
		Mode.FLEE:
			_flee(delta, slow, sick)
		_:
			_wander(delta, sick)


func _wander(delta: float, sick: bool) -> void:
	if _idle_left > 0.0:
		_idle_left -= delta
		velocity = Vector3.ZERO
		_animate(delta, sick, false)
		if _idle_left <= 0.0:
			_pick_target()
		return
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.3:
		_idle_left = _rng.randf_range(1.0, 3.0)
		velocity = Vector3.ZERO
		_animate(delta, sick, false)
		return
	var speed := walk_speed * (INFECTED_SPEED if sick else 1.0)
	_walk(to_target.normalized(), speed, delta)
	_animate(delta, sick, true)
	# Stuck against a wall or another person: give up on this point.
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		if global_position.distance_to(_stuck_from) < speed * 0.6 * 0.25:
			_pick_target()
		_stuck_from = global_position
		_stuck_check = 0.6


## Walk at the nearest rat (a torch stops at throwing range); stand planted
## while an attack winds up.
func _fight(delta: float, slow: float, sick: bool) -> void:
	if _weapon.is_winding_up():
		velocity = Vector3.ZERO
		_face(_weapon.strike_point() - global_position, delta * 10.0)
		_animate(delta, sick, false)
		return
	var rat := _fear.nearest_rat()
	if rat == null:
		velocity = Vector3.ZERO
		_animate(delta, sick, false)
		return
	var to := rat.global_position - global_position
	to.y = 0.0
	if to.length() < _weapon.preferred_range():
		velocity = Vector3.ZERO
		_face(to, delta * 10.0)
		_animate(delta, sick, false)
		return
	_walk(to.normalized(), FIGHT_SPEED * slow * _speed_mult, delta)
	_animate(delta, sick, true)


## Keep about UNEASY_KEEP from the nearest rat, sidestepping around it.
func _uneasy(delta: float, slow: float, sick: bool) -> void:
	var rat := _fear.nearest_rat()
	if rat == null:
		velocity = Vector3.ZERO
		_animate(delta, sick, false)
		return
	_side_left -= delta
	if _side_left <= 0.0:
		_side_left = _rng.randf_range(1.5, 3.0)
		if _rng.randf() < 0.4:
			_side = -_side
	var away := rat.global_position.direction_to(global_position)
	away.y = 0.0
	var d := Vector2(global_position.x - rat.global_position.x, global_position.z - rat.global_position.z).length()
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD
	var radial := clampf((UNEASY_KEEP - d) / 1.5, -0.6, 1.0)
	var dir := away * radial + away.cross(Vector3.UP) * _side * 0.7
	var speed := UNEASY_SPEED * slow * _speed_mult * clampf(dir.length(), 0.4, 1.0)
	var before := global_position
	velocity = dir.normalized() * speed
	move_and_slide()
	# Backed into a wall: sidestep the other way.
	if global_position.distance_to(before) < speed * delta * 0.2:
		_side = -_side
	_face(-away, delta * 6.0)   # keep an eye on the rats
	_animate(delta, sick, true)


## Run directly away from the rats.
func _flee(delta: float, slow: float, sick: bool) -> void:
	var away := _fear.away_direction()
	if away != Vector3.ZERO:
		_flee_dir = away
	elif _flee_dir == Vector3.ZERO:
		_flee_dir = global_basis.z
	_walk(_flee_dir, FLEE_SPEED * slow * _speed_mult, delta)
	_animate(delta, sick, true)


func _walk(dir: Vector3, speed: float, delta: float) -> void:
	velocity = dir * speed
	move_and_slide()
	_face(dir, delta * 6.0)


func _face(dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, weight))


## A light bob while walking; a slow side-to-side sway once infected. FLEE runs
## with a quicker gait and the arms thrown up; FIGHT leans forward with a heavy
## step, rears back over a wind-up and slams forward when the stomp lands.
func _animate(delta: float, sick: bool, walking: bool) -> void:
	var lean := 0.0
	var sway := 0.0
	var lift := 0.0
	if sick:
		sway = sin(_gait_time * 2.0) * 0.13
		lean = 0.08
		lift = absf(sin(_gait_time * 2.0)) * 0.04 if walking else 0.0
	else:
		lift = absf(sin(_gait_time * 9.0)) * 0.05 if walking else 0.0
	if _mode == Mode.FLEE:
		lean += 0.1
		lift *= 1.6
	elif _mode == Mode.FIGHT:
		lean += 0.16
		lift *= 1.4
	if _weapon.is_winding_up():
		var t := _weapon.windup_progress()
		lean = -0.14 * t
		lift = 0.2 * t
	elif _slam_left > 0.0:
		lean = 0.35 * _slam_left / 0.25
		lift = 0.0
	_visual.rotation = Vector3(lean, 0.0, sway)
	_visual.position.y = lift
	_arms_up = move_toward(_arms_up, 1.0 if _mode == Mode.FLEE else 0.0, delta * 6.0)
	for i in _arm_pivots.size():
		var s := -1.0 if i == 0 else 1.0
		var flail := sin(_gait_time * 14.0 + i * PI) * 0.3 * _arms_up
		_arm_pivots[i].rotation.z = s * (_arms_up * 2.5 + flail)


func _pick_target() -> void:
	var b := wander_bounds.abs()
	_target = Vector3(_rng.randf_range(b.position.x, b.end.x), global_position.y if is_inside_tree() else 0.0,
			_rng.randf_range(b.position.y, b.end.y))
	_stuck_from = global_position if is_inside_tree() else position
	_stuck_check = 0.6


func _on_infection_changed(value: float) -> void:
	if _dead:
		return
	# Clearly saturated by about 60 %, fully red from there on.
	var t := smoothstep(0.0, 60.0, value)
	_cloak_mat.albedo_color = _cloak_color.lerp(_sick_color, t)


func _on_infected() -> void:
	_cough_left = _rng.randf_range(0.5, 2.0)


func _on_band_changed(band: int) -> void:
	if band == FearComponent.Band.FLEE and not _dead and not always_fight:
		_flee_left = FLEE_MIN


func _on_struck(_point: Vector3, _hits: int) -> void:
	_slam_left = 0.25


func _on_died() -> void:
	_dead = true
	_cancel_going()
	remove_from_group("townsfolk")
	remove_from_group("indoors")
	# Indoors the body stays hidden inside the house: no corpse to Feed on.
	if not is_indoors:
		add_to_group("corpses")
	meals_left = MEALS
	_weapon.cancel()
	_weapon.enabled = false
	_weapon.set_physics_process(false)
	_fear.set_physics_process(false)
	for p in _arm_pivots:
		p.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	_cloak_mat.albedo_color = CORPSE_INK
	# Tip over sideways onto the ground; lift a little so the cloak doesn't sink in.
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	_visual.scale = Vector3.ONE
	_death_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(_visual, "rotation", Vector3(0.0, 0.0, side * PI * 0.5), 0.45)
	_death_tween.tween_property(_visual, "position", Vector3(0.0, 0.42, 0.0), 0.45)


func is_dead() -> bool:
	return _dead


## A rat Feeds on this corpse. Returns false if alive or already picked clean.
## Each meal flattens the body a little; the last leaves a flat ink smear that
## is no longer in group "corpses".
func take_meal() -> bool:
	if not _dead or meals_left <= 0:
		return false
	meals_left -= 1
	if _death_tween and _death_tween.is_valid():
		_death_tween.custom_step(10.0)   # finish the topple at once
		_death_tween.kill()
	var eaten := float(MEALS - meals_left) / float(MEALS)
	# Lying on its side, the visual's local X is the world's vertical.
	var flat := lerpf(1.0, 0.2, eaten)
	var thin := lerpf(1.0, 0.85, eaten)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3(flat, thin, thin), 0.25)
	tw.tween_property(_visual, "position:y", 0.42 * flat, 0.25)
	if meals_left == 0:
		remove_from_group("corpses")
		_smear()
	return true


## A flat ink stain under what's left of the body.
func _smear() -> void:
	var stain := MeshInstance3D.new()
	stain.name = "Smear"
	stain.mesh = _props.cyl(0.8, 0.8, 0.02, 14)
	stain.material_override = _props.mat(Props.INK)
	stain.top_level = true
	add_child(stain)
	var b := Basis(Vector3.UP, rotation.y) * Basis.from_scale(Vector3(0.7, 1.0, 1.3))
	stain.global_transform = Transform3D(b, Vector3(global_position.x, 0.03, global_position.z))


## A small ink dot puffs out beside the face and fades away.
func _cough() -> void:
	var dot := MeshInstance3D.new()
	dot.mesh = _props.sphere(0.07, 6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Props.INK
	m.roughness = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material_override = m
	dot.top_level = true
	add_child(dot)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var start := global_transform * Vector3(side * 0.35, 2.15, 0.35)
	dot.global_position = start
	var tw := dot.create_tween().set_parallel(true)
	tw.tween_property(dot, "global_position", start + global_basis * Vector3(side * 0.5, 0.25, 0.4), 0.9)
	tw.tween_property(dot, "scale", Vector3.ONE * 1.8, 0.9)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(dot.queue_free)


# ------------------------------------------------------------------------ houses
## Spawns already inside `house` (no walking). Safe before or after add_child.
func start_indoors(house: House) -> void:
	if house == null:
		return
	if not is_node_ready():
		_start_house = house
		return
	_enter(house, _rng.randf_range(START_STAY.x, START_STAY.y))


## Walks to the house's door (steering around walls) and vanishes inside.
## Stays `stay` seconds (a routine trip home when negative); `flee` runs.
## Gives up after DOOR_TIMEOUT if the door can't be reached.
func go_inside(house: House, stay := -1.0, flee := false) -> void:
	if house == null or _dead or is_indoors:
		return
	_going = house
	_going_flee = flee
	_going_stay = stay if stay >= 0.0 else _rng.randf_range(ROUTINE_STAY.x, ROUTINE_STAY.y)
	_going_time = 0.0
	_has_waypoint = false
	_replan_left = 0.0
	_stuck_from = global_position if is_inside_tree() else position
	_stuck_check = 0.6


## Steps out of the house, just outside its door. The dead stay inside.
func come_outside() -> void:
	if not is_indoors or _dead:
		return
	var house := current_house
	is_indoors = false
	current_house = null
	if house != null and is_instance_valid(house):
		var n := _door_normal(house)
		global_position = _door_of(house) + n * DOOR_STEP_OUT
		rotation.y = atan2(n.x, n.z)
		house.leave(self)
	visible = true
	collision_layer = _layer
	collision_mask = _mask
	_shape.set_deferred("disabled", false)
	_fear.set_physics_process(true)
	_fear.update_now()
	_weapon.set_physics_process(true)
	remove_from_group("indoors")
	add_to_group("townsfolk")
	_mode = Mode.WANDER
	_flee_left = 0.0
	_reenter_left = REENTER_COOLDOWN
	_routine_left = _rng.randf_range(ROUTINE_GAP.x, ROUTINE_GAP.y)
	_idle_left = _rng.randf_range(0.3, 1.2)
	_pick_target()


func _enter(house: House, stay: float) -> void:
	_cancel_going()
	is_indoors = true
	current_house = house
	_inside_left = stay
	visible = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	_weapon.cancel()
	_weapon.enabled = false
	_weapon.set_physics_process(false)
	_fear.set_physics_process(false)
	_flee_left = 0.0
	remove_from_group("townsfolk")
	add_to_group("indoors")
	# Wait just inside the door (nothing outdoors looks at the indoors).
	var at := _door_of(house) - _door_normal(house)
	if is_inside_tree():
		global_position = at
	else:
		position = at
	house.enter(self)


func _cancel_going() -> void:
	_going = null
	_going_flee = false
	_has_waypoint = false


## Heads for the door of `_going`. A clear straight line walks straight; a
## blocked one goes via a waypoint that sees both us and the door, or failing
## that slides along the wall. Gives up after DOOR_TIMEOUT.
func _walk_to_door(delta: float, speed: float, sick: bool) -> void:
	if not is_instance_valid(_going):
		_cancel_going()
		return
	_going_time += delta
	if _going_time > DOOR_TIMEOUT:
		_cancel_going()
		_routine_left = _rng.randf_range(ROUTINE_GAP.x, ROUTINE_GAP.y)
		_reenter_left = REENTER_COOLDOWN
		_pick_target()
		return
	var door := _door_of(_going)
	var to_door := door - global_position
	to_door.y = 0.0
	if to_door.length() <= DOOR_REACH:
		_enter(_going, _going_stay)
		return
	_replan_left -= delta
	if _replan_left <= 0.0:
		_replan_left = 0.4
		if _clear(global_position, door):
			_has_waypoint = false
		elif not _has_waypoint or not _clear(global_position, _waypoint):
			_has_waypoint = _find_waypoint(door)
	var goal := _waypoint if _has_waypoint else door
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if _has_waypoint and to_goal.length() < 0.5:
		_has_waypoint = false
		_replan_left = 0.0
		to_goal = to_door
	var dir := to_goal.normalized()
	if not _has_waypoint and not _clear(global_position, global_position + dir * 1.2):
		dir = _slide_dir(dir)
	_walk(dir, speed, delta)
	_animate(delta, sick, true)
	# Pinned in place: plan afresh and try the other side.
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		if global_position.distance_to(_stuck_from) < speed * 0.6 * 0.2:
			_has_waypoint = false
			_replan_left = 0.0
			_side = -_side
		_stuck_from = global_position
		_stuck_check = 0.6


## A point near us with a clear line from here and a clear line to the door,
## preferring the shortest detour. Returns false if there is none.
func _find_waypoint(door: Vector3) -> bool:
	var best := INF
	var here := global_position
	for r: float in [2.5, 5.0, 8.0]:
		for i in 12:
			var a := TAU * float(i) / 12.0
			var p := here + Vector3(cos(a), 0.0, sin(a)) * r
			var cost := r + Vector2(p.x - door.x, p.z - door.z).length()
			if cost >= best:
				continue
			if _clear(here, p) and _clear(p, door):
				best = cost
				_waypoint = p
	return best < INF


## Turns `dir` left or right (keeping the side we turned last) until the way is
## open, so a person slides along a wall instead of pushing into it.
func _slide_dir(dir: Vector3) -> Vector3:
	for step in range(1, 7):
		for s: float in [_side, -_side]:
			var d := dir.rotated(Vector3.UP, s * step * PI / 7.0)
			if _clear(global_position, global_position + d * 1.2):
				_side = s
				return d
	return dir


## True when a body-sized sphere can travel from a to b without hitting the world.
func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.collision_mask = WORLD_MASK
	var from := Vector3(a.x, 0.7, a.z)
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = Vector3(b.x, 0.7, b.z) - from
	var hit := get_world_3d().direct_space_state.cast_motion(q)
	return hit.is_empty() or hit[0] >= 1.0


## Home if its door is close, else the nearest house door within FLEE_DOOR_RANGE.
func _flee_house() -> House:
	var here := global_position
	var r2 := FLEE_DOOR_RANGE * FLEE_DOOR_RANGE
	if home != null and is_instance_valid(home) and _flat_d2(_door_of(home), here) <= r2:
		return home
	var best: House = null
	var best_d := r2
	for n: Node in get_tree().get_nodes_in_group("houses"):
		var h := n as House
		if h == null:
			continue
		var d := _flat_d2(_door_of(h), here)
		if d <= best_d:
			best_d = d
			best = h
	return best


func _flat_d2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()


func _door_of(house: House) -> Vector3:
	return house.door_position


## The door normal, flattened; +Z if the house has none set.
func _door_normal(house: House) -> Vector3:
	var n := house.door_normal
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.BACK
