## The Run (autoload `Run`): everything that lasts between Rounds. Holds the
## wallet (Pestilence, Bones), the Year, the bought Upgrade Tree levels and the
## last Round's Colony size; turns those into gameplay stats (stat()), and
## saves to a ConfigFile after every change.
## Command-line user args (after `--`): --fresh wipes the save on boot, --dev
## turns on developer shortcuts (dev_mode; the HUD's R restart), --year=<n>
## plays this session in Year n; the save keeps its own Year. --district=<id>
## plays this session in that District (locked or not); the save keeps its own.
## Districts (M6): data/districts/*.tres, the one being played, the beaten ones
## and the most dead houses seen per District (for the M7 Scroll Map).
## M7: open_map() goes to the Scroll Map; each District stores its house
## layout (store_layout / layout_of) so the map can draw it. --dev also turns
## on Fleas and Contagion.
extends Node

signal wallet_changed
signal upgrades_changed

const SAVE_PATH := "user://plaag_run.cfg"
const START_YEAR := 1347
const UPGRADES_DIR := "res://data/upgrades/"
const DISTRICTS_DIR := "res://data/districts/"
const START_DISTRICT := "slums"
const DISTRICT_SCENE := "res://scenes/game/district.tscn"
const TREE_SCENE := "res://scenes/ui/upgrade_tree.tscn"
const MAP_SCENE := "res://scenes/ui/scroll_map.tscn"
const BASE_STATS := {
	"rat_speed": 6.0, "bite_range": 1.6, "bite_cooldown": 1.2, "bite_chunk": 3.0,
	"bite_rate_bonus": 0.5, "start_adults": 0.0, "feed_time": 1.5, "pup_maturity": 15.0,
	"lethality": 1.0,          # multiplies every townsperson's Infection base_rate
	"carry_over": 0.0,         # 0..1 share of last Round's final Colony size
	"round_length": 90.0,
	"unlock_hide": 0.0, "unlock_raid": 0.0, "unlock_fleas": 0.0, "unlock_contagion": 0.0,
	"hide_duration": 6.0,      # s the Colony stays hidden in a house (half if nobody is inside)
	"hide_cooldown": 3.0,      # s after leaving before Hide works again
	"raid_size": 3.0,          # follower Adults sent on a Raid
	"raid_duration": 4.0,      # s the raiders Bite inside
	"raid_cooldown": 10.0,     # s between Raids
	"flea_radius": 2.0,        # u: Fleas reach townsfolk this close to an Adult (M7)
	"flea_chance": 0.15,       # per Adult, per townsperson in reach, per roll
	"flea_interval": 1.0,      # s between Flea rolls
	"contagion_radius": 1.8,   # u: an infected townsperson spreads it this far (M7)
	"contagion_chance": 0.10,  # per infected, per healthy neighbour, per roll
	"contagion_interval": 1.5, # s between Contagion rolls
}

var year := START_YEAR
var pestilence := 0             # wallet
var bones := 0                  # wallet
var levels := {}                # upgrade id (String) -> bought level (int)
var last_colony_size := 0       # Adults + Pups alive when the last Round ended
var rounds_played := 0
## District id being played (see district_defs()).
var current_district := START_DISTRICT
## District id -> true once its Exterminator has been beaten.
var beaten := {}
## District id -> Array[int]: the house indices of the Round with the most
## dead houses there (House.index, stable per layout).
var best_dead_houses := {}
## District id -> Array of {index: int, center: Vector2, size: Vector2,
## rot: float}: the house footprints of its layout (see store_layout()).
var layouts := {}
## Where the Run is saved; tests point this somewhere else.
var save_path := SAVE_PATH
## True with --dev (developer shortcuts such as R to restart a Round).
var dev_mode := false
## The Year the save holds while --year overrides `year` (-1 = no override).
var _saved_year := -1
## The District the save holds while --district overrides it ("" = no override).
var _saved_district := ""

var _nodes: Array[UpgradeNodeDef] = []
var _nodes_loaded := false
var _districts: Array[DistrictDef] = []
var _districts_loaded := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	dev_mode = args.has("--dev")
	if args.has("--fresh"):
		reset()
	else:
		load_run()
	for arg in args:
		if arg.begins_with("--year="):
			_saved_year = year
			year = int(arg.trim_prefix("--year="))
		elif arg.begins_with("--district="):
			var id := arg.trim_prefix("--district=")
			if district_def(id) == null:
				push_warning("Run: unknown District '%s'" % id)
			else:
				_saved_district = current_district
				current_district = id


# ---------------------------------------------------------------------- stats
## BASE_STATS[key] plus every owned node's effect (delta per level). A node
## with `level_stat == key` replaces the base with level_values[level - 1].
func stat(key: String) -> float:
	var value: float = BASE_STATS.get(key, 0.0)
	var absolute := -INF
	var delta := 0.0
	for node in all_nodes():
		var lv := level(node.id)
		if lv <= 0:
			continue
		if node.level_stat == key and not node.level_values.is_empty():
			absolute = maxf(absolute, node.level_values[mini(lv, node.level_values.size()) - 1])
		if node.effects.has(key):
			delta += float(node.effects[key]) * lv
	if absolute > -INF:
		value = absolute
	return value + delta


func level(id: String) -> int:
	return int(levels.get(id, 0))


## Unlock stats read as on/off (M4 Hide/Raid, M7 Fleas/Contagion).
## --dev unlocks Hide, Raid, Fleas and Contagion.
func is_unlocked(key: String) -> bool:
	if dev_mode and key in ["unlock_hide", "unlock_raid", "unlock_fleas", "unlock_contagion"]:
		return true
	return stat(key) >= 1.0


## Colony size at the start of the next Round:
## start_adults + floor(carry_over * last_colony_size).
func start_colony_size() -> int:
	return int(floor(stat("start_adults"))) + int(floor(stat("carry_over") * last_colony_size + 0.0001))


# ---------------------------------------------------------------------- buying
## (pestilence, bones) for the NEXT level; each level after the first costs
## the previous one times cost_growth, rounded up. Zero once maxed.
func cost_of(node: UpgradeNodeDef) -> Vector2i:
	var lv := level(node.id)
	if lv >= node.max_level:
		return Vector2i.ZERO
	var p := node.cost_pestilence
	var b := node.cost_bones
	for i in lv:
		p = _grow(p, node.cost_growth)
		b = _grow(b, node.cost_growth)
	return Vector2i(p, b)


static func _grow(cost: int, growth: float) -> int:
	# The small epsilon keeps 10 * 1.6 from rounding up to 17.
	return ceili(cost * growth - 0.0001)


## Every `requires` id has level >= 1.
func is_visible(node: UpgradeNodeDef) -> bool:
	for id in node.requires:
		if level(id) < 1:
			return false
	return true


func can_buy(node: UpgradeNodeDef) -> bool:
	if not is_visible(node) or level(node.id) >= node.max_level:
		return false
	var c := cost_of(node)
	return pestilence >= c.x and bones >= c.y


## Spends both currencies, levels the node up, saves and emits.
func buy(node: UpgradeNodeDef) -> bool:
	if not can_buy(node):
		return false
	var c := cost_of(node)
	pestilence -= c.x
	bones -= c.y
	levels[node.id] = level(node.id) + 1
	save_run()
	wallet_changed.emit()
	upgrades_changed.emit()
	return true


# ---------------------------------------------------------------------- rounds
## result: {pestilence: int, bones: int, reason: "timer" | "lead_rat_died" |
## "exterminator_beaten", colony_size: int, dead_houses: Array[int]}. Adds the
## earnings and records the dead houses; the Year advances only when the Lead
## Rat died. "exterminator_beaten" beats the current District (and moves on
## to the next open one, see beat_district()).
func finish_round(result: Dictionary) -> void:
	pestilence += int(result.get("pestilence", 0))
	bones += int(result.get("bones", 0))
	var reason := str(result.get("reason", ""))
	if reason == "lead_rat_died":
		year += 1
	var dead: Variant = result.get("dead_houses")
	if dead is Array:
		var ids: Array[int] = []
		for i: Variant in dead:
			ids.append(int(i))
		_record_dead_houses(current_district, ids)
	if reason == "exterminator_beaten":
		_beat(current_district)
	last_colony_size = maxi(0, int(result.get("colony_size", 0)))
	rounds_played += 1
	save_run()
	wallet_changed.emit()


func start_round() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(DISTRICT_SCENE)


## The Scroll Map, where the player picks the next District (falls back to
## start_round() while the map scene does not exist).
func open_map() -> void:
	get_tree().paused = false
	if not ResourceLoader.exists(MAP_SCENE):
		push_warning("Run: %s missing, starting the next Round instead" % MAP_SCENE)
		start_round()
		return
	get_tree().change_scene_to_file(MAP_SCENE)


func open_tree() -> void:
	get_tree().paused = false
	if not ResourceLoader.exists(TREE_SCENE):
		push_warning("Run: %s missing, starting the next Round instead" % TREE_SCENE)
		start_round()
		return
	get_tree().change_scene_to_file(TREE_SCENE)


# ---------------------------------------------------------------------- districts
## Every res://data/districts/*.tres, loaded once, in unlock order: a District
## comes after the one it requires (then by file name).
func district_defs() -> Array[DistrictDef]:
	if not _districts_loaded:
		_districts_loaded = true
		_districts = _load_districts(DISTRICTS_DIR)
	return _districts


## The District with this id, or null.
func district_def(id: String) -> DistrictDef:
	for d in district_defs():
		if d.id == id:
			return d
	return null


## The District being played (null only without any district data).
func current_district_def() -> DistrictDef:
	var d := district_def(current_district)
	if d == null and not district_defs().is_empty():
		d = district_defs()[0]
	return d


## Known, and either needs nothing or the District it requires is beaten.
func is_district_open(id: String) -> bool:
	var d := district_def(id)
	if d == null:
		return false
	return d.requires.is_empty() or beaten.has(d.requires)


func is_district_beaten(id: String) -> bool:
	return beaten.has(id)


## Marks the District beaten; when it is the one being played, switches to
## the first open District not yet beaten (M7's Scroll Map will let the
## player choose). Saves.
func beat_district(id: String) -> void:
	_beat(id)
	save_run()


func _beat(id: String) -> void:
	beaten[id] = true
	if id != current_district:
		return
	for d in district_defs():
		if is_district_open(d.id) and not beaten.has(d.id):
			current_district = d.id
			_saved_district = ""   # the switch outlasts a --district override
			return


## Keeps the Round with the most dead houses in this District. Saves.
func record_dead_houses(district_id: String, house_indices: Array[int]) -> void:
	_record_dead_houses(district_id, house_indices)
	save_run()


func _record_dead_houses(district_id: String, house_indices: Array[int]) -> void:
	var best: Array = best_dead_houses.get(district_id, [])
	if best_dead_houses.has(district_id) and house_indices.size() <= best.size():
		return
	var copy: Array[int] = house_indices.duplicate()
	copy.sort()
	best_dead_houses[district_id] = copy


## Remembers a District's house layout for the Scroll Map. Each entry is
## {index: int, center: Vector2, size: Vector2, rot: float} in District ground
## units (x -> X, y -> Z); rot is the 2D rotation (radians) for which
## Transform2D(rot, center) maps the footprint's local (x, z) to the ground.
## The layout is deterministic per District, so this only saves on a change.
func store_layout(district_id: String, houses: Array) -> void:
	var copy := _clean_layout(houses)
	if layouts.has(district_id) and layouts[district_id] == copy:
		return
	layouts[district_id] = copy
	save_run()


## The stored layout of a District ([] if it was never visited).
func layout_of(district_id: String) -> Array:
	return (layouts.get(district_id, []) as Array).duplicate(true)


## Typed copies of the layout entries (also checks what a save file holds).
static func _clean_layout(houses: Array) -> Array:
	var out: Array = []
	for h: Variant in houses:
		if not h is Dictionary:
			continue
		var d: Dictionary = h
		out.append({
			"index": int(d.get("index", out.size())),
			"center": d.get("center", Vector2.ZERO) as Vector2,
			"size": d.get("size", Vector2.ONE) as Vector2,
			"rot": float(d.get("rot", 0.0)),
		})
	return out


## Replaces the District data (tests).
func set_district_defs(defs: Array[DistrictDef]) -> void:
	_districts = defs
	_districts_loaded = true


static func _load_districts(dir_path: String) -> Array[DistrictDef]:
	var found: Array[DistrictDef] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return found
	var names: Array[String] = []
	for file in DirAccess.get_files_at(dir_path):
		var file_name := file.trim_suffix(".remap")
		if file_name.get_extension() == "tres" and not names.has(file_name):
			names.append(file_name)
	names.sort()
	var seen := {}
	for file_name in names:
		var d := ResourceLoader.load(dir_path.path_join(file_name)) as DistrictDef
		if d == null or d.id.is_empty() or seen.has(d.id):
			push_warning("Run: %s is not a DistrictDef with a unique id" % file_name)
			continue
		seen[d.id] = true
		found.append(d)
	# Unlock order: repeatedly take the Districts whose requirement is placed.
	var out: Array[DistrictDef] = []
	var placed := {}
	while not found.is_empty():
		var moved := false
		for d in found.duplicate():
			if d.requires.is_empty() or placed.has(d.requires) or not seen.has(d.requires):
				out.append(d)
				placed[d.id] = true
				found.erase(d)
				moved = true
		if not moved:
			out.append_array(found)   # a requirement loop: keep file order
			break
	return out


# ---------------------------------------------------------------------- upgrade data
## Every res://data/upgrades/*.tres, sorted by file name; loaded once. Copes
## with a missing or empty folder and with exported builds (*.tres.remap).
func all_nodes() -> Array[UpgradeNodeDef]:
	if not _nodes_loaded:
		_nodes_loaded = true
		_nodes = _load_nodes(UPGRADES_DIR)
	return _nodes


## Replaces the upgrade data (tests; or a reload after editing data).
func set_nodes(nodes: Array[UpgradeNodeDef]) -> void:
	_nodes = nodes
	_nodes_loaded = true
	upgrades_changed.emit()


## The node with this id, or null.
func find_node_def(id: String) -> UpgradeNodeDef:
	for node in all_nodes():
		if node.id == id:
			return node
	return null


static func _load_nodes(dir_path: String) -> Array[UpgradeNodeDef]:
	var out: Array[UpgradeNodeDef] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var names: Array[String] = []
	for file in DirAccess.get_files_at(dir_path):
		# Exported builds list "x.tres.remap" (the converted file sits elsewhere).
		var file_name := file.trim_suffix(".remap")
		if file_name.get_extension() == "tres" and not names.has(file_name):
			names.append(file_name)
	names.sort()
	var seen := {}
	for file_name in names:
		var res := ResourceLoader.load(dir_path.path_join(file_name))
		var node := res as UpgradeNodeDef
		if node == null:
			push_warning("Run: %s is not an UpgradeNodeDef" % file_name)
			continue
		if node.id.is_empty() or seen.has(node.id):
			push_warning("Run: %s has an empty or duplicate id '%s'" % [file_name, node.id])
			continue
		seen[node.id] = true
		out.append(node)
	return out


# ---------------------------------------------------------------------- save
func save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "year", _saved_year if _saved_year >= 0 else year)
	cfg.set_value("run", "pestilence", pestilence)
	cfg.set_value("run", "bones", bones)
	cfg.set_value("run", "last_colony_size", last_colony_size)
	cfg.set_value("run", "rounds_played", rounds_played)
	cfg.set_value("run", "district", _saved_district if not _saved_district.is_empty() else current_district)
	for id: String in levels:
		cfg.set_value("levels", id, int(levels[id]))
	for id: String in beaten:
		cfg.set_value("beaten", id, true)
	for id: String in best_dead_houses:
		cfg.set_value("best_dead_houses", id, best_dead_houses[id])
	for id: String in layouts:
		cfg.set_value("layouts", id, layouts[id])
	var err := cfg.save(save_path)
	if err != OK:
		push_warning("Run: could not save %s (error %d)" % [save_path, err])


## Loads the save; missing keys (or no save at all) keep their defaults.
func load_run() -> void:
	_set_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		year = int(cfg.get_value("run", "year", START_YEAR))
		pestilence = maxi(0, int(cfg.get_value("run", "pestilence", 0)))
		bones = maxi(0, int(cfg.get_value("run", "bones", 0)))
		last_colony_size = maxi(0, int(cfg.get_value("run", "last_colony_size", 0)))
		rounds_played = maxi(0, int(cfg.get_value("run", "rounds_played", 0)))
		current_district = str(cfg.get_value("run", "district", START_DISTRICT))
		if cfg.has_section("beaten"):
			for id in cfg.get_section_keys("beaten"):
				if bool(cfg.get_value("beaten", id, false)):
					beaten[id] = true
		if cfg.has_section("best_dead_houses"):
			for id in cfg.get_section_keys("best_dead_houses"):
				var arr: Variant = cfg.get_value("best_dead_houses", id, [])
				if arr is Array:
					var ids: Array[int] = []
					for i: Variant in arr:
						ids.append(int(i))
					best_dead_houses[id] = ids
		if cfg.has_section("layouts"):
			for id in cfg.get_section_keys("layouts"):
				var arr: Variant = cfg.get_value("layouts", id, [])
				if arr is Array:
					layouts[id] = _clean_layout(arr)
		if cfg.has_section("levels"):
			for id in cfg.get_section_keys("levels"):
				var lv := int(cfg.get_value("levels", id, 0))
				if lv > 0:
					levels[id] = lv
	wallet_changed.emit()
	upgrades_changed.emit()


## Wipes the save and starts a new Run (--fresh).
func reset() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_set_defaults()
	wallet_changed.emit()
	upgrades_changed.emit()


func _set_defaults() -> void:
	year = START_YEAR
	pestilence = 0
	bones = 0
	levels = {}
	last_colony_size = 0
	rounds_played = 0
	current_district = START_DISTRICT
	beaten = {}
	best_dead_houses = {}
	layouts = {}
