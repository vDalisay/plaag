## Automatic Bite: every `cooldown` seconds, bites the nearest living
## townsperson within `bite_range` (measured on the ground plane from this
## node). A Bite adds a chunk of Infection and raises the rate it climbs.
## Reused by every Adult rat (M2). While `house` is set (the rat is hidden
## inside it: Hide, Raid) it Bites a random living occupant instead.
## While nothing is in range it only looks again every SCAN_INTERVAL seconds
## (performance: many Adults scanning every townsperson every frame).
## Each street Bite sprays the Vfx "bite" burst (red droplets away from the
## biter and an ink snap tick); a Bite inside a house shows on the house.
class_name BiteComponent
extends Node3D

signal bit(target: Node3D)

const Vfx := preload("res://scripts/vfx/vfx.gd")

## Seconds between scans while no target is in range (~10 Hz).
const SCAN_INTERVAL := 0.1

@export var bite_range := 1.6
@export var cooldown := 1.2
@export var chunk := 3.0
@export var rate_bonus := 0.5
## Max targets struck per Bite (1 by default; Ravenous Maw keystone raises for Lead Rat).
@export var cleave_targets := 1
## Lead Rat bites play bolder VFX and expose ready-state cleanly.
@export var is_lead := false
## When false it stops Biting (a dead rat).
@export var enabled := true
## The house this rat is inside, or null when it is out in the street.
var house: House

var _cooldown_left := 0.0
var _scan_left := randf() * SCAN_INTERVAL


## 0.0 right after a Bite, 1.0 when ready to Bite again.
func cooldown_progress() -> float:
	if cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _cooldown_left / cooldown, 0.0, 1.0)


func is_ready() -> bool:
	return _cooldown_left <= 0.0


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left > 0.0:
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	var targets := find_targets(maxi(1, cleave_targets))
	if targets.is_empty():
		_scan_left = SCAN_INTERVAL
		return
	_scan_left = 0.0
	_cooldown_left = cooldown
	var primary := targets[0]
	for target in targets:
		(target.get_node("Infection") as InfectionComponent).bite(chunk, rate_bonus)
		if house:
			house.show_bite()
		else:
			var away := target.global_position - global_position
			var fx_kind := &"lead_bite" if is_lead else &"bite"
			Vfx.play(get_tree(), fx_kind, target.global_position, away, chunk / 3.0, bite_range)
	bit.emit(primary)


## The nearest townsperson in range whose Infection is not dead, or null.
func find_target() -> Node3D:
	var list := find_targets(1)
	return list[0] if not list.is_empty() else null


## Up to `limit` nearest living townsfolk within `bite_range` (or house occupants).
func find_targets(limit := 1) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if house:
		if not is_instance_valid(house):
			house = null
			return out
		var living := house.living_occupants()
		if not living.is_empty():
			out.append(living[randi() % living.size()])
		return out
	var best_d2 := bite_range * bite_range
	var here := global_position
	var candidates: Array = []
	for n in get_tree().get_nodes_in_group("townsfolk"):
		var t := n as Node3D
		if t == null:
			continue
		var inf := t.get_node_or_null("Infection") as InfectionComponent
		if inf == null or inf.is_dead():
			continue
		var d := t.global_position - here
		var d2 := d.x * d.x + d.z * d.z
		if d2 <= best_d2:
			candidates.append([d2, t])
	if candidates.is_empty():
		return out
	if limit == 1:
		var best_i := 0
		for i in range(1, candidates.size()):
			if float(candidates[i][0]) < float(candidates[best_i][0]):
				best_i = i
		out.append(candidates[best_i][1] as Node3D)
		return out
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(limit, candidates.size()):
		out.append(candidates[i][1] as Node3D)
	return out
