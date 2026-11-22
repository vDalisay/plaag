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
## The rats counted at the last update (may contain freed nodes until the next one).
var near: Array[Node3D] = []

var _host: Node3D
var _left := 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	# Spread the counts of many townsfolk over different frames.
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
	if _host == null or not _host.is_inside_tree():
		rats_near = 0
		return
	var p := _host.global_position
	var r2 := radius * radius
	for n: Node in get_tree().get_nodes_in_group("rats"):
		var r := n as Node3D
		if r == null or r.is_queued_for_deletion() or not r.is_inside_tree():
			continue
		var d := r.global_position - p
		d.y = 0.0
		if d.length_squared() <= r2:
			near.append(r)
	rats_near = near.size()
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


## The nearest still-valid rat from the last count, or null.
func nearest_rat() -> Node3D:
	var best: Node3D = null
	var bd := INF
	if _host == null:
		return null
	for r in near:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		var d := r.global_position - _host.global_position
		d.y = 0.0
		if d.length_squared() < bd:
			bd = d.length_squared()
			best = r
	return best


## Flat unit direction away from the counted rats, nearer ones weighing more;
## Vector3.ZERO if there are none.
func away_direction() -> Vector3:
	var sum := Vector3.ZERO
	if _host == null:
		return sum
	for r in near:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		var d := _host.global_position - r.global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.05:
			d = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			l = maxf(d.length(), 0.01)
		sum += d / (l * l)
	return sum.normalized() if sum.length_squared() > 0.0 else Vector3.ZERO
