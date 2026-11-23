## Ground dressing for a District (graphics pass B.1): breaks up the bare mud
## and the paving by District and Year stage. Everything is a static
## MultiMesh (one draw call per kind) or, for the few planters, prop-kit parts
## the District's MeshBatcher merges. Visual only: no collision, no blockers,
## its own RNG, and it keeps off door points and gates.
##   Slums  stage 0: wheel ruts, stones, straw wisps, sage grass tufts along
##          wall bases and fences, scraps; stages 1-2 get tidier.
##   Merchant: kerb stones and a stone-lined gutter along the streets, planters
##          round the square, fallen leaves, a little grass at the walls.
## (Blue puddles and refuse heaps are the stage decoration's, district_decor.gd.)
extends RefCounted

const Props := preload("res://scripts/town_props.gd")
const WorldMesh := preload("res://scripts/world/world_mesh.gd")

const RUT := Color(0.44, 0.40, 0.35)
const STRAW := Color(0.86, 0.80, 0.62)
const SCRAP := Color(0.55, 0.50, 0.43)
const GUTTER := Color(0.22, 0.17, 0.11)
## Mud level, and the top of the cobbles (Props.cobbles slabs are 0.045 high).
const MUD_Y := 0.0
const PAVED_Y := 0.045
## Per style, per stage: stones, straw clusters, scraps, ruts (bool), grass
## density along wall bases (chance per 0.6 u), kerbs + gutters, planters, leaves.
const LOOK := {
	"slums": [
		{"stones": 70, "straw": 18, "scraps": 12, "ruts": true, "tufts": 0.55, "kerbs": false, "planters": 0, "leaves": 0},
		{"stones": 35, "straw": 6, "scraps": 4, "ruts": true, "tufts": 0.35, "kerbs": false, "planters": 0, "leaves": 0},
		{"stones": 18, "straw": 0, "scraps": 0, "ruts": false, "tufts": 0.16, "kerbs": false, "planters": 0, "leaves": 10},
	],
	"merchant": [
		{"stones": 30, "straw": 6, "scraps": 10, "ruts": false, "tufts": 0.2, "kerbs": true, "planters": 4, "leaves": 30},
		{"stones": 14, "straw": 0, "scraps": 0, "ruts": false, "tufts": 0.12, "kerbs": true, "planters": 6, "leaves": 40},
		{"stones": 6, "straw": 0, "scraps": 0, "ruts": false, "tufts": 0.08, "kerbs": true, "planters": 8, "leaves": 50},
	],
}

var stage := 0
var style := "slums"
## What was placed (debug output).
var placed := {}
var _d: Node3D
var _k: Props
var _rng := RandomNumberGenerator.new()
var _look: Dictionary
var _paved: Array[Rect2] = []
var _avoid: Array[Vector3] = []      # door points and gates: (x, z, radius) as Vector3(x, r, z)
var _xf := {}                         # kind -> Array[Transform3D]


func _init(district: Node3D, kit: Props, stage_: int, style_: String, seed_value: int) -> void:
	_d = district
	_k = kit
	stage = clampi(stage_, 0, 2)
	style = style_ if LOOK.has(style_) else "slums"
	_look = LOOK[style][stage]
	_rng.seed = seed_value


## info: "streets" / "paved" (Array[Rect2], x -> X, y -> Z), "doors" and
## "gates" (Array[Vector3]), "houses" (Array of {"center": Vector2, "size":
## Vector2, "yaw": float deg}), "fences" (Array of [Vector3, Vector3] base
## lines), "ruts" (Array[Vector3] (z, x0, x1) track centre lines), "kerbs"
## (Array of [Vector3, Vector3]), "gutters" (Array[Vector3] (z, x0, x1)),
## "square" (Rect2, merchant planters go round it).
func build(info: Dictionary) -> void:
	_paved.assign(info.get("paved", []))
	for p: Vector3 in info.get("doors", []):
		_avoid.append(Vector3(p.x, 1.3, p.z))
	for p: Vector3 in info.get("gates", []):
		_avoid.append(Vector3(p.x, 2.2, p.z))
	var streets: Array[Rect2] = []
	streets.assign(info.get("streets", []))
	if _look["ruts"]:
		for line: Vector3 in info.get("ruts", []):
			_ruts(line)
	for h: Dictionary in info.get("houses", []):
		_wall_tufts(h)
	for f: Array in info.get("fences", []):
		_line_tufts(f[0], f[1], float(_look["tufts"]) * 1.4)
	if _look["kerbs"]:
		for k: Array in info.get("kerbs", []):
			_kerb(k[0], k[1])
		for g: Vector3 in info.get("gutters", []):
			_gutter(g)
	for i in int(_look["stones"]):
		var p := _spot(streets, 0.15, style == "slums")
		if p.is_finite():
			_stone_cluster(p)
	for i in int(_look["straw"]):
		var p := _spot(streets, 0.3, true)
		if p.is_finite():
			_straw(p)
	for i in int(_look["scraps"]):
		var p := _spot(streets, 0.2, true)
		if p.is_finite():
			_add("scrap", p + Vector3(0, 0.02, 0), _rng.randf() * TAU, _rng.randf_range(0.7, 1.4),
				Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)))
	var square: Rect2 = info.get("square", Rect2())
	if int(_look["planters"]) > 0 and square.has_area():
		_planters(square, int(_look["planters"]))
	for i in int(_look["leaves"]):
		var p := _spot(streets, 0.1, false)
		if p.is_finite():
			_leaves(p, _rng.randi_range(1, 3))
	_flush()


# ---------------------------------------------------------------------- placing
## A random open spot in `streets` (off the paving when `mud_only`), clear of
## every footprint and away from doors and gates; INF when none is found.
func _spot(streets: Array[Rect2], radius: float, mud_only: bool) -> Vector3:
	if streets.is_empty():
		return Vector3.INF
	for i in 30:
		var r := streets[_rng.randi() % streets.size()]
		var p := Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y, r.end.y))
		if mud_only and _on_paving(p, radius):
			continue
		if _near_avoid(p, radius) or not _d.call("is_free", p, radius):
			continue
		p.y = _ground_y(p)
		return p
	return Vector3.INF


func _near_avoid(p: Vector3, radius: float) -> bool:
	for a in _avoid:
		var dx := a.x - p.x
		var dz := a.z - p.z
		if dx * dx + dz * dz < (a.y + radius) * (a.y + radius):
			return true
	return false


func _on_paving(p: Vector3, margin: float) -> bool:
	for r in _paved:
		if r.grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _ground_y(p: Vector3) -> float:
	return PAVED_Y if _on_paving(p, 0.0) else MUD_Y


## Files one instance of `kind`: at p, turned `yaw` (rad), scaled `s`,
## optionally tilted (`tilt` x / z in rad).
func _add(kind: String, p: Vector3, yaw: float, s: float, tilt := Vector3.ZERO, stretch := Vector3.ONE) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis.from_euler(tilt)
	b = b * Basis.from_scale(stretch * s)
	if not _xf.has(kind):
		var arr: Array[Transform3D] = []
		_xf[kind] = arr
	(_xf[kind] as Array[Transform3D]).append(Transform3D(b, p))
	placed[kind] = int(placed.get(kind, 0)) + 1


# ---------------------------------------------------------------------- slums
## A pair of wheel ruts along a street: shallow strips in short wobbly
## segments, broken where the street is paved, blocked or at a door.
func _ruts(line: Vector3) -> void:
	var x := line.y + _rng.randf_range(0.0, 1.5)
	var z := line.x
	while x < line.z:
		var l := _rng.randf_range(0.9, 1.6)
		var nz := clampf(z + _rng.randf_range(-0.1, 0.1), line.x - 0.25, line.x + 0.25)
		var a := Vector3(x, 0, z)
		var b := Vector3(minf(x + l, line.z), 0, nz)
		var mid := (a + b) * 0.5
		if _rng.randf() > 0.15 and not _on_paving(mid, 0.5) and not _near_avoid(mid, 0.8) \
				and _d.call("is_free", mid, 0.4):
			var d := b - a
			var yaw := atan2(-d.z, d.x)
			for side: float in [-0.55, 0.55]:
				var w := _rng.randf_range(0.85, 1.15)
				_add("rut", mid + Vector3(_rng.randf_range(-0.05, 0.05), 0.0, side), yaw, 1.0, Vector3.ZERO,
					Vector3(d.length() + 0.05, 1.0, w))
		x += l
		z = nz


## Grass tufts along the visible base lines of a house footprint (the +Z and
## side walls; the -Z walls face away from the camera).
func _wall_tufts(h: Dictionary) -> void:
	var c: Vector2 = h["center"]
	var size: Vector2 = h["size"]
	var b := Basis(Vector3.UP, deg_to_rad(float(h["yaw"])))
	var centre := Vector3(c.x, 0, c.y)
	var hx := size.x * 0.5 + 0.08
	var hz := size.y * 0.5 + 0.08
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for i in 4:
		var a: Vector3 = centre + b * corners[i]
		var e: Vector3 = centre + b * corners[(i + 1) % 4]
		var mid := (a + e) * 0.5 - centre
		if mid.z < -0.5:
			continue  # faces away from the camera
		_line_tufts(a, e, float(_look["tufts"]))


func _line_tufts(a: Vector3, b: Vector3, chance: float) -> void:
	var d := b - a
	var n := int(d.length() / 0.6)
	for i in n:
		if _rng.randf() > chance:
			continue
		var p := a + d * ((i + _rng.randf()) / n)
		if _near_avoid(p, 0.0) or not (_d.get("bounds") as Rect2).grow(-0.3).has_point(Vector2(p.x, p.z)):
			continue
		var paved := _on_paving(p, 0.0)
		if paved and _rng.randf() < 0.6:
			continue
		p.y = PAVED_Y if paved else MUD_Y
		for k in _rng.randi_range(1, 3):
			var q := p + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.12, 0.12))
			_add("tuft", q, _rng.randf() * TAU, _rng.randf_range(0.7, 1.25))
		if not paved and _rng.randf() < 0.2:
			_stone_cluster(p + Vector3(_rng.randf_range(-0.3, 0.3), 0, 0.25))


func _stone_cluster(p: Vector3) -> void:
	for k in _rng.randi_range(1, 3):
		var q := p + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
		_add("stone", q, _rng.randf() * TAU, _rng.randf_range(0.55, 1.35),
			Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15)))


## A few straw wisps lying across each other.
func _straw(p: Vector3) -> void:
	var yaw := _rng.randf() * TAU
	for k in _rng.randi_range(3, 5):
		var q := p + Vector3(_rng.randf_range(-0.18, 0.18), 0.012 + k * 0.004, _rng.randf_range(-0.18, 0.18))
		_add("straw", q, yaw + _rng.randf_range(-0.7, 0.7), _rng.randf_range(0.7, 1.2))


# ---------------------------------------------------------------------- merchant
## A row of kerb stones from a to b (skipping doors and gates).
func _kerb(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var total := d.length()
	var yaw := atan2(-d.z, d.x)
	var x := 0.0
	while x < total:
		var l := _rng.randf_range(0.7, 1.0)
		var p := a + d / total * (x + l * 0.5)
		if not _near_avoid(p, 0.2) and _d.call("is_free", p, 0.05):
			_add("kerb", p, yaw + _rng.randf_range(-0.03, 0.03), 1.0, Vector3.ZERO, Vector3(l / 0.95, 1.0, 1.0))
		x += l + 0.03


## A stone-lined gutter (kennel) along z from x0 to x1: a dark channel between two lips.
func _gutter(line: Vector3) -> void:
	var x := line.y
	while x < line.z:
		var l := _rng.randf_range(1.6, 2.4)
		var p := Vector3(minf(x + l * 0.5, line.z), PAVED_Y, line.x)
		if not _near_avoid(p, 0.3) and _d.call("is_free", p, 0.2):
			_add("gutter", p + Vector3(0, 0.006, 0), 0.0, 1.0, Vector3.ZERO, Vector3(l, 1.0, 1.0))
			for s: float in [-1.0, 1.0]:
				_add("lip", p + Vector3(0, 0.0, s * 0.17), 0.0, 1.0, Vector3.ZERO, Vector3(l, 1.0, 1.0))
		x += l


## Stone planters with sage shrubs round the square's edge (prop-kit parts,
## merged by the District's batcher).
func _planters(square: Rect2, n: int) -> void:
	var done := 0
	for i in 60:
		if done >= n:
			return
		var side := _rng.randi() % 4
		var t := _rng.randf_range(0.1, 0.9)
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(lerpf(square.position.x, square.end.x, t), 0, square.position.y + 0.6)
			1: p = Vector3(lerpf(square.position.x, square.end.x, t), 0, square.end.y - 0.6)
			2: p = Vector3(square.position.x + 0.6, 0, lerpf(square.position.y, square.end.y, t))
			_: p = Vector3(square.end.x - 0.6, 0, lerpf(square.position.y, square.end.y, t))
		if _near_avoid(p, 1.0) or not _d.call("is_free", p, 0.9):
			continue
		_avoid.append(Vector3(p.x, 1.4, p.z))
		done += 1
		var root := _k.node(_d, p, 90.0 if side >= 2 else 0.0)
		_k.part(root, _k.box(Vector3(1.2, 0.5, 0.6)), Props.STONE, Vector3(0, 0.25, 0))
		_k.part(root, _k.box(Vector3(1.3, 0.08, 0.7)), Props.STONE, Vector3(0, 0.52, 0))
		for k in 4:
			var q := Vector3(-0.42 + k * 0.28 + _rng.randf_range(-0.05, 0.05), 0.66 + _rng.randf_range(0.0, 0.1), _rng.randf_range(-0.08, 0.08))
			_k.part(root, _k.sphere(_rng.randf_range(0.17, 0.24), 8), Props.GREEN, q)
		_leaves(p + Vector3(0, PAVED_Y, 0), 4)
		placed["planter"] = int(placed.get("planter", 0)) + 1


## Fallen leaves round a point (sage, flat).
func _leaves(p: Vector3, n: int) -> void:
	for k in n:
		var q := p + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-0.8, 0.8))
		if _near_avoid(q, 0.0):
			continue
		q.y = _ground_y(q) + 0.012
		_add("leaf", q, _rng.randf() * TAU, _rng.randf_range(0.8, 1.2))


# ---------------------------------------------------------------------- build
func _flush() -> void:
	var meshes := {
		"stone": [_pebble_mesh(), Props.STONE],
		"scrap": [_k.box(Vector3(0.22, 0.04, 0.12)), SCRAP],
		"straw": [_k.box(Vector3(0.55, 0.018, 0.03)), STRAW],
		"rut": [_k.box(Vector3(1.0, 0.02, 0.17)), RUT],
		"tuft": [WorldMesh.tuft_mesh(), Props.GREEN],
		"kerb": [Props.slab_mesh(0.95, 0.3, 0.12, 0.03), Props.STONE],
		"gutter": [_k.box(Vector3(1.0, 0.012, 0.22)), GUTTER],
		"lip": [_k.box(Vector3(1.0, 0.05, 0.08)), Props.STONE],
		"leaf": [_leaf_mesh(), Props.GREEN],
	}
	for kind: String in _xf:
		var m: Array = meshes[kind]
		WorldMesh.scatter(_d, m[0], _xf[kind], _k.mat(m[1]), "Ground_" + kind)
	_xf.clear()


## A low, rounded pebble (flat-shaded enough to get an ink rim).
func _pebble_mesh() -> Mesh:
	var s := _k.sphere(1.0, 7)
	return WorldMesh.bake([[s, Transform3D(Basis.from_scale(Vector3(0.17, 0.08, 0.13)), Vector3(0, 0.02, 0)), Color.WHITE]])


func _leaf_mesh() -> Mesh:
	var s := _k.sphere(1.0, 6)
	return WorldMesh.bake([[s, Transform3D(Basis.from_scale(Vector3(0.1, 0.015, 0.055)), Vector3.ZERO), Color.WHITE]])
