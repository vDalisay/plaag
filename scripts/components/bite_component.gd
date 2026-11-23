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
## When false it stops Biting (a dead rat).
@export var enabled := true
## The house this rat is inside, or null when it is out in the street.
var house: House

var _cooldown_left := 0.0
var _scan_left := randf() * SCAN_INTERVAL


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left > 0.0:
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	var target := find_target()
	if target == null:
		_scan_left = SCAN_INTERVAL
		return
	_scan_left = 0.0
	(target.get_node("Infection") as InfectionComponent).bite(chunk, rate_bonus)
	_cooldown_left = cooldown
	if house:
		house.show_bite()
	else:
		var away := target.global_position - global_position
		Vfx.play(get_tree(), &"bite", target.global_position, away, chunk / 3.0)
	bit.emit(target)


## The nearest townsperson in range whose Infection is not dead, or null.
func find_target() -> Node3D:
	if house:
		if not is_instance_valid(house):
			house = null
			return null
		var living := house.living_occupants()
		return living[randi() % living.size()] if not living.is_empty() else null
	var best: Node3D = null
	var best_d2 := bite_range * bite_range
	var here := global_position
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
			best_d2 = d2
			best = t
	return best
