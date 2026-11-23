## Procedural meshes for the event VFX (no textures from disk): the particle
## shapes and the flat ground-mark (decal) shapes. Decals are thin prisms
## (a flat top plus short side walls) so the parchment shader sees a depth and
## normal edge round them and inks an outline.
extends RefCounted


## A low-poly sphere of radius 0.5 (unit diameter): scaled per instance.
static func puff() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 10
	s.rings = 5
	return s


## A unit box along local Z (strokes, ticks, straw, plaster chips).
static func stroke() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b


## A flame tongue: a unit-tall 6-sided cone, pivot at its base.
static func flame() -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 6
	c.rings = 1
	var arrays := c.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.5
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## An irregular blot of about unit radius: a wobbly polygon with a few lobes.
static func blob(seed_value: int, points := 18, lumpy := 0.28) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var outline := PackedVector2Array()
	var ph := rng.randf() * TAU
	for i in points:
		var a := TAU * float(i) / float(points)
		var r := 1.0 + lumpy * (0.55 * sin(a * 3.0 + ph) + 0.45 * sin(a * 5.0 + ph * 1.7)) + rng.randf_range(-0.08, 0.08)
		outline.append(Vector2(cos(a), sin(a)) * r)
	return prism(outline, 0.018)


## A round drop (satellite splashes).
static func drop() -> ArrayMesh:
	var outline := PackedVector2Array()
	for i in 9:
		var a := TAU * float(i) / 9.0
		outline.append(Vector2(cos(a), sin(a)))
	return prism(outline, 0.018)


## A ground crack of about unit radius: 5 jagged, tapering branches from the
## centre, one with a fork, as flat strips.
static func crack(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var branches := 5
	for b in branches:
		var a := TAU * float(b) / float(branches) + rng.randf_range(-0.35, 0.35)
		var p := Vector2.ZERO
		var w := 0.11
		var steps := 4
		for s in steps:
			a += rng.randf_range(-0.6, 0.6)
			var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(0.2, 0.3)
			_strip(st, p, q, w, w * 0.72, 0.015)
			if s == 1 and b % 2 == 0:
				var fa := a + (0.8 if rng.randf() < 0.5 else -0.8)
				_strip(st, q, q + Vector2(cos(fa), sin(fa)) * 0.3, w * 0.6, 0.01, 0.015)
			p = q
			w *= 0.72
	return st.commit()


## A flat prism (top face up, short side walls) from a convex-ish outline
## around the origin, `h` tall.
static func prism(outline: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, h, 0))
		st.add_vertex(Vector3(b.x, h, b.y))
		st.add_vertex(Vector3(a.x, h, a.y))
		var out := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
		st.set_normal(out)
		st.add_vertex(Vector3(a.x, h, a.y))
		st.add_vertex(Vector3(b.x, h, b.y))
		st.add_vertex(Vector3(b.x, 0.0, b.y))
		st.add_vertex(Vector3(a.x, h, a.y))
		st.add_vertex(Vector3(b.x, 0.0, b.y))
		st.add_vertex(Vector3(a.x, 0.0, a.y))
	return st.commit()


static func _strip(st: SurfaceTool, a: Vector2, b: Vector2, w0: float, w1: float, h: float) -> void:
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x)
	var p0 := a + side * w0 * 0.5
	var p1 := a - side * w0 * 0.5
	var p2 := b - side * w1 * 0.5
	var p3 := b + side * w1 * 0.5
	var v := [Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p2.x, h, p2.y), Vector3(p3.x, h, p3.y)]
	# Wound so the top faces up (+Y).
	for idx: int in [0, 2, 1, 0, 3, 2]:
		st.add_vertex(v[idx])
	# Side walls along both long edges so the shader finds an edge.
	for e: Array in [[0, 3], [2, 1]]:
		var t0: Vector3 = v[e[0]]
		var t1: Vector3 = v[e[1]]
		var b0 := Vector3(t0.x, 0.0, t0.z)
		var b1 := Vector3(t1.x, 0.0, t1.z)
		for q: Vector3 in [t0, t1, b1, t0, b1, b0]:
			st.add_vertex(q)
