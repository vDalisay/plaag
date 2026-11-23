## The recipe of every event effect: which particles and ground marks a
## burst kind makes. Colours follow the effect colour rules: RED for plague
## only, near-black ink for rat deaths / impacts / flies, pale parchment for
## dust and smoke, sage GREEN for the Plague Doctor, AMBER (emissive) for fire.
## Bursts stay low (<= 0.8 u near the ground) and short (<= 1 s).
## play(kind, pos, dir, scale, extra): `pos` on the ground (y ignored unless
## the kind says so), `dir` a direction (flat) where it matters, `scale` the
## size, `extra` a kind-specific number.
extends RefCounted

const Particles := preload("res://scripts/vfx/vfx_particles.gd")
const C := Particles.Life

const INK := Color(0.06, 0.05, 0.04)
const RED := Color(0.72, 0.12, 0.10)
## A softer plague red for clouds (still saturated enough to stay a red wash).
const RED_SOFT := Color(0.80, 0.30, 0.25)
const PALE := Color(0.93, 0.88, 0.76)
const PALE2 := Color(0.82, 0.78, 0.70)
const PLASTER := Color(0.88, 0.85, 0.78)
const STRAW := Color(0.76, 0.68, 0.53)
const GREEN := Color(0.30, 0.55, 0.25)
const GREEN_SOFT := Color(0.42, 0.62, 0.34)
const AMBER := Color(1.0, 0.55, 0.10)
## Ground marks: a corpse's blot (dark sepia, hatched dense by the shader),
## what's left of an eaten corpse, scorched ground.
const SEPIA := Color(0.42, 0.36, 0.29)
const REMAINS := Color(0.35, 0.29, 0.24)
const SCORCH := Color(0.36, 0.30, 0.24)

## Size factors for the far game camera (see _pe).
const PUFF_K := 2.0
const STROKE_K := 1.6
const STROKE_LEN_K := 1.5
const FLAME_K := 1.5

## Height of each mark kind over the base (later kinds lie on top).
const LAYER := {&"blot": 0.0, &"scorch": 0.002, &"crack": 0.004, &"remains": 0.008, &"splat": 0.008, &"drop": 0.011}

## Every kind, in the order --vfx-test plays them.
const TEST_KINDS: Array[StringName] = [
	&"bite", &"infect", &"cough", &"flies", &"topple", &"blot", &"corpse_splat", &"rat_splat",
	&"lead_hurt", &"lead_death", &"nibble", &"pup_born", &"pup_mature", &"run_dust",
	&"stomp", &"broom", &"club", &"fire_test", &"cat_pounce", &"trap_snap", &"herb", &"heal",
	&"cleanse_pulse", &"incense_trail", &"incense", &"ext_arrive", &"ext_beaten", &"contagion",
	&"door_dust", &"plaster", &"house_miasma",
]

var v: Node3D
var puffs: Particles
var strokes: Particles
var flames: Particles


func _init(vfx: Node3D) -> void:
	v = vfx
	puffs = vfx.get("puffs")
	strokes = vfx.get("strokes")
	flames = vfx.get("flames")


func play(kind: StringName, pos: Vector3, dir: Vector3, scale: float, extra: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else _rand_flat()
	match kind:
		&"bite": _bite(pos, flat, scale)
		&"infect": _infect(pos)
		&"cough": _cough(pos, flat)
		&"topple": _dust_ring(pos, _n(6), 0.25, 1.4, Vector2(0.16, 0.24), 0.6)
		&"blot": mark(&"blot", pos, randf() * TAU, 0.8 * scale, 45.0)
		&"corpse_splat": _corpse_splat(pos, scale)
		&"rat_splat": _rat_splat(pos, scale)
		&"lead_hurt": _lead_hurt(pos)
		&"lead_death": _lead_death(pos)
		&"nibble": _nibble(pos)
		&"pup_born": _pup_born(pos)
		&"pup_mature": _ink_ring(pos, 0.25, 0.75, _n(10), 0.3, 0.3)
		&"run_dust": _run_dust(pos, flat, scale)
		&"stomp": _stomp(pos, scale)
		&"club": _club(pos, scale)
		&"broom": _broom(pos, flat, scale, extra if extra > 0.0 else 100.0)
		&"flame": _flame(pos, scale)
		&"smoke": _smoke(pos, scale)
		&"fire_test": _fire_test(pos)
		&"cat_pounce": _dust_ring(pos, _n(5), 0.2, 1.6, Vector2(0.12, 0.18), 0.5)
		&"trap_snap": _star(pos + Vector3(0, 0.35, 0), _n(7), 0.4, 0.3)
		&"herb": _herb(pos, scale)
		&"heal": _heal(pos)
		&"cleanse_pulse": _cleanse_pulse(pos, scale, extra if extra > 0.0 else 0.5)
		&"incense_trail": _incense_trail(pos)
		&"incense": _incense(pos, scale)
		&"ext_arrive": _ext_arrive(pos)
		&"ext_beaten": _ext_beaten(pos)
		&"contagion": _contagion(pos, dir if dir.length_squared() > 0.01 else flat * 1.8)
		&"door_dust": _door_dust(pos, flat)
		&"plaster": _plaster(pos, flat)
		&"house_miasma": _house_miasma(pos)
		_:
			push_warning("Vfx: unknown burst kind %s" % kind)


## Ground marks by kind name (decal()).
func mark(kind: StringName, pos: Vector3, rot: float, size: float, life: float, spread := 0.15) -> void:
	var d: Variant = v.get("decals")
	# Each kind on its own layer (no z-fighting where marks overlap).
	var y := _ground(pos) + 0.02 + float(LAYER.get(kind, 0.006)) + randf() * 0.0015
	var at := Vector3(pos.x, y, pos.z)
	match kind:
		&"blot":
			d.call("add", &"blob", at, rot, size, life, 0.6, SEPIA, 0.7)
		&"splat":
			_splat_mark(at, size, life, INK, spread)
		&"remains":
			_splat_mark(at, size, life, REMAINS, spread)
		&"drop":
			d.call("add", &"drop", at, rot, size, life, spread, INK)
		&"crack":
			d.call("add", &"crack", at, rot, size, life, spread, INK)
		&"scorch":
			d.call("add", &"scorch", at, rot, size, life, 0.3, SCORCH)
		_:
			push_warning("Vfx: unknown decal kind %s" % kind)


# ---------------------------------------------------------------------- plague
## 3-6 red droplets spraying on past the victim from its biter, and an ink
## "snap": two tiny crossing strokes facing the camera.
func _bite(pos: Vector3, away: Vector3, scale: float) -> void:
	var o := Vector3(pos.x, 0.55, pos.z) - away * 0.2
	var n := _n(clampi(3 + roundi(scale * 1.5), 3, 6))
	var side := away.cross(Vector3.UP)
	for i in n:
		var vel := away * randf_range(1.0, 2.2) + Vector3.UP * randf_range(1.2, 2.4) + side * randf_range(-0.9, 0.9)
		_drop(o, vel, randf_range(0.07, 0.1) * clampf(0.8 + scale * 0.2, 0.8, 1.3), randf_range(0.45, 0.6), RED)
	var tick := o + Vector3(0, 0.15, 0) - away * 0.1
	for s: float in [1.0, -1.0]:
		var axis := (v.get("cam_right") as Vector3) * 0.7071 + (v.get("cam_up") as Vector3) * (0.7071 * s)
		_se(tick, Vector3.ZERO, Vector3(0.035, 0.035, 0.3), 0.15, C.TICK, INK, 0.0, 0.0, axis)


## First infection: a soft red ring of puffs round the chest, swelling out.
func _infect(pos: Vector3) -> void:
	var c := Vector3(pos.x, 1.3, pos.z)
	var n := _n(8)
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.25, 0.25)
		var o := Vector3(cos(a), 0.0, sin(a))
		_puff(c + o * randf_range(0.3, 0.45) + Vector3(0, randf_range(-0.15, 0.15), 0), o * randf_range(0.6, 1.0) + Vector3.UP * 0.2,
			randf_range(0.12, 0.22), randf_range(0.55, 0.7), RED_SOFT, 0.0, 1.5)


## A pale puff from the mouth drifting forward, one red fleck in it.
func _cough(mouth: Vector3, fwd: Vector3) -> void:
	for i in _n(2):
		_puff(mouth + fwd * 0.1 * i, fwd * 0.7 + Vector3.UP * 0.15 + _rand_flat() * 0.15,
			randf_range(0.15, 0.2), 0.9, PALE, 0.0, 1.2)
	_pe(mouth + fwd * 0.08, fwd * 0.85 + Vector3.UP * 0.05, Vector3.ONE * 0.06, 0.85, C.DROP, RED, 0.0, 1.0)


## Contagion: red cough clouds drifting from one person to the next. `span`
## is from the coughing mouth to the other person's chest.
func _contagion(mouth: Vector3, span: Vector3) -> void:
	var life := 0.85
	_puff(mouth, span.normalized() * 0.4, 0.16, 0.6, PALE, 0.0, 1.0)
	for i in _n(3):
		var k := randf_range(0.8, 1.05)
		var vel := span * k / life + Vector3(0, randf_range(-0.1, 0.25), 0) + _rand_flat() * 0.2
		_pe(mouth + span * 0.06 * i, vel, Vector3.ONE * randf_range(0.17, 0.23), life, C.DROP, RED_SOFT)


## A red miasma puff rising from the roof of a fallen house (`pos` with y).
func _house_miasma(pos: Vector3) -> void:
	for i in _n(8):
		var o := _rand_flat() * randf_range(0.0, 0.9)
		_puff(pos + o, Vector3.UP * randf_range(0.6, 1.1) + o * 0.3, randf_range(0.26, 0.38), randf_range(0.8, 1.0),
			RED_SOFT if i % 3 != 0 else RED, 0.0, 0.6)


## The Exterminator beaten: a big red miasma bloom. The Round ends (and the
## world pauses) on the same frame, so it is shown already half bloomed.
func _ext_beaten(pos: Vector3) -> void:
	var c := Vector3(pos.x, 0.4, pos.z)
	for i in _n(18):
		var a := TAU * float(i) / 18.0 + randf() * 0.3
		var o := Vector3(cos(a), 0.0, sin(a))
		var r := randf_range(0.2, 0.9)
		_pe(c + o * r + Vector3(0, randf_range(0.0, 0.6), 0), o * randf_range(1.2, 2.0) + Vector3.UP * randf_range(0.5, 1.3),
			Vector3.ONE * randf_range(0.4, 0.62), 1.0, C.PUFF, RED_SOFT if i % 4 != 0 else RED, 0.0, 1.4, Vector3.ZERO, -INF, 0.3)
	_splat_mark(Vector3(pos.x, _ground(pos) + 0.024, pos.z), 1.0, 30.0, Color(0.55, 0.12, 0.09), 0.0)


# ---------------------------------------------------------------------- deaths
## What's left of an eaten corpse: an irregular blob plus satellite drops.
func _corpse_splat(pos: Vector3, scale: float) -> void:
	mark(&"remains", pos, 0.0, 0.75 * scale, 40.0, 0.2)
	for i in _n(3):
		_drop(Vector3(pos.x, 0.25, pos.z), _rand_flat() * randf_range(1.0, 1.8) + Vector3.UP * 1.5, 0.06, 0.4, INK)


## A rat's death: radial ink droplets and an ink splat on the ground.
func _rat_splat(pos: Vector3, scale: float) -> void:
	var c := Vector3(pos.x, 0.15, pos.z)
	for i in _n(7):
		var o := _rand_flat()
		_drop(c, o * randf_range(1.2, 2.4) * scale + Vector3.UP * randf_range(1.0, 1.8), randf_range(0.055, 0.08) * scale,
			randf_range(0.35, 0.5), INK)
	mark(&"splat", pos, 0.0, 0.34 * scale, 9.0, 0.1)


## The Lead Rat is hurt: a bigger ink burst and an ink ring.
func _lead_hurt(pos: Vector3) -> void:
	var c := Vector3(pos.x, 0.3, pos.z)
	for i in _n(10):
		var o := _rand_flat()
		_drop(c, o * randf_range(1.8, 3.0) + Vector3.UP * randf_range(1.4, 2.4), randf_range(0.07, 0.11), 0.5, INK)
	_ink_ring(pos, 0.35, 1.5, _n(16), 0.35, 0.36)
	mark(&"splat", pos, 0.0, 0.32, 5.0, 0.08)


## The Lead Rat dies: a large splat (shown at once: the Round ends with it).
func _lead_death(pos: Vector3) -> void:
	var c := Vector3(pos.x, 0.2, pos.z)
	for i in _n(12):
		var o := _rand_flat()
		_pe(c, o * randf_range(2.0, 3.4) + Vector3.UP * randf_range(1.2, 2.2), Vector3.ONE * randf_range(0.08, 0.12),
			0.6, C.DROP, INK, 9.0, 0.4, Vector3.ZERO, _ground(pos) + 0.03, 0.12)
	_splat_mark(Vector3(pos.x, _ground(pos) + 0.026, pos.z), 0.85, 60.0, INK, 0.0)


## Feeding: two tiny dark flecks nibbled off.
func _nibble(pos: Vector3) -> void:
	for i in _n(2):
		_drop(Vector3(pos.x, 0.25, pos.z), _rand_flat() * randf_range(0.4, 0.9) + Vector3.UP * randf_range(1.0, 1.6),
			0.045, 0.35, INK if i == 0 else REMAINS)


## A Pup is born: a pale puff and three ink sparkle ticks.
func _pup_born(pos: Vector3) -> void:
	var c := Vector3(pos.x, 0.15, pos.z)
	for i in _n(3):
		_puff(c + _rand_flat() * 0.15, _rand_flat() * 0.5 + Vector3.UP * 0.3, randf_range(0.12, 0.16), 0.5, PALE, 0.0, 2.0)
	var r: Vector3 = v.get("cam_right")
	var u: Vector3 = v.get("cam_up")
	for i in 3:
		var a := PI * 0.5 + TAU * float(i) / 3.0
		var axis := r * cos(a) + u * sin(a)
		_se(c + Vector3(0, 0.25, 0) + axis * 0.28, axis * 0.6, Vector3(0.03, 0.03, 0.15), 0.32, C.TICK, INK, 0.0, 2.0, axis)


# ---------------------------------------------------------------------- weapons
func _stomp(pos: Vector3, radius: float) -> void:
	_dust_ring(pos, _n(9), radius * 0.45, radius * 2.6, Vector2(0.18, 0.26), 0.55)
	mark(&"crack", pos, randf() * TAU, radius * 0.85, 6.0, 0.06)


## Club: an ink impact star of spikes, dust, and a wider crack.
func _club(pos: Vector3, radius: float) -> void:
	_star(pos + Vector3(0, 0.45, 0), _n(9), 0.55, 0.28)
	_dust_ring(pos, _n(7), radius * 0.4, radius * 2.2, Vector2(0.2, 0.28), 0.55)
	mark(&"crack", pos, randf() * TAU, radius * 1.0, 7.0, 0.05)


## Broom: dust swept along the arc (from `origin`, facing `fwd`, `radius`
## long, `arc_deg` wide) and straw flecks flung out.
func _broom(origin: Vector3, fwd: Vector3, radius: float, arc_deg: float) -> void:
	var half := deg_to_rad(arc_deg) * 0.5
	var base := atan2(fwd.x, fwd.z)
	var n := _n(9)
	for i in n:
		var a := base + lerpf(-half, half, float(i) / float(maxi(n - 1, 1)))
		var o := Vector3(sin(a), 0.0, cos(a))
		var tangent := Vector3(cos(a), 0.0, -sin(a))
		var p := Vector3(origin.x, 0.15, origin.z) + o * radius * randf_range(0.75, 0.95)
		_puff(p, o * 1.4 + tangent * 1.0 + Vector3.UP * 0.25, randf_range(0.14, 0.2), randf_range(0.45, 0.55), PALE, 0.0, 3.0)
	for i in _n(6):
		var a := base + randf_range(-half, half)
		var o := Vector3(sin(a), 0.0, cos(a))
		var p := Vector3(origin.x, 0.2, origin.z) + o * radius * randf_range(0.5, 0.9)
		_se(p, o * randf_range(1.5, 2.6) + Vector3.UP * randf_range(1.6, 2.4), Vector3(0.03, 0.03, 0.2),
			randf_range(0.5, 0.65), C.DROP, STRAW, 8.0, 0.5, Vector3.ZERO, _ground(p) + 0.02)


## One flame tongue of a fire patch (AMBER, emissive, flickering).
func _flame(pos: Vector3, scale: float) -> void:
	var s := randf_range(0.7, 1.1) * scale
	_fe(Vector3(pos.x, 0.08, pos.z), Vector3.UP * randf_range(0.5, 0.9) + _rand_flat() * 0.15,
		Vector3(0.26, 0.55, 0.26) * s, randf_range(0.35, 0.5), C.FLAME, AMBER, 0.0, 1.5)


## Pale smoke rising off a fire.
func _smoke(pos: Vector3, scale: float) -> void:
	_puff(Vector3(pos.x, 0.55, pos.z), Vector3.UP * randf_range(0.7, 1.0) + _rand_flat() * 0.2,
		randf_range(0.16, 0.22) * scale, randf_range(0.8, 1.0), PALE2, 0.0, 0.4)


func _fire_test(pos: Vector3) -> void:
	for i in 10:
		_flame(pos + _rand_flat() * randf_range(0.0, 0.6), 1.0)
	for i in 3:
		_smoke(pos + _rand_flat() * 0.4, 1.0)
	mark(&"scorch", pos, randf() * TAU, 0.85, 4.0)


# ---------------------------------------------------------------------- doctor
## Sage herb smoke swirling round the Plague Doctor's cleanse aura.
func _herb(centre: Vector3, radius: float) -> void:
	var a := randf() * TAU
	var r := randf_range(1.1, 1.7) * radius
	var o := Vector3(cos(a), 0.0, sin(a))
	var tangent := Vector3(-sin(a), 0.0, cos(a))
	_puff(Vector3(centre.x, randf_range(0.4, 1.2), centre.z) + o * r, tangent * randf_range(1.2, 1.8) + Vector3.UP * 0.25 - o * 0.25,
		randf_range(0.18, 0.26), randf_range(0.8, 1.0), GREEN_SOFT if randf() < 0.6 else GREEN, 0.0, 0.3)


## Green flecks rising from a cleansed townsperson.
func _heal(pos: Vector3) -> void:
	for i in _n(4):
		_pe(Vector3(pos.x, 0.9, pos.z) + _rand_flat() * 0.3, Vector3.UP * randf_range(0.9, 1.5) + _rand_flat() * 0.2,
			Vector3.ONE * randf_range(0.06, 0.09), randf_range(0.6, 0.8), C.DROP, GREEN, -0.5, 1.0)


## The cleanse pulse: a ring of green puffs racing out to `radius` in `t` s.
func _cleanse_pulse(pos: Vector3, radius: float, t: float) -> void:
	var n := _n(clampi(roundi(radius * 6.0), 12, 40))
	var start := 0.6
	for i in n:
		var a := TAU * float(i) / float(n) + randf() * 0.12
		var o := Vector3(cos(a), 0.0, sin(a))
		_pe(Vector3(pos.x, 0.25, pos.z) + o * start, o * (radius - start) / t, Vector3.ONE * randf_range(0.22, 0.3),
			t + 0.2, C.DROP, GREEN_SOFT if i % 2 == 0 else GREEN)


## Censer trail: a small pale-green wisp where the censer swings.
func _incense_trail(pos: Vector3) -> void:
	_puff(pos, Vector3.UP * 0.35 + _rand_flat() * 0.15, randf_range(0.08, 0.12), 0.5, GREEN_SOFT if randf() < 0.5 else PALE, 0.0, 1.0)


## The incense cloud bursts: pale and sage puffs billowing up, an ink rim.
func _incense(pos: Vector3, radius: float) -> void:
	for i in _n(14):
		var o := _rand_flat()
		var r := radius * randf_range(0.1, 0.75)
		_puff(Vector3(pos.x, 0.3, pos.z) + o * r, o * 0.8 + Vector3.UP * randf_range(0.4, 0.8), randf_range(0.36, 0.5),
			randf_range(0.8, 1.0), PALE if i % 3 != 0 else GREEN_SOFT, 0.0, 1.0)
	_ink_ring(pos, radius * 0.85, radius * 1.2, _n(20), 0.35, 0.36)


# ---------------------------------------------------------------------- arrivals, houses
func _ext_arrive(pos: Vector3) -> void:
	_dust_ring(pos, _n(12), 0.5, 3.0, Vector2(0.26, 0.36), 0.8)
	v.call("disturb", pos, 8.0)


## Rats pouring in or out of a door (`out` points out of the house).
func _door_dust(door: Vector3, out: Vector3) -> void:
	var side := out.cross(Vector3.UP)
	for i in _n(5):
		var p := Vector3(door.x, 0.15, door.z) + side * randf_range(-0.5, 0.5)
		_puff(p, out * randf_range(0.6, 1.1) + side * randf_range(-0.4, 0.4) + Vector3.UP * 0.2, randf_range(0.13, 0.18),
			randf_range(0.4, 0.55), PALE, 0.0, 2.5)


## Plaster dust falling from the eaves (`pos` with y; `out` away from the wall).
func _plaster(pos: Vector3, out: Vector3) -> void:
	var side := out.cross(Vector3.UP)
	var floor_y := _ground(pos) + 0.02
	for i in _n(5):
		var p := pos + side * randf_range(-0.6, 0.6)
		_se(p, out * randf_range(0.2, 0.6) + Vector3.UP * randf_range(0.0, 0.5), Vector3(0.07, 0.05, 0.08),
			randf_range(0.7, 0.9), C.DROP, PLASTER, 7.0, 0.3, Vector3.ZERO, floor_y)
	for i in _n(2):
		_puff(pos + side * randf_range(-0.4, 0.4), out * 0.3 + Vector3.DOWN * 0.6, randf_range(0.12, 0.16), 0.6, PALE, 0.0, 1.0)


# ---------------------------------------------------------------------- building blocks
## Pale dust puffs thrown out from a ring of `r0` (speed drops with drag).
func _dust_ring(pos: Vector3, n: int, r0: float, speed: float, size: Vector2, life: float) -> void:
	for i in n:
		var a := TAU * float(i) / float(n) + randf() * 0.4
		var o := Vector3(cos(a), 0.0, sin(a))
		_puff(Vector3(pos.x, 0.15, pos.z) + o * r0, o * speed * randf_range(0.8, 1.15) + Vector3.UP * randf_range(0.2, 0.5),
			randf_range(size.x, size.y), life * randf_range(0.85, 1.0), PALE if i % 3 != 0 else PALE2, 0.0, 4.0)


func _run_dust(pos: Vector3, fwd: Vector3, scale: float) -> void:
	_puff(Vector3(pos.x, 0.08, pos.z) - fwd * 0.2, -fwd * 0.5 + Vector3.UP * 0.35 + _rand_flat() * 0.15,
		randf_range(0.08, 0.12) * scale, randf_range(0.35, 0.45), PALE, 0.0, 2.0)


## Short ink dashes laid along a ring, flying out from `r0` to about `r1`.
func _ink_ring(pos: Vector3, r0: float, r1: float, n: int, life: float, y: float) -> void:
	for i in n:
		var a := TAU * float(i) / float(n)
		var o := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		_se(Vector3(pos.x, y * 0.4, pos.z) + o * r0, o * (r1 - r0) / life * 1.6, Vector3(0.05, 0.04, 0.2), life,
			C.DROP, INK, 0.0, 3.2, tangent)


## An ink impact star: spikes radiating from `c` in the camera plane.
func _star(c: Vector3, n: int, length: float, life: float) -> void:
	var r: Vector3 = v.get("cam_right")
	var u: Vector3 = v.get("cam_up")
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var axis := r * cos(a) + u * sin(a)
		var l := length * (1.0 if i % 2 == 0 else 0.6)
		_se(c + axis * (0.12 + l * 0.5), axis * 1.8, Vector3(0.05, 0.05, l), life, C.TICK, INK, 0.0, 6.0, axis)


## An irregular splat mark plus 4-6 satellite drops round it.
func _splat_mark(at: Vector3, size: float, life: float, color: Color, spread: float) -> void:
	var d: Variant = v.get("decals")
	d.call("add", &"blob", at, randf() * TAU, size, life, spread, color, randf_range(0.75, 1.0))
	for i in _n(5):
		var o := _rand_flat() * size * randf_range(1.25, 1.9)
		d.call("add", &"drop", at + o + Vector3(0, 0.003, 0), 0.0, size * randf_range(0.12, 0.22), life, spread, color)


func _puff(pos: Vector3, vel: Vector3, size: float, life: float, color: Color, grav := 0.0, drag := 0.0) -> void:
	_pe(pos, vel, Vector3.ONE * size, life, C.PUFF, color, grav, drag)


## Every particle goes through these, scaled up for the far game camera (a
## Lead Rat is about 40 px long at 1600x900): sizes in the recipes are "rat
## sized" and the K factors make them read on screen.
func _pe(pos: Vector3, vel: Vector3, shape: Vector3, life: float, curve: int, color: Color, grav := 0.0, drag := 0.0,
		axis := Vector3.ZERO, floor_y := -INF, pre := 0.0) -> void:
	puffs.emit(pos, vel, shape * PUFF_K, life, curve, color, grav, drag, axis, floor_y, pre)


func _se(pos: Vector3, vel: Vector3, shape: Vector3, life: float, curve: int, color: Color, grav := 0.0, drag := 0.0,
		axis := Vector3.ZERO, floor_y := -INF) -> void:
	strokes.emit(pos, vel, Vector3(shape.x * STROKE_K, shape.y * STROKE_K, shape.z * STROKE_LEN_K), life, curve, color,
		grav, drag, axis, floor_y)


func _fe(pos: Vector3, vel: Vector3, shape: Vector3, life: float, curve: int, color: Color, grav := 0.0, drag := 0.0) -> void:
	flames.emit(pos, vel, shape * FLAME_K, life, curve, color, grav, drag)


## A falling droplet that comes to rest on the ground and shrinks away.
func _drop(pos: Vector3, vel: Vector3, size: float, life: float, color: Color) -> void:
	_pe(pos, vel, Vector3.ONE * size, life, C.DROP, color, 9.0, 0.4, Vector3.ZERO, _ground(pos) + 0.03)


func _n(count: int) -> int:
	return int(v.call("count", count))


func _ground(p: Vector3) -> float:
	return float(v.call("ground_y", p))


static func _rand_flat() -> Vector3:
	var a := randf() * TAU
	return Vector3(sin(a), 0.0, cos(a))
