## The Plague Doctor (M6), the Exterminator of the Merchant quarter: the red
## "doctor" figure of the prop kit with a pale beak mask, ink lenses, a cane
## and a censer. He belongs to the plague, hence the red. He follows the Colony
## at `keep_distance` and fights with:
##   cleanse pulse: every `pulse_interval` s an INK ring expands to
##     `pulse_radius` and Cleanses `pulse_amount` Infection from every living
##     townsperson inside it (himself excluded; his own self-Cleanse is the
##     Infection's cleanse_rate);
##   incense cloud: when rats come within `incense_trigger`, an INK dashed
##     circle of `incense_radius` fills in over `incense_windup` where he swings
##     the censer; then a pale cloud bursts there, knocking back every rat in it
##     and killing Pups.
## Rats are thrown out of Bite range, so only a big Colony Biting him at the
## same moment gets through his Cleanse.
## VFX pass (pooled, scripts/vfx/vfx.gd): sage herb smoke swirls round him
## all the time; the cleanse pulse is a ring of green puffs racing out to
## `pulse_radius`, with green flecks rising from everyone it cleansed; the
## swinging censer trails wisps; the incense cloud is pale and sage puffs
## billowing up inside an ink rim.
class_name PlagueDoctor
extends Exterminator

## Herb smoke puffs a second round him, and censer wisps a second in a swing.
const HERB_RATE := 9.0
const TRAIL_RATE := 24.0

@export var keep_distance := 3.0
@export var pulse_interval := 3.0
@export var pulse_radius := 6.0
@export var pulse_amount := 15.0
## Seconds the pulse ring takes to reach its full radius.
@export var pulse_expand := 0.5
@export var incense_trigger := 3.2
@export var incense_radius := 2.5
@export var incense_windup := 0.9
@export var incense_cooldown := 4.0
@export var incense_knockback := 3.5
## The cloud lands this far from him at most, towards the rats.
@export var incense_reach := 1.5

var pulses := 0

var _pulse_left := 1.5
var _incense_left := 0.0      # wind-up left (0 = not swinging)
var _incense_cd := 1.0
var _incense_at := Vector3.ZERO
var _telegraph: DangerZone
var _fill: Node3D
var _censer: Node3D
var _cane_arm: Node3D
var _herb_left := 0.0
var _trail_left := 0.0


func _build() -> void:
	var fig := _props.figure(_visual, Vector3.ZERO, 0.0, "doctor", 1.2)
	# The beak mask: a long pale cone over the face, ink-rimmed lenses.
	var beak := _props.node(fig, Vector3(0, 2.02, 0.2))
	beak.name = "Beak"
	_props.part(beak, _props.cyl(0.0, 0.14, 0.85, 10), Props.STONE, Vector3(0, -0.08, 0.4), Vector3(98, 0, 0))
	_props.strip(beak, Vector3(0, 0.07, 0.02), Vector3(0, -0.13, 0.8), 0.03, Props.TIMBER)
	for s: float in [-1.0, 1.0]:
		_props.part(beak, _props.torus(0.065, 0.03), Props.INK, Vector3(s * 0.1, 0.1, 0.03), Vector3(90, 0, 0))
		_props.part(beak, _props.sphere(0.05, 8), Props.INK, Vector3(s * 0.1, 0.1, 0.03), Vector3.ZERO, Vector3(1, 1, 0.4))
	# A wider brim on the red hat.
	for c: Node in fig.get_children():
		var n3 := c as Node3D
		if n3 != null and not (n3 is MeshInstance3D) and n3.position.y > 2.2:
			_props.part(n3, _props.cyl(0.46, 0.48, 0.03, 20), Props.RED, Vector3(0, -0.01, 0))
	# The cane in the right hand, down to the ground, with a pale knob.
	_cane_arm = _props.node(fig, Vector3(0.5, 0.78, 0.18))
	_cane_arm.name = "Cane"
	_props.strip(_cane_arm, Vector3(0, 0.25, 0), Vector3(0.08, -0.78, 0.22), 0.06, Props.TIMBER)
	_props.part(_cane_arm, _props.sphere(0.07, 8), Props.STONE, Vector3(0, 0.28, 0))
	# The censer on a chain from the left hand.
	_censer = _props.node(fig, Vector3(-0.48, 0.74, 0.1))
	_censer.name = "Censer"
	_props.strip(_censer, Vector3.ZERO, Vector3(0, -0.32, 0), 0.025, Props.INK)
	_props.part(_censer, _props.sphere(0.11, 8), Props.TIMBER, Vector3(0, -0.4, 0))
	_props.part(_censer, _props.cyl(0.0, 0.07, 0.1, 6), Props.TIMBER, Vector3(0, -0.27, 0))
	tint_color(fig, Props.RED, Props.TAIL)


func _think(delta: float) -> void:
	_incense_cd = maxf(0.0, _incense_cd - delta)
	_pulse_left -= delta
	if _pulse_left <= 0.0:
		_pulse_left = pulse_interval
		pulse()
	if _incense_left > 0.0:
		_incense_left -= delta
		velocity = Vector3.ZERO
		face(_incense_at - global_position, delta * 10.0)
		set_fill(_fill, incense_progress())
		if _telegraph != null:
			_telegraph.danger_time_left = maxf(0.0, _incense_left)
		if _incense_left <= 0.0:
			_burst()
		return
	var centre := _rats_centre(incense_trigger)
	if centre != Vector3.INF and _incense_cd <= 0.0:
		begin_incense(centre)
		return
	var goal := _goal()
	if goal == Vector3.INF:
		velocity = Vector3.ZERO
		return
	var to := flat(goal - global_position)
	if to.length() > keep_distance:
		walk(to.normalized(), walk_speed, delta)
	else:
		velocity = Vector3.ZERO
		face(to, delta * 5.0)


## The Lead Rat, else the nearest infected townsperson, else nothing (INF).
func _goal() -> Vector3:
	var lead := lead_rat()
	if lead != null:
		return lead.global_position
	var best := Vector3.INF
	var bd := INF
	for t: Node3D in _patients():
		var inf := t.get_node("Infection") as InfectionComponent
		var d := flat_dist(t.global_position, global_position)
		if inf.is_infected() and d < bd:
			bd = d
			best = t.global_position
	return best


## Every living townsperson but the Exterminators.
func _patients() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group("townsfolk"):
		var t := n as Node3D
		if t == null or t == self or t.is_in_group("exterminator"):
			continue
		var inf := t.get_node_or_null("Infection") as InfectionComponent
		if inf != null and not inf.is_dead():
			out.append(t)
	return out


## Mean position of the rats within `radius`, or Vector3.INF if none.
func _rats_centre(radius: float) -> Vector3:
	var col := get_tree().get_first_node_in_group("colony") as Colony
	if col != null and col.has_method("query_crowd"):
		var q: Dictionary = col.query_crowd(global_position, radius)
		return q["centre"] as Vector3 if int(q["count"]) > 0 else Vector3.INF
	var sum := Vector3.ZERO
	var count := 0
	for r in live_rats():
		if flat_dist(r.global_position, global_position) <= radius:
			sum += flat(r.global_position)
			count += 1
	return sum / float(count) if count > 0 else Vector3.INF


# ---------------------------------------------------------------------- cleanse pulse
## Cleanses `pulse_amount` from every living townsperson within `pulse_radius`
## and sends the green pulse ring out. Returns how many were Cleansed.
func pulse() -> int:
	pulses += 1
	var here := global_position
	var n := 0
	for t in _patients():
		if flat_dist(t.global_position, here) > pulse_radius:
			continue
		var inf := t.get_node("Infection") as InfectionComponent
		if inf.value > 0.0:
			inf.cleanse(pulse_amount)
			n += 1
			Vfx.play(get_tree(), &"heal", t.global_position)
	_pulse_ring()
	return n


## The pulse: green puffs racing out to the radius, and the cane raised.
func _pulse_ring() -> void:
	Vfx.play(get_tree(), &"cleanse_pulse", global_position, Vector3.ZERO, pulse_radius, pulse_expand)
	# The cane is raised for the pulse.
	if _cane_arm != null:
		var ct := _cane_arm.create_tween()
		ct.tween_property(_cane_arm, "rotation_degrees", Vector3(-35, 0, 0), 0.12)
		ct.tween_property(_cane_arm, "rotation_degrees", Vector3.ZERO, 0.3)


# ---------------------------------------------------------------------- incense
func is_swinging() -> bool:
	return _incense_left > 0.0


func incense_progress() -> float:
	return clampf(1.0 - _incense_left / incense_windup, 0.0, 1.0) if incense_windup > 0.0 else 1.0


## Starts the telegraphed censer swing towards `towards` (the rats' centre).
func begin_incense(towards: Vector3) -> void:
	var off := flat(towards - global_position)
	if off.length() > incense_reach:
		off = off.normalized() * incense_reach
	_incense_at = flat(global_position) + off
	_incense_left = incense_windup
	_free_telegraph()
	_telegraph = world_zone("IncenseCircle", _incense_at)
	_telegraph.set_circle(_incense_at, incense_radius, _incense_left)
	ink_dashes(_telegraph, incense_radius, 18)
	ink_ring(_telegraph, incense_radius * 0.35, 0.07)
	_fill = fill_disc(_telegraph, incense_radius)
	set_fill(_fill, 0.0)


## The cloud bursts: Pups in it die, everything else is shoved out.
## Returns the number of rats affected.
func _burst() -> int:
	_incense_left = 0.0
	_incense_cd = incense_cooldown
	_free_telegraph()
	var n := 0
	var col := get_tree().get_first_node_in_group("colony") as Colony
	if col != null and col.has_method("knockback_rats_in_circle"):
		n = col.knockback_rats_in_circle(_incense_at, incense_radius, incense_knockback, true)
	else:
		for r in live_rats():
			if not DangerZone.circle_contains(_incense_at, incense_radius, r.global_position):
				continue
			if r.get("is_pup") == true and r.has_method("hit"):
				r.call("hit")
				n += 1
			elif r.has_method("knockback"):
				r.call("knockback", _incense_at, incense_knockback)
				n += 1
	_cloud()
	GameFeel.shake_camera(get_tree(), 0.2)
	return n


## Pale and sage puffs that billow up, with an ink rim flung outwards.
func _cloud() -> void:
	Vfx.play(get_tree(), &"incense", _incense_at, Vector3.ZERO, incense_radius)


func _free_telegraph() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.retire()
	_telegraph = null
	_fill = null


func _on_beaten() -> void:
	_free_telegraph()
	_incense_left = 0.0


func _animate(delta: float) -> void:
	super._animate(delta)
	if not is_beaten:
		_herb_left -= delta
		if _herb_left <= 0.0:
			_herb_left += 1.0 / HERB_RATE
			Vfx.play(get_tree(), &"herb", global_position)
	if _censer == null:
		return
	if _incense_left > 0.0:
		var t := incense_progress()
		_censer.rotation.x = sin(t * TAU * 2.0) * 1.2 * t
		_trail_left -= delta
		if _trail_left <= 0.0:
			_trail_left += 1.0 / TRAIL_RATE
			Vfx.play(get_tree(), &"incense_trail", _censer.global_transform * Vector3(0, -0.4, 0))
	else:
		_censer.rotation.x = sin(_gait * 3.0) * 0.25
