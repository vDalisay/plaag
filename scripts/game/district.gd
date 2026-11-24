## A slum District (~44 x 44 units) for one Round: irregular rows of shabby
## half-timbered houses on mud, a small well square, barrels and crates, and
## alleys between the house rows so the streets form a small maze.
##
## Props (scripts/town_props.gd) only builds visuals, so every house, the well
## and the clutter also get box / cylinder collision on layer 1 ("world"),
## computed from the same position, rotation and size passed to the prop kit.
## The same footprints are used to find free spots for the townsfolk.
##
## Each house has its own House body (scripts/game/house.gd, see
## house_visual()) that knows its door; 0-3 residents spawn indoors in each
## and every outdoor townsperson gets the nearest house as `home`. The `raid`
## action sends a Raid at the house under the mouse (gamepad: the nearest
## house within 10 u of the Lead Rat). When a house
## stands between the camera and the Lead Rat it is squashed down towards its
## footprint (the occlusion cutaway) and pops back up once clear.
##
## Debug flags (after `--`): --screenshot=<path> (saves a frame after ~3 s and
## quits; --screenshot-delay=<s> changes the wait), --bot (the Lead Rat steers itself), --set=<uniform>=<float> (sets a
## parchment shader value), --no-shadows, --start-colony=<n> (n Adult
## followers), --pups=<n> (n Pups), --god (the Lead Rat ignores hits),
## --lead-at=<x>,<z> (start the Lead Rat there), --no-cutaway, --dev (the
## HUD's R restart, unlocks Hide and Raid; prints the applied Run stats and the
## Hide / Raid events, as --bot does; --bot also Raids and Hides),
## --raid-test / --hide-test (Raid / Hide the nearest occupied house after
## ~1 s), --kill-house (kills every resident of the house nearest the Lead Rat
## after ~1 s), --knock-test (knocks every rat back from a point next to the
## Lead Rat after ~1 s), --no-residents.
## --perf (prints FPS, rat, townsfolk and resident counts every 2 s, vsync
## off), --fill (the Spawner fills the street up to its cap at once),
## --no-batch (no mesh merging, see _batch_meshes).
## HUD flags (read by scripts/ui/hud.gd): --results-test=<reason> ends the
## Round after 6 s with that reason, --pause-test opens the pause menu after
## 2 s, --toast-test fires one of each toast. Settings flags (autoload):
## --reduce-motion, --no-numbers, --pad.
## Run flags (read by the Run autoload): --fresh wipes the save, --year=<n>
## plays this session in Year n without saving it.
##
## The Spawner child (scripts/game/spawner.gd, gates as its Marker3D
## children) brings in new townsfolk during the Round (M5) and picks a Year
## type for 30% of the starting population.
##
## At Round start the Upgrade Tree stats (Run.stat) set the Lead Rat's speed,
## every Adult's Bite, the Colony's Feeding, Pup maturity and start size
## (start_adults + carry-over), every townsperson's Infection base_rate
## (x lethality, later spawns included) and the Round length.
##
## M6: the District played is Run.current_district_def() (a DistrictDef from
## data/districts/; --district=<id> picks one for the session). Its
## layout_style picks the layout ("slums": _build_slums, "merchant":
## _build_merchant), its wanderers and residents_per_house the starting
## population. Every House gets `index`, its build order (stable per layout
## seed). --force-exterminator brings the Exterminator in after 3 s (Spawner).
##
## M7: the Year visual stage (0..2, YearTable visual_stage; --stage=<n>
## overrides it) picks the decoration (scripts/game/district_decor.gd), the
## paving and the fence sag. Only visuals change: house positions, indices,
## colliders and doors are the same at every stage. Once built, the District
## stores its house layout in the Run (Run.store_layout, for the Scroll Map).
## With "unlock_fleas" (or --dev) a Fleas node (scripts/game/fleas.gd) gives
## every Adult its flea aura (--flea-test: every Flea roll hits).
extends Node3D

const Props := preload("res://scripts/town_props.gd")
const MedievalAssets := preload("res://scripts/world/medieval_assets.gd")
const Decor := preload("res://scripts/game/district_decor.gd")
const FleasScript := preload("res://scripts/game/fleas.gd")
const GroundScatter := preload("res://scripts/world/ground_scatter.gd")
const AmbientScript := preload("res://scripts/world/ambient.gd")
const YEAR_TABLE := "res://data/year_table.tres"
const TOWNSPERSON_SCENE := "res://scenes/game/townsperson.tscn"
const ROUND_DIRECTOR_SCRIPT := "res://scripts/game/round_director.gd"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const WORLD_LAYER := 1
## Gamepad Raid: the nearest house within this distance of the Lead Rat.
const RAID_PAD_RANGE := 12.0
## Cutaway: squashed height, tween times, how long a house must be clear
## before it stands up again, and the check rate.
const CUT_SCALE := 0.12
const CUT_DOWN_TIME := 0.2
const CUT_UP_TIME := 0.25
const CUT_RESTORE_DELAY := 0.5
const CUT_INTERVAL := 0.1
## Ground cell size (u) the static scenery is merged in (see _batch_meshes).
const BATCH_CELL := 14.0
## Expanded 68x68 street bands (north, middle, south avenues — 10-12u wide!).
const MERCHANT_GATE_Z: Array[float] = [-20.0, 0.0, 20.0]
const SQUARE_HALF := 12.0
const SLUM_STREETS: Array[Vector2] = [Vector2(-24.0, -14.0), Vector2(-5.5, 5.5), Vector2(14.0, 24.0)]
## Fence post tilt (x the base random tilt) per visual stage: sagging to straight.
const FENCE_SAG: Array[float] = [3.0, 1.0, 0.35]

## District rectangle on the ground (x -> X, y -> Z): spacious 68 x 68 u arena.
@export var bounds := Rect2(-34.0, -34.0, 68.0, 68.0)
@export var townsfolk_count := 38
@export var layout_seed := 23
@export var spawn_seed := 5
## Size of the patch each townsperson wanders in, around its spawn point.
@export var wander_size := 20.0
## Residents per house: a random count in [0, residents_max], spawned indoors.
@export var residents_max := 3
## Residents per house: the low end of the range (DistrictDef.residents_per_house.x).
@export var residents_min := 0

## The District being played (null: slums defaults).
var district_def: DistrictDef
## "slums" or "merchant" (DistrictDef.layout_style).
var layout_style := "slums"
## Year visual stage 0..2 (see _read_stage()).
var visual_stage := 0
## Tests: >= 0 forces the visual stage (before the District enters the tree).
var stage_override := -1
@onready var _sun: DirectionalLight3D = $Sun
@onready var _camera: Camera3D = $Camera3D
@onready var _rat: Node3D = $LeadRat
@onready var _colony: Colony = $Colony
@onready var _spawner: Spawner = $Spawner

var _k: Props
var _rng := RandomNumberGenerator.new()
var _screenshot_delay := 3.0
var _collision: StaticBody3D
# Ground footprints of everything solid: {"xf": Transform3D (centre + yaw), "half": Vector2 (x, z)}.
var _blockers: Array[Dictionary] = []
## One per house: {"root": Node3D visual, "inv": Transform3D world -> house
## local, "boxes": Array of [centre, half] local occluder boxes (walls, roof),
## "cut": bool, "clear": float s since it last occluded, "tween": Tween}.
var _houses: Array[Dictionary] = []
var _house_by_body := {}     # StaticBody3D -> visual root
var _cutaway := true
var _cut_left := 0.0
## Run "lethality": multiplies every townsperson's Infection base_rate.
var _lethality := 1.0
var _print_stats := false
var _residents := true
var _test := ""                 # --raid-test / --hide-test / --kill-house
var _perf := false
var _perf_census := true
var _perf_acc := Vector4.ZERO      # x physics ms, z process ms, summed over frames
var _perf_max_ph := 0.0
var _perf_frames := 0
var _fill := false
var _perf_left := 2.0
var _spawn_log_left := 15.0
## Picks the Year types of the starting population (own seed, so the
## resident counts stay the same as before M5).
var _def_rng := RandomNumberGenerator.new()
## Paving kit (own seed: the stage's paving never shifts the layout kit's RNG).
var _cobble_kit: Props
## Visible house fronts for the stage decoration (see Decor.build()).
var _facades: Array[Dictionary] = []
var _well_pos := Vector3.INF
var _fleas: Node3D
var _decor_placed := {}
## Graphics pass: its own RNG for the roof dressing, roof colours and signs
## (never the layout RNG, so house positions and indices stay the same).
var _look_rng := RandomNumberGenerator.new()
## Hanging shop signs: [house root, pivot in its frame] (scripts/world/sway.gd).
var _signs: Array = []
## Crow perches on fences and walls: [a, b] world points.
var _perch_lines: Array = []
var _ambient: Node3D


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	_apply_district_def()
	visual_stage = _read_stage()
	_setup_light()
	_k = Props.new(layout_seed)
	_cobble_kit = Props.new(layout_seed + 101)
	_rng.seed = layout_seed
	_look_rng.seed = layout_seed * 31 + 7
	_collision = StaticBody3D.new()
	_collision.name = "WorldCollision"
	_collision.collision_layer = WORLD_LAYER
	_collision.collision_mask = 0
	add_child(_collision)
	var keep: Array[Node] = get_children()
	_build_district()
	_colony.setup_nav(bounds, _blockers)
	_camera.set("bounds", bounds)
	_decorate()
	_k.flush(self)
	_batch_meshes(keep)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_store_layout()
	_apply_run_stats()
	_add_round_director()
	_add_hud()
	_parse_debug_args()
	var t1 := Time.get_ticks_usec()
	_add_ambient()
	build_ms += (Time.get_ticks_usec() - t1) / 1000.0
	_setup_spawner()
	_spawn_townsfolk()
	if _print_stats or _perf:
		print("district: built %s stage %d in %.0f ms" % [layout_style, visual_stage, build_ms])
	if _print_stats:
		_print_run_stats()
		print(_spawner.counts_text())
	if _fill:
		_fill_street.call_deferred()
	if not _test.is_empty():
		_run_test.call_deferred()


## Reads the DistrictDef being played: layout and starting population.
func _apply_district_def() -> void:
	district_def = Run.current_district_def()
	if district_def == null:
		return
	layout_style = district_def.layout_style
	townsfolk_count = district_def.wanderers
	residents_min = district_def.residents_per_house.x
	residents_max = district_def.residents_per_house.y


## The Year visual stage: stage_override, else --stage=<n>, else the
## YearTable entry of this Year and District (the merchant quarter never
## below 1); 0 without a table.
func _read_stage() -> int:
	if stage_override >= 0:
		return clampi(stage_override, 0, 2)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			return clampi(int(arg.trim_prefix("--stage=")), 0, 2)
	var st := 0
	var table: YearTable = null
	if ResourceLoader.exists(YEAR_TABLE):
		table = load(YEAR_TABLE) as YearTable
	if table:
		var e := table.entry_for(Run.year, district_id())
		if e:
			st = e.visual_stage
	if layout_style == "merchant":
		st = maxi(st, 1)
	return clampi(st, 0, 2)


## The id of the District being played ("slums" without data).
func district_id() -> String:
	return district_def.id if district_def else layout_style


func _setup_light() -> void:
	# Dramatic gothic key light + subdued cool fill so shadows carve real depth.
	_sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	_sun.directional_shadow_max_distance = 110.0
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-16.0, 82.0, 0.0)
	fill.light_color = Color(0.68, 0.74, 0.86)
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)


# ---------------------------------------------------------------------- layout
## Spacious 68x68 Slums layout: 4 staggered medieval house clusters framing
## broad 10u avenues, wide 6u alleys, and an open central well courtyard (~18x18u)
## so massive rat swarms and boss fights have room to breathe.
func _slum_house_specs() -> Array[Dictionary]:
	return [
		# North row (facing south into north avenue, z=-28.5)
		{"pos": Vector3(-25.0, 0, -28.5), "rot": 0.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(-15.5, 0, -28.2), "rot": 2.0, "bays": 3, "depth": 2, "stories": 2},
		{"pos": Vector3(-1.5, 0, -28.5), "rot": -2.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(11.5, 0, -28.3), "rot": 1.5, "bays": 3, "depth": 2, "stories": 2},
		{"pos": Vector3(23.5, 0, -28.5), "rot": -1.5, "bays": 4, "depth": 2, "stories": 2},
		# Mid-north clusters (flanking the central well courtyard, wide 6u+ alleys)
		{"pos": Vector3(-23.5, 0, -10.5), "rot": 0.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(-13.5, 0, -10.2), "rot": 2.5, "bays": 3, "depth": 2, "stories": 1},
		{"pos": Vector3(14.5, 0, -10.4), "rot": -2.0, "bays": 3, "depth": 2, "stories": 1},
		{"pos": Vector3(24.5, 0, -10.5), "rot": 1.0, "bays": 4, "depth": 2, "stories": 2},
		# Mid-south clusters (low 1-storey south-facing sides so camera sightlines stay open)
		{"pos": Vector3(-24.0, 0, 10.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 1},
		{"pos": Vector3(-13.5, 0, 10.8), "rot": 178.0, "bays": 3, "depth": 2, "stories": 1},
		{"pos": Vector3(14.0, 0, 10.5), "rot": 182.0, "bays": 3, "depth": 2, "stories": 1},
		{"pos": Vector3(24.5, 0, 10.6), "rot": 179.0, "bays": 4, "depth": 2, "stories": 1},
		# South row (facing north into south avenue, z=28.5)
		{"pos": Vector3(-25.0, 0, 28.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 1},
		{"pos": Vector3(-14.5, 0, 28.2), "rot": 182.0, "bays": 3, "depth": 2, "stories": 1},
		{"pos": Vector3(0.5, 0, 28.5), "rot": 179.0, "bays": 4, "depth": 2, "stories": 1},
		{"pos": Vector3(13.5, 0, 28.4), "rot": 181.5, "bays": 3, "depth": 2, "stories": 1},
		{"pos": Vector3(24.5, 0, 28.5), "rot": 178.5, "bays": 4, "depth": 2, "stories": 1},
	]


func _build_district() -> void:
	match layout_style:
		"merchant":
			_build_merchant()
		_:
			_build_slums()


func _build_slums() -> void:
	var k := _k
	var ground := PlaneMesh.new()
	ground.size = Vector2(220, 220)
	k.part(self, ground, Color(0.58, 0.52, 0.44), Vector3.ZERO)
	for r in slum_paving(visual_stage):
		_cobble_kit.cobbles(self, r.position.x, r.end.x, r.position.y, r.end.y, 0.58, -100.0, 0.0)

	for spec in _slum_house_specs():
		_place_megakit_house(spec, "slums")

	# Central well courtyard — generous open space for kiting & swarming
	_well(Vector3(0.0, 0, 0.0))
	_wagon(Vector3(-7.0, 0, -5.0), 22.0)
	_stall_cart(Vector3(7.4, 0, -4.5), -18.0)
	_bench(Vector3(-4.2, 0, 4.6), 12.0)
	_bench(Vector3(4.5, 0, 4.4), -10.0)
	_barrel(Vector3(-7.8, 0, 6.2))
	_barrel(Vector3(-7.0, 0, 6.7))
	_crate(Vector3(7.8, 0, 6.0), Vector3(1.0, 0.9, 1.0), 14.0)
	_rubble(Vector3(-3.0, 0, -7.2))
	_rubble(Vector3(5.6, 0, 7.2))
	# North & south avenue dressing (kept tucked near building edges so avenues stay wide)
	_wagon(Vector3(16.0, 0, -21.5), 86.0)
	_barrel(Vector3(-19.5, 0, -23.5))
	_barrel(Vector3(-18.6, 0, -23.6))
	_crate(Vector3(5.5, 0, -23.8), Vector3(1.0, 0.9, 1.0), 18.0)
	_barrel(Vector3(-28.0, 0, 2.5))
	_crate(Vector3(-27.0, 0, 3.0), Vector3(1.0, 0.9, 1.0), -12.0)
	_barrel(Vector3(27.5, 0, -2.5))
	_crate(Vector3(26.8, 0, -3.2), Vector3(1.0, 0.9, 1.0), 24.0)
	_barrel(Vector3(-6.0, 0, 23.0))
	_crate(Vector3(19.5, 0, 23.2), Vector3(1.0, 0.9, 1.0), -14.0)
	_stall_cart(Vector3(-17.5, 0, 22.8), 10.0)
	# Perimeter medieval wooden fences closing the street ends
	for x in [bounds.position.x + 0.5, bounds.end.x - 0.5]:
		_fence(x, -24.5, -14.0)
		_fence(x, -6.0, 6.0)
		_fence(x, 14.0, 24.5)
	_add_bounds()


## Builds one modular medieval house from MedievalAssets (falling back cleanly to
## procedural Props.house if glTFs are unavailable).
func _place_megakit_house(spec: Dictionary, style: String) -> void:
	var pos: Vector3 = spec["pos"]
	var rot: float = float(spec["rot"])
	var bays: int = int(spec["bays"])
	var depth_bays: int = int(spec["depth"])
	var stories: int = int(spec["stories"])
	var length := float(bays) * 2.0
	var depth := float(depth_bays) * 2.0
	var info: Dictionary
	if MedievalAssets.has_asset(&"wall_plaster"):
		info = MedievalAssets.build_house(self, _k, pos, rot, bays, depth_bays, stories, style, visual_stage, _rng)
	else:
		var opts := {"roof": Props.WOOD, "stories": mini(stories, 2), "door_bay": _rng.randi_range(0, bays - 1),
			"lit": [true, false, true, false], "chimney": true, "braces": true, "pitch": 38.0}
		var root_fb := _k.house(self, pos, rot, length, depth, 2.9, 2.6, opts)
		info = {"root": root_fb, "length": length, "depth": depth, "top": 2.9 * stories,
			"jetty": 0.45 if stories >= 2 else 0.0, "pitch": 38.0, "door_bay": opts["door_bay"],
			"n_bays": bays, "chimney": Vector3(0, 6.0, 0), "has_chimney": true}
	var root: Node3D = info["root"]
	var opts_body := {"pitch": info["pitch"], "door_bay": info["door_bay"], "chimney": info["has_chimney"]}
	_add_house_body(root, pos, rot, info["length"], info["depth"], info["top"], info["jetty"], opts_body, info["n_bays"])
	var h: Dictionary = _houses.back()
	h["roof_root"] = root
	h["chimney"] = info["chimney"]
	var ridge_y := float(info["top"]) + 2.4
	h["ridge"] = [Vector3(-length * 0.4, ridge_y, 0.0), Vector3(length * 0.4, ridge_y, 0.0)]


func _barrel(pos: Vector3) -> void:
	if MedievalAssets.has_asset(&"barrel"):
		var key := &"barrel_apples" if _rng.randf() < 0.25 else &"barrel"
		MedievalAssets.spawn(self, key, pos, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * 1.15, &"wood")
	else:
		_k.barrel(self, pos)
	_add_cylinder(pos, 0.48, 1.1)
	_blockers.append({"xf": Transform3D(Basis(), pos), "half": Vector2(0.55, 0.55)})


func _crate(pos: Vector3, size: Vector3, rot_y: float, y := 0.0) -> void:
	if MedievalAssets.has_asset(&"crate"):
		MedievalAssets.spawn(self, &"crate", pos + Vector3(0, y, 0), Vector3(0, rot_y, 0), Vector3.ONE * 0.9, &"wood")
	else:
		_k.crate(self, pos + Vector3(0, y, 0), size, rot_y)
	if y > 0.0:
		return
	_add_box(Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos), size)


func _wagon(pos: Vector3, rot_y: float) -> void:
	if MedievalAssets.has_asset(&"wagon"):
		MedievalAssets.spawn(self, &"wagon", pos, Vector3(0, rot_y, 0), Vector3.ONE * 0.95, &"wood")
		_add_box(Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos), Vector3(1.9, 1.5, 3.6))


func _stall_cart(pos: Vector3, rot_y: float) -> void:
	if MedievalAssets.has_asset(&"stall_cart"):
		MedievalAssets.spawn(self, &"stall_cart", pos, Vector3(0, rot_y, 0), Vector3.ONE, &"wood")
		_add_box(Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos), Vector3(2.8, 1.4, 1.3))


func _bench(pos: Vector3, rot_y: float) -> void:
	if MedievalAssets.has_asset(&"bench"):
		MedievalAssets.spawn(self, &"bench", pos, Vector3(0, rot_y, 0), Vector3.ONE * 0.85, &"wood")
		_add_box(Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos), Vector3(2.2, 0.6, 0.6))


func _rubble(pos: Vector3) -> void:
	if MedievalAssets.has_asset(&"rubble"):
		MedievalAssets.spawn(self, &"rubble", pos, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * 1.1, &"stone")


## A medieval wooden fence along Z at x, from z0 to z1.
func _fence(x: float, z0: float, z1: float) -> void:
	var use_gl := MedievalAssets.has_asset(&"fence_wood")
	var step := 2.0
	var z := z0 + step * 0.5
	while z < z1:
		if use_gl:
			MedievalAssets.spawn(self, &"fence_wood", Vector3(x, 0, z), Vector3(0, 90.0, 0), Vector3.ONE, &"wood")
		else:
			_k.part(self, _k.box(Vector3(0.16, 1.2, step)), Props.WOOD, Vector3(x, 0.6, z))
		_perch_lines.append([Vector3(x, 0.9, z), Vector3(x, 0.9, z)])
		z += step


## The House body of a built house visual: collider, door, cutaway occluders
## and its `index` (the build order). `top` is the wall height, `j` the jetty.
func _add_house_body(root: Node3D, pos: Vector3, rot: float, length: float, depth: float,
		top: float, j: float, opts: Dictionary, n_bays: int) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(rot))
	var centre := pos + basis * Vector3(0, 0, j * 0.5)
	var body := House.new()
	body.name = "HouseBody%d" % _houses.size()
	body.index = _houses.size()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	var size := Vector3(length + 0.2, top, depth + 0.12 + j)
	_add_box(Transform3D(basis, centre), size, body)
	body.setup(root, length, depth, top, j, opts["pitch"], opts["door_bay"], n_bays,
		j * 0.5 + size.z * 0.5, _k)
	_house_by_body[body] = root
	var rise := (depth + j + 0.7) * 0.5 * tan(deg_to_rad(opts["pitch"]))
	var roof_h := rise + (0.6 if opts["chimney"] else 0.0)
	_houses.append({
		"house": body,
		"root": root,
		"center": Vector2(centre.x, centre.z),
		"size": Vector2(size.x, size.z),
		"yaw": rot,
		"inv": root.global_transform.affine_inverse(),
		"boxes": [
			[Vector3(0, top * 0.5, j * 0.5), Vector3(length + 0.2, top, depth + 0.12 + j) * 0.5],
			[Vector3(0, top + roof_h * 0.5, j * 0.5), Vector3(length + 0.7, roof_h, depth + j + 0.7) * 0.5],
		],
		"cut": false,
		"clear": 0.0,
		"tween": null,
	})


func _well(pos: Vector3) -> void:
	_well_pos = pos
	_add_cylinder(pos, 2.0, 1.4)
	_blockers.append({"xf": Transform3D(Basis(), pos), "half": Vector2(2.3, 2.3)})


# ---------------------------------------------------------------------- year stages
## Slums paving rects (x -> X, y -> Z) for a visual stage on the 68x68 map.
static func slum_paving(stage: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	match stage:
		0:
			out = [Rect2(-9.0, -7.0, 18.0, 14.0), Rect2(10.0, -22.0, 14.0, 6.0), Rect2(-22.0, 16.0, 14.0, 6.0)]
		1:
			out = [Rect2(-34.0, -5.5, 68.0, 11.0), Rect2(-9.0, -10.0, 18.0, 20.0),
				Rect2(-12.0, -22.0, 32.0, 7.0), Rect2(-22.0, 15.0, 32.0, 7.0)]
		_:
			for band in SLUM_STREETS:
				out.append(Rect2(-34.0, band.x, 68.0, band.y - band.x))
			out.append(Rect2(-10.0, -14.0, 20.0, 28.0))
	return out


## Builds the stage's decoration (scripts/game/district_decor.gd) on top of
## the finished layout, from its own RNG.
func _decorate() -> void:
	var streets: Array[Rect2] = []
	var paved: Array[Rect2] = []
	var drains: Array[Vector3] = []
	if layout_style == "merchant":
		for z: Vector2 in [Vector2(-17.6, -8.4), Vector2(-3.7, 3.4), Vector2(11.4, 18.2)]:
			streets.append(Rect2(bounds.position.x + 1.0, z.x, bounds.size.x - 2.0, z.y - z.x))
		paved = streets.duplicate()
	else:
		for band in SLUM_STREETS:
			streets.append(Rect2(bounds.position.x + 1.0, band.x + 0.3, bounds.size.x - 2.0, band.y - band.x - 0.6))
		streets.append(Rect2(-1.6, 2.75, 9.2, 4.25))
		paved = slum_paving(visual_stage)
		# Open drains down the middle of the south and north streets (z, x0, x1).
		drains = [Vector3(14.5, bounds.position.x + 0.8, bounds.end.x - 0.8),
			Vector3(-14.5, bounds.position.x + 0.8, bounds.end.x - 0.8)]
	var doors: Array[Vector3] = []
	for h in _houses:
		doors.append((h["house"] as House).door_position)
	var decor := Decor.new(self, _k, visual_stage, layout_style, layout_seed * 7 + 3)
	decor.build(_facades, _well_pos, streets, paved, drains, doors)
	_decor_placed = decor.placed
	var scatter := GroundScatter.new(self, _k, visual_stage, layout_style, layout_seed * 11 + 5)
	scatter.build(_scatter_info(streets, paved, doors))
	_decor_placed["ground"] = scatter.placed


## Window list of a Props.house() front (house-local, floor at `y0`):
## [[centre, size, lit, upper], ...], the same maths as the kit.
static func _kit_windows(y0: float, length: float, depth: float, h1: float, h2: float,
		stories: int, n_bays: int, door_bay: int, lit: Array[bool]) -> Array:
	var out: Array = []
	var bw := length / n_bays
	var front1 := depth * 0.5
	var front2 := front1 + (0.45 if stories == 2 else 0.0)
	var wi := 0
	for b in n_bays:
		if b == door_bay:
			continue
		var cx := -length * 0.5 + (b + 0.5) * bw
		out.append([Vector3(cx, y0 + h1 * 0.55, front1), Vector2(0.8, 1.0), lit[wi] if wi < lit.size() else true, false])
		wi += 1
	if stories == 2:
		for b in n_bays:
			var cx := -length * 0.5 + (b + 0.5) * bw
			out.append([Vector3(cx, y0 + h1 + h2 * 0.6, front2), Vector2(0.7, 0.95), lit[wi] if wi < lit.size() else true, true])
			wi += 1
	return out


## Records a visible house front for _decorate(): its windows, a wall
## lantern spot beside the door (none if it has a lantern) and, under a
## jetty (`j` > 0, inside the collider), a spot for a tub or a heap.
func _add_facade(root: Node3D, windows: Array, length: float, depth: float, door_h: float,
		j: float, n_bays: int, door_bay: int, has_lantern: bool) -> void:
	var bw := length / n_bays
	var door_x := -length * 0.5 + (door_bay + 0.5) * bw
	var side := 1.0 if door_bay < n_bays - 1 else -1.0
	var front := depth * 0.5
	var lantern := Vector3(NAN, 0, 0) if has_lantern else Vector3(door_x + side * 0.85, minf(door_h - 0.7, 2.6), front)
	var tub := Vector3(door_x - side * 0.95, 0.0, front + 0.25) if j > 0.0 else Vector3(NAN, 0, 0)
	_facades.append({"root": root, "windows": windows, "lantern": lantern, "tub": tub})


## The house footprints for the Scroll Map (Run.store_layout format):
## [{index, center: Vector2, size: Vector2, rot: float}], rot being the 2D
## rotation (radians) that takes local (x, z) to the ground (= -yaw).
func layout_entries() -> Array:
	var out: Array = []
	for h in _houses:
		out.append({
			"index": (h["house"] as House).index,
			"center": h["center"],
			"size": h["size"],
			"rot": -deg_to_rad(float(h["yaw"])),
		})
	return out


func _store_layout() -> void:
	Run.store_layout(district_id(), layout_entries())


# ---------------------------------------------------------------------- graphics pass
## Roof dressing of a slum house by stage: holes, patches and moss at stage 0,
## repaired step by step (scripts/town_props.gd roof_dressing()).
func _slum_roof_look(color: Color) -> Dictionary:
	var r := _look_rng
	var look := {"color": color}
	match visual_stage:
		0:
			look["holes"] = (1 if r.randf() < 0.55 else 0) + (1 if r.randf() < 0.15 else 0)
			look["patches"] = r.randi_range(0, 2)
			look["moss"] = r.randi_range(1, 3)
			look["gaps"] = r.randi_range(3, 7)
		1:
			look["holes"] = 1 if r.randf() < 0.12 else 0
			look["patches"] = r.randi_range(1, 2)
			look["moss"] = r.randi_range(0, 2)
			look["gaps"] = r.randi_range(1, 3)
		_:
			look["patches"] = r.randi_range(0, 1)
			look["moss"] = 1 if r.randf() < 0.3 else 0
	return look


## Roof dressing of a merchant's house: dormers, a little moss.
func _merchant_roof_look(color: Color, length: float) -> Dictionary:
	var r := _look_rng
	var dormers := 0
	if r.randf() < 0.55:
		dormers = 2 if length > 6.4 else 1
	return {"color": color, "dormers": dormers, "lit": 0.5,
		"moss": 1 if visual_stage < 2 and r.randf() < 0.25 else 0,
		"patches": 1 if visual_stage == 0 and r.randf() < 0.3 else 0}


## Remembers the roof of the house just added (smoke, crows).
func _note_roof(roof_root: Node3D, roof: Dictionary) -> void:
	var h: Dictionary = _houses.back()
	var l: float = roof["length"]
	h["roof_root"] = roof_root
	h["chimney"] = roof["chimney"]
	h["ridge"] = [Props.ridge_point(roof, -l * 0.5 + 0.7), Props.ridge_point(roof, l * 0.5 - 0.7)]


## An iron bracket on a facade (`at` = wall point, house frame) for a
## hanging shop sign; the sign itself swings in scripts/world/sway.gd.
func _sign_bracket(root: Node3D, at: Vector3) -> void:
	_k.part(root, _k.box(Vector3(0.07, 0.07, 1.0)), Props.INK, at + Vector3(0, 0, 0.5))
	_k.strip(root, at + Vector3(0, -0.55, 0.02), at + Vector3(0, -0.03, 0.6), 0.05, Props.INK)
	_signs.append([root, at + Vector3(0, -0.04, 0.84)])


## What the ground scatter needs (scripts/world/ground_scatter.gd).
func _scatter_info(streets: Array[Rect2], paved: Array[Rect2], doors: Array[Vector3]) -> Dictionary:
	var houses: Array = []
	for h in _houses:
		houses.append({"center": h["center"], "size": h["size"], "yaw": h["yaw"]})
	var info := {"streets": streets, "paved": paved, "doors": doors, "gates": gate_points(), "houses": houses}
	var x0 := bounds.position.x + 0.6
	var x1 := bounds.end.x - 0.6
	if layout_style == "merchant":
		var sq := SQUARE_HALF + 0.2
		var kerbs: Array = []
		# Street edges just clear of the house fronts (z), and the x ranges left
		# open (the square, the gate alleys).
		for e: Array in [[-16.95, 2.5], [-8.2, sq], [-3.05, sq], [2.75, sq], [12.05, sq], [17.25, 2.5]]:
			var z: float = e[0]
			var gap: float = e[1]
			kerbs.append([Vector3(x0, 0, z), Vector3(-gap, 0, z)])
			kerbs.append([Vector3(gap, 0, z), Vector3(x1, 0, z)])
		info["kerbs"] = kerbs
		info["gutters"] = [Vector3(-12.6, x0, x1), Vector3(14.65, x0, x1),
			Vector3(-0.15, x0, -sq - 0.3), Vector3(-0.15, sq + 0.3, x1)]
		info["square"] = Rect2(-SQUARE_HALF, -8.4, SQUARE_HALF * 2.0, 19.8)
	else:
		info["ruts"] = [Vector3(-14.5 + 1.3, x0, x1), Vector3(0.0, x0, x1), Vector3(14.5 - 1.3, x0, x1)]
		var fences: Array = []
		for x: float in [bounds.position.x + 0.45, bounds.end.x - 0.45]:
			for band in SLUM_STREETS:
				fences.append([Vector3(x, 0, band.x), Vector3(x, 0, band.y)])
		info["fences"] = fences
	return info


## Ambient life (scripts/world/ambient.gd): smoke, crows, laundry, signs,
## ripples, lantern flicker, the plague stain and fallen houses.
func _add_ambient() -> void:
	var houses: Array = []
	for h in _houses:
		if not h.has("roof_root"):
			continue
		houses.append({"house": h["house"], "root": h["root"], "roof_root": h["roof_root"],
			"chimney": h["chimney"], "ridge": h["ridge"]})
	var water: Array = []
	if _well_pos.is_finite():
		if layout_style != "merchant" and visual_stage == 2:
			water.append([_well_pos + Vector3(0, 0.69, 0), 1.6])   # the fountain basin and bowl
			water.append([_well_pos + Vector3(0, 2.37, 0), 0.62])
		else:
			water.append([_well_pos + Vector3(0, 1.38, 0), 1.6])   # the dark well shaft
	var overlay := _camera.get_node_or_null("ParchmentOverlay") as MeshInstance3D
	var laundry := _laundry_lines() if layout_style != "merchant" else []
	_decor_placed["ambient"] = {"chimneys": houses.filter(func(h: Dictionary) -> bool: return not is_nan((h["chimney"] as Vector3).x)).size(),
		"laundry": laundry.size(), "signs": _signs.size(), "perches": _perch_lines.size(), "water": water.size()}
	_ambient = AmbientScript.new()
	_ambient.name = "Ambient"
	add_child(_ambient)
	_ambient.call("setup", _k, {
		"style": layout_style,
		"seed": layout_seed * 17 + visual_stage,
		"bounds": bounds,
		"houses": houses,
		"perches": _perch_lines,
		"laundry": laundry,
		"signs": _signs,
		"water": water,
		"overlay": overlay.material_override as ShaderMaterial if overlay else null,
	})
	_ambient.call("collect_lanterns", self)


## Laundry lines across the alleys between neighbouring slum houses of a row
## (a gap of 1.5-4.8 u), near the fronts, under the eaves.
func _laundry_lines() -> Array:
	var out: Array = []
	for a in _houses:
		var ca: Vector2 = a["center"]
		var sa: Vector2 = a["size"]
		var right := ca.x + sa.x * 0.5
		var best: Dictionary = {}
		var best_gap := INF
		for b in _houses:
			var cb: Vector2 = b["center"]
			var sb: Vector2 = b["size"]
			if absf(cb.y - ca.y) > 1.0 or absf(angle_difference(deg_to_rad(float(a["yaw"])), deg_to_rad(float(b["yaw"])))) > 0.25:
				continue
			var gap := (cb.x - sb.x * 0.5) - right
			if gap > 0.0 and gap < best_gap:
				best_gap = gap
				best = b
		if best.is_empty() or best_gap < 1.5 or best_gap > 4.8 or _look_rng.randf() > 0.85:
			continue
		var cb2: Vector2 = best["center"]
		var sb2: Vector2 = best["size"]
		var facing := 1.0 if absf(angle_difference(deg_to_rad(float(a["yaw"])), 0.0)) < 0.5 else -1.0
		var z := (ca.y + cb2.y) * 0.5 + facing * (minf(sa.y, sb2.y) * 0.5 - 0.8)
		out.append([Vector3(right - 0.1, 2.45, z), Vector3(cb2.x - sb2.x * 0.5 + 0.1, 2.45, z)])
	return out


# ---------------------------------------------------------------------- merchant quarter
## Merchant quarter house rows, north (-Z) to south (+Z), as in _rows(): `z`
## centre line, `rot` facing, `depth`, `gaps` x ranges left open (the square,
## the gate alleys). `tall` rows hide no street from the camera, so 3 storeys
## may stand there; the others keep to 2.
## Spacious 68x68 Merchant quarter: grand central market plaza (~24x22u),
## broad 11u cobbled avenues, MegaKit brick/plaster 2-3 storey houses, stalls & lamps.
func _merchant_house_specs() -> Array[Dictionary]:
	return [
		# North avenue facade (tall 2-3 storey merchant townhouses)
		{"pos": Vector3(-24.5, 0, -28.5), "rot": 0.0, "bays": 4, "depth": 2, "stories": 3},
		{"pos": Vector3(-13.5, 0, -28.5), "rot": 0.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(13.5, 0, -28.5), "rot": 0.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(24.5, 0, -28.5), "rot": 0.0, "bays": 4, "depth": 2, "stories": 3},
		# Mid-north blocks framing the grand central market square
		{"pos": Vector3(-23.5, 0, -10.5), "rot": 0.0, "bays": 4, "depth": 3, "stories": 2},
		{"pos": Vector3(23.5, 0, -10.5), "rot": 0.0, "bays": 4, "depth": 3, "stories": 2},
		# Mid-south blocks framing the square
		{"pos": Vector3(-23.5, 0, 10.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(23.5, 0, 10.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 2},
		# South avenue townhouses
		{"pos": Vector3(-24.5, 0, 28.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(-13.5, 0, 28.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(13.5, 0, 28.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 2},
		{"pos": Vector3(24.5, 0, 28.5), "rot": 180.0, "bays": 4, "depth": 2, "stories": 2},
	]


func _build_merchant() -> void:
	var k := _k
	var ground := PlaneMesh.new()
	ground.size = Vector2(220, 220)
	k.part(self, ground, Color(0.56, 0.52, 0.46), Vector3.ZERO)
	var x0 := bounds.position.x
	var x1 := bounds.end.x
	var sq := SQUARE_HALF + 0.5
	k.cobbles(self, x0, x1, -24.5, -14.5, 0.68, -100.0, 0.0)
	k.cobbles(self, x0, x1, -5.5, 5.5, 0.68, -100.0, 0.0)
	k.cobbles(self, x0, x1, 14.5, 24.5, 0.68, -100.0, 0.0)
	k.cobbles(self, -sq, sq, -14.5, 14.5, 0.68, -100.0, 0.0)
	k.cobbles(self, -4.5, 4.5, bounds.position.y, -24.5, 0.68, -100.0, 0.0)
	k.cobbles(self, -4.5, 4.5, 24.5, bounds.end.y, 0.68, -100.0, 0.0)

	for spec in _merchant_house_specs():
		_place_megakit_house(spec, "merchant")

	# Grand central market plaza: well + stalls + carts + wagons + glowing lamps
	_well(Vector3(0.0, 0, 0.0))
	_stall(Vector3(-7.0, 0, -9.5), 0.0, Props.COAT)
	_stall(Vector3(7.0, 0, -9.5), 0.0, Props.WOOD)
	_stall(Vector3(-7.0, 0, 9.5), 180.0, Props.WOOD)
	_stall(Vector3(7.0, 0, 9.5), 180.0, Props.COAT)
	_wagon(Vector3(-10.5, 0, 0.0), 8.0)
	_stall_cart(Vector3(10.2, 0, 0.0), -12.0)
	_barrel(Vector3(-11.0, 0, -8.5))
	_barrel(Vector3(-10.2, 0, -8.0))
	_crate(Vector3(10.8, 0, -8.2), Vector3(1.0, 0.9, 1.0), 10.0)
	_crate(Vector3(-10.6, 0, 8.8), Vector3(1.0, 0.9, 1.0), -12.0)
	_barrel(Vector3(10.8, 0, 8.8))
	_sacks(Vector3(-2.4, 0, 9.5))
	_sacks(Vector3(2.4, 0, -9.2))
	for p: Vector3 in [Vector3(-11.0, 0, -11.5), Vector3(11.0, 0, -11.5), Vector3(-11.0, 0, 11.5),
			Vector3(11.0, 0, 11.5), Vector3(-22.0, 0, -15.5), Vector3(22.0, 0, -15.5),
			Vector3(-22.0, 0, 4.5), Vector3(22.0, 0, 4.5), Vector3(-18.0, 0, 23.0),
			Vector3(18.0, 0, 23.0), Vector3(-5.0, 0, -24.5), Vector3(5.0, 0, -24.5)]:
		_lamp(p)
	# Perimeter low stone walls closing street ends
	for x in [x0 + 0.5, x1 - 0.5]:
		_stone_wall(Vector3(x, 0, -19.5), 11.0, 90.0)
		_stone_wall(Vector3(x, 0, 0.0), 11.0, 90.0)
		_stone_wall(Vector3(x, 0, 19.5), 11.0, 90.0)
	_stone_wall(Vector3(0, 0, bounds.position.y + 0.5), 9.0, 0.0)
	_stone_wall(Vector3(0, 0, bounds.end.y - 0.5), 9.0, 0.0)
	_add_bounds()


## Fills [x0, x1] of a merchant row with long houses and narrow slits.
func _merchant_fill(row: Dictionary, x0: float, x1: float) -> void:
	var x := x0
	while x1 - x >= 4.6:
		var length := _rng.randf_range(5.4, 7.2)
		if x1 - x - length < 4.6:
			length = minf(x1 - x, 8.2)
		_merchant_house(row, x + length * 0.5, length)
		x += length + _rng.randf_range(0.15, 0.35)


## A merchant's house: 2 storeys from the prop kit, or 3 (a stone-quoined
## lime-washed shop storey of our own with the door, under the kit's 2-storey
## house without a door). Steep slate / pale / plank roofs, never red.
func _merchant_house(row: Dictionary, cx: float, length: float) -> void:
	var rot0: float = row["rot"]
	var storeys := 3 if row["tall"] and _rng.randf() < 0.75 else 2
	var depth: float = row["depth"] + _rng.randf_range(-0.1, 0.1)
	var hg := _rng.randf_range(3.0, 3.3)
	var h1 := _rng.randf_range(2.9, 3.2)
	var h2 := _rng.randf_range(2.6, 2.9)
	var rot := rot0 + _rng.randf_range(-2.0, 2.0)
	var facing := 1.0 if rot0 == 0.0 else -1.0
	var pos := Vector3(cx + _rng.randf_range(-0.1, 0.1), 0, row["z"] + facing * _rng.randf_range(0.0, 0.15))
	var n_bays := maxi(2, roundi(length / 2.1))
	var door_bay := _rng.randi_range(0, n_bays - 1)
	var lit: Array[bool] = []
	for i in n_bays * 2:
		lit.append(_rng.randf() < 0.55)
	var roll := _rng.randf()
	var opts := {
		"roof": Props.STONE if roll < 0.45 else (Props.WALL if roll < 0.8 else Props.WOOD),
		"stories": 2,
		"door_bay": door_bay,
		"lit": lit,
		"chimney": _rng.randf() < 0.5,
		"braces": true,
		"pitch": _rng.randf_range(44.0, 52.0),
	}
	# Graphics pass: slate roofs, about half of them washed azure (own RNG).
	if _look_rng.randf() < 0.45:
		opts["roof"] = Props.AZURE
	elif opts["roof"] == Props.STONE:
		opts["roof"] = Props.SLATE
	var lantern := _rng.randf() < 0.6
	var root: Node3D
	var roof_root: Node3D
	var top := h1 + h2
	var bw := length / n_bays
	var door_x := -length * 0.5 + (door_bay + 0.5) * bw
	# The lantern beside the door, on the side away from the house corner.
	var lantern_x := door_x + (0.95 if door_bay < n_bays - 1 else -0.95)
	if storeys == 3:
		root = _k.node(self, pos, rot)
		_shop_storey(root, length, depth, hg, n_bays, door_bay, lantern_x if lantern else NAN)
		var upper := opts.duplicate()
		upper["door_bay"] = -1   # every bay of the kit's ground floor gets a window
		roof_root = _k.house(root, Vector3(0, hg, 0), 0.0, length, depth, h1, h2, upper)
		top += hg
	else:
		if lantern:
			opts["lantern"] = lantern_x
		root = _k.house(self, pos, rot, length, depth, h1, h2, opts)
		roof_root = root
	var roof := Props.house_roof(length, depth, h1, h2, opts)
	var look := _merchant_roof_look(opts["roof"], length)
	look["dormer_side"] = 1.0 if rot0 == 0.0 else -1.0   # the slope the camera sees
	_k.roof_dressing(roof_root, roof, look, _look_rng)
	var chim: Vector3 = roof["chimney"]
	if not is_nan(chim.x):
		var pots := 1 + _look_rng.randi() % 2
		_k.chimney_pots(roof_root, chim, pots)
		roof["chimney"] = chim + Vector3(0, 0.42, 0)
	if rot0 == 0.0 and _look_rng.randf() < 0.6:
		var sx := -1.0 if door_x > 0.0 else 1.0
		var sign_y := hg - 0.55 if storeys == 3 else h1 - 0.3
		_sign_bracket(root, Vector3(sx * (length * 0.5 - 0.5), sign_y, depth * 0.5))
	_k.flush(root)
	var tiles := root.get_child(root.get_child_count() - 1) as Node3D
	tiles.transform = root.global_transform.affine_inverse()
	_add_house_body(root, pos, rot, length, depth, top, 0.45, opts, n_bays)
	_note_roof(roof_root, roof)
	if rot0 == 0.0:
		var wins: Array
		if storeys == 3:
			wins = _kit_windows(hg, length, depth, h1, h2, 2, n_bays, -1, lit)
		else:
			wins = _kit_windows(0.0, length, depth, h1, h2, 2, n_bays, door_bay, lit)
		# Doors with a lantern already keep theirs; shop storeys have no jetty.
		_add_facade(root, wins, length, depth, hg if storeys == 3 else h1, 0.0 if storeys == 3 else 0.45,
			n_bays, door_bay, lantern)


## The ground (shop) storey of a 3-storey merchant house, local frame as
## Props.house(): plinth, lime-washed wall, stone quoins, a timber lintel,
## posts between the bays, wide shop windows and the door (+ a wall lantern
## at `lantern_x` unless NAN).
func _shop_storey(root: Node3D, length: float, depth: float, h: float, n_bays: int,
		door_bay: int, lantern_x: float) -> void:
	var k := _k
	var front := depth * 0.5
	var bw := length / n_bays
	k.part(root, k.box(Vector3(length + 0.14, 0.45, depth + 0.14)), Props.STONE, Vector3(0, 0.225, 0))
	k.part(root, k.box(Vector3(length, h, depth)), Props.WALL, Vector3(0, h * 0.5, 0))
	# Alternating long and short quoin stones up both front corners.
	var n_q := int((h - 0.6) / 0.5)
	for sx: float in [-1.0, 1.0]:
		for q in n_q:
			var w := 0.55 if q % 2 == 0 else 0.35
			k.part(root, k.box(Vector3(w, 0.4, 0.1)), Props.STONE,
				Vector3(sx * (length * 0.5 - w * 0.5 + 0.04), 0.7 + q * 0.5, front + 0.04))
	k.part(root, k.box(Vector3(length + 0.2, 0.24, 0.22)), Props.TIMBER, Vector3(0, h - 0.32, front + 0.06))
	for b in n_bays:
		var cx := -length * 0.5 + (b + 0.5) * bw
		if b > 0:
			k.part(root, k.box(Vector3(0.18, h - 0.5, 0.16)), Props.TIMBER, Vector3(cx - bw * 0.5, (h - 0.5) * 0.5 + 0.2, front + 0.05))
		if b == door_bay:
			k.door(root, Vector3(cx, 0, front), 2.5)
		else:
			k.window(root, Vector3(cx, 1.5, front), Vector2(minf(bw * 0.45, 1.1), 1.1), _rng.randf() < 0.6)
			# Shop board under the window.
			k.part(root, k.box(Vector3(minf(bw - 0.4, 1.9), 0.12, 0.45)), Props.WOOD, Vector3(cx, 0.75, front + 0.22))
	if not is_nan(lantern_x):
		k.wall_lantern(root, Vector3(lantern_x, 2.4, front))


## A market stall like Props.market_stall(), but its awning stripes are
## `stripe` and cream (red stays the plague's colour). Collision on its counter.
func _stall(pos: Vector3, rot_y: float, _stripe: Color) -> void:
	if MedievalAssets.has_asset(&"stall"):
		MedievalAssets.spawn(self, &"stall", pos, Vector3(0, rot_y, 0), Vector3.ONE * 1.45, &"wood")
		var basis := Basis(Vector3.UP, deg_to_rad(rot_y))
		_add_box(Transform3D(basis, pos), Vector3(2.8, 1.5, 1.5))
		return
	var k := _k
	var root := k.node(self, pos, rot_y)
	k.part(root, k.box(Vector3(3.0, 1.0, 1.3)), Props.WOOD, Vector3(0, 0.5, 0.0))
	var basis2 := Basis(Vector3.UP, deg_to_rad(rot_y))
	_add_box(Transform3D(basis2, pos), Vector3(3.2, 1.2, 1.6))


## A heap of grain sacks (no collision: townsfolk wade past).
func _sacks(pos: Vector3) -> void:
	if MedievalAssets.has_asset(&"bag"):
		for i in 3:
			var p := pos + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.4, 0.4))
			MedievalAssets.spawn(self, &"bag", p, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * 0.9, &"wood")
		return
	for i in 3:
		var p := pos + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.3, 0.3))
		_k.part(self, _k.sphere(0.32, 8), Props.CLOTH, p + Vector3(0, 0.26, 0), Vector3(0, _rng.randf() * 90.0, 0), Vector3(1.0, 0.8, 0.8))


func _lamp(pos: Vector3) -> void:
	_k.lamp_post(self, pos)
	_add_cylinder(pos, 0.15, 3.0)
	_blockers.append({"xf": Transform3D(Basis(), pos), "half": Vector2(0.25, 0.25)})


## A low stone wall of `length` centred on pos, along local X (rot_y yaw), with
## cap stones; it blocks.
func _stone_wall(pos: Vector3, length: float, rot_y: float) -> void:
	var root := _k.node(self, pos, rot_y)
	_k.part(root, _k.box(Vector3(length, 0.9, 0.45)), Props.STONE, Vector3(0, 0.45, 0))
	var n := maxi(2, int(length / 0.8))
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * length / n
		_k.part(root, _k.box(Vector3(length / n - 0.06, 0.16, 0.55)), Props.STONE, Vector3(x, 0.98, 0))
	_add_box(Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos), Vector3(length, 1.1, 0.5))
	var along := Basis(Vector3.UP, deg_to_rad(rot_y)) * Vector3(length * 0.5 - 0.4, 0, 0)
	_perch_lines.append([pos - along + Vector3(0, 1.06, 0), pos + along + Vector3(0, 1.06, 0)])


## Merges the prop kit's thousands of small parts (performance): each house
## into one mesh per material under its own root (so the cutaway still
## squashes it), the rest of the scenery per material and BATCH_CELL cell.
## `keep` are the scene's own nodes, left alone.
func _batch_meshes(keep: Array[Node]) -> void:
	if OS.get_cmdline_user_args().has("--no-batch"):
		return  # every prop part stays a node of its own (before/after checks)
	var skip: Array[Node] = keep.duplicate()
	for h in _houses:
		var root: Node3D = h["root"]
		MeshBatcher.merge(root)
		skip.append(root)
	MeshBatcher.merge(self, skip, BATCH_CELL)


# ---------------------------------------------------------------------- collision
## Box collider standing on the ground; `xf` is its ground centre and yaw.
## It goes on `body`, or on the shared world collision body.
func _add_box(xf: Transform3D, size: Vector3, body: StaticBody3D = null) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(xf.basis, xf.origin + Vector3(0, size.y * 0.5, 0))
	(body if body else _collision).add_child(cs)
	_blockers.append({"xf": xf, "half": Vector2(size.x, size.z) * 0.5})


func _add_cylinder(pos: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos + Vector3(0, height * 0.5, 0)
	_collision.add_child(cs)


## Four walls just outside the District rectangle.
func _add_bounds() -> void:
	var t := 1.0
	var h := 4.0
	var c := bounds.get_center()
	var s := bounds.size
	var walls := [
		[Vector3(c.x, 0, bounds.position.y - t * 0.5), Vector3(s.x + 2 * t, h, t)],
		[Vector3(c.x, 0, bounds.end.y + t * 0.5), Vector3(s.x + 2 * t, h, t)],
		[Vector3(bounds.position.x - t * 0.5, 0, c.y), Vector3(t, h, s.y)],
		[Vector3(bounds.end.x + t * 0.5, 0, c.y), Vector3(t, h, s.y)],
	]
	for w in walls:
		var shape := BoxShape3D.new()
		shape.size = w[1]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = w[0] + Vector3(0, h * 0.5, 0)
		_collision.add_child(cs)


## True if a circle of `radius` at p overlaps no footprint and lies inside the bounds.
func is_free(p: Vector3, radius: float) -> bool:
	if not bounds.grow(-radius - 0.3).has_point(Vector2(p.x, p.z)):
		return false
	for b in _blockers:
		var xf: Transform3D = b["xf"]
		var half: Vector2 = b["half"]
		var l := xf.affine_inverse() * p
		if absf(l.x) < half.x + radius and absf(l.z) < half.y + radius:
			return false
	return true


## The visual root of the house a StaticBody3D belongs to, or null.
func house_visual(body: Node) -> Node3D:
	return _house_by_body.get(body) as Node3D


# ---------------------------------------------------------------------- cutaway
func _process(delta: float) -> void:
	_debug_tick(delta)
	if not _cutaway or _houses.is_empty():
		return
	_cut_left -= delta
	if _cut_left > 0.0:
		return
	var step := CUT_INTERVAL - _cut_left
	_cut_left = CUT_INTERVAL
	_update_cutaway(step)


## Squashes every house that hides the Lead Rat from the camera (tested on a
## few points of the rat against each house's occluder box), and stands a
## house back up once it has been clear for CUT_RESTORE_DELAY.
func _update_cutaway(step: float) -> void:
	if not is_instance_valid(_rat):
		return
	var eye := _camera.global_position
	var r := _rat.global_position
	var points: Array[Vector3] = [r + Vector3(0, 0.3, 0), r + Vector3(0.3, 0.15, 0),
		r + Vector3(-0.3, 0.15, 0)]
	for h in _houses:
		var inv: Transform3D = h["inv"]
		var a := inv * eye
		var hides := false
		for p in points:
			var lp := inv * p
			for box: Array in h["boxes"]:
				if _segment_hits_box(a, lp, box[0], box[1]):
					hides = true
					break
			if hides:
				break
		if hides:
			h["clear"] = 0.0
			if not h["cut"]:
				h["cut"] = true
				_tween_house(h, CUT_SCALE, CUT_DOWN_TIME)
		elif h["cut"]:
			h["clear"] += step
			if h["clear"] >= CUT_RESTORE_DELAY:
				h["cut"] = false
				_tween_house(h, 1.0, CUT_UP_TIME)


func _tween_house(h: Dictionary, scale_y: float, time: float) -> void:
	var old: Tween = h["tween"]
	if old and old.is_valid():
		old.kill()
	var root: Node3D = h["root"]
	var tw := root.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(root, "scale:y", scale_y, time)
	h["tween"] = tw


## Slab test: does the segment a-b pass through the box centre +- half?
static func _segment_hits_box(a: Vector3, b: Vector3, centre: Vector3, half: Vector3) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		var lo := centre[i] - half[i]
		var hi := centre[i] + half[i]
		if absf(d[i]) < 0.000001:
			if a[i] < lo or a[i] > hi:
				return false
			continue
		var ta := (lo - a[i]) / d[i]
		var tb := (hi - a[i]) / d[i]
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


# ---------------------------------------------------------------------- actors
func _add_round_director() -> void:
	if not ResourceLoader.exists(ROUND_DIRECTOR_SCRIPT):
		push_warning("District: %s missing, no RoundDirector" % ROUND_DIRECTOR_SCRIPT)
		return
	var director := Node.new()
	director.set_script(load(ROUND_DIRECTOR_SCRIPT))
	director.name = "RoundDirector"
	# Before add_child: the director reads round_length in its _ready.
	director.set("round_length", Run.stat("round_length"))
	add_child(director)


func _add_hud() -> void:
	if not ResourceLoader.exists(HUD_SCENE):
		push_warning("District: %s missing, no HUD" % HUD_SCENE)
		return
	var hud := (load(HUD_SCENE) as PackedScene).instantiate()
	hud.name = "HUD"
	add_child(hud)


func _spawn_townsfolk() -> void:
	if not ResourceLoader.exists(TOWNSPERSON_SCENE):
		push_warning("District: %s missing, no townsfolk" % TOWNSPERSON_SCENE)
		return
	var scene := load(TOWNSPERSON_SCENE) as PackedScene
	var container := Node3D.new()
	container.name = "Townsfolk"
	add_child(container)
	_spawner.person_scene = scene
	_spawner.container = container
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < townsfolk_count and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(bounds.position.x, bounds.end.x), 0,
			rng.randf_range(bounds.position.y, bounds.end.y))
		if not is_free(p, 0.7) or p.distance_to(_rat.global_position) < 4.0:
			continue
		var crowded := false
		for q in placed:
			if p.distance_to(q) < 1.6:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		var person := scene.instantiate() as Node3D
		var half := wander_size * 0.5
		person.set("wander_bounds", Rect2(p.x - half, p.z - half, wander_size, wander_size).intersection(bounds.grow(-1.0)))
		person.set("rng_seed", 1000 + placed.size())
		person.position = p
		var home := _nearest_house(p)
		person.set("home", home)
		_spawner.apply_def(person, _spawner.resident_def(_def_rng))
		container.add_child(person)
		if home:
			home.add_resident(person)
	var outdoors := placed.size()
	var indoors := 0
	if _residents:
		for h in _houses:
			var house: House = h["house"]
			var n := rng.randi_range(residents_min, residents_max)
			for i in n:
				_spawn_resident(scene, container, house, 2000 + indoors)
				indoors += 1
	if _print_stats:
		var homes := 0
		for h in _houses:
			if not (h["house"] as House).residents.is_empty():
				homes += 1
		print("district: houses=%d with_residents=%d residents_indoors=%d outdoor=%d population=%d" % [
			_houses.size(), homes, indoors, outdoors, indoors + outdoors])


## A resident of `house`, spawned already inside it.
func _spawn_resident(scene: PackedScene, container: Node3D, house: House, seed_value: int) -> void:
	var person := scene.instantiate() as Node3D
	var p := house.door_position + house.door_normal * 0.8
	var half := wander_size * 0.5
	person.set("wander_bounds", Rect2(p.x - half, p.z - half, wander_size, wander_size).intersection(bounds.grow(-1.0)))
	person.set("rng_seed", seed_value)
	person.set("home", house)
	person.position = p
	_spawner.apply_def(person, _spawner.resident_def(_def_rng))
	container.add_child(person)
	house.add_resident(person)
	if person.has_method("start_indoors"):
		person.call("start_indoors", house)


## The house whose door is nearest to `p`, or null (the Spawner uses it too).
func nearest_house(p: Vector3) -> House:
	return _nearest_house(p)


func _nearest_house(p: Vector3) -> House:
	var best: House = null
	var best_d := INF
	for h in _houses:
		var house: House = h["house"]
		var d := p.distance_squared_to(house.door_position)
		if d < best_d:
			best_d = d
			best = house
	return best


# ---------------------------------------------------------------------- spawner
func _setup_spawner() -> void:
	_def_rng.seed = spawn_seed + 31 * Run.year
	_spawner.district = self
	_spawner.set_gates(gate_points())


## The street ends at the District bounds where people (and the Exterminator)
## come in: the Spawner's markers for the slums, the street ends for the
## merchant quarter.
func gate_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for z: float in MERCHANT_GATE_Z:
		out.append(Vector3(bounds.position.x + 1.8, 0, z))
		out.append(Vector3(bounds.end.x - 1.8, 0, z))
	out.append(Vector3(0, 0, bounds.position.y + 1.8))
	out.append(Vector3(0, 0, bounds.end.y - 1.8))
	return out


## --fill: spawn up to the Spawner's cap at once (performance tests).
func _fill_street() -> void:
	var guard := 0
	while _spawner.alive_outdoors() < Spawner.CAP and guard < 200:
		guard += 1
		_spawner.spawn_one()


## Visible mesh instances per top-level child (--perf, once).
func _print_mesh_census() -> void:
	var out: Array[String] = []
	for c: Node in get_children():
		var n := 0
		for m: Node in c.find_children("*", "GeometryInstance3D", true, false):
			if (m as Node3D).is_visible_in_tree():
				n += 1
		if n > 0:
			out.append("%s=%d" % [c.name, n])
	print("perf: meshes ", " ".join(out))


## --perf every 2 s; the Spawner's counts every 15 s with --dev / --bot.
func _debug_tick(delta: float) -> void:
	if _perf:
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var pr := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_perf_acc += Vector4(ph, 0.0, pr, 0.0)
		_perf_max_ph = maxf(_perf_max_ph, ph)
		_perf_frames += 1
		_perf_left -= delta
		if _perf_left <= 0.0:
			if _perf_census:
				_perf_census = false
				_print_mesh_census()
			_perf_left += 2.0
			var frames := maxf(1.0, _perf_frames)
			print("perf: fps=%d frame=%.1fms process_avg=%.1fms physics_avg=%.1fms physics_max=%.1fms rats=%d townsfolk=%d indoors=%d corpses=%d draw_calls=%d objects=%d" % [
				Engine.get_frames_per_second(),
				1000.0 / maxf(1.0, Engine.get_frames_per_second()),
				_perf_acc.z / frames, _perf_acc.x / frames, _perf_max_ph,
				_colony.adult_count + _colony.pup_count,
				get_tree().get_nodes_in_group("townsfolk").size(),
				get_tree().get_nodes_in_group("indoors").size(),
				get_tree().get_nodes_in_group("corpses").size(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			_perf_acc = Vector4.ZERO
			_perf_max_ph = 0.0
			_perf_frames = 0
	if _print_stats:
		_spawn_log_left -= delta
		if _spawn_log_left <= 0.0:
			_spawn_log_left += 15.0
			print(_spawner.counts_text())


# ---------------------------------------------------------------------- run stats
## Reads the Upgrade Tree stats from the Run before anything else spawns.
## Debug flags parsed afterwards (--start-colony, --pups, --god) win.
func _apply_run_stats() -> void:
	_rat.set("max_speed", Run.stat("rat_speed"))
	_colony.feed_time = maxf(0.25, Run.stat("feed_time"))
	_colony.pup_maturity = maxf(2.0, Run.stat("pup_maturity"))
	_colony.extra_pups_per_feed = maxi(0, int(round(Run.stat("extra_pups_per_feed"))))
	# Followers spawn deferred, so this lands before the Colony's start spawn.
	_colony.start_adults = Run.start_colony_size()
	_colony.set_bite_stats(Run.stat("bite_range"), maxf(0.3, Run.stat("bite_cooldown")),
		Run.stat("bite_chunk"), Run.stat("bite_rate_bonus"))
	var lb := _rat.get_node_or_null("BiteComponent") as BiteComponent
	if lb != null:
		lb.cleave_targets = maxi(1, int(round(Run.stat("lead_cleave"))))
	_lethality = Run.stat("lethality")
	_colony.hide_unlocked = Run.is_unlocked("unlock_hide")
	_colony.raid_unlocked = Run.is_unlocked("unlock_raid")
	_colony.hide_duration = Run.stat("hide_duration")
	_colony.hide_cooldown = Run.stat("hide_cooldown")
	_colony.raid_size = int(round(Run.stat("raid_size")))
	_colony.raid_duration = Run.stat("raid_duration")
	_colony.raid_cooldown = Run.stat("raid_cooldown")
	if Run.is_unlocked("unlock_fleas"):
		_fleas = FleasScript.new()
		_fleas.set("colony", _colony)
		_fleas.set("radius", Run.stat("flea_radius"))
		_fleas.set("chance", Run.stat("flea_chance"))
		_fleas.set("interval", Run.stat("flea_interval"))
		if OS.get_cmdline_user_args().has("--flea-test"):
			_fleas.set("chance", 1.0)   # every roll hits, 4x a second: specks for screenshots
			_fleas.set("interval", 0.25)
		add_child(_fleas)
	# Every Infection that enters the tree from now on, the later spawns too.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	var inf := n as InfectionComponent
	if inf == null or inf.has_meta("run_lethality"):
		return
	inf.set_meta("run_lethality", _lethality)
	inf.base_rate *= _lethality


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _print_run_stats() -> void:
	print("run: year=%d pestilence=%d bones=%d rounds=%d last_colony=%d levels=%s" % [
		Run.year, Run.pestilence, Run.bones, Run.rounds_played, Run.last_colony_size, Run.levels])
	var bite := _rat.get_node("BiteComponent") as BiteComponent
	var director := get_tree().get_first_node_in_group("round_director")
	print("run stats applied: rat_speed=%.2f bite range=%.2f cooldown=%.2f chunk=%.2f rate_bonus=%.2f feed_time=%.2f pup_maturity=%.2f start_adults=%d lethality=%.2f round_length=%s" % [
		_rat.get("max_speed"), bite.bite_range, bite.cooldown, bite.chunk, bite.rate_bonus,
		_colony.feed_time, _colony.pup_maturity, _colony.start_adults, _lethality,
		director.get("round_length") if director else "-"])
	print("run stats applied: fleas=%s visual_stage=%d decor=%s" % [_fleas != null, visual_stage, _decor_placed])
	print("run stats applied: hide=%s raid=%s hide_duration=%.1f hide_cooldown=%.1f raid_size=%d raid_duration=%.1f raid_cooldown=%.1f" % [
		_colony.hide_unlocked, _colony.raid_unlocked, _colony.hide_duration, _colony.hide_cooldown,
		_colony.raid_size, _colony.raid_duration, _colony.raid_cooldown])


# ---------------------------------------------------------------------- raid & deliberate hide
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hide") and not event.is_echo() and _colony.hide_unlocked:
		if _colony.try_hide():
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("raid") or not _colony.raid_unlocked:
		return
	var h: House = null
	var mouse := event as InputEventMouseButton
	if mouse:
		h = house_at_screen(mouse.position)
	elif is_instance_valid(_rat):
		h = _colony.nearest_house(_rat.global_position, RAID_PAD_RANGE)
	if h and _colony.raid(h):
		get_viewport().set_input_as_handled()


## The house under a screen point: a ray against layer 1 for its body, or,
## for a click on a roof (no collision up there), its occluder boxes.
func house_at_screen(screen: Vector2) -> House:
	var from := _camera.project_ray_origin(screen)
	var to := from + _camera.project_ray_normal(screen) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] is House:
		return hit["collider"] as House
	var best: House = null
	var best_d := INF
	for h in _houses:
		var inv: Transform3D = h["inv"]
		var a := inv * from
		var b := inv * to
		for box: Array in h["boxes"]:
			if _segment_hits_box(a, b, box[0], box[1]):
				var house: House = h["house"]
				var d := from.distance_squared_to(house.global_position)
				if d < best_d:
					best_d = d
					best = house
				break
	return best


# ---------------------------------------------------------------------- debug
## --raid-test / --hide-test / --kill-house, ~1 s into the Round.
func _run_test() -> void:
	await get_tree().create_timer(1.0, false).timeout
	var p := _rat.global_position
	match _test:
		"raid":
			var h := _colony.nearest_house(p, 30.0, true)
			print("test: raid %s -> %s" % [h.name if h else "-", _colony.raid(h)])
		"hide":
			var h := _colony.nearest_house(p, 30.0, true)
			if h:
				_rat.global_position = h.door_position
				_colony.hide_in(h)
		"knock":
			var lead_before := _rat.global_position
			var n := 0
			for r: Node in get_tree().get_nodes_in_group("rats"):
				if r.has_method("knockback"):
					r.call("knockback", p + Vector3(1.0, 0.0, 0.0), 3.0)
					n += 1
			await get_tree().create_timer(0.5, false).timeout
			print("test: knockback on %d rats, lead moved %.2f u, hits_left=%s, adults=%d pups=%d deaths=%d" % [
				n, _rat.global_position.distance_to(lead_before), _rat.get("hits_left"),
				_colony.adult_count, _colony.pup_count, _colony.deaths])
		"kill":
			var h := _nearest_house(p)
			if h:
				for r in h.residents:
					var inf := r.get_node_or_null("Infection") as InfectionComponent
					if inf:
						inf.bite(100.0, 0.0)
				print("test: killed %d residents of %s, dead house=%s" % [h.residents.size(), h.name, h.is_dead_house()])



func _parse_debug_args() -> void:
	var overlay := _camera.get_node("ParchmentOverlay") as MeshInstance3D
	var overlay_material := overlay.material_override as ShaderMaterial
	var shot_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			var kv := arg.trim_prefix("--set=").split("=")
			if kv.size() == 2:
				overlay_material.set_shader_parameter(kv[0], float(kv[1]))
		elif arg == "--bot":
			_rat.set("bot_mode", true)
			_print_stats = true
			_colony.debug_print = true
		elif arg == "--dev":
			_print_stats = true
			_colony.debug_print = true
		elif arg == "--raid-test":
			_test = "raid"
		elif arg == "--hide-test":
			_test = "hide"
		elif arg == "--kill-house":
			_test = "kill"
		elif arg == "--perf":
			_perf = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif arg == "--fill":
			_fill = true
		elif arg == "--knock-test":
			_test = "knock"
		elif arg == "--no-residents":
			_residents = false
		elif arg == "--god":
			_rat.set("god_mode", true)
		elif arg == "--no-cutaway":
			_cutaway = false
		elif arg.begins_with("--start-colony="):
			_colony.start_adults = int(arg.trim_prefix("--start-colony="))
		elif arg.begins_with("--pups="):
			_colony.start_pups = int(arg.trim_prefix("--pups="))
		elif arg.begins_with("--lead-at="):
			var xz := arg.trim_prefix("--lead-at=").split(",")
			if xz.size() == 2:
				_rat.global_position = Vector3(float(xz[0]), 0.0, float(xz[1]))
				_camera.call("snap")
		elif arg == "--no-shadows":
			_sun.shadow_enabled = false
		elif arg.begins_with("--screenshot-delay="):
			_screenshot_delay = float(arg.trim_prefix("--screenshot-delay="))
		elif arg.begins_with("--screenshot="):
			shot_path = arg.trim_prefix("--screenshot=")
	if not shot_path.is_empty():
		_screenshot(shot_path)


func _screenshot(path: String) -> void:
	await get_tree().create_timer(_screenshot_delay, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved to ", path)
	print("colony: adults=%d (incl. Lead Rat) pups=%d births=%d matured=%d deaths=%d lead_hits_left=%s" % [
		_colony.adult_count, _colony.pup_count, _colony.births, _colony.maturings, _colony.deaths,
		_rat.get("hits_left")])
	_print_house_state()
	print(_spawner.counts_text())
	get_tree().quit()


## Hide / Raid / house counts (screenshots, --dev).
func _print_house_state() -> void:
	var dead := 0
	var inside := 0
	for h in _houses:
		var house: House = h["house"]
		if house.is_dead_house():
			dead += 1
		inside += house.occupants.size()
	if _fleas:
		print("fleas: hits=%d" % int(_fleas.get("hits")))
	print("houses: dead=%d occupants_total=%d | colony hidden=%s time_left=%.1f hides=%d raids=%d raiders_inside=%d raid_cooldown=%.1f hidden_rats=%d rats=%d" % [
		dead, inside, _colony.is_hidden, _colony.hidden_time_left, _colony.hides, _colony.raids,
		_colony.raiders_inside, _colony.raid_cooldown_left,
		get_tree().get_nodes_in_group("hidden_rats").size(), get_tree().get_nodes_in_group("rats").size()])
