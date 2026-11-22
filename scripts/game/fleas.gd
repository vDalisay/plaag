## Fleas (M7, behind the "unlock_fleas" upgrade): an aura round every Adult
## rat, the Lead Rat included. Every `interval` s each Adult out in the street
## rolls `chance` for each living townsperson within `radius` (ground plane);
## a success Bites them lightly (Infection.bite(BITE_CHUNK, BITE_RATE)).
## Exterminators are never touched. Each success sends 2-3 tiny ink specks
## hopping in an arc from the rat to the victim (one MultiMesh, one draw call).
## Sources: the Colony (duck typed: `lead`, followers() with is_pup), or
## `sources` when set (tests).
extends Node3D

const BITE_CHUNK := 1.0
const BITE_RATE := 0.2
const MAX_SPECKS := 120
const SPECK_SIZE := 0.15
const HOP_TIME := 0.6
const HOP_HEIGHT := 1.5
## Delay between the specks of one hop.
const SPECK_STAGGER := 0.09

var colony: Node
## Test override: these Node3Ds are the Adults (empty = ask the Colony).
var sources: Array[Node3D] = []
var radius := 2.0
var chance := 0.15
var interval := 1.0
## Townsfolk infected by Fleas this Round (debug output).
var hits := 0
var rng := RandomNumberGenerator.new()

var _left := 0.0
var _mm: MultiMesh
## Active specks: [from: Vector3, to: Vector3, age: float (s, < 0 = waiting), sway: Vector3].
var _specks: Array[Array] = []


func _ready() -> void:
	name = "Fleas"
	rng.randomize()
	_left = interval
	_build_specks()


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left += maxf(interval, 0.05)
		tick()


func _process(delta: float) -> void:
	_update_specks(delta)


## One round of rolls; returns how many townsfolk were Bitten.
func tick() -> int:
	var adults := _adults()
	if adults.is_empty():
		return 0
	var targets: Array[InfectionComponent] = []
	var pos := PackedVector3Array()
	for n: Node in get_tree().get_nodes_in_group("townsfolk"):
		var t := n as Node3D
		if t == null or t.is_in_group("exterminator"):
			continue
		var inf := t.get_node_or_null("Infection") as InfectionComponent
		if inf == null or inf.is_dead():
			continue
		targets.append(inf)
		pos.append(t.global_position)
	var r2 := radius * radius
	var n_hit := 0
	for a in adults:
		var ap := a.global_position
		for i in targets.size():
			var dx := pos[i].x - ap.x
			var dz := pos[i].z - ap.z
			if dx * dx + dz * dz > r2 or targets[i].is_dead():
				continue
			if rng.randf() < chance:
				targets[i].bite(BITE_CHUNK, BITE_RATE)
				n_hit += 1
				_hop(ap, pos[i])
	hits += n_hit
	return n_hit


## The Adults out in the street (group "rats": alive, not hidden).
func _adults() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not sources.is_empty():
		for s in sources:
			if is_instance_valid(s):
				out.append(s)
		return out
	if colony == null:
		return out
	var lead := colony.get("lead") as Node3D
	if lead and lead.is_in_group("rats"):
		out.append(lead)
	for r: Node3D in colony.call("followers"):
		if is_instance_valid(r) and r.is_in_group("rats") and not bool(r.get("is_pup")):
			out.append(r)
	return out


# ---------------------------------------------------------------------- specks
func _build_specks() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var m := BoxMesh.new()
	m.size = Vector3.ONE * SPECK_SIZE
	_mm.mesh = m
	_mm.instance_count = MAX_SPECKS
	_mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.05, 0.04)
	mat.roughness = 1.0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Specks"
	mmi.multimesh = _mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
	mmi.top_level = true
	add_child(mmi)


## 2-3 specks from a rat (at `from`) to its victim (at `to`), staggered.
func _hop(from: Vector3, to: Vector3) -> void:
	var n := rng.randi_range(2, 3)
	for i in n:
		if _specks.size() >= MAX_SPECKS:
			return
		var sway := Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.35, 0.35))
		_specks.append([from + Vector3(0, 0.25, 0), to + Vector3(0, 1.1, 0), -i * SPECK_STAGGER, sway])


## Active specks in flight (tests).
func speck_count() -> int:
	return _specks.size()


func _update_specks(delta: float) -> void:
	if _specks.is_empty() and _mm.visible_instance_count == 0:
		return
	var shown := 0
	var i := 0
	while i < _specks.size():
		var s: Array = _specks[i]
		s[2] = float(s[2]) + delta
		var age: float = s[2]
		if age >= HOP_TIME:
			_specks.remove_at(i)
			continue
		i += 1
		if age < 0.0:
			continue
		var f := age / HOP_TIME
		var from: Vector3 = s[0]
		var to: Vector3 = s[1]
		var sway: Vector3 = s[3]
		var p := from.lerp(to, f) + Vector3(0, 4.0 * f * (1.0 - f) * HOP_HEIGHT, 0) + sway * sin(f * PI)
		var spin := Basis.from_euler(Vector3(f * 9.0, f * 7.0, 0.0))
		_mm.set_instance_transform(shown, Transform3D(spin, p))
		shown += 1
	_mm.visible_instance_count = shown
