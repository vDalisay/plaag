## Infection meter of a townsperson (0..100 %).
## A Bite adds a chunk and raises the rate; once infected the meter keeps
## climbing on its own at base_rate + bonus_rate - cleanse_rate per second,
## and the host dies when it reaches 100.
## Every Bite emits `bitten(chunk)` (floating Bite numbers, the Round's Bite count).
## Exterminators (M6) also set `bonus_decay`: their Bite rate bonus fades
## (exponentially, per second), so only Bites kept up together can beat them.
class_name InfectionComponent
extends Node

signal infected            # first time value goes above 0
signal died                # value reached 100
signal value_changed(value: float)
## A Bite landed (UX pass): the Infection it added at once (after gain_multiplier).
signal bitten(chunk: float)
## Emitted when an entity with cleanse_rate > 0 has its Cleanse overwhelmed
## (base_rate + bonus_rate > cleanse_rate) after previously resisting.
signal cleanse_broken

@export var base_rate := 5.0         # %/s once infected  (about 20 s to death)
@export var gain_multiplier := 1.0   # scales Bite chunk + rate bonus (Exterminators < 1)
@export var cleanse_rate := 0.0      # %/s self-Cleanse (Exterminators > 0)
@export var bonus_decay := 0.0       # 1/s fade of bonus_rate (0 = permanent; Exterminators > 0)

var value := 0.0                     # 0..100
var bonus_rate := 0.0                # accumulated from Bites

var _was_infected := false
var _dead := false
var _was_overwhelmed := false


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if bonus_decay > 0.0 and bonus_rate != 0.0:
		bonus_rate *= exp(-bonus_decay * delta)
		if bonus_rate < 0.005:
			bonus_rate = 0.0
	if cleanse_rate > 0.0 and not is_overwhelmed() and value <= 0.05:
		_was_overwhelmed = false
	if value <= 0.0:
		return
	var rate := base_rate + bonus_rate - cleanse_rate
	if rate != 0.0:
		_set_value(value + rate * delta)


## Adds a Bite: an instant chunk of Infection and a permanent rate bonus.
func bite(chunk: float, rate_bonus: float) -> void:
	if _dead:
		return
	var was_over := is_overwhelmed()
	bonus_rate += rate_bonus * gain_multiplier
	_set_value(value + chunk * gain_multiplier)
	if cleanse_rate > 0.0 and not was_over and is_overwhelmed() and not _was_overwhelmed:
		_was_overwhelmed = true
		cleanse_broken.emit()
	bitten.emit(chunk * gain_multiplier)


## Net Infection change per second right now (positive = climbing, negative = Cleansing).
func net_rate() -> float:
	if _dead:
		return 0.0
	return base_rate + bonus_rate - cleanse_rate


## True when incoming Infection rate exceeds self-Cleanse (always true for ordinary townsfolk).
func is_overwhelmed() -> bool:
	return cleanse_rate <= 0.0 or (base_rate + bonus_rate) > cleanse_rate


## 0..1 ratio of current Bite pressure against Cleanse resistance (1 = Cleanse broken).
func cleanse_pressure() -> float:
	if cleanse_rate <= 0.0:
		return 1.0
	return clampf((base_rate + bonus_rate) / cleanse_rate, 0.0, 1.0)


## Visual escalation tier for escalating plague presentation:
## 0 healthy, 1 tainted (1..30), 2 feverish (31..65), 3 critical (66..99), 4 dead.
static func visual_tier(val: float) -> int:
	if val >= 100.0:
		return 4
	if val >= 66.0:
		return 3
	if val >= 31.0:
		return 2
	if val > 0.0:
		return 1
	return 0


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
