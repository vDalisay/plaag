## Prop kit for the demo square: builds houses, the well, figures, rats, ... out
## of primitive meshes under a given parent node.
##
## Colour conventions the parchment shader relies on (see README):
##   * pale, low-saturation albedo (walls, stone, dull wood) -> parchment
##   * saturated red / amber / green / blue -> ink wash of that hue
##   * near-black albedo -> solid ink (timber beams, rats, hats, ...)
##   * amber emission -> glowing, un-hatched lamps and windows
## The shader only inks EDGES, so every drawn detail (beams, frames, tile rows,
## hat brims, belts) is a thin raised strip of real geometry.
extends RefCounted

const CREAM := Color(0.93, 0.88, 0.76)
const WALL := Color(0.90, 0.85, 0.74)
const CLOTH := Color(0.80, 0.77, 0.70)
const COAT := Color(0.52, 0.48, 0.42)
const STONE := Color(0.78, 0.74, 0.66)
const WOOD := Color(0.66, 0.59, 0.50)
const TIMBER := Color(0.13, 0.10, 0.08)
const INK := Color(0.06, 0.05, 0.04)
const RED := Color(0.72, 0.12, 0.10)
const AMBER := Color(1.0, 0.55, 0.10)
const GREEN := Color(0.30, 0.55, 0.25)
const SKIN := Color(0.93, 0.85, 0.72)
const TAIL := Color(0.42, 0.10, 0.07)

var _materials := {}
var _rng := RandomNumberGenerator.new()
# Roof tile joints are gathered here and drawn as one MultiMesh by flush().
var _tiles: Array[Transform3D] = []
var _tile_colors: Array[Color] = []


func _init(seed_value := 11) -> void:
	_rng.seed = seed_value


# ---------------------------------------------------------------------- helpers
func mat(color: Color, emission_energy := 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), emission_energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	_materials[key] = m
	return m


func node(parent: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = rot_y
	parent.add_child(n)
	return n


func part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO,
		scl := Vector3.ONE, emission_energy := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emission_energy)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func cyl(top: float, bottom: float, height: float, sides := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


func sphere(radius: float, segments := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = maxi(segments / 2, 4)
	return s


func torus(radius: float, thickness: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness * 0.5
	t.outer_radius = radius + thickness * 0.5
	t.rings = 48
	t.ring_segments = 6
	return t


## A thin square bar from a to b (beams, ribs, planks).
func strip(parent: Node3D, a: Vector3, b: Vector3, thickness: float, color: Color) -> MeshInstance3D:
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var mi := MeshInstance3D.new()
	mi.mesh = box(Vector3(thickness, thickness, d.length()))
	mi.material_override = mat(color)
	mi.transform = Transform3D(Basis.looking_at(d, up), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


## Flat-shaded slab with sloped sides (a cobble / flagstone). The bevel slope
## decides how strongly the shader inks its outline: steeper = darker line.
static func slab_mesh(w: float, d: float, h: float, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5
	var hd := d * 0.5
	var bot := [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]
	var top := [Vector3(-hw + bevel, h, -hd + bevel), Vector3(hw - bevel, h, -hd + bevel),
		Vector3(hw - bevel, h, hd - bevel), Vector3(-hw + bevel, h, hd - bevel)]
	var centre := Vector3(0, h * 0.5, 0)
	_quad(st, top[0], top[1], top[2], top[3], centre)
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, bot[i], bot[j], top[j], top[i], centre)
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	var mid := (a + b + c + d) * 0.25
	if n.dot(mid - centre) < 0.0:
		# Wrong winding for an outward face: flip it (Godot front faces are clockwise).
		var t := b
		b = d
		d = t
		n = -n
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


## Builds the batched geometry gathered while placing props (roof tile joints).
func flush(parent: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box(Vector3(0.05, 0.06, 0.36))
	mm.instance_count = _tiles.size()
	for i in _tiles.size():
		mm.set_instance_transform(i, _tiles[i])
		mm.set_instance_color(i, _tile_colors[i])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	_tiles.clear()
	_tile_colors.clear()


# ---------------------------------------------------------------------- ground
## Flagstones in offset rows over the rectangle [x0, x1] x [z0, z1].
## Stones further than `grow_from_z` (towards -Z, away from the viewer) are
## scaled up uniformly, so the pavement stays sparse in the distance instead of
## turning into a mesh of pixel-width lines (the bevel slope, and with it the
## line weight, stays the same).
func cobbles(parent: Node3D, x0: float, x1: float, z0: float, z1: float, row_depth := 0.48,
		grow_from_z := 2.0, grow := 0.03) -> void:
	var lengths := [0.55, 0.75, 0.95]
	var meshes: Array[ArrayMesh] = []
	var xforms: Array = [[], [], []]
	for l in lengths:
		meshes.append(slab_mesh(l - 0.014, row_depth - 0.014, 0.045, 0.016))
	var z := z1
	while z > z0:
		var sc := clampf(1.0 + (grow_from_z - z) * grow, 1.0, 1.9)
		var rd := row_depth * sc
		var zc := z - rd * 0.5
		var x := x0 - _rng.randf() * sc
		while x < x1:
			var k := _rng.randi_range(0, 2)
			var l: float = lengths[k] * sc
			if x + l * 0.5 > x0 - 0.5:
				var b := Basis(Vector3.UP, deg_to_rad(_rng.randf_range(-2.5, 2.5)))
				b = b * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-1.5, 1.5)))
				b = b.scaled(Vector3.ONE * sc * _rng.randf_range(0.97, 1.01))
				var p := Vector3(x + l * 0.5, _rng.randf_range(-0.012, 0.012), zc + _rng.randf_range(-0.03, 0.03))
				xforms[k].append(Transform3D(b, p))
			x += l
		z -= rd
	for k in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = xforms[k].size()
		for i in xforms[k].size():
			mm.set_instance_transform(i, xforms[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat(CREAM)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


# ---------------------------------------------------------------------- houses
## Half-timbered house. Local frame: facade faces +Z, ridge runs along X.
## opts: roof (Color), door_bay (int), lit (Array of bools per window), chimney (bool),
##       braces (bool), stories (1 or 2)
func house(parent: Node3D, pos: Vector3, rot_y: float, length: float, depth: float,
		h1: float, h2: float, opts := {}) -> Node3D:
	var root := node(parent, pos, rot_y)
	var roof_col: Color = opts.get("roof", RED)
	var stories: int = opts.get("stories", 2)
	var j := 0.45 if stories == 2 else 0.0
	var t := 0.16
	var front1 := depth * 0.5
	var front2 := front1 + j
	var top_y := h1 + (h2 if stories == 2 else 0.0)
	var n_bays := maxi(2, roundi(length / 2.1))
	var bw := length / n_bays
	var door_bay: int = opts.get("door_bay", 0)

	# Stone plinth, ground floor, jettied upper floor.
	part(root, box(Vector3(length + 0.12, 0.4, depth + 0.12)), STONE, Vector3(0, 0.2, 0))
	part(root, box(Vector3(length, h1, depth)), WALL, Vector3(0, h1 * 0.5, 0))
	if stories == 2:
		part(root, box(Vector3(length + 0.2, h2, depth + j)), WALL, Vector3(0, h1 + h2 * 0.5, j * 0.5))
		# Jetty beam and the joist ends under the overhang.
		part(root, box(Vector3(length + 0.3, 0.24, 0.24)), TIMBER, Vector3(0, h1 + 0.12, front2 + 0.02))
		var nj := int(length / 0.7)
		for k in nj + 1:
			var x := -length * 0.5 + k * length / nj
			part(root, box(Vector3(0.14, 0.14, j + 0.1)), TIMBER, Vector3(x, h1 - 0.05, front1 + j * 0.5))
	# Top plate and corner posts.
	part(root, box(Vector3(length + 0.3, 0.2, 0.2)), TIMBER, Vector3(0, top_y - 0.1, front2 + 0.03))
	for sx in [-1.0, 1.0]:
		part(root, box(Vector3(t + 0.04, h1, 0.2)), TIMBER, Vector3(sx * (length * 0.5 - 0.02), h1 * 0.5, front1 + 0.03))
		if stories == 2:
			part(root, box(Vector3(t + 0.04, h2, 0.2)), TIMBER, Vector3(sx * (length * 0.5 + 0.06), h1 + h2 * 0.5, front2 + 0.03))

	var lit: Array = opts.get("lit", [])
	var win_i := 0
	# Ground floor: posts between bays, a door, windows.
	part(root, box(Vector3(length, 0.14, 0.14)), TIMBER, Vector3(0, 0.45, front1 + 0.04))
	for b in n_bays:
		var cx := -length * 0.5 + (b + 0.5) * bw
		if b > 0:
			part(root, box(Vector3(t, h1, 0.14)), TIMBER, Vector3(cx - bw * 0.5, h1 * 0.5, front1 + 0.04))
		if b == door_bay:
			door(root, Vector3(cx, 0, front1), minf(h1 - 0.5, 2.3))
		else:
			var on: bool = lit[win_i] if win_i < lit.size() else true
			win_i += 1
			window(root, Vector3(cx, h1 * 0.55, front1), Vector2(0.8, 1.0), on)
	# Upper floor: rail, studs, windows and diagonal braces.
	if stories == 2:
		var fz := front2
		part(root, box(Vector3(length + 0.2, 0.14, 0.14)), TIMBER, Vector3(0, h1 + h2 * 0.32, fz + 0.04))
		for b in n_bays:
			var cx := -length * 0.5 + (b + 0.5) * bw
			if b > 0:
				part(root, box(Vector3(t, h2, 0.14)), TIMBER, Vector3(cx - bw * 0.5, h1 + h2 * 0.5, fz + 0.04))
			var on: bool = lit[win_i] if win_i < lit.size() else true
			win_i += 1
			window(root, Vector3(cx, h1 + h2 * 0.6, fz), Vector2(0.7, 0.95), on)
			if opts.get("braces", true):
				# Braces in the low panel under each window, like a St Andrew's cross.
				var ph := h2 * 0.32 - 0.25
				var ang := rad_to_deg(atan2(ph, bw * 0.5 - 0.2))
				for s in [-1.0, 1.0]:
					var l := sqrt(ph * ph + pow(bw * 0.5 - 0.2, 2.0))
					part(root, box(Vector3(l, 0.12, 0.12)), TIMBER,
						Vector3(cx + s * (bw * 0.25 - 0.05), h1 + 0.25 + ph * 0.5, fz + 0.04),
						Vector3(0, 0, ang * s))
	roof(root, Vector3(0, top_y, j * 0.5), length + 0.7, depth + j + 0.7, opts.get("pitch", 38.0), roof_col)
	if opts.has("lantern"):
		wall_lantern(root, Vector3(opts["lantern"], minf(h1 - 0.7, 2.6), front1))
	if opts.get("chimney", false):
		var cx2: float = length * 0.3
		var rh := (depth + j + 0.7) * 0.5 * tan(deg_to_rad(opts.get("pitch", 38.0)))
		part(root, box(Vector3(0.7, rh + 1.0, 0.7)), STONE, Vector3(cx2, top_y + (rh + 1.0) * 0.5 + 0.2, -0.3))
		part(root, box(Vector3(0.9, 0.18, 0.9)), STONE, Vector3(cx2, top_y + rh + 1.3, -0.3))
		for k in 3:
			part(root, box(Vector3(0.74, 0.06, 0.74)), STONE, Vector3(cx2, top_y + rh + 0.4 + k * 0.28, -0.3))
	return root


## Gable roof with tile rows (shingle steps) on both slopes. `base` is the eave
## line centre; ridge along local X.
func roof(parent: Node3D, base: Vector3, length: float, depth: float, pitch_deg: float, color: Color) -> void:
	var half := depth * 0.5
	var rh := half * tan(deg_to_rad(pitch_deg))
	var prism := PrismMesh.new()
	prism.size = Vector3(depth, rh, length)
	part(parent, prism, color, base + Vector3(0, rh * 0.5, 0), Vector3(0, 90, 0))
	var slope_len := sqrt(half * half + rh * rh)
	var alpha := rad_to_deg(atan2(rh, half))
	var n_rows := int(slope_len / 0.42)
	for s in [1.0, -1.0]:
		var nrm := Vector3(0, half, s * rh) / slope_len
		for r in n_rows:
			var f := (r + 0.6) / n_rows
			var p := base + Vector3(0, rh * (1.0 - f), s * f * half) + nrm * 0.07
			var row_rot := Vector3(s * (alpha - 7.0), 0, 0)
			part(parent, box(Vector3(length + 0.04, 0.08, slope_len / n_rows * 1.05)), color, p, row_rot)
			# Tile joints: short raised ridges, staggered from row to row.
			var basis := Basis.from_euler(row_rot * (PI / 180.0))
			var row_w := slope_len / n_rows
			var x := -length * 0.5 + (0.12 if r % 2 == 0 else 0.33)
			while x < length * 0.5 - 0.1:
				var local := Transform3D(basis.scaled(Vector3(1, 1, row_w * 0.8 / 0.36)), p + Vector3(x, 0, 0) + nrm * 0.045)
				_tiles.append(parent.global_transform * local)
				_tile_colors.append(color)
				x += 0.42
	# Ridge cap and bargeboards.
	part(parent, box(Vector3(length + 0.1, 0.22, 0.3)), color, base + Vector3(0, rh + 0.05, 0))
	for sx in [-1.0, 1.0]:
		for s in [1.0, -1.0]:
			part(parent, box(Vector3(0.12, 0.18, slope_len)), TIMBER,
				base + Vector3(sx * length * 0.5, rh * 0.5 + 0.06, s * half * 0.5), Vector3(s * alpha, 0, 0))


func window(parent: Node3D, c: Vector3, size: Vector2, lit := true) -> void:
	var fz := c.z
	part(parent, box(Vector3(size.x + 0.24, size.y + 0.24, 0.1)), TIMBER, Vector3(c.x, c.y, fz + 0.03))
	if lit:
		part(parent, box(Vector3(size.x, size.y, 0.1)), AMBER, Vector3(c.x, c.y, fz + 0.06), Vector3.ZERO, Vector3.ONE, 2.2)
	else:
		part(parent, box(Vector3(size.x, size.y, 0.1)), INK, Vector3(c.x, c.y, fz + 0.04))
	part(parent, box(Vector3(0.07, size.y, 0.06)), TIMBER, Vector3(c.x, c.y, fz + 0.12))
	part(parent, box(Vector3(size.x, 0.07, 0.06)), TIMBER, Vector3(c.x, c.y + size.y * 0.12, fz + 0.12))
	part(parent, box(Vector3(size.x + 0.4, 0.1, 0.22)), WOOD, Vector3(c.x, c.y - size.y * 0.5 - 0.15, fz + 0.1))
	# Open shutters, with a batten across.
	for s in [-1.0, 1.0]:
		var sx: float = c.x + s * (size.x * 0.5 + 0.12 + size.x * 0.25)
		part(parent, box(Vector3(size.x * 0.5, size.y + 0.1, 0.06)), WOOD, Vector3(sx, c.y, fz + 0.08))
		part(parent, box(Vector3(size.x * 0.5, 0.07, 0.05)), TIMBER, Vector3(sx, c.y + size.y * 0.25, fz + 0.12))
		part(parent, box(Vector3(size.x * 0.5, 0.07, 0.05)), TIMBER, Vector3(sx, c.y - size.y * 0.25, fz + 0.12))


func door(parent: Node3D, c: Vector3, height: float) -> void:
	var w := 1.0
	var fz := c.z
	var rect_h := height - w * 0.5
	# Dark doorway with a round arch, framed by timber.
	part(parent, box(Vector3(w, rect_h, 0.1)), INK, Vector3(c.x, rect_h * 0.5, fz + 0.03))
	part(parent, cyl(w * 0.5, w * 0.5, 0.1, 16), INK, Vector3(c.x, rect_h, fz + 0.03), Vector3(90, 0, 0))
	for s in [-1.0, 1.0]:
		part(parent, box(Vector3(0.14, rect_h, 0.18)), TIMBER, Vector3(c.x + s * (w * 0.5 + 0.07), rect_h * 0.5, fz + 0.05))
	part(parent, box(Vector3(w + 0.5, 0.16, 0.2)), TIMBER, Vector3(c.x, height + 0.12, fz + 0.05))
	part(parent, box(Vector3(w + 0.4, 0.12, 0.4)), STONE, Vector3(c.x, 0.06, fz + 0.2))


## A lantern hanging from a wall bracket (wall plane at local z = c.z).
func wall_lantern(parent: Node3D, c: Vector3) -> void:
	part(parent, box(Vector3(0.08, 0.08, 0.7)), INK, c + Vector3(0, 0.3, 0.35))
	part(parent, box(Vector3(0.06, 0.4, 0.06)), INK, c + Vector3(0, 0.12, 0.68))
	lantern(parent, c + Vector3(0, -0.3, 0.68))


func lantern(parent: Node3D, c: Vector3) -> void:
	part(parent, box(Vector3(0.36, 0.48, 0.36)), AMBER, c, Vector3.ZERO, Vector3.ONE, 3.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			part(parent, box(Vector3(0.05, 0.52, 0.05)), INK, c + Vector3(sx * 0.18, 0, sz * 0.18))
	part(parent, cyl(0.02, 0.32, 0.22, 4), INK, c + Vector3(0, 0.35, 0), Vector3(0, 45, 0))
	part(parent, box(Vector3(0.42, 0.06, 0.42)), INK, c + Vector3(0, -0.26, 0))


func lamp_post(parent: Node3D, pos: Vector3) -> void:
	part(parent, cyl(0.07, 0.09, 3.0, 8), INK, pos + Vector3(0, 1.5, 0))
	part(parent, box(Vector3(0.08, 0.08, 0.5)), INK, pos + Vector3(0, 2.95, 0.2))
	lantern(parent, pos + Vector3(0, 2.6, 0.42))


# ---------------------------------------------------------------------- well
func well(parent: Node3D, pos: Vector3) -> void:
	var root := node(parent, pos)
	var r := 1.9
	var courses := 4
	var ch := 0.3
	var n := 16
	part(root, cyl(r - 0.05, r - 0.05, courses * ch, 24), STONE, Vector3(0, courses * ch * 0.5, 0))
	for c in courses:
		for i in n:
			var a := TAU * (i + (0.5 if c % 2 == 1 else 0.0)) / n
			var p := Vector3(sin(a) * r, ch * (c + 0.5), cos(a) * r)
			part(root, box(Vector3(TAU * r / n - 0.07, ch - 0.05, 0.3)), STONE, p, Vector3(0, rad_to_deg(a), 0))
	# Rim of cap stones and the dark shaft.
	var rim_y := courses * ch + 0.08
	for i in n:
		var a := TAU * (i + 0.25) / n
		part(root, box(Vector3(TAU * (r + 0.05) / n - 0.05, 0.16, 0.42)), STONE,
			Vector3(sin(a) * (r + 0.02), rim_y, cos(a) * (r + 0.02)), Vector3(0, rad_to_deg(a), 0))
	part(root, cyl(r - 0.2, r - 0.2, 0.1, 24), INK, Vector3(0, rim_y + 0.02, 0))
	# Posts, windlass with rope and the octagonal plank roof.
	for sx in [-1.0, 1.0]:
		part(root, box(Vector3(0.24, 2.9, 0.24)), WOOD, Vector3(sx * (r - 0.15), rim_y + 1.4, 0))
		part(root, box(Vector3(0.12, 0.7, 0.12)), WOOD, Vector3(sx * (r - 0.35), rim_y + 2.45, 0), Vector3(0, 0, sx * 45.0))
	part(root, cyl(0.1, 0.1, r * 2.0, 8), WOOD, Vector3(0, rim_y + 1.9, 0), Vector3(0, 0, 90))
	part(root, cyl(0.02, 0.02, 1.4, 4), INK, Vector3(0, rim_y + 1.2, 0))
	part(root, cyl(0.16, 0.13, 0.25, 8), WOOD, Vector3(0, rim_y + 0.5, 0))
	var ry := rim_y + 2.9
	var rr := 2.6
	var rhgt := 1.7
	part(root, cyl(0.05, rr, rhgt, 8), COAT, Vector3(0, ry + rhgt * 0.5, 0))
	part(root, cyl(rr + 0.05, rr + 0.05, 0.12, 8), WOOD, Vector3(0, ry + 0.02, 0))
	# Octagonal plank roof: dark hip ribs on the corners, planks and shingle
	# courses on each face.
	var apex := Vector3(0, ry + rhgt + 0.04, 0)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var v0 := Vector3(sin(a0) * rr, ry, cos(a0) * rr)
		var v1 := Vector3(sin(a1) * rr, ry, cos(a1) * rr)
		var out0 := Vector3(sin(a0), 0.6, cos(a0)).normalized() * 0.05
		strip(root, apex + out0, v0 + out0, 0.09, TIMBER)
		var face_out := Vector3(sin((a0 + a1) * 0.5), 0.8, cos((a0 + a1) * 0.5)).normalized() * 0.03
		for t in [0.33, 0.67]:
			strip(root, apex + face_out, v0.lerp(v1, t) + face_out, 0.05, WOOD)
		for f in [0.35, 0.55, 0.75, 0.92]:
			var p0 := apex.lerp(v0, f) + face_out
			var p1 := apex.lerp(v1, f) + face_out
			strip(root, p0, p1, 0.06, WOOD)
	part(root, sphere(0.16, 8), WOOD, Vector3(0, ry + rhgt + 0.1, 0))
	part(root, cyl(0.04, 0.04, 0.4, 6), WOOD, Vector3(0, ry + rhgt + 0.35, 0))


# ---------------------------------------------------------------------- people
## kind: "plain" (pale cloak, black hat), "red" (red cloak, pale hat), "doctor" (all red).
func figure(parent: Node3D, pos: Vector3, facing_deg: float, kind := "plain", scale := 1.0) -> Node3D:
	var root := node(parent, pos, facing_deg)
	root.scale = Vector3.ONE * scale
	var cloak := COAT
	var hat_col := INK
	if kind == "red":
		cloak = RED
		hat_col = WALL
	elif kind == "doctor":
		cloak = RED
		hat_col = RED
	# Boots, a long flaring cloak with fold ridges, belt and the front opening.
	for s in [-1.0, 1.0]:
		part(root, box(Vector3(0.16, 0.12, 0.3)), INK, Vector3(s * 0.14, 0.06, 0.12))
	var cl_bot := 0.56
	var cl_top := 0.26
	var cl_h := 1.62
	part(root, cyl(cl_top, cl_bot, cl_h, 14), cloak, Vector3(0, 0.1 + cl_h * 0.5, 0))
	var lean := rad_to_deg(atan2(cl_bot - cl_top, cl_h))
	for fa in [-140.0, -95.0, -55.0, -20.0, 22.0, 60.0, 100.0, 145.0]:
		var pivot := node(root, Vector3(0, 0, 0), fa)
		var fh := cl_h * 0.62
		var r := cl_bot - (cl_bot - cl_top) * (fh * 0.5 / cl_h)
		part(pivot, box(Vector3(0.05, fh, 0.05)), cloak, Vector3(0, 0.1 + fh * 0.5, r + 0.005), Vector3(-lean, 0, 0))
	var belt_y := 1.12
	var belt_r := cl_bot - (cl_bot - cl_top) * ((belt_y - 0.1) / cl_h) + 0.02
	part(root, cyl(belt_r, belt_r, 0.08, 14), TIMBER, Vector3(0, belt_y, 0))
	part(root, box(Vector3(0.12, 0.12, 0.04)), STONE, Vector3(0, belt_y, belt_r + 0.01))
	# Shoulders / cape, collar.
	part(root, sphere(0.36, 12), cloak, Vector3(0, 1.66, 0), Vector3.ZERO, Vector3(1.12, 0.6, 0.82))
	part(root, cyl(0.14, 0.24, 0.18, 10), cloak, Vector3(0, 1.86, 0.0))
	# Arms hanging at the sides, hands.
	for s in [-1.0, 1.0]:
		part(root, cyl(0.1, 0.14, 0.95, 8), cloak, Vector3(s * 0.4, 1.27, 0.04), Vector3(0, 0, s * 7.0))
		part(root, cyl(0.15, 0.15, 0.05, 8), cloak, Vector3(s * 0.45, 0.82, 0.04))
		part(root, sphere(0.08, 8), SKIN, Vector3(s * 0.46, 0.74, 0.06))
	# Head with eyes and a nose; the hat sits back so the face shows from above.
	part(root, sphere(0.21, 14), SKIN, Vector3(0, 2.08, 0.03))
	part(root, sphere(0.05, 6), SKIN, Vector3(0, 2.05, 0.25))
	for s in [-1.0, 1.0]:
		part(root, sphere(0.032, 6), INK, Vector3(s * 0.08, 2.1, 0.2))
	part(root, box(Vector3(0.1, 0.025, 0.03)), TIMBER, Vector3(0, 1.97, 0.2), Vector3(-15, 0, 0))
	var hat_tilt := Vector3(-22, 0, 0)
	var hat := node(root, Vector3(0, 2.24, -0.08))
	hat.rotation_degrees = hat_tilt
	part(hat, cyl(0.37, 0.37, 0.04, 18), hat_col, Vector3(0, 0, 0))
	part(hat, cyl(0.16, 0.2, 0.24, 14), hat_col, Vector3(0, 0.13, 0))
	part(hat, sphere(0.16, 10), hat_col, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
	part(hat, cyl(0.205, 0.205, 0.05, 14), TIMBER if hat_col != INK else STONE, Vector3(0, 0.05, 0))
	return root


func rat(parent: Node3D, pos: Vector3, facing_deg: float, scale := 1.0) -> void:
	var root := node(parent, pos, facing_deg)
	root.scale = Vector3.ONE * scale
	part(root, sphere(0.25, 10), INK, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(0.95, 0.75, 1.55))
	part(root, cyl(0.0, 0.15, 0.42, 8), INK, Vector3(0, 0.2, 0.5), Vector3(90, 0, 0))
	for s in [-1.0, 1.0]:
		part(root, sphere(0.07, 6), INK, Vector3(s * 0.11, 0.33, 0.36), Vector3.ZERO, Vector3(1, 1, 0.5))
	# Tail: a thin S-curve of short segments, dark red like the manuscript's.
	var bend := _rng.randf_range(0.5, 1.0) * (1.0 if _rng.randf() > 0.5 else -1.0)
	var prev := Vector3(0, 0.12, -0.32)
	for i in 4:
		var t := float(i + 1) / 4.0
		var nxt := Vector3(sin(t * PI * 1.2) * 0.22 * bend, 0.05, -0.32 - t * 1.0)
		strip(root, prev, nxt, 0.045 - i * 0.007, TAIL)
		prev = nxt
	# The red mark on the head, like the manuscript.
	part(root, sphere(0.075, 8), RED, Vector3(0, 0.33, 0.44), Vector3.ZERO, Vector3.ONE, 1.2)


# ---------------------------------------------------------------------- small props
func barrel(parent: Node3D, pos: Vector3) -> void:
	var root := node(parent, pos, _rng.randf_range(0, 90))
	var h := 1.15
	var r_end := 0.4
	var r_mid := 0.48
	part(root, cyl(r_mid, r_end, h * 0.5, 14), WOOD, Vector3(0, h * 0.25, 0))
	part(root, cyl(r_end, r_mid, h * 0.5, 14), WOOD, Vector3(0, h * 0.75, 0))
	# Staves follow the bulge; hoops are dark bands.
	for i in 12:
		var a := TAU * i / 12.0
		var dir := Vector3(sin(a), 0, cos(a))
		strip(root, dir * (r_end + 0.01), dir * (r_mid + 0.012) + Vector3(0, h * 0.5, 0), 0.035, WOOD)
		strip(root, dir * (r_mid + 0.012) + Vector3(0, h * 0.5, 0), dir * (r_end + 0.01) + Vector3(0, h, 0), 0.035, WOOD)
	for y in [0.14, h - 0.14]:
		var rr := r_end + (r_mid - r_end) * 0.28 + 0.025
		part(root, cyl(rr, rr, 0.07, 14), TIMBER, Vector3(0, y, 0))
	for y in [h * 0.38, h * 0.62]:
		part(root, cyl(r_mid + 0.015, r_mid + 0.015, 0.05, 14), TIMBER, Vector3(0, y, 0))
	# Lid planks.
	for k in 3:
		part(root, box(Vector3(0.24, 0.03, 0.72 - abs(k - 1) * 0.2)), WOOD, Vector3((k - 1) * 0.25, h + 0.01, 0))


func crate(parent: Node3D, pos: Vector3, size := Vector3(0.7, 0.5, 0.5), rot_y := 0.0) -> void:
	var root := node(parent, pos, rot_y)
	part(root, box(size), WOOD, Vector3(0, size.y * 0.5, 0))
	part(root, box(Vector3(size.x + 0.04, 0.07, size.z + 0.04)), TIMBER, Vector3(0, size.y - 0.04, 0))
	part(root, box(Vector3(size.x + 0.04, 0.07, size.z + 0.04)), TIMBER, Vector3(0, 0.05, 0))


## Market stall with a striped awning sloping down towards +Z.
func market_stall(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var root := node(parent, pos, rot_y)
	var w := 3.4
	part(root, box(Vector3(w, 1.0, 1.3)), WOOD, Vector3(0, 0.5, 0.5))
	part(root, box(Vector3(w + 0.1, 0.1, 1.45)), WOOD, Vector3(0, 1.03, 0.5))
	for k in 4:
		part(root, box(Vector3(w, 0.06, 0.05)), TIMBER, Vector3(0, 0.25 + k * 0.22, 1.16))
	for sx in [-1.0, 1.0]:
		part(root, box(Vector3(0.14, 2.7, 0.14)), WOOD, Vector3(sx * w * 0.5, 1.35, 1.1))
		part(root, box(Vector3(0.14, 3.3, 0.14)), WOOD, Vector3(sx * w * 0.5, 1.65, -0.5))
	# Goods on the counter.
	crate(root, Vector3(-1.0, 1.08, 0.45), Vector3(0.7, 0.4, 0.55), 8)
	crate(root, Vector3(0.1, 1.08, 0.5), Vector3(0.6, 0.5, 0.5), -6)
	part(root, sphere(0.25, 8), CLOTH, Vector3(1.0, 1.3, 0.45), Vector3.ZERO, Vector3(1, 0.8, 1))
	part(root, sphere(0.2, 8), CLOTH, Vector3(1.3, 1.25, 0.6), Vector3.ZERO, Vector3(1, 0.8, 1))
	# Awning: alternating red / cream stripes running down the slope.
	var y_back := 3.3
	var y_front := 2.6
	var z_back := -0.6
	var z_front := 1.9
	var slope := sqrt(pow(z_front - z_back, 2.0) + pow(y_back - y_front, 2.0))
	var ang := rad_to_deg(atan2(y_back - y_front, z_front - z_back))
	var n_str := 8
	var sw := (w + 0.4) / n_str
	for i in n_str:
		var x := -(w + 0.4) * 0.5 + (i + 0.5) * sw
		var col := RED if i % 2 == 0 else CREAM
		part(root, box(Vector3(sw, 0.08, slope)), col,
			Vector3(x, (y_back + y_front) * 0.5 + (0.0 if i % 2 == 0 else 0.03), (z_back + z_front) * 0.5), Vector3(ang, 0, 0))
		# Scalloped valance.
		part(root, cyl(sw * 0.5, sw * 0.5, 0.06, 10), col, Vector3(x, y_front - 0.22, z_front + 0.03), Vector3(90, 0, 0))
		part(root, box(Vector3(sw, 0.22, 0.06)), col, Vector3(x, y_front - 0.11, z_front + 0.03))
	part(root, box(Vector3(w + 0.5, 0.08, 0.1)), TIMBER, Vector3(0, y_front + 0.02, z_front + 0.05))


## Leafy shrub drawn as many small pale leaves (outlines only, like the reference).
func shrub(parent: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var root := node(parent, pos)
	var leaf := cyl(0.24, 0.24, 0.03, 7)
	# A few overlapping domes of leaves, each leaf a small disc facing outwards,
	# so the outline turns into scalloped pen strokes.
	for c in 4:
		var ca := _rng.randf() * TAU
		var cr := radius * (0.25 + 0.45 * _rng.randf()) if c > 0 else 0.0
		var dome_r := radius * (0.75 if c == 0 else 0.5)
		var centre := Vector3(cos(ca) * cr, height * (0.45 if c == 0 else 0.3), sin(ca) * cr)
		# Dark core: the gaps between the leaves read as shadowed ink.
		part(root, sphere(1.0, 10), Color(0.5, 0.46, 0.39), centre,
			Vector3.ZERO, Vector3(dome_r, dome_r * height / radius, dome_r) * 0.8)
		var n := int(dome_r * dome_r * 120.0)
		for i in n:
			var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1), _rng.randf_range(-1, 1)).normalized()
			var p := centre + dir * dome_r * Vector3(1.0, height / radius, 1.0) * _rng.randf_range(0.85, 1.0)
			if p.y < 0.1:
				continue
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
			var b := Basis(side, dir, side.cross(dir)).rotated(dir, _rng.randf() * TAU)
			# Tilt each leaf off the dome so neighbours meet at an angle (= an inked crease).
			b = Basis(side, deg_to_rad(_rng.randf_range(-40.0, 40.0))) * b
			b = b * Basis.from_scale(Vector3(1.0, 1.0, 0.5) * _rng.randf_range(0.8, 1.2))
			var mi := MeshInstance3D.new()
			mi.mesh = leaf
			mi.material_override = mat(COAT if _rng.randf() < 0.35 else CLOTH)
			mi.transform = Transform3D(b, p)
			root.add_child(mi)


## Flat red mark painted on the ground.
func ground_dot(parent: Node3D, pos: Vector3, radius: float) -> void:
	part(parent, cyl(radius, radius, 0.03, 12), RED, pos + Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE, 0.6)


func ground_ring(parent: Node3D, pos: Vector3, radius: float) -> void:
	part(parent, torus(radius, 0.08), RED, pos + Vector3(0, 0.09, 0), Vector3.ZERO, Vector3(1, 0.3, 1), 0.6)
