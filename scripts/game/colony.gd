## The Colony: every rat of the player, the Lead Rat included. Owns the
## follower rats (Adults and Pups, scenes/game/colony_rat.tscn), lays out the
## loose slots they flock to behind the Lead Rat, drops a breadcrumb trail of
## the Lead Rat's path for followers cut off by a wall, and keeps the counts.
## Feeding helpers (find_corpse, take_meal) are shared with the Lead Rat.
##
## Houses (M4, both behind Upgrade Tree unlocks):
## * Hide: the Lead Rat walking into a door takes the whole Colony inside. The
##   rats are hidden and invulnerable and Bite the occupants; they are forced
##   out after hide_duration (half for a house with nobody healthy inside), or
##   once every occupant is infected or dead; then Hide cools down.
## * Raid: raid(house) sends up to raid_size follower Adults to the door; they
##   Bite inside for raid_duration and rejoin the flock. An ink ring marks the
##   door while the Raid lasts. raid_cooldown between Raids.
##
## Danger and swarming (M6b):
## * Danger zones: every DANGER_SCAN s the Colony caches the nodes in group
##   "danger_zones" (danger_center, danger_radius, danger_time_left,
##   danger_contains()). Followers ask zone_at() / escape_point() against that
##   cache, culled by the bounding radius first; the --bot Lead Rat too.
## * Swarm: while the Lead Rat is within SWARM_ENTER of a living
##   Exterminator (or Biting a townsperson), follower Adults leave their wake
##   slots for rings round that target at Bite range (swarm_world()); they go
##   back to flocking once the Lead Rat is SWARM_LEAVE away. Danger wins.
## * --danger-test drops a dummy zone (circle or arc, 1.2 s wind-up) on the
##   Colony every 3 s, to test the dodging without the bosses.
class_name Colony
extends Node3D

signal changed                           # rat added/removed, Pup matured

const RAT_SCENE := preload("res://scenes/game/colony_rat.tscn")
const Props := preload("res://scripts/town_props.gd")
const WORLD_MASK := 1
const CRUMB_STEP := 0.5
const CRUMB_MAX := 160
## The Lead Rat enters a door within this distance (u) of its door point.
const HIDE_REACH := 1.0
## How far the Lead Rat must get from the door it left before it re-arms.
const HIDE_REARM := 1.8
## Hidden at least this long before "everyone inside is infected" ends it.
const HIDE_MIN_TIME := 2.0
## The --bot Raids houses within this distance.
const BOT_RAID_RANGE := 10.0
## Cell size (u) of the grid the followers' separation looks up; at least the
## largest pair of rat radii (0.6), so neighbours are in the 3x3 cells around.
const SEP_CELL := 0.6
## Seconds between scans of the "danger_zones" group (and swarm checks).
const DANGER_SCAN := 0.1
## Escape sampling: directions, step and the extra margin past the edge.
const ESCAPE_DIRS := 12
const ESCAPE_STEP := 0.35
const ESCAPE_MARGIN := 0.6
## Swarm the target when the Lead Rat is within SWARM_ENTER of it; stop past SWARM_LEAVE.
const SWARM_ENTER := 7.0
const SWARM_LEAVE := 9.0
## A Bitten townsperson stays the swarm target this long after the last Bite.
const SWARM_BITE_HOLD := 2.0
## Rings round a swarm target: first ring radius, ring gap, spacing along a ring.
const SWARM_RING0 := 0.8
const SWARM_RING_GAP := 0.38
const SWARM_SPACING := 0.55
## --danger-test: a dummy zone every this many seconds.
const DANGER_TEST_EVERY := 3.0

@export var start_adults := 0            # followers at Round start (Upgrade Tree sets this in M3)
## Debug: Pups at Round start (--pups=<n>).
@export var start_pups := 0
@export var pup_maturity := 15.0         # s
@export var feed_time := 1.5             # s standing on a corpse per meal
@export var breed_cooldown := 4.0        # s per Adult between Pups
@export var pup_feed_bonus := 5.0        # s of maturity removed per meal a Pup eats
## Distance a follower looks for a corpse, and how close the Lead Rat must be.
@export var feed_seek_radius := 2.5
@export var feed_lead_radius := 6.0
## Followers' top speed relative to the Lead Rat's.
@export var speed_factor := 1.15
## Bite stats for every Adult (Lead Rat included), set from the Run at Round
## start; see configure_bite().
@export var bite_range := 1.6
@export var bite_cooldown := 1.2
@export var bite_chunk := 3.0
@export var bite_rate_bonus := 0.5
## Hide and Raid stats, set from the Run at Round start.
@export var hide_duration := 6.0
@export var hide_cooldown := 3.0
@export var raid_size := 3
@export var raid_duration := 4.0
@export var raid_cooldown := 10.0

## State read by the HUD.
var hide_unlocked: bool
var raid_unlocked: bool
var is_hidden: bool
var hidden_time_left: float
var raid_cooldown_left: float     # 0 = ready
var raiders_inside: int
var hide_cooldown_left := 0.0
## The house the Colony is hiding in (null when out).
var hide_house: House
## Running totals for the Round (debug output).
var hides := 0
var raids := 0

var adult_count: int                     # includes the Lead Rat
var pup_count: int
## Running totals for the Round (debug output).
var births := 0
var maturings := 0
var deaths := 0

## Shared prop kit, so every rat reuses the same materials.
var props := Props.new(41)
var lead: Node3D
## Smoothed facing of the Colony (unit, XZ); slots are laid out in this frame.
var heading := Vector3(1, 0, 0)
## 0 while the Lead Rat runs, towards 1 while it stands: the Colony gathers round it.
var gather := 1.0
## Lead Rat path, oldest first; crumb_base is the absolute index of crumbs[0].
var crumbs: Array[Vector3] = []
var crumb_base := 0

## Print Hide / Raid events (--dev, --bot).
var debug_print := false
var _followers: Array[Node3D] = []
var _last_lead_pos := Vector3.ZERO
var _hide_time := 0.0
var _hide_full := false          # entered with healthy occupants
var _rearm_house: House          # the door just left; needs walking away first
var _rings := {}                 # House -> ink ring Node3D at its door
## Separation grid, rebuilt once per physics frame (see separation()).
var _grid_frame := -1
var _grid := {}                  # Vector2i cell -> Array[int] indices
var _grid_pos := PackedVector3Array()
var _grid_rad := PackedFloat32Array()
var _grid_rats: Array[Node3D] = []
## Danger zone cache (refreshed every DANGER_SCAN s).
var _zones: Array[Node3D] = []
var _zone_center := PackedVector3Array()
var _zone_radius := PackedFloat32Array()
var _zone_time := PackedFloat32Array()
var _scan_left := 0.0
## Swarm: the target being ringed (null = normal flocking).
var swarm_target: Node3D
## The Exterminator latched for swarming (entered at SWARM_ENTER, left past SWARM_LEAVE).
var swarm_exterminator: Node3D
var _swarm_dirty := true
var _swarm_reassign_left := 0.0
var _lead_bite_target: Node3D
var _lead_bite_age := INF
var _danger_test := false
var _danger_test_left := 1.5
var _danger_test_n := 0


func _ready() -> void:
	add_to_group("colony")
	_danger_test = OS.get_cmdline_user_args().has("--danger-test")
	_spawn_start.call_deferred()


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
		_assign_swarm()
	if _danger_test:
		_update_danger_test(delta)
	var lv: Vector3 = lead.get("velocity")
	lv.y = 0.0
	var speed := lv.length()
	if speed > 0.6:
		heading = heading.slerp(lv / speed, 1.0 - exp(-3.5 * delta)).normalized()
	gather = move_toward(gather, 1.0 if speed < 0.8 else 0.0, delta * (1.2 if speed < 0.8 else 3.0))
	var p := _flat(lead.global_position)
	if p.distance_to(_last_lead_pos) >= CRUMB_STEP:
		crumbs.append(p)
		_last_lead_pos = p
		if crumbs.size() > CRUMB_MAX:
			crumbs.pop_front()
			crumb_base += 1


# ---------------------------------------------------------------------- spawning
func _spawn_start() -> void:
	_lead_ok()
	var origin := _flat(lead.global_position) if lead else global_position
	_last_lead_pos = origin
	crumbs.append(origin)
	for i in start_adults:
		_add_rat(false, origin, false)
	for i in start_pups:
		_add_rat(true, origin, false)
	_relayout()
	# Start everyone on their slot (or next to the Lead Rat if that is in a wall).
	for r in _followers:
		var s := slot_world(r)
		r.global_position = s if clear_line(origin, s) else origin + _jitter(0.6)
	_recount()


## Spawns a new Adult follower near `pos`.
func spawn_adult(pos: Vector3) -> Node3D:
	var r := _add_rat(false, pos, true)
	_relayout()
	_recount()
	return r


## Spawns a newborn Pup next to `pos` (a rat that just Fed).
func spawn_pup(pos: Vector3) -> Node3D:
	var r := _add_rat(true, pos, true)
	births += 1
	_relayout()
	_recount()
	return r


func _add_rat(pup: bool, pos: Vector3, near: bool) -> Node3D:
	var r := RAT_SCENE.instantiate() as Node3D
	r.set("colony", self)
	r.set("is_pup", pup)
	add_child(r)
	var p := _flat(pos)
	if near:
		var q := p + _jitter(0.45)
		p = q if clear_line(p, q) else p
	r.global_position = p
	_followers.append(r)
	return r


## Copies the Colony's Bite stats onto an Adult's BiteComponent.
func configure_bite(bite: BiteComponent) -> void:
	bite.bite_range = bite_range
	bite.cooldown = bite_cooldown
	bite.chunk = bite_chunk
	bite.rate_bonus = bite_rate_bonus


## Sets the Bite stats and applies them to every Adult already alive.
func set_bite_stats(range_: float, cooldown: float, chunk: float, rate_bonus: float) -> void:
	bite_range = range_
	bite_cooldown = cooldown
	bite_chunk = chunk
	bite_rate_bonus = rate_bonus
	if _lead_ok():
		var lb := lead.get_node_or_null("BiteComponent") as BiteComponent
		if lb:
			configure_bite(lb)
	for r in _followers:
		var b := r.get_node_or_null("BiteComponent") as BiteComponent
		if b:
			configure_bite(b)


func _jitter(radius: float) -> Vector3:
	var a := randf() * TAU
	return Vector3(sin(a), 0.0, cos(a)) * radius * sqrt(randf())


# ---------------------------------------------------------------------- bookkeeping
## Called by a follower when it Matures.
func on_matured(_rat: Node3D) -> void:
	maturings += 1
	_relayout()
	_recount()


## Called by a follower when it dies.
func on_rat_died(rat: Node3D) -> void:
	_followers.erase(rat)
	deaths += 1
	_relayout()
	_recount()


## Called by a follower back out in the street (after Hide or a Raid).
func on_rat_out(_rat: Node3D) -> void:
	_relayout()


## Called by the Lead Rat when it dies.
func on_lead_died() -> void:
	_recount()


func followers() -> Array[Node3D]:
	return _followers


## Push that keeps `rat` (at flat `here`, radius `mine`) apart from the other
## followers out in the street, from a grid built once per physics frame
## instead of every rat testing every other rat.
func separation(rat: Node3D, here: Vector3, mine: float) -> Vector3:
	_build_grid()
	var push := Vector3.ZERO
	var c := Vector2i(floori(here.x / SEP_CELL), floori(here.z / SEP_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell: Array = _grid.get(Vector2i(c.x + dx, c.y + dz), [])
			for i: int in cell:
				if _grid_rats[i] == rat:
					continue
				var d := here - _grid_pos[i]
				var r := mine + _grid_rad[i]
				var l2 := d.x * d.x + d.z * d.z
				if l2 < r * r and l2 > 0.000001:
					var l := sqrt(l2)
					push += d / l * (1.0 - l / r) * 6.0
	return push


func _build_grid() -> void:
	var f := Engine.get_physics_frames()
	if f == _grid_frame:
		return
	_grid_frame = f
	_grid.clear()
	_grid_pos.clear()
	_grid_rad.clear()
	_grid_rats.clear()
	for r in _followers:
		if r.get("is_hidden"):
			continue
		var p := _flat(r.global_position)
		var i := _grid_rats.size()
		_grid_rats.append(r)
		_grid_pos.append(p)
		_grid_rad.append(0.2 if r.get("is_pup") else 0.3)
		var key := Vector2i(floori(p.x / SEP_CELL), floori(p.z / SEP_CELL))
		if _grid.has(key):
			(_grid[key] as Array).append(i)
		else:
			_grid[key] = [i]


func _recount() -> void:
	var a := 0
	var p := 0
	for r in _followers:
		if r.get("is_pup"):
			p += 1
		else:
			a += 1
	if _lead_ok() and not lead.get("is_dead"):
		a += 1
	adult_count = a
	pup_count = p
	changed.emit()


## Gives every follower a slot: Adults in a loose disc right behind the Lead
## Rat, Pups in a smaller disc trailing behind the Adults. Sunflower spacing
## keeps the disc even without looking like a grid.
func _relayout() -> void:
	_swarm_dirty = true
	var adults: Array[Node3D] = []
	var pups: Array[Node3D] = []
	for r in _followers:
		if r.get("raiding"):
			continue
		if r.get("is_pup"):
			pups.append(r)
		else:
			adults.append(r)
	var ra := 0.5 * sqrt(float(adults.size()))
	var rp := 0.38 * sqrt(float(pups.size()))
	var a_back := 1.0 + ra * 1.15
	var p_back := a_back + ra * 1.25 + 0.5 + rp * 1.25
	_place_disc(adults, a_back, ra)
	_place_disc(pups, p_back, rp)


func _place_disc(rats: Array[Node3D], back: float, radius: float) -> void:
	var n := rats.size()
	for i in n:
		var r := radius * sqrt((i + 0.5) / n)
		var a := i * 2.39996
		var off := Vector3(r * cos(a), 0.0, r * sin(a) * 1.25)
		rats[i].set("slot", off)
		rats[i].set("slot_back", back)


## World position of a follower's slot: behind the Lead Rat while it runs,
## gathered round it while it stands.
func slot_world(rat: Node3D) -> Vector3:
	if not _lead_ok():
		return rat.global_position
	var off: Vector3 = rat.get("slot")
	var back: float = rat.get("slot_back")
	var local := Vector3(off.x * (1.0 + 0.2 * gather), 0.0, off.z - back * (1.0 - 0.5 * gather))
	var basis := Basis(Vector3.UP, atan2(heading.x, heading.z))
	return _flat(lead.global_position) + basis * local


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


## Index (into the cache) of a zone containing flat `p`, or -1. Only zones
## striking within `max_time` s count (persistent ones, -1, always do).
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


## The nearest spot out of every zone (striking within `max_time`) from flat
## `here`, by the shortest way, a margin past the edge and not through a wall.
## Vector3.INF if none is found. Straight out from a zone's centre always
## leaves it within its radius, so no direction is searched further than that.
func escape_point(here: Vector3, max_time := INF) -> Vector3:
	var reach := 0.0
	for i in _zones.size():
		var dd := here.distance_to(_zone_center[i])
		if dd <= _zone_radius[i]:
			reach = maxf(reach, _zone_radius[i] - dd)
	if reach <= 0.0:
		return Vector3.INF
	reach += ESCAPE_STEP * 2.0
	var best: Array = []   # [distance, dir]
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


## --danger-test: a dummy zone on the Colony every DANGER_TEST_EVERY s,
## alternating a circle on the pack and an arc behind the Lead Rat.
func _update_danger_test(delta: float) -> void:
	_danger_test_left -= delta
	if _danger_test_left > 0.0:
		return
	_danger_test_left = DANGER_TEST_EVERY
	var centre := lead_position()
	if not _followers.is_empty():
		var sum := Vector3.ZERO
		for r in _followers:
			sum += _flat(r.global_position)
		centre = sum / _followers.size()
	var z := DummyZone.new()
	z.name = "DummyDangerZone"
	add_child(z)
	if _danger_test_n % 2 == 0:
		z.setup(centre, 2.2, 0.0, heading, 1.2, props)
	else:
		z.setup(lead_position() + heading * 0.5, 3.2, deg_to_rad(60.0), -heading, 1.2, props)
	_danger_test_n += 1
	print_debug_state("danger-test: %s r=%.1f at (%.1f, %.1f)" % [
		"circle" if z.half <= 0.0 else "arc", z.danger_radius, z.danger_center.x, z.danger_center.z])


# ---------------------------------------------------------------------- swarm
func _update_swarm() -> void:
	if not _lead_ok() or lead.get("is_dead") or is_hidden:
		swarm_exterminator = null
		_set_swarm(null)
		return
	var p := lead_position()
	# Hysteresis held as state: an Exterminator is latched once the Lead Rat
	# is within SWARM_ENTER and released only past SWARM_LEAVE (or on death).
	if swarm_exterminator and (not _swarm_alive(swarm_exterminator) 			or p.distance_to(_flat(swarm_exterminator.global_position)) > SWARM_LEAVE):
		swarm_exterminator = null
	if swarm_exterminator == null:
		swarm_exterminator = _near_exterminator(p, SWARM_ENTER)
	if swarm_exterminator:
		_set_swarm(swarm_exterminator)
		return
	# Else a townsperson the Lead Rat is Biting right now.
	if _lead_bite_target and _lead_bite_age <= SWARM_BITE_HOLD and _swarm_alive(_lead_bite_target) 			and p.distance_to(_flat(_lead_bite_target.global_position)) <= SWARM_LEAVE:
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
	var was := swarm_target
	swarm_target = t
	_swarm_dirty = true
	if t == null:
		for r in _followers:
			r.set("swarm_slot", Vector3.INF)
	if (t and t.is_in_group("exterminator")) or (was and is_instance_valid(was) and was.is_in_group("exterminator")):
		print_debug_state("swarm: %s" % (t.name if t else "off"))


## Rings of evenly spread spots round the target at Bite range: the Adults
## nearest it take the inner ring; within a ring they keep their angular order
## so nobody crosses through the pack. Pups keep flocking.
func _assign_swarm() -> void:
	_swarm_dirty = false
	_swarm_reassign_left = 1.0
	if swarm_target == null or not is_instance_valid(swarm_target):
		return
	var c := _flat(swarm_target.global_position)
	var adults: Array[Node3D] = []
	for r in _followers:
		if r.get("is_pup") or r.get("raiding") or r.get("is_hidden"):
			r.set("swarm_slot", Vector3.INF)
		else:
			adults.append(r)
	adults.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat(a.global_position).distance_squared_to(c) < _flat(b.global_position).distance_squared_to(c))
	var i := 0
	var ring := 0
	while i < adults.size():
		var rad := SWARM_RING0 + SWARM_RING_GAP * ring
		var n := mini(maxi(4, floori(TAU * rad / SWARM_SPACING)), adults.size() - i)
		var members: Array[Node3D] = adults.slice(i, i + n)
		var angles := {}
		for r in members:
			var d := _flat(r.global_position) - c
			angles[r] = atan2(d.x, d.z)
		members.sort_custom(func(a: Node3D, b: Node3D) -> bool: return float(angles[a]) < float(angles[b]))
		var start := float(angles[members[0]])
		for k in n:
			var a := start + TAU * (k + 0.5 * float(ring % 2)) / n
			members[k].set("swarm_slot", Vector3(sin(a), 0.0, cos(a)) * rad)
		i += n
		ring += 1


## World spot of `rat`'s swarm slot, or Vector3.INF when not swarming.
func swarm_world(rat: Node3D) -> Vector3:
	if swarm_target == null or not is_instance_valid(swarm_target):
		return Vector3.INF
	var off: Vector3 = rat.get("swarm_slot")
	if off == Vector3.INF:
		return Vector3.INF
	return _flat(swarm_target.global_position) + off


# ---------------------------------------------------------------------- houses
## The house whose door is nearest to `p` within `max_dist`, or null. With
## `occupied`, houses with somebody alive inside win over empty ones.
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
		return
	var p := lead_position()
	if _rearm_house and (not is_instance_valid(_rearm_house) \
			or p.distance_to(_rearm_house.door_position) > HIDE_REARM):
		_rearm_house = null
	if not can_hide():
		return
	var wish: Vector3 = lead.get("wish")
	for n in get_tree().get_nodes_in_group("houses"):
		var h := n as House
		if h == null or h == _rearm_house:
			continue
		if p.distance_to(h.door_position) <= HIDE_REACH and wish.dot(-h.door_normal) > 0.3:
			hide_in(h)
			return


## The whole Colony (everyone not out on a Raid) funnels into `h`.
func hide_in(h: House) -> void:
	if is_hidden or not _lead_ok():
		return
	is_hidden = true
	hide_house = h
	hides += 1
	_hide_time = 0.0
	_hide_full = not h.healthy_occupants().is_empty()
	hidden_time_left = hide_duration * (1.0 if _hide_full else 0.5)
	lead.call("hide_in", h)
	for r in _followers:
		if r.get("raiding") or r.get("is_hidden"):
			continue
		# The rats nearest the door go first.
		var d := _flat(r.global_position).distance_to(h.door_position)
		r.call("hide_in", h, minf(0.04 + d * 0.035, 0.3))
	print_debug_state("hide: entered house %s (occupants %d, living %d, healthy %d) for %.1fs" % [
		h.name, h.occupants.size(), h.living_occupants().size(), h.healthy_occupants().size(), hidden_time_left])


## Forced out at the door: the Colony pours back into the street.
func leave_house() -> void:
	if not is_hidden:
		return
	var h := hide_house
	is_hidden = false
	hidden_time_left = 0.0
	hide_house = null
	hide_cooldown_left = hide_cooldown
	_rearm_house = h
	if h == null or not is_instance_valid(h):
		return
	var out := h.door_position + h.door_normal * 0.8
	if lead.get("is_hidden"):
		lead.call("pour_out", h, out)
	var side := h.door_normal.cross(Vector3.UP)
	var i := 0
	for r in _followers:
		if r.get("raiding") or not r.get("is_hidden") or r.get("house") != h:
			continue
		var spot := out + h.door_normal * randf_range(0.3, 1.4) + side * randf_range(-1.1, 1.1)
		if not clear_line(h.door_position, spot):
			spot = out + h.door_normal * randf_range(0.2, 0.6)
		r.call("pour_out", spot, 0.05 + 0.035 * i)
		i += 1
	crumbs.append(out)
	_last_lead_pos = out
	if crumbs.size() > CRUMB_MAX:
		crumbs.pop_front()
		crumb_base += 1
	print_debug_state("hide: left house %s after %.1fs" % [h.name, _hide_time])


## Follower Adults free for a Raid (not Pups, not out on one, not hidden).
func raid_followers_available() -> int:
	return _raid_pool().size()


func _raid_pool() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in _followers:
		if not r.get("is_pup") and not r.get("raiding") and not r.get("is_hidden"):
			out.append(r)
	return out


func can_raid() -> bool:
	return raid_unlocked and raid_cooldown_left <= 0.0 and not is_hidden \
		and raid_followers_available() > 0


## Sends up to raid_size follower Adults (nearest to the door first) into
## `h`. False if Raid is unavailable right now.
func raid(h: House) -> bool:
	if h == null or not can_raid():
		return false
	var pool := _raid_pool()
	var door := h.door_position
	pool.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat(a.global_position).distance_squared_to(door) < _flat(b.global_position).distance_squared_to(door))
	var n := mini(raid_size, pool.size())
	for i in n:
		pool[i].call("start_raid", h, raid_duration)
	raid_cooldown_left = raid_cooldown
	raids += 1
	_show_ring(h)
	_relayout()
	print_debug_state("raid: %d raiders sent to house %s (living %d, healthy %d)" % [
		n, h.name, h.living_occupants().size(), h.healthy_occupants().size()])
	return true


func _update_raid(delta: float) -> void:
	raid_cooldown_left = maxf(raid_cooldown_left - delta, 0.0)
	var inside := 0
	var targeted := {}
	for r in _followers:
		if not r.get("raiding"):
			continue
		targeted[r.get("house")] = true
		if r.get("is_hidden"):
			inside += 1
	raiders_inside = inside
	for h: Variant in _rings.keys():
		if not targeted.has(h):
			_hide_ring(h)
	if lead.get("bot_mode") and can_raid():
		var h := nearest_house(lead_position(), BOT_RAID_RANGE, true)
		if h:
			raid(h)


## A ring of ink on the ground at the door, breathing slowly.
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
	# The inner ring breathes in towards the door point.
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


## Prints a line in --dev / --bot runs.
func print_debug_state(msg: String) -> void:
	if debug_print:
		print("colony: ", msg)


# ---------------------------------------------------------------------- trail
## The breadcrumb at absolute index `i` (clamped to what is still kept).
func crumb(i: int) -> Vector3:
	return crumbs[clampi(i - crumb_base, 0, crumbs.size() - 1)]


func newest_crumb() -> int:
	return crumb_base + crumbs.size() - 1


## Absolute index of the crumb nearest to `p`.
func nearest_crumb(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in crumbs.size():
		var d := p.distance_squared_to(crumbs[i])
		if d < best_d:
			best_d = d
			best = i
	return crumb_base + best


## True if nothing solid (layer 1) lies between a and b, a little above the ground.
func clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.3, 0), b + Vector3(0, 0.3, 0), WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ---------------------------------------------------------------------- feeding
## The nearest corpse within `radius` of `p` that still has meals, or null.
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


## Eats one meal off `corpse`; false if there was none left.
static func take_meal(corpse: Node3D) -> bool:
	if corpse == null or not is_instance_valid(corpse):
		return false
	if corpse.has_method("take_meal"):
		return corpse.take_meal()
	# Fallback until townsperson.gd has meals: count them in metadata.
	var m := meals_left(corpse)
	if m <= 0:
		return false
	corpse.set_meta("meals_left", m - 1)
	if m - 1 <= 0:
		corpse.remove_from_group("corpses")
	return true


static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


## --danger-test: a stand-in danger zone with the M6b contract API. It winds up
## for the given time (an ink outline on the ground), then hits the followers
## inside as a sweep would, leaves the group and fades.
class DummyZone extends Node3D:
	var danger_center := Vector3.ZERO
	var danger_radius := 2.0
	var danger_time_left := 1.0
	var half := 0.0
	var dir := Vector3.FORWARD
	var hits := 0

	func setup(c: Vector3, r: float, half_: float, dir_: Vector3, windup: float, kit: Props) -> void:
		danger_center = Vector3(c.x, 0.0, c.z)
		danger_radius = r
		half = half_
		dir = Vector3(dir_.x, 0.0, dir_.z).normalized()
		danger_time_left = windup
		global_position = danger_center
		add_to_group("danger_zones")
		if half <= 0.0:
			kit.part(self, kit.torus(r, 0.07), Props.INK, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
			return
		for s: float in [-1.0, 1.0]:
			kit.strip(self, Vector3(0, 0.08, 0), dir.rotated(Vector3.UP, s * half) * r + Vector3(0, 0.08, 0), 0.09, Props.INK)
		var prev := Vector3.ZERO
		for k in 9:
			var p := dir.rotated(Vector3.UP, lerpf(-half, half, k / 8.0)) * r + Vector3(0, 0.08, 0)
			if k > 0:
				kit.strip(self, prev, p, 0.09, Props.INK)
			prev = p

	func danger_contains(p: Vector3) -> bool:
		var d := Vector3(p.x - danger_center.x, 0.0, p.z - danger_center.z)
		if d.length_squared() > danger_radius * danger_radius:
			return false
		if half <= 0.0 or d.length_squared() <= 0.25:
			return true
		return absf(dir.signed_angle_to(d, Vector3.UP)) <= half

	func _physics_process(delta: float) -> void:
		if danger_time_left < 0.0:
			return
		danger_time_left -= delta
		if danger_time_left > 0.0:
			return
		danger_time_left = -1.0
		remove_from_group("danger_zones")
		var inside := 0
		for n: Node in get_tree().get_nodes_in_group("rats").duplicate():
			var r := n as Node3D
			if r == null or not danger_contains(r.global_position):
				continue
			inside += 1
			if not r.is_in_group("lead_rat") and r.has_method("hit"):
				r.call("hit")
				hits += 1
		print("colony: danger-test: impact killed %d followers (%d rats inside, %d rats total)" % [
			hits, inside, get_tree().get_nodes_in_group("rats").size()])
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(1.2, 1.0, 1.2), 0.3)
		tw.tween_callback(queue_free)
