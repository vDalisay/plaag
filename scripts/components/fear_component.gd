## Fear of a townsperson. About 5 times a second it counts the rats (group
## "rats", Pups included) within `radius` of its host and turns the count into
## a band: FIGHT (few rats), UNEASY (uneasy_at or more), FLEE (flee_at or more).
## Rising is immediate; dropping back to a calmer band needs `hysteresis`
## fewer rats than that band's threshold, so the band doesn't flicker.
class_name FearComponent
extends Node

enum Band { FIGHT, UNEASY, FLEE }

signal band_changed(band: int)

@export var radius := 6.0
@export var uneasy_at := 4                # rats nearby (Pups count)
@export var flee_at := 12
@export var hysteresis := 1
## Seconds between counts.
@export var interval := 0.2

var band: int = Band.FIGHT
var rats_near: int
## Nearest rat world position (Vector3.INF if none) & away direction from the
## Colony's O(1) spatial hash (handles 3,000+ MultiMesh rats cleanly).
var nearest_pos := Vector3.INF
var _away := Vector3.ZERO
## Legacy list (kept populated with Lead Rat / standalone rats for unit tests).
var near: Array[Node3D] = []

var _host: Node3D
var _colony: Colony
var _left := 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	_left = randf() * interval


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = maxf(_left + interval, 0.0)
	update_now()


## Recounts the rats and updates the band at once.
func update_now() -> void:
	near.clear()
	nearest_pos = Vector3.INF
	_away = Vector3.ZERO
	if _host == null or not _host.is_inside_tree():
		rats_near = 0
		return
	var p := _host.global_position
	if _colony == null or not is_instance_valid(_colony):
		_colony = get_tree().get_first_node_in_group("colony") as Colony
	if _colony != null and _colony.has_method("query_crowd"):
		var q: Dictionary = _colony.query_crowd(p, radius)
		rats_near = int(q["count"])
		nearest_pos = q["nearest"] as Vector3
		if rats_near > 0:
			var away := p - (q["centre"] as Vector3)
			away.y = 0.0
			_away = away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD
	else:
		var r2 := radius * radius
		var best_d2 := INF
		var sum := Vector3.ZERO
		for n: Node in get_tree().get_nodes_in_group("rats"):
			var r := n as Node3D
			if r == null or r.is_queued_for_deletion() or not r.is_inside_tree():
				continue
			var d := r.global_position - p
			d.y = 0.0
			var l2 := d.length_squared()
			if l2 <= r2:
				near.append(r)
				if l2 < best_d2:
					best_d2 = l2
					nearest_pos = r.global_position
				sum -= d / maxf(l2, 0.01)
		rats_near = near.size()
		_away = sum.normalized() if sum.length_squared() > 0.0 else Vector3.ZERO
	var nb := band
	var up := band_for(rats_near)
	if up > band:
		nb = up
	else:
		var down := band_for(rats_near + hysteresis)
		if down < band:
			nb = down
	if nb != band:
		band = nb
		band_changed.emit(band)


## The band a plain count maps to, without hysteresis.
func band_for(count: int) -> int:
	if count >= flee_at:
		return Band.FLEE
	if count >= uneasy_at:
		return Band.UNEASY
	return Band.FIGHT


## Nearest rat position (works for both MultiMesh swarm rats and Node3D rats).
func nearest_rat_pos() -> Vector3:
	return nearest_pos


## The nearest still-valid Node3D rat (legacy fallback), or null.
func nearest_rat() -> Node3D:
	if not near.is_empty():
		var best: Node3D = null
		var bd := INF
		for r in near:
			if not is_instance_valid(r) or r.is_queued_for_deletion():
				continue
			var d := r.global_position - _host.global_position
			d.y = 0.0
			if d.length_squared() < bd:
				bd = d.length_squared()
				best = r
		return best
	if rats_near > 0 and _colony != null and _colony.lead != null and is_instance_valid(_colony.lead):
		return _colony.lead
	return null


## Flat unit direction away from the counted rats; Vector3.ZERO if none.
func away_direction() -> Vector3:
	return _away
