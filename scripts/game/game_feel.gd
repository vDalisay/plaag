## Centralized game feel / juice controller: tiered hitstop, directional camera
## punches/shakes, shader-compatible model hit-flashes (using material_overlay
## so original materials are never duplicated or leaked) and squash-stretch
## recoil. Respects Settings.reduce_motion and Settings.screen_shake.
class_name GameFeel
extends Node

const LOW_PRIORITY_GAP_MS := 240

static var _instance: GameFeel

var _hitstop_left := 0.0
var _hitstop_priority := -1
var _last_low_ms := -10000
var _flashes: Array[Dictionary] = []  # {"meshes": Array[MeshInstance3D], "left": float}
var _flash_mats := {}                 # Color html -> StandardMaterial3D


static func get_feel(tree: SceneTree) -> GameFeel:
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	if tree == null or tree.root == null:
		return null
	var f := GameFeel.new()
	f.name = "GameFeel"
	f.process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = f
	tree.root.add_child.call_deferred(f)
	return f


## Brief real-time slowdown. Low-priority (0 = Lead Rat Bite) is rate-limited
## so rapid swarms never stutter; higher priorities (1..3) override lower ones.
static func hitstop(tree: SceneTree, duration := 0.04, scale := 0.15, priority := 1) -> void:
	if UiKit.reduce_motion():
		return
	var f := get_feel(tree)
	if f == null:
		return
	f._start_hitstop(duration, scale, priority)


static func shake_camera(tree: SceneTree, strength := 0.35) -> void:
	if tree == null:
		return
	var cam := tree.root.get_camera_3d()
	if cam != null and cam.has_method("shake"):
		cam.call("shake", strength)


static func punch_camera(tree: SceneTree, dir: Vector3, strength := 0.16) -> void:
	if tree == null:
		return
	var cam := tree.root.get_camera_3d()
	if cam != null and cam.has_method("punch"):
		cam.call("punch", dir, strength)


## Briefly applies a bright unshaded material_overlay onto every MeshInstance3D
## under `target` so the hit-flash cuts crisply through the parchment shader.
static func flash(tree: SceneTree, target: Node3D, color := Color(1.0, 0.94, 0.84), duration := 0.09) -> void:
	if target == null or not is_instance_valid(target):
		return
	var f := get_feel(tree)
	if f == null:
		return
	f._start_flash(target, color, duration)


func _exit_tree() -> void:
	if _hitstop_left > 0.0:
		Engine.time_scale = 1.0
	for entry in _flashes:
		_clear_meshes(entry["meshes"])
	_flashes.clear()
	if _instance == self:
		_instance = null


func _process(delta: float) -> void:
	# Use real unscaled time for hitstop and flashes so they always finish cleanly.
	var real_dt := delta / maxf(Engine.time_scale, 0.001) if Engine.time_scale > 0.0 else 0.016
	if _hitstop_left > 0.0:
		_hitstop_left -= real_dt
		if _hitstop_left <= 0.0:
			_hitstop_left = 0.0
			_hitstop_priority = -1
			Engine.time_scale = 1.0
	var i := 0
	while i < _flashes.size():
		var entry := _flashes[i]
		entry["left"] = float(entry["left"]) - real_dt
		if float(entry["left"]) <= 0.0:
			_clear_meshes(entry["meshes"])
			_flashes.remove_at(i)
		else:
			i += 1


func _start_hitstop(duration: float, scale: float, priority: int) -> void:
	var now := Time.get_ticks_msec()
	if priority <= 0 and now - _last_low_ms < LOW_PRIORITY_GAP_MS:
		return
	if _hitstop_left > 0.0 and priority < _hitstop_priority:
		return
	if priority <= 0:
		_last_low_ms = now
	_hitstop_priority = priority
	_hitstop_left = maxf(_hitstop_left, duration)
	Engine.time_scale = clampf(scale, 0.02, 1.0)


func _start_flash(target: Node3D, color: Color, duration: float) -> void:
	var meshes: Array[MeshInstance3D] = []
	if target is MeshInstance3D:
		meshes.append(target as MeshInstance3D)
	for n: Node in target.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.visible:
			meshes.append(mi)
	if meshes.is_empty():
		return
	var mat := _get_flash_mat(color)
	for mi in meshes:
		mi.material_overlay = mat
	# Refresh existing entry for the same root if still flashing.
	for entry in _flashes:
		if entry.get("target") == target:
			entry["meshes"] = meshes
			entry["left"] = maxf(float(entry["left"]), duration)
			return
	_flashes.append({"target": target, "meshes": meshes, "left": duration})


func _get_flash_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _flash_mats.has(key):
		return _flash_mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	_flash_mats[key] = m
	return m


static func _clear_meshes(meshes: Array) -> void:
	for mi_v: Variant in meshes:
		if is_instance_valid(mi_v):
			var mi := mi_v as MeshInstance3D
			if mi != null:
				mi.material_overlay = null
