## The Colony: every rat of the player, the Lead Rat included. Owns the
## high-performance SwarmSim (MultiMesh + SoA simulation scaling cleanly to
## 3,000+ rats at 60 FPS), the NavField obstacle/flow grid, Hide (deliberate
## button press at a doorway), Raid, danger-zone cache, and swarm targeting.
class_name Colony
extends Node3D

signal changed                           # rat added/removed, Pup matured

const Props := preload("res://scripts/town_props.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")
const RUN_DUST_GAP := 0.09
const RUN_DUST_SPEED := 3.0
const WORLD_MASK := 1
## Deliberate Hide: distance from a door at which the "[E] Hide" prompt appears.
const HIDE_REACH := 2.2
## Minimum time inside before pressing Hide again exits early.
const HIDE_EXIT_GRACE := 0.45
## Hidden at least this long before "everyone inside is infected" auto-ends it.
const HIDE_MIN_TIME := 2.0
const BOT_RAID_RANGE := 12.0
const DANGER_SCAN := 0.1
const ESCAPE_DIRS := 12
const ESCAPE_STEP := 0.35
const ESCAPE_MARGIN := 0.6
const SWARM_ENTER := 7.5
const SWARM_LEAVE := 9.5
const SWARM_BITE_HOLD := 2.0
const SWARM_RING0 := 0.85
const SWARM_RING_GAP := 0.38
const SWARM_SPACING := 0.52
const DANGER_TEST_EVERY := 3.0

@export var start_adults := 0
@export var start_pups := 0
@export var pup_maturity := 15.0
@export var feed_time := 1.5
@export var breed_cooldown := 4.0
@export var pup_feed_bonus := 5.0
@export var extra_pups_per_feed := 0
@export var feed_seek_radius := 3.0
@export var feed_lead_radius := 7.0
@export var speed_factor := 1.15
@export var bite_range := 1.6
@export var bite_cooldown := 1.2
@export var bite_chunk := 3.0
@export var bite_rate_bonus := 0.5
@export var hide_duration := 6.0
@export var hide_cooldown := 3.0
@export var raid_size := 3
@export var raid_duration := 4.0
@export var raid_cooldown := 10.0

## State read by the HUD & WorldOverlay.
var hide_unlocked: bool
var raid_unlocked: bool
var is_hidden: bool
var hidden_time_left: float
var raid_cooldown_left: float
var raiders_inside: int
var hide_cooldown_left := 0.0
var hide_house: House
var hides := 0
var raids := 0

var adult_count: int
var pup_count: int
var births := 0
var maturings := 0
var deaths := 0

var props := Props.new(41)
var lead: Node3D
var heading := Vector3(1, 0, 0)
var gather := 1.0
var nav: NavField
var sim: SwarmSim
var debug_print := false

var _hide_time := 0.0
var _hide_full := false
var _rings := {}
var _zones: Array[Node3D] = []
var _zone_center := PackedVector3Array()
var _zone_radius := PackedFloat32Array()
var _zone_time := PackedFloat32Array()
var _scan_left := 0.0
var swarm_target: Node3D
var swarm_exterminator: Node3D
var _swarm_dirty := true
var _swarm_reassign_left := 0.0
var _lead_bite_target: Node3D
var _lead_bite_age := INF
var _dust_left := 0.0


func _ready() -> void:
	add_to_group("colony")
	if nav == null:
		nav = NavField.new()
	if sim == null:
		sim = SwarmSim.new(self, nav)
	_spawn_start.call_deferred()


## Called by District right after static geometry is built so thousands of rats
## share one O(1) obstacle SDF and flow field.
func setup_nav(rect: Rect2, blockers: Array[Dictionary]) -> void:
	if nav == null:
		nav = NavField.new()
	nav.bake(rect, blockers)
	if sim == null:
		sim = SwarmSim.new(self, nav)
	else:
		sim.set_bounds(rect)


func _physics_process(delta: float) -> void:
	if not _lead_ok():
		return
	_update_hide(delta)
	_update_raid(delta)
	_lead_bite_age += delta
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = DANGER_SCAN
		_refresh_zones()
		_update_swarm()
	_swarm_reassign_left -= delta
	if swarm_target and (_swarm_dirty or _swarm_reassign_left <= 0.0):
		_swarm_dirty = false
		_swarm_reassign_left = 1.0
		sim.assign_swarm(swarm_target)
	_update_run_dust(delta)
	var lv: Vector3 = lead.get("velocity")
	lv.y = 0.0
	var speed := lv.length()
	if speed > 0.6:
		heading = heading.slerp(lv / speed, 1.0 - exp(-3.5 * delta)).normalized()
	gather = move_toward(gather, 1.0 if speed < 0.8 else 0.0, delta * (1.2 if speed < 0.8 else 3.0))
	sim.step(delta)


# ---------------------------------------------------------------------- spawning
func _spawn_start() -> void:
	_lead_ok()
	var origin := _flat(lead.global_position) if lead else global_position
	for i in start_adults:
		var q := origin + _jitter(minf(3.0, 0.5 * sqrt(float(maxi(1, start_adults)))))
		sim.add_rat(false, q)
	for i in start_pups:
		sim.add_rat(true, origin + _jitter(1.2))
	sim.relayout()
	_emit_counts_changed()


func _update_run_dust(delta: float) -> void:
	_dust_left -= delta
	if _dust_left > 0.0 or sim.count == 0:
		return
	_dust_left = RUN_DUST_GAP
	var sample := sim.random_runner()
	if sample.is_empty():
		return
	var vel: Vector3 = sample[1]
	if vel.length() < RUN_DUST_SPEED:
		return
	Vfx.run_dust_at(get_tree(), sample[0] as Vector3, vel, 0.7 if bool(sample[2]) else 1.0)


func spawn_adult(pos: Vector3) -> int:
	var idx := sim.add_rat(false, pos + _jitter(0.45))
	if idx >= 0:
		_emit_counts_changed()
	return idx


func spawn_pup(pos: Vector3) -> int:
	var p := pos + _jitter(0.45)
	var idx := sim.add_rat(true, p)
	if idx >= 0:
		births += 1
		if births % 3 == 1 or sim.count < 60:
			Vfx.play(get_tree(), &"pup_born", p)
		_emit_counts_changed()
	return idx


func configure_bite(bite: BiteComponent) -> void:
	bite.bite_range = bite_range
	bite.cooldown = bite_cooldown
	bite.chunk = bite_chunk
	bite.rate_bonus = bite_rate_bonus


func set_bite_stats(range_: float, cooldown: float, chunk: float, rate_bonus: float) -> void:
	bite_range = range_
	bite_cooldown = cooldown
	bite_chunk = chunk
	bite_rate_bonus = rate_bonus
	if _lead_ok():
		var lb := lead.get_node_or_null("BiteComponent") as BiteComponent
		if lb:
			configure_bite(lb)


func _jitter(radius: float) -> Vector3:
	var a := randf() * TAU
	return Vector3(sin(a), 0.0, cos(a)) * radius * sqrt(randf())


func on_lead_died() -> void:
	_emit_counts_changed()


func _emit_counts_changed() -> void:
	var lead_alive := 1 if (_lead_ok() and not lead.get("is_dead")) else 0
	adult_count = sim.adult_count + lead_alive
	pup_count = sim.pup_count
	changed.emit()


## Compatibility helper returning total outdoor rats (Lead Rat + outdoor followers).
func total_outdoor_rats() -> int:
	var n := 0
	if _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		n += 1
	for i in sim.count:
		if sim.state[i] < SwarmSim.State.FUNNEL_IN:
			n += 1
	return n


func _lead_ok() -> bool:
	if lead == null or not is_instance_valid(lead):
		lead = get_tree().get_first_node_in_group("lead_rat") as Node3D
		if lead:
			var b := lead.get_node_or_null("BiteComponent") as BiteComponent
			if b and not b.bit.is_connected(_on_lead_bit):
				b.bit.connect(_on_lead_bit)
	return lead != null


func _on_lead_bit(target: Node3D) -> void:
	_lead_bite_target = target
	_lead_bite_age = 0.0


func lead_position() -> Vector3:
	return _flat(lead.global_position) if _lead_ok() else global_position


# ---------------------------------------------------------------------- unified enemy query API
## Crowd query combining Lead Rat + SwarmSim spatial hash (used by Fear, Cat, PlagueDoctor).
func query_crowd(center: Vector3, radius: float) -> Dictionary:
	var res := sim.query_crowd(center, radius) if sim else {"count": 0, "centre": center, "nearest": Vector3.INF, "nearest_d2": INF}
	if _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		var lp := _flat(lead.global_position)
		var d2 := (lp.x - center.x) * (lp.x - center.x) + (lp.z - center.z) * (lp.z - center.z)
		if d2 <= radius * radius:
			var prev_n: int = res["count"]
			var prev_c: Vector3 = res["centre"]
			var new_n := prev_n + 1
			res["count"] = new_n
			res["centre"] = (prev_c * float(prev_n) + lp) / float(new_n)
			if d2 < float(res["nearest_d2"]):
				res["nearest_d2"] = d2
				res["nearest"] = lp
	return res


func hit_rats_in_circle(center: Vector3, radius: float, pups_only := false) -> int:
	var hits := sim.hit_circle(center, radius, pups_only) if sim else 0
	if not pups_only and _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		if DangerZone.circle_contains(center, radius, lead.global_position):
			lead.call("hit")
			hits += 1
	return hits


func hit_rats_in_arc(origin: Vector3, dir: Vector3, radius: float, half_angle: float, feet_radius: float, pups_only := false) -> int:
	var hits := sim.hit_arc(origin, dir, radius, half_angle, feet_radius, pups_only) if sim else 0
	if not pups_only and _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		if DangerZone.arc_contains(origin, dir, radius, half_angle, feet_radius, lead.global_position):
			lead.call("hit")
			hits += 1
	return hits


func sweep_rats_in_arc(origin: Vector3, dir: Vector3, radius: float, half_angle: float, feet_radius: float, strength: float) -> int:
	var hits := sim.sweep_arc(origin, dir, radius, half_angle, feet_radius, strength) if sim else 0
	if _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		if DangerZone.arc_contains(origin, dir, radius, half_angle, feet_radius, lead.global_position):
			lead.call("knockback", origin, strength)
			hits += 1
	return hits


func knockback_rats_in_circle(from: Vector3, radius: float, strength: float, kill_pups := true) -> int:
	var hits := sim.knockback_circle(from, radius, strength, kill_pups) if sim else 0
	if _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		if DangerZone.circle_contains(from, radius, lead.global_position):
			lead.call("knockback", from, strength)
			hits += 1
	return hits


## Kills the nearest single rat (Lead Rat or follower) within `radius` (Cat / SpringTrap).
func hit_one_rat_near(at: Vector3, radius: float) -> bool:
	var lead_d2 := INF
	if _lead_ok() and not lead.get("is_dead") and not lead.get("is_hidden"):
		var lp := _flat(lead.global_position)
		lead_d2 = (lp.x - at.x) * (lp.x - at.x) + (lp.z - at.z) * (lp.z - at.z)
	if lead_d2 <= radius * radius:
		var q := sim.query_crowd(at, radius) if sim else {"nearest_d2": INF}
		if lead_d2 <= float(q["nearest_d2"]):
			lead.call("hit")
			return true
	return sim.hit_one_near(at, radius) if sim else false


# ---------------------------------------------------------------------- danger
func _refresh_zones() -> void:
	_zones.clear()
	_zone_center.clear()
	_zone_radius.clear()
	_zone_time.clear()
	for n in get_tree().get_nodes_in_group("danger_zones"):
		var z := n as Node3D
		if z == null or z.is_queued_for_deletion() or not z.has_method("danger_contains"):
			continue
		var c: Variant = z.get("danger_center")
		var r: Variant = z.get("danger_radius")
		var t: Variant = z.get("danger_time_left")
		_zones.append(z)
		_zone_center.append(_flat(c) if c is Vector3 else _flat(z.global_position))
		_zone_radius.append(float(r) if r != null else 1.0)
		_zone_time.append(float(t) if t != null else -1.0)


func has_zones() -> bool:
	return not _zones.is_empty()


func zone_at(p: Vector3, max_time := INF) -> int:
	for i in _zones.size():
		var t := _zone_time[i]
		if t >= 0.0 and t > max_time:
			continue
		var c := _zone_center[i]
		var r := _zone_radius[i]
		var dx := p.x - c.x
		var dz := p.z - c.z
		if dx * dx + dz * dz > r * r:
			continue
		var z := _zones[i]
		if is_instance_valid(z) and z.is_in_group("danger_zones") and z.call("danger_contains", p):
			return i
	return -1


func zone_center(i: int) -> Vector3:
	return _zone_center[i]


func zone_persistent(i: int) -> bool:
	return _zone_time[i] < 0.0


func escape_point(here: Vector3, max_time := INF) -> Vector3:
	var reach := 0.0
	for i in _zones.size():
		var dd := here.distance_to(_zone_center[i])
		if dd <= _zone_radius[i]:
			reach = maxf(reach, _zone_radius[i] - dd)
	if reach <= 0.0:
		return Vector3.INF
	reach += ESCAPE_STEP * 2.0
	var best: Array = []
	var a0 := randf() * TAU / ESCAPE_DIRS
	for k in ESCAPE_DIRS:
		var a := a0 + TAU * k / ESCAPE_DIRS
		var dir := Vector3(sin(a), 0.0, cos(a))
		var d := ESCAPE_STEP
		while d <= reach and zone_at(here + dir * d, max_time) >= 0:
			d += ESCAPE_STEP
		if d <= reach:
			best.append([d, dir])
	best.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for k in mini(best.size(), 4):
		var p: Vector3 = here + (best[k][1] as Vector3) * (float(best[k][0]) + ESCAPE_MARGIN)
		if zone_at(p, max_time) < 0 and clear_line(here, p):
			return p
	return Vector3.INF


# ---------------------------------------------------------------------- swarm
func _update_swarm() -> void:
	if not _lead_ok() or lead.get("is_dead") or is_hidden:
		swarm_exterminator = null
		_set_swarm(null)
		return
	var p := lead_position()
	if swarm_exterminator and (not _swarm_alive(swarm_exterminator) \
			or p.distance_to(_flat(swarm_exterminator.global_position)) > SWARM_LEAVE):
		swarm_exterminator = null
	if swarm_exterminator == null:
		swarm_exterminator = _near_exterminator(p, SWARM_ENTER)
	if swarm_exterminator:
		_set_swarm(swarm_exterminator)
		return
	if _lead_bite_target and _lead_bite_age <= SWARM_BITE_HOLD and _swarm_alive(_lead_bite_target) \
			and p.distance_to(_flat(_lead_bite_target.global_position)) <= SWARM_LEAVE:
		_set_swarm(_lead_bite_target)
		return
	_set_swarm(null)


func _near_exterminator(p: Vector3, within: float) -> Node3D:
	for n in get_tree().get_nodes_in_group("exterminator"):
		var e := n as Node3D
		if e and _swarm_alive(e) and p.distance_to(_flat(e.global_position)) <= within:
			return e
	return null


static func _swarm_alive(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return false
	var inf := t.get_node_or_null("Infection") as InfectionComponent
	return inf != null and not inf.is_dead()


func _set_swarm(t: Node3D) -> void:
	if t == swarm_target:
		return
	swarm_target = t
	_swarm_dirty = true
	if t == null:
		sim.clear_swarm()


# ---------------------------------------------------------------------- houses (deliberate Hide & Raid)
func nearest_house(p: Vector3, max_dist: float, occupied := false) -> House:
	var best: House = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("houses"):
		var h := n as House
		if h == null:
			continue
		var d := _flat(p).distance_to(h.door_position)
		if d > max_dist:
			continue
		if occupied and h.living_occupants().is_empty():
			d += 1000.0
		if d < best_d:
			best_d = d
			best = h
	return best


func can_hide() -> bool:
	return hide_unlocked and not is_hidden and hide_cooldown_left <= 0.0 \
		and _lead_ok() and not lead.get("is_dead")


## The house door eligible for deliberate "[E] Hide" right now, or null.
func hide_candidate() -> House:
	if not can_hide():
		return null
	return nearest_house(lead_position(), HIDE_REACH)


## Deliberate Hide button press: enters the nearby door, or exits early if already Hidden.
func try_hide() -> bool:
	if is_hidden:
		if _hide_time >= HIDE_EXIT_GRACE:
			leave_house()
			return true
		return false
	var h := hide_candidate()
	if h == null:
		return false
	hide_in(h)
	return true


func _update_hide(delta: float) -> void:
	hide_cooldown_left = maxf(hide_cooldown_left - delta, 0.0)
	if is_hidden:
		_hide_time += delta
		hidden_time_left = maxf(hidden_time_left - delta, 0.0)
		var done: bool = hidden_time_left <= 0.0 or bool(lead.get("is_dead")) or not is_instance_valid(hide_house)
		if not done and _hide_full and _hide_time >= HIDE_MIN_TIME:
			done = hide_house.healthy_occupants().is_empty()
		if done:
			leave_house()


func hide_in(h: House) -> void:
	if is_hidden or not _lead_ok():
		return
	is_hidden = true
	hide_house = h
	hides += 1
	_hide_time = 0.0
	_hide_full = not h.healthy_occupants().is_empty()
	hidden_time_left = hide_duration * (1.0 if _hide_full else 0.5)
	Vfx.play(get_tree(), &"door_dust", h.door_position, h.door_normal)
	lead.call("hide_in", h)
	sim.hide_all_in(h)
	print_debug_state("hide: entered house %s (occupants %d, living %d, healthy %d) for %.1fs" % [
		h.name, h.occupants.size(), h.living_occupants().size(), h.healthy_occupants().size(), hidden_time_left])


func leave_house() -> void:
	if not is_hidden:
		return
	var h := hide_house
	is_hidden = false
	hidden_time_left = 0.0
	hide_house = null
	hide_cooldown_left = hide_cooldown
	if h == null or not is_instance_valid(h):
		return
	var out := h.door_position + h.door_normal * 0.9
	Vfx.play(get_tree(), &"door_dust", h.door_position, h.door_normal)
	if lead.get("is_hidden"):
		lead.call("pour_out", h, out)
	sim.pour_all_out(h)
	print_debug_state("hide: left house %s after %.1fs" % [h.name, _hide_time])


func raid_followers_available() -> int:
	return sim.raid_available_count() if sim else 0


func can_raid() -> bool:
	return raid_unlocked and raid_cooldown_left <= 0.0 and not is_hidden \
		and raid_followers_available() > 0


func raid(h: House) -> bool:
	if h == null or not can_raid():
		return false
	var sent := sim.start_raid(h, raid_size, raid_duration)
	if sent <= 0:
		return false
	raid_cooldown_left = raid_cooldown
	raids += 1
	_show_ring(h)
	print_debug_state("raid: %d raiders sent to house %s" % [sent, h.name])
	return true


func _update_raid(delta: float) -> void:
	raid_cooldown_left = maxf(raid_cooldown_left - delta, 0.0)
	var targeted := sim.active_raid_houses()
	raiders_inside = sim.raiders_inside
	for h: Variant in _rings.keys():
		if not targeted.has(h):
			_hide_ring(h)
	if lead.get("bot_mode") and can_raid():
		var h := nearest_house(lead_position(), BOT_RAID_RANGE, true)
		if h:
			raid(h)


func _show_ring(h: House) -> void:
	if _rings.has(h):
		return
	var ring := Node3D.new()
	ring.name = "RaidRing"
	add_child(ring)
	ring.global_position = h.door_position
	props.part(ring, props.torus(0.85, 0.09), Props.INK, Vector3(0, 0.09, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	var inner := props.part(ring, props.torus(0.55, 0.05), Props.INK, Vector3(0, 0.09, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pulse := inner.create_tween().set_loops()
	pulse.tween_property(inner, "scale", Vector3(0.6, 0.3, 0.6), 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(inner, "scale", Vector3(1.0, 0.3, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	_rings[h] = ring


func _hide_ring(h: Variant) -> void:
	var ring := _rings[h] as Node3D
	_rings.erase(h)
	if ring == null or not is_instance_valid(ring):
		return
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(0.1, 1.0, 0.1), 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(ring.queue_free)


func print_debug_state(msg: String) -> void:
	if debug_print:
		print("colony: ", msg)


func clear_line(a: Vector3, b: Vector3) -> bool:
	if nav != null and nav.w_cols > 0:
		return nav.clear_line_xy(Vector2(a.x, a.z), Vector2(b.x, b.z))
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.3, 0), b + Vector3(0, 0.3, 0), WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ---------------------------------------------------------------------- feeding
func find_corpse(p: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d2 := radius * radius
	for n in get_tree().get_nodes_in_group("corpses"):
		var c := n as Node3D
		if c == null or meals_left(c) <= 0:
			continue
		var d := c.global_position - p
		var d2 := d.x * d.x + d.z * d.z
		if d2 <= best_d2:
			best_d2 = d2
			best = c
	return best


static func meals_left(corpse: Node3D) -> int:
	if "meals_left" in corpse:
		return corpse.get("meals_left")
	return corpse.get_meta("meals_left", 3)


static func take_meal(corpse: Node3D) -> bool:
	if corpse == null or not is_instance_valid(corpse):
		return false
	if corpse.has_method("take_meal"):
		return corpse.take_meal()
	var m := meals_left(corpse)
	if m <= 0:
		return false
	corpse.set_meta("meals_left", m - 1)
	if m - 1 <= 0:
		corpse.remove_from_group("corpses")
	return true


static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
