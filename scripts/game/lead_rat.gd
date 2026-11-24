## The Lead Rat: the one rat the player steers. Scurries over the ground plane
## (move_* actions), turns to face where it runs and Bites automatically via
## its BiteComponent child. Each Bite shows a short lunge (the BiteComponent
## sprays the Vfx "bite" burst at the victim).
## With `bot_mode` it steers itself to the nearest healthy townsperson (--bot);
## once an Exterminator is in the District it goes for it and circles it so
## the Colony crowds round and Bites (M6 boss tests). It dodges danger zones
## about to strike (M6b), standing in for a human who dodges.
## It Feeds when it stands (nearly) still on a corpse, breeding a Pup per meal.
## It survives `max_hits` hits, flickering while briefly invulnerable after
## each; at 0 it squashes flat and emits `died` (the RoundDirector ends the Round).
## Hide: the Colony calls hide_in() when it walks into a door; it funnels in,
## is hidden (out of group "rats", in "hidden_rats", ignores hits) and Bites
## the occupants until pour_out(). The bot runs for a door when hit down to 1.
## knockback() shoves it away from a broom; it costs no hit.
## UX pass: a thin near-black ground ring (the shader inks it as a circle)
## always marks the Lead Rat in the swarm; it flashes wide when hit and is
## hidden while Hidden or dead.
## VFX pass: a hit throws an ink burst and an ink ring (Vfx "lead_hurt") and
## sends a Vfx disturbance; death leaves a large ink splat ("lead_death").
class_name LeadRat
extends CharacterBody3D

signal hurt(hits_left: int)
signal died

const Props := preload("res://scripts/town_props.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")
## Bite lunge: seconds out and back, and how far the body darts forward.
const LUNGE_OUT := 0.06
const LUNGE_BACK := 0.16
const LUNGE_REACH := 0.62
const LUNGE_HOP := 0.12
## Seconds to funnel into a door / pour back out of it.
const FUNNEL_TIME := 0.3
## Seconds a knockback shove lasts (the speed eases off to 0 over it).
const KNOCK_TIME := 0.25
## The bot holds this band (u) round a present Exterminator: close enough
## that the Colony's swarm latches (Colony.SWARM_ENTER) and the followers Bite,
## outside his close-range attacks. Danger zones are still dodged first.
const BOT_BOSS_NEAR := 3.0
const BOT_BOSS_FAR := 4.0
## The bot dodges zones striking within this many seconds (M6b contract).
const BOT_DODGE_TIME := 0.5
## Seconds between the bot's danger scans, and its look-ahead for lasting zones.
const BOT_DODGE_SCAN := 0.1
const BOT_LOOKAHEAD := 0.35
## The ground ring marker: radius and stroke (u) and the flash on a hit.
const RING_RADIUS := 0.8
const RING_STROKE := 0.07
const RING_FLASH_SCALE := 1.6
const RING_FLASH_TIME := 0.35

@export var max_speed := 6.0
## Units/s^2 towards the stick direction, and when letting go.
@export var acceleration := 70.0
@export var deceleration := 55.0
## How fast the body turns to face its motion (1/s; higher = snappier).
@export var turn_rate := 16.0
@export var visual_scale := 1.4
@export var bot_mode := false
@export var max_hits := 3
## Seconds of invulnerability after a hit.
@export var invulnerable_time := 0.8
## Ignore hits altogether (--god).
@export var god_mode := false
## Below this speed (u/s) the Lead Rat counts as standing still for Feeding.
@export var feed_max_speed := 0.6

var is_pup := false
var hits_left: int
var is_dead := false
## True while inside a house (Hide).
var is_hidden := false
## The steering direction this frame (stick or bot), unit or zero.
var wish := Vector3.ZERO

var _visual: Node3D          # yaw pivot, faces the movement direction
var _body: Node3D            # child of the pivot, lunges forward on a Bite
var _lunge_t := INF          # seconds since the last Bite lunge began
var _bot_detour := Vector3.ZERO
var _bot_detour_left := 0.0
var _bot_stuck_check := 0.0
var _bot_stuck_from := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _props: Props
var _invulnerable_left := 0.0
var _feed_left := 0.0
var _breed_left := 0.0
var _nibble_time := 0.0
var _colony: Colony
var _layer := 0
var _mask := 0
var _move_tween: Tween
var _bot_want_hide := false
var _bot_hide_house: House
var _knock_vel := Vector3.ZERO
var _knock_left := 0.0
var _bot_dodge_scan := 0.0
var _bot_dodge_goal := Vector3.INF
var _bot_skirt := Vector3.ZERO
var _ring: Node3D
var _ring_tween: Tween
## Dodges taken by the bot this Round (debug output).
var bot_dodges := 0

@onready var _bite: BiteComponent = $BiteComponent


func _ready() -> void:
	add_to_group("lead_rat")
	add_to_group("rats")
	hits_left = max_hits
	_rng.seed = 7
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_body = Node3D.new()
	_body.name = "Body"
	_visual.add_child(_body)
	_props = Props.new(3)
	_props.rat(_body, Vector3.ZERO, 0.0, visual_scale)
	# One mesh per colour instead of nine parts (performance).
	MeshBatcher.merge(_body)
	_build_ring()
	_bite.is_lead = true
	_bite.bit.connect(_on_bit)
	_bot_stuck_from = global_position
	_layer = collision_layer
	_mask = collision_mask
	# Make the District's Vfx node now rather than on the first Bite.
	(func() -> void: Vfx.get_vfx(get_tree())).call_deferred()


func _process(delta: float) -> void:
	if _lunge_t == INF:
		return
	_lunge_t += delta
	var z := 0.0
	var y := 0.0
	var scl := Vector3.ONE
	if _lunge_t < LUNGE_OUT:
		var t := ease(_lunge_t / LUNGE_OUT, 0.45)
		z = LUNGE_REACH * t
		y = sin(t * PI * 0.5) * LUNGE_HOP
		scl = Vector3(lerpf(1.0, 0.80, t), lerpf(1.0, 0.86, t), lerpf(1.0, 1.36, t))
	elif _lunge_t < LUNGE_OUT + LUNGE_BACK:
		var t := smoothstep(0.0, 1.0, (_lunge_t - LUNGE_OUT) / LUNGE_BACK)
		z = LUNGE_REACH * (1.0 - t)
		y = LUNGE_HOP * (1.0 - t)
		scl = Vector3(lerpf(0.80, 1.0, t), lerpf(0.86, 1.0, t), lerpf(1.36, 1.0, t))
	else:
		_lunge_t = INF
	_body.position = Vector3(0, y, z)
	_body.scale = scl


## Bite cooldown progress (0 = just bit, 1 = ready) for the diegetic HUD ring.
func bite_cooldown_progress() -> float:
	return _bite.cooldown_progress() if _bite else 1.0


func bite_range_val() -> float:
	return _bite.bite_range if _bite else 1.6


func has_bite_target() -> bool:
	return _bite != null and not is_hidden and not is_dead and _bite.find_target() != null


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if is_hidden:
		wish = Vector3.ZERO
		velocity = Vector3.ZERO
		return
	_update_invulnerable(delta)
	if _knock_left > 0.0:
		# Shoved: no steering until it eases off.
		_knock_left = maxf(_knock_left - delta, 0.0)
		wish = Vector3.ZERO
		velocity = _knock_vel * (_knock_left / KNOCK_TIME)
		move_and_slide()
		position.y = 0.0
		return
	wish = _bot_direction(delta) if bot_mode else _input_direction()
	var target_vel := wish * max_speed
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if wish != Vector3.ZERO else deceleration
	flat = flat.move_toward(target_vel, rate * delta)
	velocity = flat
	move_and_slide()
	position.y = 0.0
	# Face the way we're actually running, with slight smoothing.
	if flat.length_squared() > 0.04:
		var yaw := atan2(flat.x, flat.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 1.0 - exp(-turn_rate * delta))
	_update_feeding(flat.length(), delta)


## The ground ring: one thin near-black torus, flattened, under the rat.
func _build_ring() -> void:
	_ring = Node3D.new()
	_ring.name = "Marker"
	add_child(_ring)
	_props.part(_ring, _props.torus(RING_RADIUS, RING_STROKE), Props.INK, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 0.25, 1))


## Widens the ring and eases it back (on a hit).
func _flash_ring() -> void:
	if _ring == null:
		return
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring.scale = Vector3(RING_FLASH_SCALE, 1.0, RING_FLASH_SCALE)
	_ring_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_ring_tween.tween_property(_ring, "scale", Vector3.ONE, RING_FLASH_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _input_direction() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return Vector3(v.x, 0.0, v.y)


# ---------------------------------------------------------------------- bot
## Heads for the nearest healthy (uninfected, alive) townsperson; if there is
## none, for the nearest living one. Takes a short random detour when stuck.
func _bot_direction(delta: float) -> Vector3:
	_bot_stuck_check += delta
	if _bot_stuck_check >= 0.6:
		if global_position.distance_to(_bot_stuck_from) < 0.8 and _bot_detour_left <= 0.0:
			var a := _rng.randf() * TAU
			_bot_detour = Vector3(sin(a), 0.0, cos(a))
			_bot_detour_left = 0.7
		_bot_stuck_check = 0.0
		_bot_stuck_from = global_position
	var dodge := _bot_dodge_direction(delta)
	if dodge != Vector3.ZERO:
		_bot_stuck_check = 0.0
		_bot_stuck_from = global_position
		return dodge
	if _bot_detour_left > 0.0:
		_bot_detour_left -= delta
		return _bot_detour
	var hide_dir := _bot_hide_direction()
	if hide_dir != Vector3.ZERO:
		return hide_dir
	var boss_dir := _bot_exterminator_direction()
	if boss_dir != Vector3.ZERO:
		return boss_dir
	# Stop for a meal when a corpse is close and we're ready to breed.
	var meal := _bot_meal()
	if meal:
		var to_meal := meal.global_position - global_position
		to_meal.y = 0.0
		if to_meal.length() < 0.5:
			_bot_stuck_check = 0.0
			_bot_stuck_from = global_position
			return Vector3.ZERO
		return to_meal.normalized()
	var target := _bot_pick_target()
	if target == null:
		return Vector3.ZERO
	var d := target.global_position - global_position
	d.y = 0.0
	if d.length() < 0.6:
		return Vector3.ZERO
	return d.normalized()


## Hit down to 1: run for the nearest door and deliberately trigger Hide.
func _bot_hide_direction() -> Vector3:
	var c := _get_colony()
	if not _bot_want_hide or c == null or not c.can_hide():
		return Vector3.ZERO
	if _bot_hide_house == null or not is_instance_valid(_bot_hide_house):
		_bot_hide_house = c.nearest_house(global_position, 16.0)
		if _bot_hide_house == null:
			_bot_want_hide = false
			return Vector3.ZERO
	var door := _bot_hide_house.door_position
	var front := door + _bot_hide_house.door_normal * 1.0
	var here := Vector3(global_position.x, 0.0, global_position.z)
	if here.distance_to(door) <= 1.8:
		c.try_hide()
		return Vector3.ZERO
	if here.distance_to(front) < 0.5:
		return (door - here).normalized()
	return (front - here).normalized()


## Stands in for a human who dodges (M6b): inside a danger zone that strikes
## within BOT_DODGE_TIME (or a lasting one) it runs out by the shortest way
## until clear; a lasting zone (fire, trap) just ahead is skirted round.
## Zero when there is nothing to dodge. Scans the Colony's zone cache ~10 Hz.
func _bot_dodge_direction(delta: float) -> Vector3:
	var c := _get_colony()
	if c == null:
		return Vector3.ZERO
	var here := Vector3(global_position.x, 0.0, global_position.z)
	_bot_dodge_scan -= delta
	if _bot_dodge_scan <= 0.0:
		_bot_dodge_scan = BOT_DODGE_SCAN
		_bot_skirt = Vector3.ZERO
		if not c.has_zones():
			_bot_dodge_goal = Vector3.INF
		elif c.zone_at(here, BOT_DODGE_TIME) >= 0:
			if _bot_dodge_goal == Vector3.INF or c.zone_at(_bot_dodge_goal, BOT_DODGE_TIME) >= 0 \
					or here.distance_to(_bot_dodge_goal) < 0.2:
				_bot_dodge_goal = c.escape_point(here, BOT_DODGE_TIME)
				if _bot_dodge_goal != Vector3.INF:
					bot_dodges += 1
		else:
			_bot_dodge_goal = Vector3.INF
			var ahead := here + Vector3(velocity.x, 0.0, velocity.z) * BOT_LOOKAHEAD
			var zi := c.zone_at(ahead, -1.0)
			if zi >= 0:
				var out := here - c.zone_center(zi)
				if out.length_squared() > 0.0001:
					out = out.normalized()
					var tangent := out.cross(Vector3.UP)
					if tangent.dot(velocity) < 0.0:
						tangent = -tangent
					_bot_skirt = (tangent + out * 0.5).normalized()
	if _bot_dodge_goal != Vector3.INF:
		var to := _bot_dodge_goal - here
		if to.length() > 0.1:
			return to.normalized()
	return _bot_skirt


## Towards a living Exterminator until within BOT_BOSS_FAR, then circles
## him, easing back out when closer than BOT_BOSS_NEAR (zero when there is
## none). His telegraphs are dodged by _bot_dodge_direction(), which runs first.
func _bot_exterminator_direction() -> Vector3:
	var ext := _bot_exterminator()
	if ext == null:
		return Vector3.ZERO
	var to := ext.global_position - global_position
	to.y = 0.0
	var d := maxf(to.length(), 0.01)
	var radial := to / d
	if d > BOT_BOSS_FAR:
		return radial
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	var mid := (BOT_BOSS_NEAR + BOT_BOSS_FAR) * 0.5
	return (tangent * 0.7 + radial * (d - mid) * 2.0).normalized()


## The first Exterminator (group "exterminator") whose Infection is not dead.
func _bot_exterminator() -> Node3D:
	for n in get_tree().get_nodes_in_group("exterminator"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e):
			continue
		var inf := e.get_node_or_null("Infection") as InfectionComponent
		if inf == null or not inf.is_dead():
			return e
	return null


func _bot_meal() -> Node3D:
	var c := _get_colony()
	if c == null or _breed_left > 0.0:
		return null
	return c.find_corpse(global_position, 5.0)


func _bot_pick_target() -> Node3D:
	var best_healthy: Node3D = null
	var best_any: Node3D = null
	var dh := INF
	var da := INF
	for n in get_tree().get_nodes_in_group("townsfolk"):
		var t := n as Node3D
		if t == null:
			continue
		var inf := t.get_node_or_null("Infection") as InfectionComponent
		if inf == null or inf.is_dead():
			continue
		var d2 := global_position.distance_squared_to(t.global_position)
		if not inf.is_infected() and d2 < dh:
			dh = d2
			best_healthy = t
		if d2 < da:
			da = d2
			best_any = t
	return best_healthy if best_healthy else best_any


# ---------------------------------------------------------------------- bite feedback
func _on_bit(target: Node3D) -> void:
	if is_hidden:
		return  # the house shows the Bite
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		_visual.rotation.y = atan2(to.x, to.z)
		GameFeel.punch_camera(get_tree(), to, 0.14)
	# Short forward lunge with squash-stretch and crisp micro-hitstop.
	_lunge_t = 0.0
	GameFeel.hitstop(get_tree(), 0.028, 0.22, 0)


# ---------------------------------------------------------------------- feeding
func _get_colony() -> Colony:
	if _colony == null or not is_instance_valid(_colony):
		_colony = get_tree().get_first_node_in_group("colony") as Colony
	return _colony


## Standing (nearly) still within 1 u of a corpse: after `feed_time` eat one
## meal and breed a Pup, then wait `breed_cooldown` before the next.
func _update_feeding(speed: float, delta: float) -> void:
	_breed_left = maxf(_breed_left - delta, 0.0)
	var c := _get_colony()
	var corpse: Node3D = null
	if c and speed < feed_max_speed and _breed_left <= 0.0:
		corpse = c.find_corpse(global_position, 1.0)
	if corpse == null:
		_feed_left = c.feed_time if c else 1.5
		if _nibble_time > 0.0:
			_nibble_time = 0.0
			_body.rotation.x = 0.0
		return
	_nibble_time += delta
	_body.rotation.x = 0.22 + 0.1 * sin(_nibble_time * 22.0)
	_feed_left -= delta
	if _feed_left <= 0.0:
		_feed_left = c.feed_time
		if Colony.take_meal(corpse):
			_breed_left = c.breed_cooldown
			var litter := 1 + c.extra_pups_per_feed
			for _k in litter:
				c.spawn_pup(global_position)


# ---------------------------------------------------------------------- houses
## Funnels into `h`'s door: shrinks into the door point and hides inside,
## its Bite turned on the occupants. Called by the Colony.
func hide_in(h: House) -> void:
	is_hidden = true
	_bot_want_hide = false
	_bot_hide_house = null
	remove_from_group("rats")
	add_to_group("hidden_rats")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_invulnerable_left = 0.0
	_visual.visible = true
	_body.rotation.x = 0.0
	_bite.house = h
	if _ring:
		_ring.visible = false
	var inside := h.door_position - h.door_normal * 0.45
	_visual.rotation.y = atan2(-h.door_normal.x, -h.door_normal.z)
	_kill_move_tween()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", inside, FUNNEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_move_tween.parallel().tween_property(_visual, "scale", Vector3.ONE * 0.15, FUNNEL_TIME).set_ease(Tween.EASE_IN)
	_move_tween.tween_callback(func() -> void: _visual.visible = false)


## Pours back out of `h`'s door to `to`, then takes the controls again.
func pour_out(h: House, to: Vector3) -> void:
	global_position = h.door_position - h.door_normal * 0.45
	_visual.scale = Vector3.ONE * 0.15
	_visual.visible = true
	_visual.rotation.y = atan2(h.door_normal.x, h.door_normal.z)
	_kill_move_tween()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", to, FUNNEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tween.parallel().tween_property(_visual, "scale", Vector3.ONE, FUNNEL_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.tween_callback(_finish_out)


func _finish_out() -> void:
	_visual.scale = Vector3.ONE
	is_hidden = false
	_bite.house = null
	if _ring:
		_ring.visible = not is_dead
	remove_from_group("hidden_rats")
	if not is_dead:
		add_to_group("rats")
	collision_layer = _layer
	collision_mask = _mask
	_bot_stuck_from = global_position


func _kill_move_tween() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()


# ---------------------------------------------------------------------- hits
## A townsperson's attack landed on the Lead Rat.
func hit() -> void:
	if god_mode or is_dead or is_hidden or _invulnerable_left > 0.0:
		return
	hits_left = maxi(hits_left - 1, 0)
	_flash_ring()
	GameFeel.flash(get_tree(), _visual, Color(1.0, 0.35, 0.26), 0.12)
	if hits_left > 0:
		Vfx.play(get_tree(), &"lead_hurt", global_position)
	Vfx.disturb_at(get_tree(), global_position, 5.0)
	hurt.emit(hits_left)
	if hits_left == 1:
		_bot_want_hide = true
		_bot_hide_house = null
	if hits_left <= 0:
		_die()
		return
	_invulnerable_left = invulnerable_time


## A broom (or similar) shove away from `from`, about `strength` u. No damage.
func knockback(from: Vector3, strength: float) -> void:
	if is_dead or is_hidden:
		return
	var d := global_position - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	# Speed falls linearly to 0 over KNOCK_TIME: distance = v0 * T / 2.
	_knock_vel = d.normalized() * (2.0 * strength / KNOCK_TIME)
	_knock_left = KNOCK_TIME


func _update_invulnerable(delta: float) -> void:
	if _invulnerable_left <= 0.0:
		return
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_visual.visible = _invulnerable_left <= 0.0 or fmod(_invulnerable_left, 0.12) > 0.05


## Squashes flat on the spot. The tween keeps running while the Round-end
## pause holds the rest of the world.
func _die() -> void:
	is_dead = true
	remove_from_group("rats")
	if _ring:
		_ring.visible = false
	_invulnerable_left = 0.0
	_visual.visible = true
	velocity = Vector3.ZERO
	_bite.enabled = false
	_body.rotation.x = 0.0
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3(1.25, 1.3, 0.85), 0.07)
	tw.tween_property(_visual, "scale", Vector3(1.45, 0.12, 1.3), 0.12)
	Vfx.play(get_tree(), &"lead_death", global_position)
	var c := _get_colony()
	if c:
		c.on_lead_died()
	died.emit()
