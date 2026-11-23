## Ambient life of a District (graphics pass B.3-B.8): owns the chimney
## smoke, the crows, the laundry and shop signs, the water ripples, the
## lantern flicker, the plague stain on the page and what happens to a house
## when it falls (its windows go dark, its chimney goes cold, crows gather).
## The District builds it after its meshes are merged and hands it what it
## knows (setup()). Reads Settings.effects_level duck-typed (1 Full, 0
## Reduced) and Settings.reduce_motion, and follows Settings.changed.
## Effects use the scaled delta, so they freeze with the pause and hit-stop.
##
## Debug flags (after `--`): --stain=<0..1> fixes the plague stain,
## --ambient-test puts crows next to the Lead Rat and scatters them after 2 s.
extends Node3D

const Props := preload("res://scripts/town_props.gd")
const Smoke := preload("res://scripts/world/chimney_smoke.gd")
const Crows := preload("res://scripts/world/crows.gd")
const Sway := preload("res://scripts/world/sway.gd")
const Ripples := preload("res://scripts/world/ripples.gd")

const SMOKE_CAP := 72
## Plague stain: District Infection (0..1) where it starts and where it is full,
## and how fast (per s) the stain follows it.
const STAIN_FROM := 0.08
const STAIN_FULL := 0.85
const STAIN_RATE := 0.12
## The overlay's glow_lift, so the lanterns' flicker shows through the shader.
const GLOW_LIFT := 0.8
const LANTERN_VARIANTS := 5

var smoke: Node3D
var crows: Node3D
var sway: Node3D
var ripples: Node3D
var effects_level := 1

var _kit: Props
var _overlay: ShaderMaterial
var _director: Node
var _vfx: Node
var _lookup_left := 0.0
var _stain := 0.0
var _stain_target := 0.0
var _stain_fixed := -1.0
var _time := 0.0
var _lanterns: Array[StandardMaterial3D] = []
var _lantern_base := PackedFloat32Array()
var _window_lit: Material
var _window_dark: Material
var _test_left := -1.0
var _style := "slums"
var _reduce_motion := false


## info: "style", "seed", "bounds" (Rect2), "houses" (Array of {"house":
## House, "root": Node3D (the visual root, merged), "roof_root": Node3D,
## "chimney": Vector3 (roof_root frame, NAN x: none), "ridge": [Vector3,
## Vector3] (roof_root frame)}), "perches" (Array of [a, b] world segments),
## "laundry" (Array of [a, b]), "signs" (Array of [root, pivot]), "water"
## (Array of [centre, radius]), "overlay" (the parchment ShaderMaterial).
func setup(kit: Props, info: Dictionary) -> void:
	_kit = kit
	_style = info.get("style", "slums")
	var seed_value: int = info.get("seed", 1)
	_overlay = info.get("overlay")
	_window_lit = kit.mat(Props.AMBER, Props.WINDOW_LIGHT)
	_window_dark = kit.mat(Props.INK)
	effects_level = _effects_level()

	smoke = Smoke.new()
	smoke.name = "ChimneySmoke"
	add_child(smoke)
	smoke.call("setup", kit, SMOKE_CAP, seed_value + 1)
	crows = Crows.new()
	crows.name = "Crows"
	add_child(crows)
	crows.call("setup", kit, info.get("bounds", Rect2(-22, -22, 44, 44)), seed_value + 2)
	crows.set("base_count", 9 if _style == "slums" else 8)

	var interval := 1.15 if _style == "slums" else 0.8
	for h: Dictionary in info.get("houses", []):
		var house: Node = h["house"]
		var roof_root: Node3D = h["roof_root"]
		var chim: Vector3 = h["chimney"]
		if not is_nan(chim.x):
			smoke.call("add_emitter", roof_root, chim + Vector3(0, 0.05, 0), house, interval)
		var ridge: Array = h["ridge"]
		for t: float in [0.2, 0.5, 0.8]:
			var p: Vector3 = (ridge[0] as Vector3).lerp(ridge[1], t)
			crows.call("add_perch", roof_root, p, 0.0, house)
		if house and house.has_signal("house_died"):
			house.connect("house_died", _on_house_died.bind(h))
	for seg: Array in info.get("perches", []):
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var n := maxi(1, int(a.distance_to(b) / 2.5))
		var yaw := atan2(b.x - a.x, b.z - a.z)
		for k in n:
			crows.call("add_perch", null, a.lerp(b, (k + 0.5) / n), yaw)
	crows.call("populate")

	sway = Sway.new()
	sway.name = "Sway"
	add_child(sway)
	sway.call("setup", kit, info.get("laundry", []), info.get("signs", []), seed_value + 3)
	ripples = Ripples.new()
	ripples.name = "Ripples"
	add_child(ripples)
	ripples.call("setup", kit, info.get("water", []), seed_value + 4)

	if _overlay:
		_overlay.set_shader_parameter("glow_lift", GLOW_LIFT)
	_parse_args()
	_apply_settings()
	var settings := get_node_or_null("/root/Settings")
	if settings:
		if settings.has_signal("changed") and not settings.is_connected("changed", _apply_settings):
			settings.connect("changed", _apply_settings)


## Gives each lantern part (prop-kit lantern material, after merging) one of
## a few flicker materials of its own, picked by position.
func collect_lanterns(root: Node) -> void:
	var src := _kit.mat(Props.AMBER, 3.0)
	var variants: Array[StandardMaterial3D] = []
	for k in LANTERN_VARIANTS:
		var m := src.duplicate() as StandardMaterial3D
		variants.append(m)
		_lanterns.append(m)
		_lantern_base.append(src.emission_energy_multiplier)
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == src:
			var p := mi.global_position + mi.get_aabb().get_center()
			var k := absi(int(floor(p.x * 0.37) * 7 + floor(p.z * 0.41) * 13)) % LANTERN_VARIANTS
			mi.material_override = variants[k]


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stain="):
			_stain_fixed = clampf(float(arg.trim_prefix("--stain=")), 0.0, 1.0)
		elif arg == "--ambient-test":
			_test_left = 2.0
			var lead := get_tree().get_first_node_in_group("lead_rat") as Node3D
			if lead:
				crows.call("test_near", lead.global_position, 5)
				print("AMBIENT crows placed by the Lead Rat: 5")


func _effects_level() -> int:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return 1
	var v: Variant = settings.get("effects_level")
	return int(v) if v != null else 1


func _read_reduce_motion() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and bool(settings.get("reduce_motion"))


func _apply_settings() -> void:
	effects_level = _effects_level()
	var full := effects_level >= 1
	smoke.call("set_cap", SMOKE_CAP if full else SMOKE_CAP / 2)
	crows.set("max_count", Crows.CAP if full else Crows.CAP / 2)
	_reduce_motion = _read_reduce_motion()
	sway.set("amplitude", 0.5 if _reduce_motion else 1.0)


# ---------------------------------------------------------------------- update
func _process(delta: float) -> void:
	_time += delta
	_lookup_left -= delta
	if _lookup_left <= 0.0:
		_lookup_left = 1.0
		_lookup()
	_update_stain(delta)
	_update_lanterns()
	if _test_left > 0.0:
		_test_left -= delta
		if _test_left <= 0.0:
			var lead := get_tree().get_first_node_in_group("lead_rat") as Node3D
			var n: int = crows.call("scatter_test", lead.global_position if lead else Vector3.ZERO)
			print("AMBIENT crows scatter: %d" % n)


## Finds the RoundDirector and the Vfx node lazily (both are optional).
func _lookup() -> void:
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("round_director")
		if _director and _director.has_signal("stats_changed"):
			_director.connect("stats_changed", _on_stats_changed)
			_on_stats_changed()
	if _vfx == null or not is_instance_valid(_vfx):
		_vfx = get_tree().get_first_node_in_group("vfx")
		if _vfx and _vfx.has_signal("disturbance") and not _vfx.is_connected("disturbance", _on_disturbance):
			_vfx.connect("disturbance", _on_disturbance)


func _on_stats_changed() -> void:
	if _director == null or not _director.has_method("district_infection"):
		return
	var inf := float(_director.call("district_infection"))
	if inf > 1.0:
		inf /= 100.0   # the contract allows 0..100 too
	_stain_target = clampf((inf - STAIN_FROM) / (STAIN_FULL - STAIN_FROM), 0.0, 1.0)


func _on_disturbance(point: Vector3, radius: float) -> void:
	crows.call("disturb", point, radius)


func _update_stain(delta: float) -> void:
	if _overlay == null:
		return
	var goal := _stain_fixed if _stain_fixed >= 0.0 else _stain_target
	var next := move_toward(_stain, goal, STAIN_RATE * delta) if _stain_fixed < 0.0 else goal
	if not is_equal_approx(next, _stain) or _time < 0.1:
		_stain = next
		_overlay.set_shader_parameter("plague_stain", _stain)


## A slow, smooth wobble of each lantern's glow (never a flash).
func _update_lanterns() -> void:
	var amp := 0.1 if _reduce_motion else 0.2
	for k in _lanterns.size():
		var ph := k * 2.3
		var w := 0.55 * sin(_time * 2.1 + ph) + 0.3 * sin(_time * 3.4 + ph * 1.7) + 0.15 * sin(_time * 0.9 + ph * 0.6)
		_lanterns[k].emission_energy_multiplier = _lantern_base[k] * (1.0 + w * amp)


# ---------------------------------------------------------------------- houses
## A fallen house: its lit windows go dark ink, its chimney goes cold and the
## crows gather on it.
func _on_house_died(h: Dictionary) -> void:
	var root: Node3D = h["root"]
	if is_instance_valid(root):
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.material_override == _window_lit:
				mi.material_override = _window_dark
	smoke.call("stop", h["house"])
	crows.call("add_dead", h["house"])
