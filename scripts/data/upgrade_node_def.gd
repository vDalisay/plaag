## One node of the Upgrade Tree (data/upgrades/*.tres). Run reads these:
## each level adds `effects` (stat key -> delta per level) to Run.BASE_STATS,
## or, when `level_stat` is set, that stat becomes level_values[level - 1].
## Level 1 costs cost_pestilence / cost_bones; each further level costs the
## previous one times cost_growth, rounded up. The node shows once every id in
## `requires` is owned. tree_position lays it out on the parchment.
class_name UpgradeNodeDef
extends Resource

@export var id := ""
@export var title := ""
@export_multiline var description := ""
@export var max_level := 1
@export var cost_pestilence := 0       # level 1 cost
@export var cost_bones := 0            # level 1 cost
@export var cost_growth := 1.6         # each further level costs previous * growth (rounded up)
@export var requires: Array[String] = []   # ids that must be owned (level >= 1) to show this node
@export var effects := {}              # stat key -> delta PER LEVEL (e.g. {"rat_speed": 0.5})
@export var level_values: Array[float] = []  # optional: explicit per-level value for ONE stat (carry_over 0.2,0.5,0.7,1.0)
@export var level_stat := ""           # the stat that level_values sets (absolute, replaces the base)
@export var tree_position := Vector2.ZERO   # layout on the parchment, in tree units
