## Loads, caches, and shader-harmonizes glTF models from the Medieval Village
## MegaKit and Fantasy Props MegaKit so they pair seamlessly with the dark
## gothic woodcut shader (parchment_ink.gdshader).
##
## Structural wood/plaster/brick/tile textures are subtly desaturated below the
## shader's accent_saturation_threshold while preserving all normal maps and
## value contrast, keeping saturated red strictly for the plague and warm amber
## for lanterns/windows.
class_name MedievalAssets
extends RefCounted

const Props := preload("res://scripts/town_props.gd")

const VILLAGE := "res://Assets/Medieval Village MegaKit[Standard]/glTF/"
const PROPS := "res://Assets/Fantasy Props MegaKit[Standard]/Exports/glTF/"

const PATHS := {
	# Architecture (each wall module is 2.0u wide x 3.12u tall, centered on X=0)
	&"wall_plaster": VILLAGE + "Wall_Plaster_Straight.gltf",
	&"wall_woodgrid": VILLAGE + "Wall_Plaster_WoodGrid.gltf",
	&"wall_brick": VILLAGE + "Wall_UnevenBrick_Straight.gltf",
	&"wall_door_plaster": VILLAGE + "Wall_Plaster_Door_RoundInset.gltf",
	&"wall_door_brick": VILLAGE + "Wall_UnevenBrick_Door_Round.gltf",
	&"wall_win_plaster": VILLAGE + "Wall_Plaster_Window_Wide_Round.gltf",
	&"wall_win_flat": VILLAGE + "Wall_Plaster_Window_Wide_Flat.gltf",
	&"wall_win_brick": VILLAGE + "Wall_UnevenBrick_Window_Wide_Round.gltf",
	&"door_round": VILLAGE + "Door_1_Round.gltf",
	&"window_round": VILLAGE + "Window_Wide_Round1.gltf",
	&"window_flat": VILLAGE + "Window_Wide_Flat1.gltf",
	&"shutters_open": VILLAGE + "WindowShutters_Wide_Round_Open.gltf",
	&"corner_wood": VILLAGE + "Corner_Exterior_Wood.gltf",
	&"corner_brick": VILLAGE + "Corner_Exterior_Brick.gltf",
	&"balcony": VILLAGE + "Balcony_Cross_Straight.gltf",
	&"roof_4x6": VILLAGE + "Roof_RoundTiles_4x6.gltf",
	&"roof_4x8": VILLAGE + "Roof_RoundTiles_4x8.gltf",
	&"roof_6x8": VILLAGE + "Roof_RoundTiles_6x8.gltf",
	&"roof_dormer": VILLAGE + "Roof_Dormer_RoundTile.gltf",
	&"chimney": VILLAGE + "Prop_Chimney.gltf",
	&"chimney2": VILLAGE + "Prop_Chimney2.gltf",
	&"vine1": VILLAGE + "Prop_Vine1.gltf",
	&"vine2": VILLAGE + "Prop_Vine2.gltf",
	&"fence_wood": VILLAGE + "Prop_WoodenFence_Single.gltf",
	&"fence_metal": VILLAGE + "Prop_MetalFence_Simple.gltf",
	&"wagon": VILLAGE + "Prop_Wagon.gltf",
	# Street & market props (Fantasy Props MegaKit)
	&"barrel": PROPS + "Barrel.gltf",
	&"barrel_apples": PROPS + "Barrel_Apples.gltf",
	&"crate": PROPS + "Crate_Wooden.gltf",
	&"crate_metal": PROPS + "Crate_Metal.gltf",
	&"stall": PROPS + "Stall_Empty.gltf",
	&"stall_cart": PROPS + "Stall_Cart_Empty.gltf",
	&"lantern_wall": PROPS + "Lantern_Wall.gltf",
	&"bag": PROPS + "Bag.gltf",
	&"bench": PROPS + "Bench.gltf",
	&"cage": PROPS + "Cage_Small.gltf",
	&"cauldron": PROPS + "Cauldron.gltf",
	&"bucket": PROPS + "Bucket_Wooden_1.gltf",
	&"banner": PROPS + "Banner_1.gltf",
	&"rubble": PROPS + "Vase_Rubble_Medium.gltf",
}

## Static cache across rounds so glTF scenes & harmonized materials load once.
static var _scenes := {}
static var _mats := {}  # "mat_id|tone" -> StandardMaterial3D


static func has_asset(key: StringName) -> bool:
	var p: String = PATHS.get(key, "")
	return not p.is_empty() and ResourceLoader.exists(p)


static func _scene(key: StringName) -> PackedScene:
	if _scenes.has(key):
		return _scenes[key] as PackedScene
	var p: String = PATHS.get(key, "")
	if p.is_empty() or not ResourceLoader.exists(p):
		_scenes[key] = null
		return null
	var ps := ResourceLoader.load(p) as PackedScene
	_scenes[key] = ps
	return ps


## Spawns a cached MegaKit glTF model under `parent` with shader-harmonized
## desaturated gothic materials. Returns the spawned Node3D (or null if missing).
static func spawn(parent: Node3D, key: StringName, pos := Vector3.ZERO, rot_deg := Vector3.ZERO,
		scl := Vector3.ONE, tone := &"stone") -> Node3D:
	var ps := _scene(key)
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	inst.position = pos
	inst.rotation_degrees = rot_deg
	inst.scale = scl
	_harmonize_tree(inst, tone)
	parent.add_child(inst)
	return inst


static func _harmonize_tree(root: Node3D, tone: StringName) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(s) as StandardMaterial3D
			mi.set_surface_override_material(s, _harmonize_mat(orig, tone))


## Desaturates MegaKit materials cleanly while preserving normal maps & shading
## depth so the dark parchment_ink shader inks architectural detail without
## turning brown wood or red clay tiles into glowing plague red.
static func _harmonize_mat(orig: StandardMaterial3D, tone: StringName) -> StandardMaterial3D:
	var id := orig.get_instance_id() if orig != null else 0
	var key := "%d|%s" % [id, tone]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.roughness = 0.92
	var base := Color(0.62, 0.56, 0.48)
	match tone:
		&"roof_dark":
			base = Color(0.32, 0.30, 0.28)
		&"roof_slate":
			base = Color(0.30, 0.34, 0.38)
		&"wood":
			base = Color(0.46, 0.40, 0.33)
		&"plaster":
			base = Color(0.76, 0.71, 0.62)
		&"plaster_grime":
			base = Color(0.60, 0.54, 0.46)
		&"brick":
			base = Color(0.54, 0.47, 0.41)
		&"vine":
			base = Color(0.32, 0.46, 0.28)
		&"iron":
			base = Color(0.18, 0.17, 0.17)
		&"lantern":
			base = Color(0.24, 0.22, 0.20)
	if orig != null:
		# Keep relief & roughness detail from the MegaKit textures while muting saturation.
		m.normal_enabled = orig.normal_enabled
		m.normal_texture = orig.normal_texture
		m.normal_scale = orig.normal_scale * 1.15
		m.roughness_texture = orig.roughness_texture
		m.ao_enabled = orig.ao_enabled
		m.ao_texture = orig.ao_texture
		# Desaturate the original albedo color strongly toward our dark gothic tone.
		var c := orig.albedo_color
		var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		var muted := Color(lum, lum, lum).lerp(c, 0.22)
		m.albedo_color = base * muted.lerp(Color.WHITE, 0.55)
		if orig.albedo_texture != null and tone in [&"plaster", &"plaster_grime", &"brick", &"wood", &"stone", &"roof_dark", &"roof_slate"]:
			# Keep texture detail modulated by muted low-sat multiplier.
			m.albedo_texture = orig.albedo_texture
			m.albedo_color = base * 0.85
	else:
		m.albedo_color = base
	_mats[key] = m
	return m


## Builds a modular medieval house from MegaKit glTF pieces under a new Node3D
## root at `pos` with yaw `rot_y` (facade faces local +Z, ridge along local X).
## `bays_x`: 3 (6u wide) or 4 (8u wide). `depth_u`: 4.0u or 6.0u.
## Returns metadata dictionary compatible with House.setup() & Ambient.
static func build_house(parent: Node3D, kit: Props, pos: Vector3, rot_y: float,
		bays_x: int, depth_bays: int, stories: int, style: String, visual_stage: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var root := kit.node(parent, pos, rot_y)
	var length := float(bays_x) * 2.0
	var depth := float(depth_bays) * 2.0
	var floor_h := 3.05
	var top := floor_h * float(stories)
	var door_bay := rng.randi_range(0, bays_x - 1)
	var is_merchant := style == "merchant"
	var wall_tone := &"plaster" if (is_merchant or visual_stage >= 2) else &"plaster_grime"
	var ground_brick := is_merchant or rng.randf() < 0.35
	var roof_tone := &"roof_slate" if is_merchant else &"roof_dark"

	# Subtle dark stone plinth grounding the building.
	kit.part(root, kit.box(Vector3(length + 0.18, 0.26, depth + 0.18)), Props.STONE, Vector3(0, 0.13, 0))

	# Build each storey's 4 walls from modular 2u MegaKit wall sections.
	for st in stories:
		var y := float(st) * floor_h
		var jetty := 0.28 if (st >= 1) else 0.0
		var cur_d := depth + jetty
		var fz := depth * 0.5 + jetty
		var bz := -depth * 0.5
		var tone := &"brick" if (st == 0 and ground_brick) else wall_tone

		# Front (+Z) & Back (-Z) walls
		for b in bays_x:
			var cx := -length * 0.5 + (float(b) + 0.5) * 2.0
			var front_key := &"wall_plaster"
			if st == 0 and b == door_bay:
				front_key = &"wall_door_brick" if ground_brick else &"wall_door_plaster"
			elif st == 0:
				front_key = &"wall_win_brick" if ground_brick else &"wall_win_plaster"
			else:
				front_key = &"wall_win_plaster" if rng.randf() < 0.72 else &"wall_woodgrid"
			spawn(root, front_key, Vector3(cx, y, fz), Vector3.ZERO, Vector3.ONE, tone)
			if st == 0 and b == door_bay:
				spawn(root, &"door_round", Vector3(cx - 0.52, y, fz - 0.06), Vector3.ZERO, Vector3.ONE, &"wood")
			elif front_key in [&"wall_win_plaster", &"wall_win_brick"]:
				spawn(root, &"window_round", Vector3(cx, y + 1.05, fz), Vector3.ZERO, Vector3.ONE, &"wood")
				# Warm glowing amber interior pane on ~45% of windows (pops dramatically in dark shader!).
				var is_lit := rng.randf() < (0.58 if is_merchant else 0.42)
				kit.part(root, kit.box(Vector3(0.76, 0.92, 0.08)),
					Props.AMBER if is_lit else Props.INK,
					Vector3(cx, y + 1.55, fz - 0.08), Vector3.ZERO, Vector3.ONE,
					Props.WINDOW_LIGHT if is_lit else 0.0)
				if visual_stage >= 1 or is_merchant:
					spawn(root, &"shutters_open", Vector3(cx, y + 1.05, fz + 0.04), Vector3.ZERO, Vector3.ONE, &"wood")
			# Back wall (plain / timber)
			var back_key := &"wall_brick" if (st == 0 and ground_brick) else &"wall_plaster"
			spawn(root, back_key, Vector3(cx, y, bz), Vector3(0, 180, 0), Vector3.ONE, tone)

		# Left (-X) & Right (+X) side walls
		for b in depth_bays:
			var cz := -depth * 0.5 + (float(b) + 0.5) * 2.0 + jetty * 0.5
			var side_key := &"wall_brick" if (st == 0 and ground_brick) else &"wall_woodgrid"
			spawn(root, side_key, Vector3(-length * 0.5, y, cz), Vector3(0, -90, 0), Vector3.ONE, tone)
			spawn(root, side_key, Vector3(length * 0.5, y, cz), Vector3(0, 90, 0), Vector3.ONE, tone)

		# Exterior corner beams for crisp vertical silhouettes
		var corner_key := &"corner_brick" if (st == 0 and ground_brick) else &"corner_wood"
		for sx: float in [-1.0, 1.0]:
			for sz_v: float in [bz, fz]:
				spawn(root, corner_key, Vector3(sx * length * 0.5, y, sz_v), Vector3.ZERO, Vector3.ONE, &"wood")

		# Optional balcony on merchant upper storeys
		if is_merchant and st == 1 and rng.randf() < 0.45:
			var bx := -length * 0.5 + (float(door_bay) + 0.5) * 2.0
			spawn(root, &"balcony", Vector3(bx, y, fz + 0.45), Vector3.ZERO, Vector3.ONE, &"wood")

	# Pitched MegaKit tiled roof (rotated 90° around Y so its longer span runs along local X)
	var roof_key := &"roof_4x6"
	var r_sx := 1.0
	var r_sz := 1.0
	if bays_x >= 4 and depth_bays >= 3:
		roof_key = &"roof_6x8"
	elif bays_x >= 4:
		roof_key = &"roof_4x8"
	else:
		roof_key = &"roof_4x6"
		r_sx = length / 6.0
		r_sz = depth / 4.0
	var jetty_top := 0.28 if stories >= 2 else 0.0
	spawn(root, roof_key, Vector3(0, top - 0.05, jetty_top * 0.5), Vector3(0, 90, 0),
		Vector3(r_sz * 1.03, 0.95, r_sx * 1.03), roof_tone)

	# Chimney & vines & wall lantern
	var has_chimney := rng.randf() < 0.55
	var chim_local := Vector3(NAN, 0, 0)
	if has_chimney:
		var cx := rng.randf_range(-length * 0.28, length * 0.28)
		var cz := -depth * 0.18
		spawn(root, &"chimney" if rng.randf() < 0.6 else &"chimney2",
			Vector3(cx, top + 0.6, cz), Vector3.ZERO, Vector3.ONE, &"brick")
		chim_local = Vector3(cx, top + 3.7, cz)

	# Creeping ivy/vines on slum walls (stage 0-1)
	if not is_merchant and visual_stage <= 1 and rng.randf() < 0.5:
		var vx := rng.randf_range(-length * 0.35, length * 0.35)
		spawn(root, &"vine1" if rng.randf() < 0.5 else &"vine2",
			Vector3(vx, minf(top, 3.0), depth * 0.5 + 0.14), Vector3.ZERO, Vector3.ONE, &"vine")

	# Warm glowing wall lantern beside the doorway (crucial focal pools in the dark gothic shader!)
	if is_merchant or rng.randf() < 0.45:
		var bw := length / float(bays_x)
		var door_x := -length * 0.5 + (float(door_bay) + 0.5) * bw
		var side := 1.0 if door_bay < bays_x - 1 else -1.0
		var lx := clampf(door_x + side * 0.95, -length * 0.5 + 0.45, length * 0.5 - 0.45)
		spawn(root, &"lantern_wall", Vector3(lx, 2.25, depth * 0.5 + 0.12), Vector3.ZERO, Vector3.ONE * 0.65, &"lantern")
		# Glowing amber core inside the lantern so the shader lifts it into a warm light pool.
		kit.part(root, kit.sphere(0.14, 8), Props.AMBER, Vector3(lx, 2.48, depth * 0.5 + 0.52),
			Vector3.ZERO, Vector3.ONE, 3.0)

	return {
		"root": root,
		"length": length,
		"depth": depth,
		"top": top,
		"jetty": jetty_top,
		"pitch": 38.0,
		"door_bay": door_bay,
		"n_bays": bays_x,
		"chimney": chim_local,
		"has_chimney": has_chimney,
	}
