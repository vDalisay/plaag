## Small mesh helpers for the world look and ambient life (scripts/world/):
## baking a few coloured primitives into one vertex-coloured mesh, a shared
## vertex-colour material, a MultiMesh node, and the procedural meshes the
## scatter and the crows use. Flat colours only, like the prop kit.
extends RefCounted

const Props := preload("res://scripts/town_props.gd")

static var _vc_material: StandardMaterial3D


## One triangle mesh from [Mesh, Transform3D, Color] items (vertex colours).
static func bake(items: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for item: Array in items:
		var mesh: Mesh = item[0]
		var col: Color = item[2]
		for s in mesh.get_surface_count():
			var pa := MeshBatcher.part_arrays(mesh, s)
			var arrays: Array = pa[0]
			var xf: Transform3D = (item[1] as Transform3D) * (pa[1] as Transform3D)
			var nb := xf.basis.inverse().transposed()
			var flip := xf.basis.determinant() < 0.0
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] != null:
				normals = arrays[Mesh.ARRAY_NORMAL]
			var idx := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for k in verts.size():
					idx[k] = k
			for t in range(0, idx.size() - 2, 3):
				var order := [0, 2, 1] if flip else [0, 1, 2]
				for o: int in order:
					var k := idx[t + o]
					st.set_color(col)
					st.set_normal((nb * normals[k]).normalized() if k < normals.size() else Vector3.UP)
					st.add_vertex(xf * verts[k])
	return st.commit()


## Shared opaque material that takes its colour from the vertices.
static func vc_material() -> StandardMaterial3D:
	if _vc_material == null:
		_vc_material = StandardMaterial3D.new()
		_vc_material.vertex_color_use_as_albedo = true
		_vc_material.vertex_color_is_srgb = true
		_vc_material.roughness = 1.0
	return _vc_material


## A MultiMeshInstance3D (no shadows) under `parent` with room for `count`.
static func multimesh(parent: Node3D, mesh: Mesh, count: int, material: Material, colors := false,
		node_name := "Multi") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## A MultiMesh node filled with `xforms` (static scatter).
static func scatter(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], material: Material,
		node_name := "Scatter") -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mmi := multimesh(parent, mesh, xforms.size(), material, false, node_name)
	for i in xforms.size():
		mmi.multimesh.set_instance_transform(i, xforms[i])
	return mmi


## A tuft of grass: `blades` thin three-sided spikes fanning out from a
## point, each leaning outwards; flat normals so the shader inks every blade.
static func tuft_mesh(blades := 6, seed_value := 3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var items: Array = []
	for b in blades:
		var a := TAU * b / blades + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		# Seen from high above, so the blades splay out wide and low.
		var h := rng.randf_range(0.2, 0.36)
		var lean := rng.randf_range(0.22, 0.38)
		var root := out * rng.randf_range(0.0, 0.06)
		var axis := (out * lean + Vector3(0, h, 0))
		var blade := CylinderMesh.new()
		blade.top_radius = 0.0
		blade.bottom_radius = 0.05
		blade.height = axis.length()
		blade.radial_segments = 4
		blade.rings = 1
		var y := axis.normalized()
		var x := y.cross(out).normalized()
		var basis := Basis(x, y, x.cross(y))
		items.append([blade, Transform3D(basis, root + axis * 0.5), Color.WHITE])
	return bake(items)


## A perched crow (feet at the origin, beak towards +Z): body, head, beak and
## tail, all ink.
static func crow_body_mesh(k: Props) -> ArrayMesh:
	var ink := Props.INK
	return bake([
		[k.sphere(1.0, 10), Transform3D(Basis.from_scale(Vector3(0.13, 0.12, 0.22)), Vector3(0, 0.2, 0)), ink],
		[k.sphere(1.0, 8), Transform3D(Basis.from_scale(Vector3(0.085, 0.085, 0.09)), Vector3(0, 0.31, 0.17)), ink],
		[k.cyl(0.0, 0.035, 0.13, 6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.3, 0.29)), ink],
		[k.box(Vector3(0.12, 0.03, 0.22)), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.2, -0.26)), ink],
		[k.box(Vector3(0.025, 0.12, 0.025)), Transform3D(Basis(), Vector3(0.05, 0.06, 0.0)), ink],
		[k.box(Vector3(0.025, 0.12, 0.025)), Transform3D(Basis(), Vector3(-0.05, 0.06, 0.0)), ink],
	])


## One wing, hinged at the origin, spreading along +X: a long feathered
## blade (pivot at the shoulder).
static func crow_wing_mesh(k: Props) -> ArrayMesh:
	var ink := Props.INK
	return bake([
		[k.box(Vector3(0.36, 0.025, 0.17)), Transform3D(Basis(), Vector3(0.18, 0, 0)), ink],
		[k.box(Vector3(0.16, 0.022, 0.12)), Transform3D(Basis(Vector3.UP, -0.35), Vector3(0.4, 0, -0.03)), ink],
	])
