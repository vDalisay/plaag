## Infection meter of a townsperson (0..100 %).
## A Bite adds a chunk and raises the rate; once infected the meter keeps
## climbing on its own at base_rate + bonus_rate - cleanse_rate per second,
## and the host dies when it reaches 100.
## Exterminators (M6) also set `bonus_decay`: their Bite rate bonus fades
## (exponentially, per second), so only Bites kept up together can beat them.
class_name InfectionComponent
extends Node

signal infected            # first time value goes above 0
signal died                # value reached 100
signal value_changed(value: float)

@export var base_rate := 5.0         # %/s once infected  (about 20 s to death)
@export var gain_multiplier := 1.0   # scales Bite chunk + rate bonus (Exterminators < 1)
@export var cleanse_rate := 0.0      # %/s self-Cleanse (Exterminators > 0)
@export var bonus_decay := 0.0       # 1/s fade of bonus_rate (0 = permanent; Exterminators > 0)

var value := 0.0                     # 0..100
var bonus_rate := 0.0                # accumulated from Bites

var _was_infected := false
var _dead := false


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if bonus_decay > 0.0 and bonus_rate != 0.0:
		bonus_rate *= exp(-bonus_decay * delta)
	if value <= 0.0:
		return
	var rate := base_rate + bonus_rate - cleanse_rate
	if rate != 0.0:
		_set_value(value + rate * delta)


## Adds a Bite: an instant chunk of Infection and a permanent rate bonus.
func bite(chunk: float, rate_bonus: float) -> void:
	if _dead:
		return
	bonus_rate += rate_bonus * gain_multiplier
	_set_value(value + chunk * gain_multiplier)


## Removes some Infection at once (Exterminator Cleanse, future cures).
func cleanse(amount: float) -> void:
	if _dead:
		return
	_set_value(value - amount)


func is_infected() -> bool:
	return value > 0.0 and not _dead


func is_dead() -> bool:
	return _dead


func _set_value(v: float) -> void:
	var nv := clampf(v, 0.0, 100.0)
	if nv == value:
		return
	value = nv
	value_changed.emit(value)
	if value > 0.0 and not _was_infected:
		_was_infected = true
		infected.emit()
	if value >= 100.0 and not _dead:
		_dead = true
		died.emit()
