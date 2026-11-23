## A follower rat of the Colony, an Adult or a Pup. It flocks to its slot
## behind the Lead Rat (a loose spot that wobbles, pushed apart from the other
## rats), follows the Lead Rat's breadcrumb trail when a wall cuts it off, and
## Feeds on corpses it passes. Adults Bite (BiteComponent child) and breed a
## Pup per meal; Pups Feed to Mature sooner and grow into Adults.
## One hit() kills it: it squashes flat, bursts in an ink splat (Vfx
## "rat_splat": droplets and a ground splat) and is freed.
## knockback() shoves an Adult away (no damage) and kills a Pup.
## Houses: hide_in() funnels it into a door (hidden, out of group "rats", in
## "hidden_rats", invulnerable, Biting the occupants); pour_out() brings it
## back. On a Raid (start_raid) it runs to the door itself, Bites inside for
## the raid duration and pours back out to rejoin the flock.
## Danger (M6b): every DANGER_SCAN s it checks the Colony's danger zone cache.
## Inside a zone it sprints out by the shortest way (Colony.escape_point()),
## ignoring its slot, a Feeding detour or the swarm ring until it is clear;
## Pups run slower. Outside, it waits at the edge rather than walk into a
## zone that is winding up, and skirts round a lasting one (fire, trap).
## Swarm: while the Colony rings a target, an Adult runs to its swarm slot.
## VFX pass: Feeding nibbles off tiny dark flecks, a Pup maturing pops a
## small ink ring, raiders kick up dust at the door going in and out.
class_name ColonyRat
extends CharacterBody3D

const Props := preload("res://scripts/town_props.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")
## Bite lunge: seconds out and back, and how far the body darts forward.
const LUNGE_OUT := 0.06
const LUNGE_BACK := 0.14
const LUNGE_REACH := 0.35
## Seconds between nibble flecks while Feeding.
const NIBBLE_GAP := Vector2(0.35, 0.8)
const ADULT_SCALE := 0.9
const PUP_SCALE := 0.55
## Seconds to funnel into a door / pour back out of it.
const FUNNEL_TIME := 0.3
## A raider that hasn't reached its door in this time gives up.
const RAID_GIVE_UP := 6.0
## Raiders stay inside at least this long, even in an empty house.
const RAID_MIN_INSIDE := 0.5
## Seconds a knockback shove lasts (the speed eases off to 0 over it).
const KNOCK_TIME := 0.25
## Seconds between danger checks (~10 Hz).
const DANGER_SCAN := 0.1
## Escape speed relative to the follower top speed (Pups are slower).
const ESCAPE_SPEED_ADULT := 1.12
const ESCAPE_SPEED_PUP := 0.75
## Seconds of motion looked ahead for zones it is about to walk into.
const DANGER_LOOKAHEAD := 0.3

enum State { FOLLOW, FEED, RAID_GO }
enum Danger { NONE, ESCAPE, HOLD, SKIRT }

var is_pup: bool               # Pups don't Bite and don't Feed-to-breed
var colony: Colony
## Slot offset in the Colony frame (x across, z along; set by the Colony) and
## how far behind the Lead Rat its disc sits.
var slot := Vector3.ZERO
var slot_back := 1.5
## True while inside a house (or funnelling in / pouring out).
var is_hidden := false
## True from start_raid() until it is back out in the street.
var raiding := false
## The house it is inside or raiding.
var house: House
## Offset of its spot round the Colony's swarm target (INF = not swarming).
var swarm_slot := Vector3.INF

var _state := State.FOLLOW
var _danger := Danger.NONE
var _danger_left := randf() * DANGER_SCAN
var _escape_goal := Vector3.ZERO
var _skirt_center := Vector3.ZERO
var _swarm_clear := true
var _visual: Node3D          # yaw pivot, scaled for Adult / Pup
var _body: Node3D            # bobs while running, nibbles while Feeding
var _bite: BiteComponent
var _dead := false
var _maturity_left := 0.0
var _breed_left := 0.0
var _phase := Vector3.ZERO   # wobble phases
var _wobble_speed := 1.0
var _check_left := 0.0
var _trail := false
var _crumb := 0
var _corpse: Node3D
var _corpse_spot := Vector3.ZERO
var _feed_left := 0.0
var _detour_left := 0.0
var _run_time := 0.0
var _drift := Vector3.ZERO       # slowly re-picked random nudge off the slot
var _drift_goal := Vector3.ZERO
var _drift_left := 0.0
var _layer := 0
var _mask := 0
var _raid_go_left := 0.0
var _raid_goal := Vector3.ZERO
var _inside_left := 0.0
var _inside_time := 0.0
var _move_tween: Tween
var _knock_vel := Vector3.ZERO
var _knock_left := 0.0
var _lunge_t := INF          # seconds since the last Bite lunge began
var _nibble_left := 0.0


func _ready() -> void:
	add_to_group("rats")
	_layer = collision_layer
	_mask = collision_mask
	_phase = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_wobble_speed = randf_range(0.7, 1.3)
	_check_left = randf() * 0.25
	_run_time = randf() * 10.0
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_body = Node3D.new()
	_body.name = "Body"
	_visual.add_child(_body)
	var kit: Props = colony.props if colony else Props.new(randi())
	kit.rat(_body, Vector3.ZERO, 0.0, 1.0)
	# One mesh per colour instead of nine parts (performance).
	MeshBatcher.merge(_body)
	_visual.rotation.y = randf() * TAU
	if is_pup:
		_maturity_left = colony.pup_maturity if colony else 15.0
		_visual.scale = Vector3.ONE * PUP_SCALE
	else:
		_visual.scale = Vector3.ONE * ADULT_SCALE
		_add_bite()


func _add_bite() -> void:
	_bite = BiteComponent.new()
	_bite.name = "BiteComponent"
	if colony:
		colony.configure_bite(_bite)
	add_child(_bite)
	_bite.house = house if is_hidden else null
	_bite.bit.connect(_on_bit)


func _physics_process(delta: float) -> void:
	if _dead or colony == null:
		return
	_run_time += delta
	_breed_left = maxf(_breed_left - delta, 0.0)
	if is_pup:
		_maturity_left -= delta
		if _maturity_left <= 0.0:
			_mature()
	if is_hidden:
		_update_inside(delta)
		return
	if _knock_left > 0.0:
		_update_knock(delta)
		return
	if _state == State.RAID_GO:
		_raid_go(delta)
		return
	var lead_pos := colony.lead_position()
	var here := Vector3(global_position.x, 0.0, global_position.z)
	_check_left -= delta
	var check := _check_left <= 0.0
	if check:
		_check_left = 0.25

	var goal := here
	var eating := false
	var swarm := colony.swarm_world(self) if not is_pup else Vector3.INF
	if swarm != Vector3.INF and _state == State.FEED:
		_state = State.FOLLOW
	if _state == State.FEED:
		if not _feed_still_ok(here, lead_pos, delta):
			_state = State.FOLLOW
		else:
			goal = _corpse_spot
			if here.distance_to(_corpse_spot) < 0.3:
				eating = true
				_feed_left -= delta
				if _feed_left <= 0.0:
					_eat()
	if _state == State.FOLLOW:
		if swarm != Vector3.INF:
			if check:
				_swarm_clear = colony.clear_line(here, swarm)
			if _swarm_clear:
				_trail = false
				goal = swarm
			else:
				goal = _follow_goal(here, lead_pos, check)
		else:
			if check and _can_feed() and here.distance_to(lead_pos) < colony.feed_lead_radius:
				_try_start_feed(here)
			goal = _follow_goal(here, lead_pos, check)

	# Danger beats the slot, the swarm ring and Feeding.
	_danger_left -= delta
	if _danger_left <= 0.0:
		_danger_left = DANGER_SCAN
		_scan_danger(here, goal)
	var escaping := false
	match _danger:
		Danger.ESCAPE:
			escaping = true
			eating = false
			if _state == State.FEED:
				_state = State.FOLLOW
			goal = _escape_goal
		Danger.HOLD:
			# Wait at the edge, easing away so the crowd doesn't push it in.
			var away := here - _skirt_center
			goal = here + (away.normalized() * 0.35 if away.length_squared() > 0.0001 else Vector3.ZERO)
			eating = false
		Danger.SKIRT:
			goal = _skirt_goal(here, goal)

	var max_speed: float = colony.lead.get("max_speed") * colony.speed_factor if colony.lead else 6.0
	var to_goal := goal - here
	var dist := to_goal.length()
	var want := Vector3.ZERO
	if escaping and dist > 0.05:
		# Flat out, no soft arrival.
		want = to_goal / dist * max_speed * (ESCAPE_SPEED_PUP if is_pup else ESCAPE_SPEED_ADULT)
	elif not eating and dist > 0.05:
		# Arrive softly; sprint a little harder when far behind.
		var top := max_speed * (1.12 if dist > 4.0 else 1.0)
		want = to_goal / dist * minf(dist * 3.2, top)
	# Escaping rats shove less, or the crowd at the edge pushes some back in.
	want += _separation(here, lead_pos) * (0.35 if escaping else 1.0)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(want, 38.0 * delta)
	velocity = flat
	move_and_slide()
	position.y = 0.0
	_animate(flat, eating, delta)


# ---------------------------------------------------------------------- danger
## Inside a zone: run for the escape point (kept while it stays safe). Not
## inside, but the next steps or the goal are: wait at the edge of a zone that
## is winding up, skirt round a lasting one.
func _scan_danger(here: Vector3, goal: Vector3) -> void:
	if not colony.has_zones():
		_danger = Danger.NONE
		return
	var zi := colony.zone_at(here)
	if zi >= 0:
		if _danger != Danger.ESCAPE or colony.zone_at(_escape_goal) >= 0 or here.distance_to(_escape_goal) < 0.15:
			var e := colony.escape_point(here)
			if e == Vector3.INF:
				var out := here - colony.zone_center(zi)
				out = out.normalized() if out.length_squared() > 0.0001 else _random_flat(1.0).normalized()
				e = here + out * 1.0
			_escape_goal = e
		_danger = Danger.ESCAPE
		return
	var ahead := here + Vector3(velocity.x, 0.0, velocity.z) * DANGER_LOOKAHEAD
	zi = colony.zone_at(ahead)
	if zi < 0:
		zi = colony.zone_at(goal)
	if zi < 0:
		_danger = Danger.NONE
	elif colony.zone_persistent(zi):
		_danger = Danger.SKIRT
		_skirt_center = colony.zone_center(zi)
	else:
		_danger = Danger.HOLD
		_skirt_center = colony.zone_center(zi)


## Round a lasting zone towards `goal`: along its edge, a little outwards.
func _skirt_goal(here: Vector3, goal: Vector3) -> Vector3:
	var out := here - _skirt_center
	if out.length_squared() < 0.0001:
		return here + _random_flat(1.0)
	out = out.normalized()
	var tangent := out.cross(Vector3.UP)
	if tangent.dot(goal - here) < 0.0:
		tangent = -tangent
	return here + (tangent + out * 0.4).normalized()


# ---------------------------------------------------------------------- following
## The wobbling slot, or the next breadcrumb when the Lead Rat is out of sight.
func _follow_goal(here: Vector3, lead_pos: Vector3, check: bool) -> Vector3:
	if check:
		var sees := colony.clear_line(here, lead_pos)
		if sees:
			_trail = false
		elif not _trail:
			_trail = true
			_crumb = colony.nearest_crumb(here)
	if _trail:
		if check:
			# Skip ahead along the trail while the next crumbs are in plain view.
			var steps := 0
			while _crumb < colony.newest_crumb() and steps < 6 \
					and colony.clear_line(here, colony.crumb(_crumb + 1)):
				_crumb += 1
				steps += 1
		var c := colony.crumb(_crumb)
		if here.distance_to(c) < 0.45 and _crumb < colony.newest_crumb():
			_crumb += 1
			c = colony.crumb(_crumb)
		return c
	# Jostle: a quick wobble plus a slower random drift every second or two.
	_drift_left -= get_physics_process_delta_time()
	if _drift_left <= 0.0:
		_drift_left = randf_range(0.8, 2.2)
		_drift_goal = _random_flat(0.75)
	_drift = _drift.lerp(_drift_goal, minf(1.0, get_physics_process_delta_time() * 2.0))
	var t := _run_time * _wobble_speed
	var amp := 0.25 + 0.2 * (1.0 - colony.gather)
	var wobble := Vector3(sin(t * 1.3 + _phase.x) + 0.5 * sin(t * 2.9 + _phase.y), 0.0,
		sin(t * 1.1 + _phase.z) + 0.5 * sin(t * 2.3 + _phase.x)) * amp
	return colony.slot_world(self) + wobble + _drift


## Pushes away from rats that are too close (the Lead Rat a bit harder);
## the other followers come from the Colony's grid.
func _separation(here: Vector3, lead_pos: Vector3) -> Vector3:
	var mine := _radius()
	var push := colony.separation(self, here, mine)
	var dl := here - lead_pos
	var rl := mine + 0.55
	if dl.length_squared() < rl * rl and dl.length_squared() > 0.000001:
		var l := dl.length()
		push += dl / l * (1.0 - l / rl) * 8.0
	return push


func _radius() -> float:
	return 0.2 if is_pup else 0.3


# ---------------------------------------------------------------------- feeding
func _can_feed() -> bool:
	return is_pup or _breed_left <= 0.0


func _try_start_feed(here: Vector3) -> void:
	var c := colony.find_corpse(here, colony.feed_seek_radius)
	if c == null:
		return
	_corpse = c
	var a := randf() * TAU
	_corpse_spot = Vector3(c.global_position.x, 0.0, c.global_position.z) + Vector3(sin(a), 0.0, cos(a)) * randf_range(0.15, 0.55)
	_feed_left = colony.feed_time
	_detour_left = 2.5
	_state = State.FEED


func _feed_still_ok(here: Vector3, lead_pos: Vector3, delta: float) -> bool:
	if _corpse == null or not is_instance_valid(_corpse) or Colony.meals_left(_corpse) <= 0:
		return false
	if not _corpse.is_in_group("corpses"):
		return false
	if here.distance_to(lead_pos) > colony.feed_lead_radius + 1.5:
		return false
	if here.distance_to(_corpse_spot) >= 0.3:
		_detour_left -= delta
		if _detour_left <= 0.0:
			return false
	return true


func _eat() -> void:
	_state = State.FOLLOW
	if not Colony.take_meal(_corpse):
		return
	if is_pup:
		_maturity_left -= colony.pup_feed_bonus
	else:
		_breed_left = colony.breed_cooldown
		colony.spawn_pup(global_position)


# ---------------------------------------------------------------------- houses
## Funnels into `h`'s door after `delay` s: shrinks into the door point and is
## hidden inside, out of reach, its Bite turned on the occupants.
func hide_in(h: House, delay := 0.0) -> void:
	is_hidden = true
	house = h
	_state = State.FOLLOW
	_inside_time = 0.0
	remove_from_group("rats")
	add_to_group("hidden_rats")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if _bite:
		_bite.house = h
	var inside := h.door_position - h.door_normal * 0.45
	var to := inside - global_position
	if to.length_squared() > 0.0001:
		_visual.rotation.y = atan2(to.x, to.z)
	_kill_move_tween()
	_move_tween = create_tween()
	if delay > 0.0:
		_move_tween.tween_interval(delay)
	_move_tween.tween_property(self, "global_position", inside, FUNNEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_move_tween.parallel().tween_property(_visual, "scale", Vector3.ONE * _size() * 0.15, FUNNEL_TIME).set_ease(Tween.EASE_IN)
	_move_tween.tween_callback(hide)


## Pours out of the door to `to` after `delay` s, then rejoins the Colony.
func pour_out(to: Vector3, delay := 0.0) -> void:
	if house == null or not is_instance_valid(house):
		_finish_out()
		return
	global_position = house.door_position - house.door_normal * 0.45
	_visual.scale = Vector3.ONE * _size() * 0.15
	var d := to - global_position
	_visual.rotation.y = atan2(d.x, d.z)
	_kill_move_tween()
	_move_tween = create_tween()
	if delay > 0.0:
		_move_tween.tween_interval(delay)
	_move_tween.tween_callback(show)
	_move_tween.tween_property(self, "global_position", to, FUNNEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tween.parallel().tween_property(_visual, "scale", Vector3.ONE * _size(), FUNNEL_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.tween_callback(_finish_out)


func _finish_out() -> void:
	show()
	_visual.scale = Vector3.ONE * _size()
	is_hidden = false
	raiding = false
	house = null
	if _bite:
		_bite.house = null
	remove_from_group("hidden_rats")
	add_to_group("rats")
	collision_layer = _layer
	collision_mask = _mask
	_state = State.FOLLOW
	_trail = false
	if colony:
		colony.on_rat_out(self)


## Sends this Adult on a Raid of `h`: run to the door, Bite inside for
## `duration` s, come back out.
func start_raid(h: House, duration: float) -> void:
	raiding = true
	house = h
	_state = State.RAID_GO
	_raid_go_left = RAID_GIVE_UP
	_inside_left = duration
	_raid_goal = h.door_position
	_check_left = 0.0


## Runs for the door: straight at it when in plain view, else for the street
## in front of it. Slipping in through a crack (touching the house) counts too.
func _raid_go(delta: float) -> void:
	_raid_go_left -= delta
	if house == null or not is_instance_valid(house) or _raid_go_left <= 0.0:
		raiding = false
		house = null
		_state = State.FOLLOW
		colony.on_rat_out(self)
		return
	var here := Vector3(global_position.x, 0.0, global_position.z)
	var door := house.door_position
	if here.distance_to(door) < 0.7:
		Vfx.play(get_tree(), &"door_dust", house.door_position, house.door_normal, 0.6)
		hide_in(house)
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 0.25
		var front := door + house.door_normal * 2.2
		if colony.clear_line(here, door):
			_raid_goal = door
		elif colony.clear_line(here, front):
			_raid_goal = front
		else:
			_raid_goal = door
	var max_speed: float = colony.lead.get("max_speed") * colony.speed_factor if colony.lead else 6.0
	var to_goal := _raid_goal - here
	var want := to_goal.normalized() * max_speed if to_goal.length() > 0.05 else Vector3.ZERO
	want += _separation(here, colony.lead_position()) * 0.5
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, 38.0 * delta)
	velocity = flat
	move_and_slide()
	position.y = 0.0
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == house:
			hide_in(house)
			return
	_animate(flat, false, delta)


## Inside a house: a raider counts down and pours out when done (or when
## nobody is left alive in there). During Hide the Colony calls pour_out.
func _update_inside(delta: float) -> void:
	_inside_time += delta
	if not raiding or _inside_time < FUNNEL_TIME:
		return
	if house == null or not is_instance_valid(house):
		_finish_out()
		return
	_inside_left -= delta
	if _inside_left <= 0.0 or (_inside_time > RAID_MIN_INSIDE and house.living_occupants().is_empty()):
		_inside_left = INF
		_inside_time = -INF
		var side := house.door_normal.cross(Vector3.UP)
		var to := house.door_position + house.door_normal * randf_range(0.5, 1.1) + side * randf_range(-0.6, 0.6)
		Vfx.play(get_tree(), &"door_dust", house.door_position, house.door_normal, 0.6)
		pour_out(to)


func _size() -> float:
	return PUP_SCALE if is_pup else ADULT_SCALE


func _kill_move_tween() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()


# ---------------------------------------------------------------------- growth
func _mature() -> void:
	is_pup = false
	_add_bite()
	Vfx.play(get_tree(), &"pup_mature", global_position)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE * ADULT_SCALE * 1.12, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3.ONE * ADULT_SCALE, 0.15)
	colony.on_matured(self)


# ---------------------------------------------------------------------- feedback
func _animate(flat: Vector3, eating: bool, delta: float) -> void:
	var speed := flat.length()
	if speed > 0.3:
		var yaw := atan2(flat.x, flat.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, minf(1.0, delta * 14.0))
	if eating:
		# Head down, quick nibbles.
		_body.rotation.x = 0.25 + 0.12 * sin(_run_time * 22.0)
		_body.position.y = 0.0
		_nibble_left -= delta
		if _nibble_left <= 0.0:
			_nibble_left = randf_range(NIBBLE_GAP.x, NIBBLE_GAP.y)
			var at := _corpse.global_position if _corpse != null and is_instance_valid(_corpse) else global_position
			Vfx.play(get_tree(), &"nibble", global_position.lerp(at, 0.3))
	else:
		_body.rotation.x = 0.0
		_body.position.y = absf(sin(_run_time * 18.0)) * 0.05 * minf(speed / 4.0, 1.0)
	if _lunge_t != INF:
		_lunge_t += delta
		var z := 0.0
		if _lunge_t < LUNGE_OUT:
			z = LUNGE_REACH * _lunge_t / LUNGE_OUT
		elif _lunge_t < LUNGE_OUT + LUNGE_BACK:
			z = LUNGE_REACH * (1.0 - (_lunge_t - LUNGE_OUT) / LUNGE_BACK)
		else:
			_lunge_t = INF
		_body.position.z = z


func _on_bit(target: Node3D) -> void:
	if is_hidden:
		return  # the house shows the Bite
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		_visual.rotation.y = atan2(to.x, to.z)
	# Lunge forward and back (in _animate; no Tween per Bite). The
	# BiteComponent sprays the Bite burst.
	_lunge_t = 0.0


func _random_flat(r: float) -> Vector3:
	var a := randf() * TAU
	return Vector3(sin(a), 0.0, cos(a)) * r * randf()


# ---------------------------------------------------------------------- death
## A townsperson's attack landed on this rat: it dies at once.
func hit() -> void:
	if _dead or is_hidden:
		return
	_dead = true
	remove_from_group("rats")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if _bite:
		_bite.enabled = false
	if colony:
		colony.on_rat_died(self)
	var s := _visual.scale.x
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3(s * 1.35, s * 0.12, s * 1.35), 0.12)
	tw.tween_callback(_splat)
	tw.tween_interval(0.25)
	tw.tween_callback(queue_free)


## A broom (or similar) shove away from `from`, about `strength` u. Adults
## take no damage; a Pup is killed by it.
func knockback(from: Vector3, strength: float) -> void:
	if _dead or is_hidden:
		return
	if is_pup:
		hit()
		return
	var d := global_position - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = _random_flat(1.0)
	# Speed falls linearly to 0 over KNOCK_TIME: distance = v0 * T / 2.
	_knock_vel = d.normalized() * (2.0 * strength / KNOCK_TIME)
	_knock_left = KNOCK_TIME
	_state = State.FOLLOW if _state == State.FEED else _state


func _update_knock(delta: float) -> void:
	_knock_left = maxf(_knock_left - delta, 0.0)
	velocity = _knock_vel * (_knock_left / KNOCK_TIME)
	move_and_slide()
	position.y = 0.0
	_body.rotation.x = -0.3 * (_knock_left / KNOCK_TIME)
	if _knock_left <= 0.0:
		_body.rotation.x = 0.0


## The ink splat of its death: droplets flung out and a mark on the ground.
func _splat() -> void:
	Vfx.play(get_tree(), &"rat_splat", global_position, Vector3.ZERO, 0.7 if is_pup else 1.0)
