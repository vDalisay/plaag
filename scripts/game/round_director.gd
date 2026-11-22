## Runs one Round: counts down the timer, keeps the District's plague tally and
## pays the currencies (Pestilence on a first infection, Bones on a death).
## When the Round ends it pauses the world; the director itself keeps running.
## The Round ends on the timer or when the Lead Rat (group "lead_rat") dies.
## At the end it builds `result` for Run.finish_round():
## {pestilence, bones, reason ("timer" | "lead_rat_died" | "exterminator_beaten"),
## colony_size, dead_houses (the `index` of every dead house in "houses")}.
## M6: Exterminators (group "exterminator") and the terrier (group "terrier")
## are never counted in population, Pestilence or Bones. When an Exterminator
## emits `beaten`, the director pays EXTERMINATOR_BONES and ends the Round
## with "exterminator_beaten".
## Vigilance (M5): the in-Round difficulty the Spawner reads. It starts at the
## Year's start_vigilance and rises by (1 + 0.1 * (Year - 1347)) per minute.
class_name RoundDirector
extends Node

signal stats_changed
signal round_ended(reason: String)       # "timer", "lead_rat_died" or "exterminator_beaten"
signal vigilance_changed(v: float)

const YEAR_TABLE := "res://data/year_table.tres"
const START_YEAR := 1347
## Bones paid for beating the District's Exterminator.
const EXTERMINATOR_BONES := 10

@export var round_length := 90.0

var time_left: float
var pestilence := 0     # +1 per townsperson on first infection
var bones := 0          # +1 per death
var population := 0     # townsfolk registered this Round (indoors and outdoors)
var infected_count := 0 # currently infected (alive)
var dead_count := 0     # dead anywhere, hidden indoor corpses included
var end_reason := ""    # set when the Round ends
var result := {}        # for Run.finish_round(); set when the Round ends
var vigilance := 0.0    # start_vigilance at Round start, rises over the Round (uncapped)
var elapsed := 0.0      # s of the Round played
var start_vigilance := 0.0

var _registered := {}   # instance id -> true
var _ended := false
var _vigilance_sent := -1.0


func _ready() -> void:
	add_to_group("round_director")
	process_mode = Node.PROCESS_MODE_ALWAYS
	time_left = round_length
	start_vigilance = _year_start_vigilance()
	vigilance = start_vigilance
	get_tree().node_added.connect(_on_node_added)
	_register_existing.call_deferred()


func _process(delta: float) -> void:
	if _ended or get_tree().paused:
		return
	time_left = maxf(0.0, time_left - delta)
	elapsed += delta
	vigilance = vigilance_at(elapsed)
	if absf(vigilance - _vigilance_sent) >= 0.005:
		_vigilance_sent = vigilance
		vigilance_changed.emit(vigilance)
	if time_left <= 0.0:
		end_round("timer")


## Vigilance after `t` seconds of this Round in the current Year.
func vigilance_at(t: float) -> float:
	return start_vigilance + t / 60.0 * (1.0 + 0.1 * float(year() - START_YEAR))


## Run.year, or 1347 without the Run autoload.
func year() -> int:
	var run := get_node_or_null("/root/Run")
	var y: Variant = run.get("year") if run != null else null
	return int(y) if (y is int or y is float) else START_YEAR


## The Year's start_vigilance from the YearTable (0 if anything is missing).
func _year_start_vigilance() -> float:
	if not ResourceLoader.exists(YEAR_TABLE):
		return 0.0
	var table := load(YEAR_TABLE) as YearTable
	var e := table.entry_for(year(), district_id()) if table != null else null
	return e.start_vigilance if e != null else 0.0


## Run.current_district, or "slums" without the Run autoload (or the field).
func district_id() -> String:
	var run := get_node_or_null("/root/Run")
	var d: Variant = run.get("current_district") if run != null else null
	return d if d is String and d != "" else "slums"


## Share of the registered population that is infected or dead, 0..1.
func district_infection() -> float:
	if population <= 0:
		return 0.0
	return float(infected_count + dead_count) / float(population)


func has_ended() -> bool:
	return _ended


## Ends the Round once: emits round_ended and pauses the world.
func end_round(reason: String) -> void:
	if _ended:
		return
	_ended = true
	end_reason = reason
	result = {
		"pestilence": pestilence,
		"bones": bones,
		"reason": reason,
		"colony_size": 0 if reason == "lead_rat_died" else _colony_size(),
		"dead_houses": dead_houses(),
	}
	round_ended.emit(reason)
	get_tree().paused = true


## The `index` of every house in "houses" whose residents are all dead.
func dead_houses() -> Array[int]:
	var out: Array[int] = []
	for h: Node in get_tree().get_nodes_in_group("houses"):
		if not h.has_method("is_dead_house") or not h.call("is_dead_house"):
			continue
		var i: Variant = h.get("index")
		if i is int and not out.has(i):
			out.append(i)
	out.sort()
	return out


## True for the nodes the director never counts: the Exterminators and the terrier.
static func is_uncounted(n: Node) -> bool:
	return n is Exterminator or n.is_in_group("exterminator") or n.is_in_group("terrier")


## Adults (Lead Rat included) + Pups of the Colony (group "colony"), or 0.
func _colony_size() -> int:
	var colony := get_tree().get_first_node_in_group("colony")
	if colony == null:
		return 0
	var adults: Variant = colony.get("adult_count")
	var pups: Variant = colony.get("pup_count")
	return (adults as int if adults is int else 0) + (pups as int if pups is int else 0)


func register_townsperson(t: Node3D) -> void:
	if t == null or not is_instance_valid(t):
		return
	var id := t.get_instance_id()
	if _registered.has(id):
		return
	if is_uncounted(t):
		_watch_exterminator(t)
		return
	var inf := t.get_node_or_null("Infection") as InfectionComponent
	if inf == null:
		return
	_registered[id] = true
	population += 1
	# Someone registered late may already be sick or dead.
	if inf.is_dead():
		pestilence += 1
		bones += 1
		dead_count += 1
	elif inf.is_infected():
		pestilence += 1
		infected_count += 1
	inf.infected.connect(_on_infected)
	inf.died.connect(_on_died)
	stats_changed.emit()


## Everyone already in the District, outdoors or indoors (corpses too, so a
## late director still counts the dead).
func _register_existing() -> void:
	for g: String in ["townsfolk", "indoors", "corpses"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is Node3D:
				register_townsperson(n as Node3D)
	for n: Node in get_tree().get_nodes_in_group("lead_rat"):
		_watch_lead_rat(n)
	for n: Node in get_tree().get_nodes_in_group("exterminator"):
		_watch_exterminator(n)


## Ends the Round with "exterminator_beaten" when this Exterminator emits `beaten`.
func _watch_exterminator(n: Node) -> void:
	if n == null or not is_instance_valid(n) or not n.has_signal("beaten"):
		return
	if not n.is_connected("beaten", _on_exterminator_beaten):
		n.connect("beaten", _on_exterminator_beaten)


func _on_exterminator_beaten() -> void:
	if _ended:
		return
	bones += EXTERMINATOR_BONES
	stats_changed.emit()
	end_round("exterminator_beaten")


## Ends the Round with "lead_rat_died" when this Lead Rat emits `died`.
func _watch_lead_rat(n: Node) -> void:
	if n == null or not is_instance_valid(n) or not n.is_in_group("lead_rat") or not n.has_signal("died"):
		return
	if not n.is_connected("died", _on_lead_rat_died):
		n.connect("died", _on_lead_rat_died)


func _on_lead_rat_died() -> void:
	end_round("lead_rat_died")


func _on_node_added(n: Node) -> void:
	if n is Node3D and (n is Townsperson or n is Exterminator or n is Terrier or n.is_in_group("townsfolk") 			or n.is_in_group("indoors")):
		# Deferred so the node's children (the Infection) are in place.
		register_townsperson.call_deferred(n)
	# The Lead Rat joins its group in its own _ready, after node_added: check
	# later, by id in case the node is gone by then.
	if n is Node3D:
		_watch_lead_rat_id.call_deferred(n.get_instance_id())


func _watch_lead_rat_id(id: int) -> void:
	_watch_lead_rat(instance_from_id(id) as Node)


func _on_infected() -> void:
	pestilence += 1
	infected_count += 1
	stats_changed.emit()


func _on_died() -> void:
	bones += 1
	dead_count += 1
	infected_count = maxi(0, infected_count - 1)
	stats_changed.emit()
