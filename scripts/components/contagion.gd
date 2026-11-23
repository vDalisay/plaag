## Contagion (M7, behind the "unlock_contagion" upgrade): townsfolk pass the
## plague to each other. Every `interval` s each infected, living, outdoor
## townsperson rolls `chance` for each living, uninfected, outdoor townsperson
## within `radius` (ground plane); a success calls Infection.bite(BITE_CHUNK,
## BITE_RATE) on them. Exterminators (and their terrier) never catch or spread
## it. Neighbours are found through a coarse grid (cell = radius) rebuilt on
## each roll, so a roll costs about O(people). Each success shows a red cough
## cloud drifting from the sick person's mouth to the one who caught it (the
## pooled Vfx "contagion" burst, scripts/vfx/vfx.gd).
## One Contagion per scene: Townsperson calls ensure_for(self) when it enters
## the tree, which adds it next to the current scene's root when the Run has
## Contagion unlocked (or --dev). Tests may add one by hand and set `forced`.
class_name Contagion
extends Node3D

const Vfx := preload("res://scripts/vfx/vfx.gd")

const BITE_CHUNK := 1.0
const BITE_RATE := 0.1
const DEFAULT_RADIUS := 1.8
const DEFAULT_CHANCE := 0.10
const DEFAULT_INTERVAL := 1.5
## Mouth / chest heights of the cough cloud.
const MOUTH_HEIGHT := 2.0
const CHEST_HEIGHT := 1.4
## Cough clouds started per roll at most.
const MAX_LINES := 24
## Groups that never catch or spread Contagion.
const IMMUNE_GROUPS: Array[StringName] = [&"exterminator", &"terrier", &"exterminator_pets"]

static var _instance: Contagion

var radius := DEFAULT_RADIUS
var chance := DEFAULT_CHANCE
var interval := DEFAULT_INTERVAL
## True = spread even when the Run has it locked (tests).
var forced := false
## Townsfolk infected by Contagion this Round (debug output).
var hits := 0
var rng := RandomNumberGenerator.new()

var _left := 0.0
## Cough clouds started on the last roll (tests).
var _clouds := 0


## Adds the scene's Contagion if `person`'s Run has it unlocked and there is
## none yet. Safe to call for everyone; a no-op when locked.
static func ensure_for(person: Node) -> void:
	if is_instance_valid(_instance):
		return   # in the tree, or about to be added
	if not person.is_inside_tree() or not is_enabled(person.get_tree()):
		return
	var tree := person.get_tree()
	var host: Node = tree.current_scene
	if host == null or not host.is_ancestor_of(person):
		host = person.get_parent()
	var c := Contagion.new()
	_instance = c
	host.add_child.call_deferred(c)


## Run.is_unlocked("unlock_contagion") (which includes --dev); false without a Run.
static func is_enabled(tree: SceneTree) -> bool:
	var run := tree.root.get_node_or_null("Run")
	return run != null and run.has_method("is_unlocked") and bool(run.call("is_unlocked", "unlock_contagion"))


func _ready() -> void:
	name = "Contagion"
	add_to_group("contagion")
	if not is_instance_valid(_instance):
		_instance = self
	rng.randomize()
	var run := get_node_or_null("/root/Run")
	if run != null and run.has_method("stat"):
		radius = _stat_or(run, "contagion_radius", DEFAULT_RADIUS)
		chance = _stat_or(run, "contagion_chance", DEFAULT_CHANCE)
		interval = _stat_or(run, "contagion_interval", DEFAULT_INTERVAL)
	_left = interval


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Run.stat(key), or `fallback` when the Run doesn't know the stat (0).
static func _stat_or(run: Node, key: String, fallback: float) -> float:
	var v := float(run.call("stat", key))
	return v if v > 0.0 else fallback


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left += maxf(interval, 0.05)
		if forced or is_enabled(get_tree()):
			tick()


## One round of rolls; returns how many townsfolk caught it.
func tick() -> int:
	var cell := maxf(radius, 0.5)
	var grid := {}                       # Vector2i -> Array[int] (healthy people)
	var people: Array[Node3D] = []
	var infs: Array[InfectionComponent] = []
	var sick: Array[int] = []
	for n: Node in get_tree().get_nodes_in_group("townsfolk"):
		var p := n as Node3D
		if p == null or not _can_take_part(p):
			continue
		var inf := p.get_node_or_null("Infection") as InfectionComponent
		if inf == null or inf.is_dead():
			continue
		var i := people.size()
		people.append(p)
		infs.append(inf)
		if inf.is_infected():
			sick.append(i)
		else:
			var key := Vector2i(floori(p.global_position.x / cell), floori(p.global_position.z / cell))
			if grid.has(key):
				(grid[key] as Array).append(i)
			else:
				grid[key] = [i]
	if sick.is_empty() or grid.is_empty():
		return 0
	var r2 := radius * radius
	var n_hit := 0
	_clouds = 0
	for s in sick:
		var sp := people[s].global_position
		var kx := floori(sp.x / cell)
		var kz := floori(sp.z / cell)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var bucket: Variant = grid.get(Vector2i(kx + dx, kz + dz))
				if bucket == null:
					continue
				for j: int in bucket:
					var tp := people[j].global_position
					var ddx := tp.x - sp.x
					var ddz := tp.z - sp.z
					if ddx * ddx + ddz * ddz > r2 or infs[j].is_infected() or infs[j].is_dead():
						continue
					if rng.randf() < chance:
						infs[j].bite(BITE_CHUNK, BITE_RATE)
						n_hit += 1
						if _clouds < MAX_LINES:
							_clouds += 1
							var mouth := sp + Vector3(0, MOUTH_HEIGHT, 0)
							Vfx.play(get_tree(), &"contagion", mouth, tp + Vector3(0, CHEST_HEIGHT, 0) - mouth)
	hits += n_hit
	return n_hit


## Outdoors, alive and not an Exterminator (or its pet).
static func _can_take_part(p: Node3D) -> bool:
	if not p.is_inside_tree():
		return false
	for g in IMMUNE_GROUPS:
		if p.is_in_group(g):
			return false
	# Exterminators and pets have no is_indoors; get() returns null for them.
	if p.get("is_indoors") == true or p.is_in_group("indoors"):
		return false
	if p.has_method("is_dead") and p.call("is_dead") == true:
		return false
	return true


## Cough clouds started on the last roll (tests).
func line_count() -> int:
	return _clouds
