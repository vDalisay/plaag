## One row of the YearTable: what the District looks like and who lives there
## from `from_year` on (until the next row).
class_name YearEntry
extends Resource

@export var from_year := 1347
@export var district_id := "slums"           # slums | merchant (M6)
@export var types: Array[TownsfolkDef] = []  # what can spawn
@export var hygiene := 0.0                   # 0..0.6; Infection gain *= (1 - hygiene)
@export var speed_mult := 1.0                # townsfolk walk speed
@export var windup_mult := 1.0               # <1 = faster attacks
@export var start_vigilance := 0.0           # added to Vigilance at Round start
@export var visual_stage := 0                # 0..2, used by M7 visuals
