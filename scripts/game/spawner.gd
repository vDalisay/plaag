## Brings new townsfolk into the District during a Round (M5, Escalation).
## Every `interval()` seconds (9 s when calm, down to 1.5 s from Vigilance 2)
## it picks a type from the Year's YearEntry, weighted by
## base_weight * (1 + vigilance * tier) so Vigilance favours the strong types,
## and spawns it at a gate (an open street end at the District bounds) or out
## of the door of a living house; never within LEAD_CLEARANCE of the Lead Rat
## and never while CAP outdoor townsfolk are alive. Types with look "cat"
## spawn scenes/game/cat.tscn instead (at most MAX_CATS alive).
## Vigilance is read from the RoundDirector; the YearTable from
## res://data/year_table.tres ("plain only" when either is missing).
## The District also asks it for the look of its starting population
## (resident_def(): a Year type for RESIDENT_TYPE_CHANCE of them).
## The YearEntry is looked up for Run.current_district (M6).
##
## Exterminator (M6): the first time the RoundDirector's district_infection()
## reaches EXTERMINATOR_AT, the District's Exterminator (DistrictDef) is
## instanced at the gate farthest from the Lead Rat, once per Round.
## --force-exterminator brings it in after FORCE_EXTERMINATOR_AFTER s instead.
class_name Spawner
extends Node3D

const YEAR_TABLE := "res://data/year_table.tres"
const CAT_SCENE := "res://scenes/game/cat.tscn"
## Alive outdoor townsfolk above which nobody new spawns.
const CAP := 45
## Cats are not townsfolk; keep their number small on their own.
const MAX_CATS := 4
const LEAD_CLEARANCE := 6.0
const INTERVAL_CALM := 9.0
const INTERVAL_HUNTING := 1.5
## Vigilance at which the interval bottoms out.
const INTERVAL_FULL_AT := 2.0
## Share of the starting population that gets a Year type (the rest plain).
const RESIDENT_TYPE_CHANCE := 0.3
## Chance a spawn comes in at a gate rather than out of a house door.
const GATE_CHANCE := 0.5
## District Infection (0..1) at which the Exterminator arrives.
const EXTERMINATOR_AT := 0.5
const FORCE_EXTERMINATOR_AFTER := 3.0

signal exterminator_arrived(exterminator: Node3D)

## Set by the District before add_child.
var district: Node3D
var person_scene: PackedScene
var container: Node3D
## Counts of everything spawned this Round, by type id ("plain" without data).
var counts := {}
var spawned := 0
## The Exterminator once it has arrived (stays set after it is beaten).
var exterminator: Node3D

var _exterminator_done := false
var _force_exterminator := -1.0  # s left with --force-exterminator, else < 0
var _arrived_at := 0.0           # _elapsed when the Exterminator arrived

var _table: Resource            # YearTable, or null
var _entry: Resource            # YearEntry for Run.year, or null
var _cat_scene: PackedScene
var _gates: Array[Vector3] = []
var _left := 0.0
var _elapsed := 0.0
var _rng := RandomNumberGenerator.new()
var _seed_next := 5000
var _director: Node
var _lead: Node3D
var _cats: Array[Node3D] = []


func _ready() -> void:
	_rng.seed = 77 + Run.year
	load_year()
	_left = interval()
	if OS.get_cmdline_user_args().has("--force-exterminator"):
		_force_exterminator = FORCE_EXTERMINATOR_AFTER


## Loads the YearTable and picks this Year's entry (safe to call again).
func load_year() -> void:
	_table = null
	_entry = null
	if ResourceLoader.exists(YEAR_TABLE):
		_table = load(YEAR_TABLE)
		if _table and _table.has_method("entry_for"):
			# entry_for(year, district_id) from M6 on; older tables take the Year only.
			if _table.get_method_argument_count("entry_for") >= 2:
				_entry = _table.call("entry_for", Run.year, Run.current_district) as Resource
			else:
				_entry = _table.call("entry_for", Run.year) as Resource
	if ResourceLoader.exists(CAT_SCENE):
		_cat_scene = load(CAT_SCENE) as PackedScene


## Positions of the Marker3D children (the gates placed in district.tscn).
func marker_gates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c: Node in get_children():
		if c is Marker3D:
			out.append((c as Marker3D).global_position)
	return out


## Sets the gates; only spots the District says are free are kept.
func set_gates(points: Array[Vector3]) -> void:
	_gates.clear()
	for p in points:
		if district == null or district.call("is_free", p, 0.5):
			_gates.append(p)


func gates() -> Array[Vector3]:
	return _gates


func year_entry() -> Resource:
	return _entry


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_check_exterminator(delta)
	_left -= delta
	if _left > 0.0:
		return
	_left = interval()
	spawn_one()


## Current Vigilance: the RoundDirector's, else the contract formula from the
## time this spawner has been running.
func vigilance() -> float:
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("round_director")
	if _director:
		var v: Variant = _director.get("vigilance")
		if v is float:
			return v
	var start := float(_entry.get("start_vigilance")) if _entry else 0.0
	return start + _elapsed / 60.0 * (1.0 + 0.1 * (Run.year - Run.START_YEAR))


## Seconds until the next spawn at the current Vigilance.
func interval() -> float:
	return lerpf(INTERVAL_CALM, INTERVAL_HUNTING, clampf(vigilance() / INTERVAL_FULL_AT, 0.0, 1.0))


## A type picked from the Year's types: weight base_weight * (1 + v * tier).
## `no_cats` leaves out the cat type. Null when there is no data (plain).
func pick_def(v: float, no_cats := false) -> Resource:
	if _entry == null:
		return null
	var types: Array = _entry.get("types")
	var total := 0.0
	var weights: Array[float] = []
	for t: Resource in types:
		var w := 0.0
		if t and not (no_cats and _is_cat(t)):
			w = maxf(0.0, float(t.get("base_weight")) * (1.0 + v * float(t.get("tier"))))
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for i in types.size():
		roll -= weights[i]
		if roll <= 0.0 and weights[i] > 0.0:
			return types[i]
	return types[types.size() - 1]


## For the starting population: a Year type (never a cat) for 30% of them,
## else null (the person keeps its plain M1 look).
func resident_def(rng: RandomNumberGenerator) -> Resource:
	if _entry == null or rng.randf() >= RESIDENT_TYPE_CHANCE:
		return null
	return pick_def(vigilance(), true)


## Calls person.setup(def, entry) when both the method and the data exist.
func apply_def(person: Node, def: Resource) -> void:
	if def and _entry and person.has_method("setup"):
		person.call("setup", def, _entry)


# ---------------------------------------------------------------------- exterminator
## District Infection from the RoundDirector (0 without one).
func district_infection() -> float:
	vigilance()  # finds the director
	if _director and _director.has_method("district_infection"):
		return float(_director.call("district_infection"))
	return 0.0


func _check_exterminator(delta: float) -> void:
	if _exterminator_done:
		return
	if _force_exterminator >= 0.0:
		_force_exterminator -= delta
		if _force_exterminator < 0.0:
			spawn_exterminator()
		return
	if district_infection() >= EXTERMINATOR_AT:
		spawn_exterminator()


## Brings in the District's Exterminator at the gate farthest from the Lead
## Rat (once per Round). Returns it, or null when there is no scene.
func spawn_exterminator() -> Node3D:
	if _exterminator_done:
		return exterminator
	_exterminator_done = true
	var def: DistrictDef = district.get("district_def") as DistrictDef if district else null
	var scene := def.exterminator_packed() if def else null
	if scene == null:
		push_warning("Spawner: no Exterminator scene for District '%s'" % (def.id if def else "?"))
		return null
	var gate := farthest_gate()
	var ext := scene.instantiate() as Node3D
	ext.add_to_group("exterminator")
	ext.position = gate
	# Face into the District.
	var c: Vector2 = (district.get("bounds") as Rect2).get_center() if district else Vector2.ZERO
	ext.rotation.y = atan2(c.x - gate.x, c.y - gate.z)
	var parent: Node = container if container else (district if district else get_parent())
	parent.add_child(ext)
	exterminator = ext
	_arrived_at = _elapsed
	print("spawner: exterminator %s arrived at (%.1f, %.1f) after %.1f s, district_infection=%.2f" % [
		ext.name, gate.x, gate.z, _elapsed, district_infection()])
	if ext.has_signal("beaten"):
		ext.connect("beaten", _on_exterminator_beaten)
	exterminator_arrived.emit(ext)
	return ext


func _on_exterminator_beaten() -> void:
	var colony := get_tree().get_first_node_in_group("colony")
	print("spawner: exterminator beaten %.1f s after it arrived; colony adults=%s pups=%s (rats out %d)" % [
		_elapsed - _arrived_at, colony.get("adult_count") if colony else "?", colony.get("pup_count") if colony else "?",
		get_tree().get_nodes_in_group("rats").size()])


## The gate farthest from the Lead Rat (the first gate without a Lead Rat).
func farthest_gate() -> Vector3:
	if _lead == null or not is_instance_valid(_lead):
		_lead = get_tree().get_first_node_in_group("lead_rat") as Node3D
	if _gates.is_empty():
		return Vector3.ZERO
	if _lead == null:
		return _gates[0]
	var best := _gates[0]
	var best_d := -1.0
	for g in _gates:
		var d := _flat_dist(g, _lead.global_position)
		if d > best_d:
			best_d = d
			best = g
	return best


# ---------------------------------------------------------------------- spawning
## Spawns one person (or cat) now if the cap allows. Returns it, or null.
func spawn_one() -> Node3D:
	var def := pick_def(vigilance())
	if def and _is_cat(def):
		_cats.assign(_cats.filter(func(c: Variant) -> bool: return is_instance_valid(c)))
		if _cat_scene == null or _cats.size() >= MAX_CATS:
			def = pick_def(vigilance(), true)
		else:
			return _spawn_cat(def)
	if person_scene == null or container == null or alive_outdoors() >= CAP:
		return null
	var spot := _pick_spot()
	if spot.is_empty():
		return null
	var p: Vector3 = spot["pos"]
	var house: House = spot["house"]
	var person := person_scene.instantiate() as Node3D
	var half: float = float(district.get("wander_size")) * 0.5 if district else 7.0
	var b: Rect2 = district.get("bounds") if district else Rect2(-22, -22, 44, 44)
	person.set("wander_bounds", Rect2(p.x - half, p.z - half, half * 2.0, half * 2.0).intersection(b.grow(-1.0)))
	person.set("rng_seed", _seed_next)
	_seed_next += 1
	person.position = p
	var home: House = house if house else (district.call("nearest_house", p) as House if district else null)
	person.set("home", home)
	apply_def(person, def)
	container.add_child(person)
	if home and not home.is_dead_house():
		home.add_resident(person)
	if house:
		var n := house.door_normal
		person.rotation.y = atan2(n.x, n.z)
	_count(def)
	return person


func _spawn_cat(def: Resource) -> Node3D:
	var spot := _pick_spot()
	if spot.is_empty() or container == null:
		return null
	var cat := _cat_scene.instantiate() as Node3D
	cat.position = spot["pos"]
	apply_def(cat, def)
	container.add_child(cat)
	_cats.append(cat)
	_count(def)
	return cat


func _count(def: Resource) -> void:
	var id := str(def.get("id")) if def else "plain"
	counts[id] = int(counts.get(id, 0)) + 1
	spawned += 1


static func _is_cat(def: Resource) -> bool:
	return str(def.get("look")) == "cat"


## Outdoor townsfolk still alive (group "townsfolk" holds only the outdoor
## ones), the Exterminator and its terrier ("exterminator_pets") left out.
func alive_outdoors() -> int:
	var n := 0
	for t: Node in get_tree().get_nodes_in_group("townsfolk"):
		if t.is_in_group("exterminator") or t.is_in_group("exterminator_pets") or t.is_in_group("terrier"):
			continue
		if not (t.has_method("is_dead") and t.call("is_dead")):
			n += 1
	return n


## {"pos": Vector3, "house": House or null}: a gate or a living house's door
## step, at least LEAD_CLEARANCE from the Lead Rat; {} if there is none.
func _pick_spot() -> Dictionary:
	if _lead == null or not is_instance_valid(_lead):
		_lead = get_tree().get_first_node_in_group("lead_rat") as Node3D
	var lead_p := _lead.global_position if _lead else Vector3(INF, 0, INF)
	var gate_ok: Array[Vector3] = []
	for g in _gates:
		if _flat_dist(g, lead_p) >= LEAD_CLEARANCE:
			gate_ok.append(g)
	var doors: Array[House] = []
	for n: Node in get_tree().get_nodes_in_group("houses"):
		var h := n as House
		if h == null or h.is_dead_house():
			continue
		if _flat_dist(h.door_position + h.door_normal * 0.8, lead_p) >= LEAD_CLEARANCE:
			doors.append(h)
	var use_gate := not gate_ok.is_empty() and (doors.is_empty() or _rng.randf() < GATE_CHANCE)
	if use_gate:
		var g := gate_ok[_rng.randi() % gate_ok.size()]
		var side := Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
		var p := g + side
		if district and not district.call("is_free", p, 0.5):
			p = g
		return {"pos": p, "house": null}
	if doors.is_empty():
		return {}
	var h := doors[_rng.randi() % doors.size()]
	return {"pos": h.door_position + h.door_normal * 0.8, "house": h}


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## "plain=12 broom=4 ..." for debug output.
func counts_text() -> String:
	var parts: Array[String] = []
	var keys := counts.keys()
	keys.sort()
	for k: Variant in keys:
		parts.append("%s=%d" % [k, counts[k]])
	return "spawner: year=%d vigilance=%.2f interval=%.2fs gates=%d spawned=%d alive_outdoors=%d [%s]%s" % [
		Run.year, vigilance(), interval(), _gates.size(), spawned, alive_outdoors(), " ".join(parts),
		exterminator_text()]


## " exterminator=<Infection>% lead_dist=<u> rats_in_reach=<n>" while one is
## in the District, else "" (debug output, boss tuning).
func exterminator_text() -> String:
	if exterminator == null or not is_instance_valid(exterminator):
		return ""
	var inf := exterminator.get_node_or_null("Infection") as InfectionComponent
	var p := exterminator.global_position
	var near := 0
	for r: Node in get_tree().get_nodes_in_group("rats"):
		if r is Node3D and _flat_dist((r as Node3D).global_position, p) <= 1.6:
			near += 1
	var lead_d := _flat_dist(_lead.global_position, p) if _lead and is_instance_valid(_lead) else -1.0
	return " exterminator=%.0f%%%s lead_dist=%.1f rats_in_reach=%d/%d" % [
		inf.value if inf else -1.0, " (dead)" if inf and inf.is_dead() else "", lead_d, near,
		get_tree().get_nodes_in_group("rats").size()]
