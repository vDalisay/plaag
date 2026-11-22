## Builds a throw-away medieval square out of primitive meshes so the parchment
## shader can be judged without real assets. Replace with proper models later.
##
## The layout echoes docs/reference_style.png: a cobbled street seen from above
## at ~50 degrees, half-timbered houses crowding both edges, a roofed well at the
## top, a striped market stall on the left, townsfolk in wide-brimmed hats, a
## plague doctor in red ringed by red marks, and a wedge of rats coming in from
## the bottom left. The prop builders live in scripts/town_props.gd.
##
## Colour conventions the shader relies on: see town_props.gd / README.
extends Node3D

const Props := preload("res://scripts/town_props.gd")

## Camera framing: look-at point on the ground, pitch below the horizon,
## distance and vertical field of view.
@export var look_at_point := Vector3(0.0, 0.0, -2.5)
@export var camera_pitch_deg := 47.0
@export var camera_distance := 24.0
@export var camera_fov := 45.0
## Street edges, and how far the row houses are turned towards the viewer.
@export var street_half_width := 8.0
@export var row_turn_deg := 20.0

@onready var _camera: Camera3D = $Camera3D
@onready var _sun: DirectionalLight3D = $Sun

var _k: Props


func _ready() -> void:
	_setup_view()
	_k = Props.new(11)
	_build_town()

	# Debug helpers:  -- --set=uniform=value ... --screenshot=path.png
	var overlay_material := $Camera3D/ParchmentOverlay.material_override as ShaderMaterial
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			var kv := arg.trim_prefix("--set=").split("=")
			if kv.size() == 2:
				overlay_material.set_shader_parameter(kv[0], float(kv[1]))
		elif arg == "--no-shadows":
			_sun.shadow_enabled = false
		elif arg.begins_with("--screenshot="):
			_screenshot(arg.trim_prefix("--screenshot="))


func _setup_view() -> void:
	# Sun from the upper left and a little behind the viewer: lights the ground and
	# the right-hand facades, casts shadows to the right. A weak shadowless fill
	# from the right keeps the left facades out of the hatched band.
	_sun.rotation_degrees = Vector3(-58.0, -41.0, 0.0)
	_sun.directional_shadow_max_distance = 80.0
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-14.0, 79.0, 0.0)
	fill.light_energy = 0.5
	fill.shadow_enabled = false
	add_child(fill)

	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = camera_fov
	# In a portrait window keep the width instead, so the houses at both edges
	# stay in frame (the reference is portrait; the demo renders 16:9 by default).
	var vp := get_viewport().get_visible_rect().size
	if vp.x < vp.y * 1.2:
		_camera.keep_aspect = Camera3D.KEEP_WIDTH
		_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(camera_fov) * 0.5) * 1.15))
	_camera.rotation_degrees = Vector3(-camera_pitch_deg, 0.0, 0.0)
	_camera.position = look_at_point + _camera.basis.z * camera_distance


## A house of the left (side = -1) or right (side = 1) row whose facade centre
## sits on the street edge at depth z.
func _row_house(side: float, z: float, length: float, h1: float, h2: float, opts: Dictionary) -> void:
	var depth := 4.4
	var rot := -side * (90.0 - row_turn_deg)
	var normal := Vector3(sin(deg_to_rad(rot)), 0, cos(deg_to_rad(rot)))
	var facade := Vector3(side * street_half_width, 0, z)
	_k.house(self, facade - normal * (depth * 0.5 + 0.2), rot, length, depth, h1 * 1.15, h2 * 1.15, opts)


func _screenshot(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved to ", path)
	get_tree().quit()


# ---------------------------------------------------------------------- layout
func _build_town() -> void:
	var k := _k
	var ground := PlaneMesh.new()
	ground.size = Vector2(160, 160)
	k.part(self, ground, Props.CREAM, Vector3.ZERO)
	k.cobbles(self, -10.0, 10.0, -36.0, 16.0)

	# Left / right rows: facades turned ~20 degrees towards the viewer, so they
	# read like the oblique facades of the reference instead of edge-on walls.
	var left := [
		[-21.0, 6.0, 3.2, 3.0, {"roof": Props.RED, "door_bay": 1}],
		[-15.0, 6.5, 3.4, 3.0, {"roof": Props.RED, "door_bay": 0, "chimney": true, "lit": [true, true, false, true]}],
		[-9.0, 5.5, 3.0, 2.8, {"roof": Props.WALL, "door_bay": 1}],
		[-3.2, 6.0, 3.2, 3.0, {"roof": Props.RED, "door_bay": 2, "lit": [false, true], "lantern": 1.25}],
		[2.8, 6.5, 3.4, 3.0, {"roof": Props.RED, "door_bay": 0}],
		[9.0, 6.0, 3.0, 2.8, {"roof": Props.WALL, "door_bay": 1, "pitch": 44.0}],
	]
	var right := [
		[-21.0, 6.0, 3.4, 3.0, {"roof": Props.WALL, "door_bay": 1}],
		[-14.8, 6.5, 3.2, 3.2, {"roof": Props.RED, "door_bay": 2, "chimney": true}],
		[-8.6, 6.0, 3.4, 3.0, {"roof": Props.WALL, "door_bay": 0, "lit": [true, false, true, true]}],
		[-2.5, 6.5, 3.0, 3.0, {"roof": Props.RED, "door_bay": 1}],
		[3.8, 6.0, 3.4, 3.2, {"roof": Props.RED, "door_bay": 2, "chimney": true}],
		[10.0, 6.5, 3.2, 3.0, {"roof": Props.WALL, "door_bay": 0}],
	]
	for h in left:
		_row_house(-1.0, h[0], h[1], h[2], h[3], h[4])
	for h in right:
		_row_house(1.0, h[0], h[1], h[2], h[3], h[4])
	# Far end of the street (facades face +Z, towards the viewer).
	k.house(self, Vector3(-7.0, 0, -29.0), 0, 7.0, 5.0, 3.4, 3.0, {"roof": Props.RED, "door_bay": 2})
	k.house(self, Vector3(7.5, 0, -29.5), 0, 7.0, 5.0, 3.2, 3.2, {"roof": Props.WALL, "door_bay": 0, "chimney": true})

	k.well(self, Vector3(0.0, 0, -9.5))
	k.market_stall(self, Vector3(-6.0, 0, -1.8), 45)
	k.lamp_post(self, Vector3(-4.7, 0, -0.1))
	k.barrel(self, Vector3(-6.9, 0, -9.6))
	k.barrel(self, Vector3(-7.0, 0, 1.2))
	k.crate(self, Vector3(-7.1, 0, 2.2), Vector3(0.8, 0.6, 0.7), 10)
	k.barrel(self, Vector3(6.0, 0, 3.4))
	k.barrel(self, Vector3(6.7, 0, 4.2))
	k.shrub(self, Vector3(6.3, 0, 5.6), 1.4, 1.5)
	k.shrub(self, Vector3(-7.0, 0, -16.0), 1.0, 1.0)

	# Townsfolk: sepia bystanders in black hats, red-cloaked figures.
	var fs := 1.1
	k.figure(self, Vector3(-3.6, 0, -6.6), 25, "plain", fs)
	k.figure(self, Vector3(-3.4, 0, 1.2), 15, "plain", fs)
	k.figure(self, Vector3(-6.0, 0, 3.6), 40, "plain", fs)
	k.figure(self, Vector3(4.4, 0, -5.4), -25, "red", fs)
	k.figure(self, Vector3(5.4, 0, 0.2), -45, "red", fs)
	k.figure(self, Vector3(3.0, 0, 3.6), 10, "red", fs)

	# The plague doctor, ringed by red marks.
	var doc := Vector3(1.0, 0, -2.8)
	k.figure(self, doc, 0, "doctor", fs * 1.08)
	k.ground_ring(self, doc, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 15:
		var a := deg_to_rad(-80.0 + i * 20.0 + rng.randf_range(-8.0, 8.0))
		var r := 2.3 + rng.randf_range(-0.5, 0.7)
		k.ground_dot(self, doc + Vector3(cos(a) * r, 0, -sin(a) * r), rng.randf_range(0.12, 0.26))

	# A wedge of rats advancing from the bottom left, led by a big one.
	var lead := Vector3(-0.8, 0, 0.6)
	var to_doc := (doc - lead).normalized()
	k.rat(self, lead, rad_to_deg(atan2(to_doc.x, to_doc.z)), 1.5)
	k.ground_ring(self, lead, 1.25)
	for i in 2:
		k.ground_dot(self, lead + to_doc * (1.6 + i * 0.8) + Vector3(0.7, 0, 0.1), 0.12)
	var dir := Vector3(0.6, 0, -1.0).normalized()
	var perp := Vector3(-dir.z, 0, dir.x)
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	for row in range(1, 6):
		var centre := lead - dir * (1.2 + row * 0.95)
		var n := row + 1
		for c in n:
			var off := (c - (n - 1) * 0.5) * 0.95
			var p := centre + perp * off + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			k.rat(self, p, yaw + rng.randf_range(-12.0, 12.0), 0.85)

	k.flush(self)
