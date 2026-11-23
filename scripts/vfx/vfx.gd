## The event VFX of a District (docs/dev/vfx_contract.md, Agent A): one Node3D
## in group "vfx" under the current scene, made on first use by get_vfx().
## Everything is pooled, opaque geometry that the parchment post-process inks:
##   burst(kind, pos, dir, scale, extra): one-shot particles (vfx_recipes.gd
##     lists the kinds), drawn by three CPU-updated MultiMesh pools: pale /
##     ink / red / green spheres (puffs, droplets), boxes (strokes, ticks,
##     straw, chips) and AMBER emissive cones (flame tongues);
##   decal(kind, pos, rot, size, life): flat ground marks (vfx_decals.gd):
##     blot, splat, drop, crack, scorch;
##   attach(kind, node) / detach(kind, node): flies on a node (vfx_flies.gd):
##     "flies" round a sick head, "corpse_flies" on a body;
##   disturb(point, radius): emits `disturbance` (crows scatter; Agent B).
## Callers use the static helpers (play, mark, attach_to, detach_from,
## disturb_at), which do nothing without a District (the style demo, the
## title). Effects run on the scaled delta, so the hit-stop and every pause
## freeze them.
## Settings.effects_level: 1 Full, 0 Reduced (pools at half size, bursts at
## half count, no flies, no run dust). Debug flags (after `--`):
## --vfx-test plays every kind in a ring round the Lead Rat, one every 0.4 s,
## looping (prints "VFX <kind>"); --vfx-grid plays every kind at once on a
## grid round the Lead Rat (8 a row, 3 u apart, in TEST_KINDS order) every
## GRID_INTERVAL s, for screenshots (--vfx-grid-at=<s>: once, <s> after the
## Round starts; --vfx-kinds=a,b,c plays only those, in one row along X);
## --effects=reduced (read by Settings); --vfx-perf prints the live counts and
## the CPU time of the update every 2 s; --no-vfx turns every effect off (A/B
## performance checks).
extends Node3D

const Particles := preload("res://scripts/vfx/vfx_particles.gd")
const Decals := preload("res://scripts/vfx/vfx_decals.gd")
const Flies := preload("res://scripts/vfx/vfx_flies.gd")
const Meshes := preload("res://scripts/vfx/vfx_meshes.gd")
const Recipes := preload("res://scripts/vfx/vfx_recipes.gd")
const SCRIPT_PATH := "res://scripts/vfx/vfx.gd"

## Pool sizes at Full (Reduced halves them).
const PUFF_CAP := 720
const STROKE_CAP := 320
const FLAME_CAP := 96
const TEST_INTERVAL := 0.4
const TEST_RADIUS := 3.2
const GRID_INTERVAL := 1.5
const GRID_STEP := 3.0

signal disturbance(point: Vector3, radius: float)

static var _instance: Node3D

var puffs: Particles
var strokes: Particles
var flames: Particles
var decals: Decals
var flies: Flies
var recipes: Recipes
var full := true
## Camera right / up (ticks and stars face the camera).
var cam_right := Vector3.RIGHT
var cam_up := Vector3.UP

var _paved: Array[Rect2] = []
var _paved_all := false
var _test := false
var _grid := false
var _grid_kinds: Array[StringName] = []
var _test_left := 1.0
var _test_i := 0
var _built := false
var _perf := false
var _perf_us := 0
var _perf_frames := 0
var _perf_left := 2.0


# ---------------------------------------------------------------------- access
## The District's Vfx node, made under the current scene on first use; null
## (and every caller does nothing) when the scene has no RoundDirector or
## Lead Rat.
static func get_vfx(tree: SceneTree) -> Node:
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	if tree == null or tree.current_scene == null or OS.get_cmdline_user_args().has("--no-vfx"):
		return null
	if tree.get_first_node_in_group("round_director") == null and tree.get_first_node_in_group("lead_rat") == null:
		return null
	var scene := tree.current_scene
	var v: Node3D = (load(SCRIPT_PATH) as GDScript).new()
	v.name = "Vfx"
	v.call("_build", scene)
	_instance = v
	if scene.is_node_ready():
		scene.add_child(v)
	else:
		scene.add_child.call_deferred(v)
	return v


static func play(tree: SceneTree, kind: StringName, pos: Vector3, dir := Vector3.ZERO, scale := 1.0, extra := 0.0) -> void:
	var v := get_vfx(tree)
	if v != null:
		v.call("burst", kind, pos, dir, scale, extra)


static func mark(tree: SceneTree, kind: StringName, pos: Vector3, rot: float, size: float, life: float) -> void:
	var v := get_vfx(tree)
	if v != null:
		v.call("decal", kind, pos, rot, size, life)


static func attach_to(tree: SceneTree, kind: StringName, node: Node3D, offset := Vector3.ZERO) -> void:
	var v := get_vfx(tree)
	if v != null:
		v.call("attach", kind, node, offset)


static func detach_from(_tree: SceneTree, kind: StringName, node: Node3D) -> void:
	if is_instance_valid(_instance):
		_instance.call("detach", kind, node)


static func disturb_at(tree: SceneTree, point: Vector3, radius: float) -> void:
	var v := get_vfx(tree)
	if v != null:
		v.call("disturb", point, radius)


# ---------------------------------------------------------------------- setup
func _build(scene: Node) -> void:
	if _built:
		return
	_built = true
	add_to_group("vfx")
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.vertex_color_is_srgb = true
	vc.albedo_color = Color.WHITE
	vc.roughness = 1.0
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Recipes.AMBER
	fire.roughness = 1.0
	fire.emission_enabled = true
	fire.emission = Recipes.AMBER
	fire.emission_energy_multiplier = 2.6
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Recipes.INK
	ink.roughness = 1.0
	puffs = Particles.new(self, "Puffs", Meshes.puff(), vc, PUFF_CAP, false)
	strokes = Particles.new(self, "Strokes", Meshes.stroke(), vc, STROKE_CAP, true)
	flames = Particles.new(self, "Flames", Meshes.flame(), fire, FLAME_CAP, false)
	decals = Decals.new(self)
	flies = Flies.new(self, ink, Meshes.puff())
	recipes = Recipes.new(self)
	_read_ground(scene)


func _ready() -> void:
	_build(get_parent())
	_test = OS.get_cmdline_user_args().has("--vfx-test")
	_grid = OS.get_cmdline_user_args().has("--vfx-grid")
	_perf = OS.get_cmdline_user_args().has("--vfx-perf")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfx-kinds="):
			for k in a.trim_prefix("--vfx-kinds=").split(",", false):
				_grid_kinds.append(StringName(k))
		if a.begins_with("--vfx-grid-at="):
			get_tree().create_timer(float(a.trim_prefix("--vfx-grid-at=")), true).timeout.connect(_play_grid)
	var s := get_node_or_null("/root/Settings")
	if s != null and s.has_signal("changed"):
		s.connect("changed", _apply_settings)
	_apply_settings()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _apply_settings() -> void:
	var s := get_node_or_null("/root/Settings")
	var lvl: Variant = s.get("effects_level") if s != null else null
	full = lvl == null or int(lvl) >= 1
	puffs.set_full(full)
	strokes.set_full(full)
	flames.set_full(full)
	decals.set_full(full)
	flies.enabled = full


## Where the ground is paved (decals sit on the cobbles), duck-typed from the
## District: the Merchant quarter is paved throughout, the Slums by stage.
func _read_ground(scene: Node) -> void:
	_paved.clear()
	_paved_all = false
	if scene == null:
		return
	if str(scene.get("layout_style")) == "merchant":
		_paved_all = true
	elif scene.has_method("slum_paving"):
		var stage: Variant = scene.get("visual_stage")
		var rects: Variant = scene.call("slum_paving", int(stage) if stage != null else 0)
		if rects is Array:
			for r: Variant in rects:
				if r is Rect2:
					_paved.append(r)


func is_paved(p: Vector3) -> bool:
	if _paved_all:
		return true
	var q := Vector2(p.x, p.z)
	for r in _paved:
		if r.has_point(q):
			return true
	return false


## Top of the ground at `p` (on the cobbles where paved, else the mud).
func ground_y(p: Vector3) -> float:
	return 0.07 if is_paved(p) else 0.012


# ---------------------------------------------------------------------- API
func burst(kind: StringName, pos: Vector3, dir := Vector3.ZERO, scale := 1.0, extra := 0.0) -> void:
	recipes.play(kind, pos, dir, scale, extra)


## A small run-dust puff behind a running animal at `pos` heading `dir`;
## only on unpaved ground and only at Full.
func run_dust(pos: Vector3, dir: Vector3, scale := 1.0) -> void:
	if full and not is_paved(pos):
		recipes.play(&"run_dust", pos, dir, scale, 0.0)


static func run_dust_at(tree: SceneTree, pos: Vector3, dir: Vector3, scale := 1.0) -> void:
	var v := get_vfx(tree)
	if v != null:
		v.call("run_dust", pos, dir, scale)


## A ground mark: `kind` is blot, splat, drop, crack or scorch.
func decal(kind: StringName, pos: Vector3, rot: float, size: float, life: float) -> void:
	recipes.mark(kind, pos, rot, size, life)


func attach(kind: StringName, node: Node3D, offset := Vector3.ZERO) -> void:
	if node == null:
		return
	match kind:
		&"flies":
			flies.attach(node, Flies.Mode.HEAD, randi_range(2, 4), offset)
		&"corpse_flies":
			flies.attach(node, Flies.Mode.CORPSE, randi_range(3, 5), offset)


func detach(_kind: StringName, node: Node3D) -> void:
	flies.detach(node)


func disturb(point: Vector3, radius: float) -> void:
	disturbance.emit(point, radius)


## Half the count at Reduced (at least 1).
func count(n: int) -> int:
	return n if full else maxi(1, (n + 1) / 2)


# ---------------------------------------------------------------------- update
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cam_right = cam.global_basis.x
		cam_up = cam.global_basis.y
	var t0 := Time.get_ticks_usec() if _perf else 0
	puffs.update(delta)
	strokes.update(delta)
	flames.update(delta)
	decals.update(delta)
	flies.update(delta)
	if _perf:
		_perf_us += Time.get_ticks_usec() - t0
		_perf_frames += 1
		_perf_left -= delta
		if _perf_left <= 0.0:
			_perf_left = 2.0
			print("vfx: update=%.2fms puffs=%d strokes=%d flames=%d decals=%d flies=%d" % [
				_perf_us / 1000.0 / maxf(1.0, _perf_frames), puffs.n, strokes.n, flames.n, decals.count(), flies.count()])
			_perf_us = 0
			_perf_frames = 0
	if _test or _grid:
		_update_test(delta)


func _update_test(delta: float) -> void:
	_test_left -= delta
	if _test_left > 0.0:
		return
	_test_left = GRID_INTERVAL if _grid else TEST_INTERVAL
	var lead := get_tree().get_first_node_in_group("lead_rat") as Node3D
	var c := lead.global_position if lead != null else Vector3.ZERO
	var kinds := Recipes.TEST_KINDS
	if _grid:
		_play_grid()
		return
	var kind: StringName = kinds[_test_i % kinds.size()]
	var a := TAU * float(_test_i % kinds.size()) / float(kinds.size())
	_test_i += 1
	var out := Vector3(sin(a), 0.0, cos(a))
	var p := c + out * TEST_RADIUS
	p.y = 0.0
	print("VFX ", kind)
	_test_play(kind, p, out)


## Every kind at once on a grid round the Lead Rat (TEST_KINDS order, 8 a row).
func _play_grid() -> void:
	var lead := get_tree().get_first_node_in_group("lead_rat") as Node3D
	var c := lead.global_position if lead != null else Vector3.ZERO
	print("VFX grid")
	if not _grid_kinds.is_empty():
		for i in _grid_kinds.size():
			var at := c + Vector3((float(i) - _grid_kinds.size() * 0.5) * GRID_STEP, 0.0, 0.0)
			_test_play(_grid_kinds[i], at, Vector3(0.3, 0, 1))
		return
	var kinds := Recipes.TEST_KINDS
	for i in kinds.size():
		var cell := c + Vector3((float(i % 8) - 3.5) * GRID_STEP, 0.0, (float(i / 8) - 1.5) * GRID_STEP)
		_test_play(kinds[i], cell, Vector3(1, 0, 0.3))


func _test_play(kind: StringName, p: Vector3, out: Vector3) -> void:
	if kind == &"flies":
		var dummy := Node3D.new()
		dummy.name = "VfxTestFlies"
		add_child(dummy)
		dummy.global_position = p + Vector3(0, -1.6, 0)
		attach(&"flies", dummy)
		get_tree().create_timer(3.0, false).timeout.connect(dummy.queue_free)
		return
	burst(kind, p, out, 1.0, 0.0)
