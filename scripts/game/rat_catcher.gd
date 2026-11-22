## The Rat-catcher (M6), the Exterminator of the slums. A tall figure in a long
## dark coat and a wide hat, a pole over the shoulder and a cage of dead rats
## on his back. He stalks the Lead Rat and fights with:
##   pole sweep: when the Lead Rat comes within `sweep_trigger`, an INK sector
##     (radius `sweep_radius`, `sweep_deg`) aimed at it fills in over
##     `sweep_windup`, then every rat inside gets `hit()` (Colony rats die, the
##     Lead Rat loses one hit);
##   spring traps: every `trap_interval` s he tosses a trap ~`trap_lead` u ahead
##     along the Lead Rat's path; at most `trap_max`, each lasts `trap_life` s;
##   the terrier: released when he arrives, it hunts the Lead Rat.
class_name RatCatcher
extends Exterminator

## Dark sepia of his coat: hatched heavily, so he reads darker than townsfolk.
const COAT := Color(0.30, 0.25, 0.20)
## The pole at rest: over the right shoulder, raised and angled out.
const REST_POLE := Vector3(-24.0, 32.0, 0.0)

@export var terrier_scene: PackedScene
@export var sweep_radius := 3.0
@export var sweep_deg := 120.0
@export var sweep_windup := 1.2
@export var sweep_cooldown := 6.0
## He winds up when the Lead Rat is this close (inside the sweep).
@export var sweep_trigger := 2.8
@export var trap_interval := 6.0
@export var trap_lead := 2.0
@export var trap_life := 20.0
@export var trap_max := 4
@export var trap_radius := 0.5
## Rats this close to him are swept whatever the angle.
const SWEEP_FEET := 0.5

## Distance he likes to keep from the Lead Rat while stalking it.
@export var stalk_distance := 2.0

var terrier: Node3D
var traps: Array[Node3D] = []

var _pole: Node3D
var _sweep_left := 0.0       # wind-up left (0 = not sweeping)
var _sweep_cd := 1.0
var _sweep_dir := Vector3.BACK
var _sweep_origin := Vector3.ZERO
var _telegraph: DangerZone
var _fill: Node3D
var _swing_left := 0.0       # follow-through animation after the strike
var _trap_left := 3.0


func _build() -> void:
	var fig := _props.figure(_visual, Vector3.ZERO, 0.0, "plain", 1.25)
	# Recolour the cloak a dark sepia, and swap the hat for a wide one.
	var old := _props.mat(Props.COAT)
	var coat := _props.mat(COAT)
	for n: Node in fig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == old:
			mi.material_override = coat
	for c: Node in fig.get_children():
		var n3 := c as Node3D
		if n3 != null and not (n3 is MeshInstance3D) and n3.position.y > 2.2:
			n3.free()
	var hat := _props.node(fig, Vector3(0, 2.25, -0.05))
	hat.name = "WideHat"
	hat.rotation_degrees = Vector3(-14, 0, 0)
	_props.part(hat, _props.cyl(0.66, 0.7, 0.05, 20), Props.INK, Vector3.ZERO)
	_props.part(hat, _props.cyl(0.22, 0.26, 0.3, 14), Props.INK, Vector3(0, 0.16, 0))
	_props.part(hat, _props.cyl(0.27, 0.27, 0.06, 14), Props.STONE, Vector3(0, 0.06, 0))
	# A long apron flap down the front: pale, with a ink strap at the neck.
	_props.part(fig, _props.box(Vector3(0.5, 0.95, 0.04)), Props.STONE, Vector3(0, 0.75, 0.47), Vector3(-17, 0, 0))
	# Straps of the cage across the chest.
	for s: float in [-1.0, 1.0]:
		_props.strip(fig, Vector3(s * 0.22, 1.82, 0.22), Vector3(s * 0.2, 1.25, 0.38), 0.07, Props.TIMBER)
	_build_cage(fig)
	# The pole: over the right shoulder, the hook end high in front.
	_pole = _props.node(fig, Vector3(0.36, 1.85, 0.0))
	_pole.name = "Pole"
	_pole.rotation_degrees = REST_POLE
	_props.strip(_pole, Vector3(0, 0, -1.1), Vector3(0, 0, 2.3), 0.12, Props.TIMBER)
	# The noose at the tip.
	_props.part(_pole, _props.torus(0.2, 0.06), Props.INK, Vector3(0, -0.05, 2.45), Vector3(90, 0, 0))
	_props.part(_pole, _props.cyl(0.05, 0.05, 0.12, 6), Props.STONE, Vector3(0, 0, 2.28), Vector3(90, 0, 0))
	tint_color(fig, COAT)


## A wooden cage on his back with three dead rats slumped inside.
func _build_cage(fig: Node3D) -> void:
	var cage := _props.node(fig, Vector3(0, 1.45, -0.6))
	cage.name = "Cage"
	var w := 0.62
	var h := 0.6
	var d := 0.42
	_props.part(cage, _props.box(Vector3(w + 0.06, 0.06, d + 0.06)), Props.WOOD, Vector3(0, h * 0.5, 0))
	_props.part(cage, _props.box(Vector3(w + 0.06, 0.06, d + 0.06)), Props.WOOD, Vector3(0, -h * 0.5, 0))
	for i in 5:
		var x := lerpf(-w * 0.5, w * 0.5, float(i) / 4.0)
		for z: float in [-d * 0.5, d * 0.5]:
			_props.strip(cage, Vector3(x, -h * 0.5, z), Vector3(x, h * 0.5, z), 0.04, Props.TIMBER)
	for z: float in [-d * 0.5, 0.0, d * 0.5]:
		for x: float in [-w * 0.5, w * 0.5]:
			_props.strip(cage, Vector3(x, -h * 0.5, z), Vector3(x, h * 0.5, z), 0.04, Props.TIMBER)
	for i in 3:
		var r := _props.node(cage, Vector3(-0.17 + i * 0.17, -h * 0.5 + 0.12 + (i % 2) * 0.13, 0.0))
		r.rotation_degrees = Vector3(0, 60.0 * i, 90.0 + 20.0 * i)
		_props.part(r, _props.sphere(0.1, 8), Props.INK, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.7, 1.5))
		_props.strip(r, Vector3(0, 0, -0.14), Vector3(0.05, -0.08, -0.4), 0.025, Props.TAIL)
	# A handle on top.
	_props.part(cage, _props.torus(0.12, 0.04), Props.TIMBER, Vector3(0, h * 0.5 + 0.1, 0), Vector3(90, 0, 0))


func _on_arrived() -> void:
	if terrier_scene == null:
		return
	terrier = terrier_scene.instantiate() as Node3D
	var side := global_basis.x * 0.9
	terrier.position = flat(global_position + side)
	get_parent().add_child(terrier)


func _think(delta: float) -> void:
	_sweep_cd = maxf(0.0, _sweep_cd - delta)
	_swing_left = maxf(0.0, _swing_left - delta)
	_update_traps(delta)
	if _sweep_left > 0.0:
		_sweep_left -= delta
		velocity = Vector3.ZERO
		face(_sweep_dir, delta * 12.0)
		set_fill(_fill, sweep_progress())
		if _telegraph != null:
			_telegraph.danger_time_left = maxf(0.0, _sweep_left)
		if _sweep_left <= 0.0:
			_strike()
		return
	var lead := lead_rat()
	var target := _sweep_target()
	if target != null and _sweep_cd <= 0.0:
		begin_sweep(target.global_position)
		return
	if lead == null:
		velocity = Vector3.ZERO
		return
	var to := flat(lead.global_position - global_position)
	if to.length() > stalk_distance:
		walk(to.normalized(), walk_speed, delta)
	else:
		velocity = Vector3.ZERO
		face(to, delta * 6.0)


## The rat to sweep at: the Lead Rat once it is within `sweep_trigger` (he
## stalks the Lead Rat; followers Biting him are swept only when it comes
## close), else null.
func _sweep_target() -> Node3D:
	var lead := lead_rat()
	if lead != null and flat_dist(lead.global_position, global_position) <= sweep_trigger:
		return lead
	return null


func is_sweeping() -> bool:
	return _sweep_left > 0.0


func sweep_progress() -> float:
	return clampf(1.0 - _sweep_left / sweep_windup, 0.0, 1.0) if sweep_windup > 0.0 else 1.0


## Starts the telegraphed sweep towards `at`: an INK sector outline with a fill
## that grows until the pole lands.
func begin_sweep(at: Vector3) -> void:
	_sweep_origin = flat(global_position)
	_sweep_dir = flat(at) - _sweep_origin
	_sweep_dir = _sweep_dir.normalized() if _sweep_dir.length_squared() > 0.0001 else global_basis.z
	_sweep_left = sweep_windup
	_free_telegraph()
	_telegraph = world_zone("SweepArc", _sweep_origin, atan2(_sweep_dir.x, _sweep_dir.z))
	_telegraph.set_arc(_sweep_origin, _sweep_dir, sweep_radius, deg_to_rad(sweep_deg) * 0.5, SWEEP_FEET, _sweep_left)
	ink_arc(_telegraph, sweep_radius, sweep_deg)
	_fill = fill_fan(_telegraph, sweep_radius, sweep_deg)
	set_fill(_fill, 0.0)


## The pole lands: every rat in the sector is hit. Returns the number hit.
func _strike() -> int:
	_sweep_left = 0.0
	_sweep_cd = sweep_cooldown
	_swing_left = 0.35
	_free_telegraph()
	var hits := 0
	var half := deg_to_rad(sweep_deg) * 0.5
	for r in live_rats():
		if not DangerZone.arc_contains(_sweep_origin, _sweep_dir, sweep_radius, half, SWEEP_FEET, r.global_position):
			continue
		if r.has_method("hit"):
			r.call("hit")
			hits += 1
	_swoosh()
	return hits


func _free_telegraph() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.retire()
	_telegraph = null
	_fill = null


## The arc's edge flung outwards and fading after the strike.
func _swoosh() -> void:
	var puff := world_node("SweepPuff", _sweep_origin, atan2(_sweep_dir.x, _sweep_dir.z))
	var m := fade_mat()
	var half := deg_to_rad(sweep_deg) * 0.5
	var prev := Vector3.ZERO
	for i in ARC_SEGMENTS + 1:
		var a := lerpf(-half, half, float(i) / ARC_SEGMENTS)
		var p := Vector3(sin(a), 0.0, cos(a)) * sweep_radius * 0.9 + Vector3(0, 0.15, 0)
		if i > 0:
			_props.strip(puff, prev, p, 0.14, Props.INK).material_override = m
		prev = p
	var tw := puff.create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3(1.3, 1.0, 1.3), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(puff.queue_free)


# ---------------------------------------------------------------------- traps
func _update_traps(delta: float) -> void:
	for i in range(traps.size() - 1, -1, -1):
		if not is_instance_valid(traps[i]) or traps[i].is_queued_for_deletion():
			traps.remove_at(i)
	_trap_left -= delta
	if _trap_left > 0.0:
		return
	var lead := lead_rat()
	if lead == null:
		_trap_left = 1.0
		return
	_trap_left = trap_interval
	var vel: Variant = lead.get("velocity")
	var v: Vector3 = vel if vel is Vector3 else Vector3.ZERO
	v.y = 0.0
	var ahead := v.normalized() if v.length() > 0.5 else flat(lead.global_basis.z).normalized()
	drop_trap(lead.global_position + ahead * trap_lead)


## Tosses a trap to `at` (the oldest goes when there are `trap_max`).
func drop_trap(at: Vector3) -> Node3D:
	while traps.size() >= trap_max:
		var old: Node3D = traps.pop_front()
		if is_instance_valid(old):
			(old as SpringTrap).disarm()
			old.queue_free()
	var trap := SpringTrap.new()
	trap.name = "SpringTrap"
	trap.setup(_props, trap_radius, trap_life)
	var world: Node = get_parent() if get_parent() != null else get_tree().root
	world.add_child(trap)
	trap.global_position = flat(at)
	trap.toss_from(global_position + Vector3(0, 1.6, 0))
	traps.append(trap)
	return trap


func _on_beaten() -> void:
	_free_telegraph()
	_sweep_left = 0.0


func _animate(delta: float) -> void:
	super._animate(delta)
	if _pole == null:
		return
	# Over the shoulder while walking; levelled and drawn back over the wind-up;
	# flung across the sector on the strike.
	if _sweep_left > 0.0:
		var t := sweep_progress()
		_pole.rotation_degrees = Vector3(lerpf(REST_POLE.x, 4.0, t), lerpf(REST_POLE.y, 70.0, t), 0.0)
	elif _swing_left > 0.0:
		var t := 1.0 - _swing_left / 0.35
		_pole.rotation_degrees = Vector3(4.0, lerpf(70.0, -70.0, minf(1.0, t * 2.5)), 0.0)
	else:
		_pole.rotation_degrees = _pole.rotation_degrees.lerp(REST_POLE, minf(1.0, delta * 6.0))


## A spring trap: a small INK jaw-ring with teeth pointing in. The first rat
## that steps within `radius` is `hit()`; the jaws snap shut and the trap is
## used up. It rusts away after `life` s. Group "traps"; a persistent
## DangerZone ("danger_zones") for as long as it is armed.
class SpringTrap extends DangerZone:
	var radius := 0.5
	var life := 20.0
	var armed := false
	var sprung := false
	var _props: Props
	var _age := 0.0
	var _jaws: Node3D
	var _teeth: Array[Node3D] = []
	var _from := Vector3.ZERO
	var _land := Vector3.ZERO

	func setup(props: Props, r: float, t: float) -> void:
		_props = props
		radius = r
		life = t

	func _ready() -> void:
		add_to_group("traps")
		if _props == null:
			_props = Props.new(31)
		_props.part(self, _props.cyl(radius * 0.45, radius * 0.45, 0.04, 12), Props.STONE, Vector3(0, 0.05, 0))
		_jaws = _props.node(self, Vector3.ZERO)
		_props.part(_jaws, _props.torus(radius * 0.8, 0.09), Props.INK, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
		for i in 10:
			var a := TAU * float(i) / 10.0
			var tooth := _props.node(_jaws, Vector3(sin(a), 0, cos(a)) * radius * 0.8 + Vector3(0, 0.12, 0))
			tooth.rotation.y = a
			_props.part(tooth, _props.cyl(0.0, 0.05, 0.2, 4), Props.INK, Vector3(0, 0, -0.1), Vector3(-90, 0, 0))
			_teeth.append(tooth)
		# The spring and the chain stake.
		_props.strip(self, Vector3(0, 0.1, radius * 0.8), Vector3(0.1, 0.06, radius * 1.4), 0.05, Props.INK)
		_props.part(self, _props.cyl(0.05, 0.05, 0.18, 6), Props.INK, Vector3(0.1, 0.09, radius * 1.4))

	## Flies in from `from` in a short arc; arms on landing.
	func toss_from(from: Vector3) -> void:
		_land = global_position
		_from = from
		global_position = from
		var tw := create_tween()
		tw.tween_method(_fly, 0.0, 1.0, 0.35)
		tw.tween_callback(arm_now)

	func _fly(t: float) -> void:
		var mid := (_from + _land) * 0.5 + Vector3(0, 1.2, 0)
		global_position = _from.lerp(mid, t).lerp(mid.lerp(_land, t), t)

	func arm_now() -> void:
		if sprung:
			return
		armed = true
		set_circle(global_position, radius, -1.0)
		activate()


	func disarm() -> void:
		armed = false
		if is_in_group(GROUP):
			remove_from_group(GROUP)

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= life and not sprung:
			sprung = true
			disarm()
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector3(0.05, 1.0, 0.05), 0.4)
			tw.tween_callback(queue_free)
			return
		if not armed or sprung:
			return
		for n: Node in get_tree().get_nodes_in_group("rats").duplicate():
			var r := n as Node3D
			if r == null or not is_instance_valid(r) or r.is_queued_for_deletion() or not r.has_method("hit"):
				continue
			if danger_contains(r.global_position):
				r.call("hit")
				_snap()
				return

	## Jaws shut: the teeth fold in, a little ink flash, then gone.
	func _snap() -> void:
		sprung = true
		disarm()
		for t in _teeth:
			t.rotation.x = -1.2
		_jaws.scale = Vector3(0.55, 1.6, 0.55)
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(self, "scale", Vector3(0.05, 1.0, 0.05), 0.3)
		tw.tween_callback(queue_free)
