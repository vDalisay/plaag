## Year visual stages (M7): the decoration a District gets on top of its
## layout, so the player sees the town clean itself up over the Years.
##   0  mud: dark puddles, refuse heaps, open drains, boarded windows,
##      grimy walls, a neglected well without its roof.
##   1  fewer puddles, one stone-lined drain, the well cleaned (roof, bucket),
##      a few painted shutters and lanterns.
##   2  no puddles, painted shutters and window boxes, lime-washed (paler)
##      walls, more wall lanterns; the slums' well becomes a fountain.
## Paving and fence sag are stage-dependent too, but built by the District.
## Only visuals: no collision, no blockers, and its own RNG, so house
## positions, indices, colliders and doors never depend on the stage.
## Everything is plain prop-kit parts, merged later by MeshBatcher (house
## decoration under each house root, so the cutaway squashes it too).
extends RefCounted

const Props := preload("res://scripts/town_props.gd")
const PUDDLE := Color(0.25, 0.19, 0.13)
const DRAIN := Color(0.22, 0.17, 0.11)
const GRIME := Color(0.84, 0.78, 0.66)
const LIME := Color(0.97, 0.95, 0.90)
const SHUTTER := Color(0.24, 0.38, 0.62)
const WATER := Color(0.32, 0.50, 0.72)
## Well roof parts sit above this height (Props.well); stage 0 drops them.
const WELL_ROOF_Y := 4.1
## Per layout style, per stage: puddles, refuse heaps, open drains (streets),
## and the share of windows boarded / with painted shutters / with window
## boxes, and of houses that get a wall lantern.
const LOOK := {
	"slums": [
		{"puddles": 18, "refuse": 9, "drains": 2, "board": 0.4, "shutter": 0.0, "box": 0.0, "lantern": 0.0},
		{"puddles": 6, "refuse": 3, "drains": 1, "board": 0.08, "shutter": 0.22, "box": 0.0, "lantern": 0.12},
		{"puddles": 0, "refuse": 0, "drains": 0, "board": 0.0, "shutter": 0.6, "box": 0.4, "lantern": 0.5},
	],
	"merchant": [
		{"puddles": 12, "refuse": 5, "drains": 0, "board": 0.15, "shutter": 0.1, "box": 0.0, "lantern": 0.0},
		{"puddles": 4, "refuse": 1, "drains": 0, "board": 0.0, "shutter": 0.3, "box": 0.1, "lantern": 0.0},
		{"puddles": 0, "refuse": 0, "drains": 0, "board": 0.0, "shutter": 0.7, "box": 0.55, "lantern": 1.0},
	],
}

var stage := 0
var style := "slums"
var _d: Node3D          # the District (is_free, bounds)
var _k: Props
var _rng := RandomNumberGenerator.new()
var _look: Dictionary
var _paved: Array[Rect2] = []
var _doors: Array[Vector3] = []
## What was placed (debug output): puddles, refuse heaps, drain segments.
var placed := {"puddles": 0, "refuse": 0, "drain": 0}


func _init(district: Node3D, kit: Props, stage_: int, style_: String, seed_value: int) -> void:
	_d = district
	_k = kit
	stage = clampi(stage_, 0, 2)
	style = style_ if LOOK.has(style_) else "slums"
	_look = LOOK[style][stage]
	_rng.seed = seed_value


## Builds every stage decoration. `facades`: one per visible house front,
## {"root": Node3D, "windows": [[pos: Vector3, size: Vector2, lit: bool,
## upper: bool], ...] (house-local), "lantern": Vector3 (or NAN x: has one),
## "tub": Vector3 (or NAN x: no room)}. `streets` are the open ground rects
## for puddles and refuse, `paved` the cobbled ones, `drains` the street
## centre lines [z, x0, x1] for open drains, `doors` the house door points.
func build(facades: Array[Dictionary], well_pos: Vector3, streets: Array[Rect2],
		paved: Array[Rect2], drains: Array[Vector3], doors: Array[Vector3]) -> void:
	_paved = paved
	_doors = doors
	_tint_walls()
	if well_pos.is_finite():
		_well(well_pos)
	for f in facades:
		_facade(f)
	for i in mini(int(_look["drains"]), drains.size()):
		_drain(drains[i])
	for i in int(_look["puddles"]):
		var p := _ground_spot(streets, 1.0)
		if p.is_finite():
			_puddle(p)
			placed["puddles"] += 1
	for i in int(_look["refuse"]):
		var p := _ground_spot(streets, 0.6)
		if p.is_finite():
			_refuse(p)
			placed["refuse"] += 1


# ---------------------------------------------------------------------- houses
## Grime (stage 0 slums) or lime-wash (stage 2) on the kit's shared wall colour.
func _tint_walls() -> void:
	var m := _k.mat(Props.WALL)
	if stage == 2:
		m.albedo_color = LIME
	elif stage == 0 and style == "slums":
		m.albedo_color = GRIME
	else:
		m.albedo_color = Props.WALL


func _facade(f: Dictionary) -> void:
	var root: Node3D = f["root"]
	for w: Array in f["windows"]:
		var pos: Vector3 = w[0]
		var size: Vector2 = w[1]
		var lit: bool = w[2]
		var upper: bool = w[3]
		if not lit and _rng.randf() < float(_look["board"]):
			_boards(root, pos, size)
			continue
		if _rng.randf() < float(_look["shutter"]):
			_shutters(root, pos, size)
		if upper and _rng.randf() < float(_look["box"]):
			_window_box(root, pos, size)
	var spot: Vector3 = f["lantern"]
	if not is_nan(spot.x) and _rng.randf() < float(_look["lantern"]):
		_k.wall_lantern(root, spot)
	var tub: Vector3 = f["tub"]
	if not is_nan(tub.x):
		if stage == 2 and _rng.randf() < 0.45:
			_tub(root, tub)
		elif stage == 0 and _rng.randf() < 0.3:
			_heap(root, tub, 0.7)


## Two planks nailed across a dark window.
func _boards(root: Node3D, c: Vector3, size: Vector2) -> void:
	var l := size.length() + 0.1
	var ang := rad_to_deg(atan2(size.y, size.x))
	for s: float in [-1.0, 1.0]:
		_k.part(root, _k.box(Vector3(l, 0.13, 0.05)), Props.WOOD, c + Vector3(0, 0, 0.2 + s * 0.01),
			Vector3(0, 0, s * ang + _rng.randf_range(-6.0, 6.0)))


## Painted shutters over the kit's plain ones, with dark battens.
func _shutters(root: Node3D, c: Vector3, size: Vector2) -> void:
	for s: float in [-1.0, 1.0]:
		var sx := c.x + s * (size.x * 0.5 + 0.12 + size.x * 0.25)
		_k.part(root, _k.box(Vector3(size.x * 0.5 + 0.03, size.y + 0.14, 0.05)), SHUTTER, Vector3(sx, c.y, c.z + 0.14))
		for dy: float in [-0.25, 0.25]:
			_k.part(root, _k.box(Vector3(size.x * 0.5 + 0.03, 0.06, 0.04)), Props.TIMBER,
				Vector3(sx, c.y + size.y * dy, c.z + 0.18))


## A plank box under the sill with leafy plants.
func _window_box(root: Node3D, c: Vector3, size: Vector2) -> void:
	var y := c.y - size.y * 0.5 - 0.31
	var w := size.x + 0.3
	_k.part(root, _k.box(Vector3(w, 0.22, 0.26)), Props.WOOD, Vector3(c.x, y, c.z + 0.24))
	_k.part(root, _k.box(Vector3(w + 0.04, 0.05, 0.28)), Props.TIMBER, Vector3(c.x, y + 0.1, c.z + 0.24))
	var n := 4
	for i in n:
		var x := c.x - w * 0.5 + (i + 0.5) * w / n
		_k.part(root, _k.sphere(0.13, 6), Props.GREEN, Vector3(x, y + 0.2 + _rng.randf_range(-0.03, 0.04), c.z + 0.26),
			Vector3.ZERO, Vector3(1.0, 0.8, 0.8))


## A flower tub against the wall beside the door.
func _tub(root: Node3D, p: Vector3) -> void:
	_k.part(root, _k.cyl(0.28, 0.22, 0.4, 10), Props.WOOD, p + Vector3(0, 0.2, 0))
	_k.part(root, _k.cyl(0.29, 0.29, 0.05, 10), Props.TIMBER, p + Vector3(0, 0.33, 0))
	for i in 3:
		var a := TAU * i / 3.0
		_k.part(root, _k.sphere(0.16, 6), Props.GREEN, p + Vector3(sin(a) * 0.1, 0.5, cos(a) * 0.1))


# ---------------------------------------------------------------------- well
func _well(pos: Vector3) -> void:
	if stage == 2 and style == "slums":
		_fountain(pos)
		return
	_k.well(_d, pos)
	var root := _d.get_child(_d.get_child_count() - 1) as Node3D
	if stage == 0:
		# Neglected: the roof has fallen in, a plank lies across the shaft.
		for c: Node in root.get_children():
			if (c as Node3D).position.y > WELL_ROOF_Y:
				root.remove_child(c)
				c.free()
		_k.part(root, _k.box(Vector3(3.2, 0.1, 0.3)), Props.WOOD, Vector3(0.2, 1.42, 0.4), Vector3(0, 28, 4))
		_heap(_d, pos + Vector3(-1.7, 0, 1.9), 1.0)
	else:
		_bucket(root, Vector3(0.6, 1.36, 1.9))


func _bucket(root: Node3D, p: Vector3) -> void:
	_k.part(root, _k.cyl(0.2, 0.16, 0.3, 10), Props.WOOD, p + Vector3(0, 0.15, 0))
	for y: float in [0.06, 0.24]:
		_k.part(root, _k.cyl(0.2, 0.2, 0.04, 10), Props.TIMBER, p + Vector3(0, y, 0))
	_k.part(root, _k.torus(0.17, 0.025), Props.TIMBER, p + Vector3(0, 0.3, 0), Vector3(90, 0, 0), Vector3(1, 1, 0.8))


## Octagonal stone basin with a bowl on a column and four spouts; fits the
## well's collider (radius 2).
func _fountain(pos: Vector3) -> void:
	var root := _k.node(_d, pos)
	var r := 1.9
	_k.part(root, _k.cyl(r, r + 0.05, 0.7, 8), Props.STONE, Vector3(0, 0.35, 0), Vector3(0, 22.5, 0))
	_k.part(root, _k.cyl(r - 0.22, r - 0.22, 0.05, 8), WATER, Vector3(0, 0.66, 0), Vector3(0, 22.5, 0))
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0 + PI / 8.0
		var side := 2.0 * r * sin(PI / 8.0)
		var rr := r * cos(PI / 8.0)
		_k.part(root, _k.box(Vector3(side + 0.08, 0.14, 0.32)), Props.STONE,
			Vector3(sin(a - PI / 8.0) * rr, 0.75, cos(a - PI / 8.0) * rr), Vector3(0, rad_to_deg(a - PI / 8.0), 0))
	_k.part(root, _k.cyl(0.28, 0.4, 1.5, 8), Props.STONE, Vector3(0, 1.4, 0))
	_k.part(root, _k.cyl(0.8, 0.35, 0.3, 10), Props.STONE, Vector3(0, 2.2, 0))
	_k.part(root, _k.cyl(0.7, 0.7, 0.04, 10), WATER, Vector3(0, 2.34, 0))
	_k.part(root, _k.cyl(0.1, 0.14, 0.6, 8), Props.STONE, Vector3(0, 2.6, 0))
	_k.part(root, _k.sphere(0.16, 8), Props.STONE, Vector3(0, 2.98, 0))
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var dir := Vector3(sin(a), 0, cos(a))
		var prev := dir * 0.78 + Vector3(0, 2.3, 0)
		for s in 5:
			var t := float(s + 1) / 5.0
			var nxt := dir * (0.78 + t * 0.6) + Vector3(0, 2.3 - t * t * 1.6, 0)
			_k.strip(root, prev, nxt, 0.06, WATER)
			prev = nxt
	_bucket(root, Vector3(-1.2, 0.82, 1.2))


# ---------------------------------------------------------------------- ground
## A random open spot in `streets`, clear of every footprint by `radius`,
## off the paving and away from doors; INF when none is found.
func _ground_spot(streets: Array[Rect2], radius: float) -> Vector3:
	if streets.is_empty():
		return Vector3.INF
	for i in 40:
		var r := streets[_rng.randi() % streets.size()]
		var p := Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y, r.end.y))
		if style == "slums" and _on_paving(p, radius):
			continue
		if not _d.call("is_free", p, radius):
			continue
		var near_door := false
		for door in _doors:
			if door.distance_squared_to(p) < 1.6 * 1.6:
				near_door = true
				break
		if not near_door:
			return p
	return Vector3.INF


func _on_paving(p: Vector3, margin: float) -> bool:
	for r in _paved:
		if r.grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	return false


## Ground height: on top of the cobbles where paved, else just over the mud.
func _ground_y(p: Vector3) -> float:
	return 0.07 if _on_paving(p, 0.0) else 0.012


## A flat, irregular dark puddle: a few overlapping squashed discs.
func _puddle(p: Vector3) -> void:
	var y := _ground_y(p)
	var n := _rng.randi_range(2, 4)
	for i in n:
		var off := Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.35, 0.35)) if i > 0 else Vector3.ZERO
		var r := _rng.randf_range(0.5, 0.95) * (1.0 if i == 0 else 0.7)
		_k.part(_d, _k.cyl(r, r, 0.02, 12), PUDDLE, p + off + Vector3(0, y + i * 0.002, 0),
			Vector3(0, _rng.randf() * 180.0, 0), Vector3(_rng.randf_range(1.0, 1.7), 1.0, 1.0))


func _refuse(p: Vector3) -> void:
	_heap(_d, p, 1.4)


## A low heap of refuse: rags, a broken plank, a staved-in crate, scraps.
func _heap(parent: Node3D, p: Vector3, s: float) -> void:
	var root := _k.node(parent, p, _rng.randf() * 360.0)
	for i in 4:
		var q := Vector3(_rng.randf_range(-0.35, 0.35), 0.08, _rng.randf_range(-0.25, 0.25)) * s
		_k.part(root, _k.sphere(0.2 * s, 6), Props.COAT if i % 2 == 0 else PUDDLE, q,
			Vector3(0, _rng.randf() * 90.0, 0), Vector3(1.3, 0.55, 1.0))
	_k.part(root, _k.box(Vector3(1.0, 0.05, 0.16) * s), Props.WOOD, Vector3(0.1, 0.2, 0.05) * s,
		Vector3(_rng.randf_range(-8, 8), 30.0, 12.0))
	_k.part(root, _k.box(Vector3(0.4, 0.28, 0.35) * s), Props.WOOD, Vector3(-0.4, 0.12, 0.1) * s,
		Vector3(0, 15, 24))
	_k.part(root, _k.box(Vector3(0.12, 0.06, 0.1) * s), Props.TIMBER, Vector3(0.35, 0.04, -0.2) * s)


## An open drain along a street: a dark channel with plank (stage 0) or
## stone (stage 1) edges, broken where the street is paved or blocked.
## `line` = (z, x0, x1).
func _drain(line: Vector3) -> void:
	var edge := Props.WOOD if stage == 0 else Props.STONE
	var x := line.y
	var z := line.x
	while x < line.z:
		var l := _rng.randf_range(1.2, 2.0)
		var nz := clampf(z + _rng.randf_range(-0.18, 0.18), line.x - 0.4, line.x + 0.4)
		var a := Vector3(x, 0, z)
		var b := Vector3(minf(x + l, line.z), 0, nz)
		var mid := (a + b) * 0.5
		if not _on_paving(mid, 0.4) and _d.call("is_free", mid, 0.3):
			var d := b - a
			var yaw := rad_to_deg(atan2(-d.z, d.x))
			placed["drain"] += 1
			var seg := d.length() + 0.04
			_k.part(_d, _k.box(Vector3(seg, 0.02, 0.34)), DRAIN, mid + Vector3(0, 0.012, 0), Vector3(0, yaw, 0))
			var side := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.22)
			for s: float in [-1.0, 1.0]:
				_k.part(_d, _k.box(Vector3(seg, 0.07, 0.09)), edge, mid + side * s + Vector3(0, 0.035, 0), Vector3(0, yaw, 0))
		x += l
		z = nz
