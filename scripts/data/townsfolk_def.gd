## One townsfolk type of the YearTable: its look, weapon and stats. The spawner
## picks types by `base_weight * (1 + vigilance * tier)` and hands the chosen
## def to Townsperson.setup() (or Cat.setup() for look "cat").
class_name TownsfolkDef
extends Resource

@export var id := ""
@export var look := "plain"            # visual variant: plain | red | broom | torch | club | guard | cat
@export var weapon: WeaponDef          # may be null (null = basic stomp)
@export var walk_speed := 1.6
@export var hp_note := ""              # free text for designers, unused
@export var tier := 0                  # 0 weak … 3 strong; Vigilance favours higher tiers
@export var base_weight := 1.0         # spawn weight before Vigilance
@export var always_fight := false      # Guards: attack whatever their Fear
@export var gain_multiplier := 1.0     # Infection gain (multiplied further by Year Hygiene)
