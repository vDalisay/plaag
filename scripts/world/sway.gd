## Things that move in the wind (graphics pass B.7): laundry lines across the
## slum alleys with pale cloth swaying on them, and hanging shop signs that
## swing from their brackets in the Merchant quarter. Pooled MultiMeshes,
## CPU-updated; no nodes per frame.
## A laundry line folds away (squashes) while the Lead Rat is under it, so it
## never hides the rat; signs hang from house roots and squash with the cutaway.
extends Node3D

const WorldMesh := preload("res://scripts/world/world_mesh.gd")
const Props := preload("res://scripts/town_props.gd")

## Cloth is always pale (never red): linen, cream, grey wool.
const CLOTHS: Array[Color] = [Color(0.93, 0.90, 0.82), Color(0.84, 0.80, 0.72), Color(0.74, 0.71, 0.65),
	Color(0.95, 0.93, 0.88)]
const ROPE_SEGMENTS := 4
## The line folds away while the Lead Rat is closer than this (ground plan).
const CLEAR_RADIUS := 3.2

## Swing amplitude scale (reduce motion halves it).
var amplitude := 1.0

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _lead: Node3D
# Laundry: per line {"a", "b", "fold": float, "first_rope", "first_cloth", "cloths": int}.
var _lines: Array[Dictionary] = []
var _ropes: MultiMesh
var _cloth: MultiMesh
# Per cloth piece: line index, rope point, size, phase.
var _c_line := PackedInt32Array()
var _c_t := PackedFloat32Array()
var _c_size := PackedVector2Array()
var _c_phase := PackedFloat32Array()
# Signs: per sign root + pivot (in the root's frame) + phase.
var _sign_roots: Array[Node3D] = []
var _sign_pivot := PackedVector3Array()
var _sign_phase := PackedFloat32Array()
var _signs: MultiMesh


## `lines`: Array of [a: Vector3, b: Vector3] world end points (rope height
## included). `signs`: Array of [root: Node3D, pivot: Vector3 (root frame)].
func setup(kit: Props, lines: Array, signs: Array, seed_value: int) -> void:
	_rng.seed = seed_value
	if not lines.is_empty():
		_build_laundry(kit, lines)
	if not signs.is_empty():
		_build_signs(kit, signs)


func _build_laundry(kit: Props, lines: Array) -> void:
	var cloth_colors: Array[Color] = []
	for l: Array in lines:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var n := clampi(int(a.distance_to(b) / 0.75), 2, 5)
		var line := {"a": a, "b": b, "fold": 1.0, "first_cloth": _c_line.size(), "cloths": n}
		var used := 0.1
		for k in n:
			var w := _rng.randf_range(0.32, 0.55)
			var t := clampf(used + w * 0.5 / maxf(a.distance_to(b), 0.1) + _rng.randf_range(0.0, 0.08), 0.1, 0.9)
			used = t + w * 0.5 / maxf(a.distance_to(b), 0.1) + 0.04
			if used > 0.95:
				break
			_c_line.append(_lines.size())
			_c_t.append(t)
			_c_size.append(Vector2(w, _rng.randf_range(0.38, 0.72)))
			_c_phase.append(_rng.randf() * TAU)
			cloth_colors.append(CLOTHS[_rng.randi() % CLOTHS.size()])
		line["cloths"] = _c_line.size() - int(line["first_cloth"])
		_lines.append(line)
	_ropes = WorldMesh.multimesh(self, kit.box(Vector3(1.0, 0.035, 0.035)), _lines.size() * ROPE_SEGMENTS,
		kit.mat(Props.TIMBER), false, "LaundryRopes").multimesh
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.vertex_color_is_srgb = true
	cm.roughness = 1.0
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth = WorldMesh.multimesh(self, kit.box(Vector3(1.0, 1.0, 0.03)), _c_line.size(), cm, true, "Laundry").multimesh
	for i in _c_line.size():
		_cloth.set_instance_color(i, cloth_colors[i])


## The sagging rope's point at t (0..1).
func _rope_point(line: Dictionary, t: float) -> Vector3:
	var a: Vector3 = line["a"]
	var b: Vector3 = line["b"]
	return a.lerp(b, t) - Vector3(0, sin(PI * t) * 0.28 * float(line["fold"]), 0)


func _build_signs(kit: Props, signs: Array) -> void:
	var board := Props.WOOD
	var ink := Props.INK
	var mesh := WorldMesh.bake([
		[kit.box(Vector3(0.035, 0.16, 0.035)), Transform3D(Basis(), Vector3(-0.34, -0.08, 0)), ink],
		[kit.box(Vector3(0.035, 0.16, 0.035)), Transform3D(Basis(), Vector3(0.34, -0.08, 0)), ink],
		[kit.box(Vector3(0.95, 0.62, 0.07)), Transform3D(Basis(), Vector3(0, -0.47, 0)), board],
		[kit.box(Vector3(1.0, 0.07, 0.09)), Transform3D(Basis(), Vector3(0, -0.17, 0)), Props.TIMBER],
		[kit.box(Vector3(1.0, 0.07, 0.09)), Transform3D(Basis(), Vector3(0, -0.77, 0)), Props.TIMBER],
		[kit.cyl(0.16, 0.16, 0.09, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.47, 0)), ink],
	])
	_signs = WorldMesh.multimesh(self, mesh, signs.size(), WorldMesh.vc_material(), false, "Signs").multimesh
	for s: Array in signs:
		_sign_roots.append(s[0])
		_sign_pivot.append(s[1])
		_sign_phase.append(_rng.randf() * TAU)


func _process(delta: float) -> void:
	_time += delta
	if _cloth:
		_update_laundry(delta)
	if _signs:
		_update_signs()


func _update_laundry(delta: float) -> void:
	if _lead == null or not is_instance_valid(_lead):
		_lead = get_tree().get_first_node_in_group("lead_rat") as Node3D
	var lp := _lead.global_position if _lead else Vector3.INF
	for li in _lines.size():
		var line := _lines[li]
		var a: Vector3 = line["a"]
		var b: Vector3 = line["b"]
		var near := lp.is_finite() and _dist_to_segment_2d(lp, a, b) < CLEAR_RADIUS
		var fold := move_toward(float(line["fold"]), 0.0 if near else 1.0, delta * 4.0)
		line["fold"] = fold
		for k in ROPE_SEGMENTS:
			var p0 := _rope_point(line, float(k) / ROPE_SEGMENTS)
			var p1 := _rope_point(line, float(k + 1) / ROPE_SEGMENTS)
			var d := p1 - p0
			var xf := Transform3D(Basis(), (p0 + p1) * 0.5)
			if fold > 0.01:
				var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
				xf.basis = Basis.looking_at(d, up) * Basis(Vector3.UP, PI * 0.5)
				xf.basis = xf.basis * Basis.from_scale(Vector3(d.length() + 0.02, fold, fold))
			else:
				xf.basis = Basis.from_scale(Vector3.ZERO)
			_ropes.set_instance_transform(li * ROPE_SEGMENTS + k, xf)
	var dir_cache := Vector3.RIGHT
	for i in _c_line.size():
		var line := _lines[_c_line[i]]
		var fold: float = line["fold"]
		if fold <= 0.01:
			_cloth.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
			continue
		var a: Vector3 = line["a"]
		var b: Vector3 = line["b"]
		dir_cache = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var size := _c_size[i]
		var ph := _c_phase[i]
		var swing := (0.22 * sin(_time * 1.6 + ph) + 0.08 * sin(_time * 3.3 + ph * 1.7)) * amplitude
		var p := _rope_point(line, _c_t[i])
		var base := Basis(dir_cache, Vector3.UP, dir_cache.cross(Vector3.UP))
		var rot := base * Basis(Vector3.RIGHT, swing)
		var hang := rot * Vector3(0, -size.y * 0.5 * fold, 0)
		_cloth.set_instance_transform(i, Transform3D(rot * Basis.from_scale(Vector3(size.x, size.y * fold, 1.0)), p + hang))


func _update_signs() -> void:
	for i in _sign_roots.size():
		var root := _sign_roots[i]
		if not is_instance_valid(root):
			_signs.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
			continue
		var ph := _sign_phase[i]
		var swing := (0.16 * sin(_time * 1.25 + ph) + 0.05 * sin(_time * 2.7 + ph * 1.3)) * amplitude
		_signs.set_instance_transform(i, root.global_transform * Transform3D(Basis(Vector3.RIGHT, swing), _sign_pivot[i]))


static func _dist_to_segment_2d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()
