# M3 integration contract (the meta loop)

This builds on `docs/dev/m1_contract.md` and `docs/dev/m2_contract.md`, which still hold.
Terms are defined in `GLOSSARY.md`.

## Review rules so far
- **Red means plague.** Saturated red is used only for Infection, Bite marks and blood. Everything else is drawn in ink and parchment.
- **Corpses are dark sepia** (hatched), not solid ink, so rats on a body stay readable.
- **Gameplay numbers live in data.** Put them in Resources or in `Run.BASE_STATS`, not scattered through scripts.

## Flow
```
boot (district.tscn is the main scene)
  └─ Round  ──end panel──▶  [Continue]  ──▶  Upgrade Tree  ──[Begin Round]──▶  Round ...
```
- The first launch with no save goes straight into a Round.
- After every Round, the end panel shows a **Continue** button (Enter / A / click). It replaces "Press R", which now only works with the `--dev` flag.
- Continue calls `Run.finish_round(result)` and then `Run.open_tree()`.
- The Upgrade Tree's **Begin Round** button calls `Run.start_round()`.

## `Run` autoload: `scripts/game/run.gd` (implementer A; registered in project.godot as `Run`)
```gdscript
extends Node
signal wallet_changed
signal upgrades_changed
const SAVE_PATH := "user://plaag_run.cfg"
const START_YEAR := 1347
const BASE_STATS := {
	"rat_speed": 6.0, "bite_range": 1.6, "bite_cooldown": 1.2, "bite_chunk": 3.0,
	"bite_rate_bonus": 0.5, "start_adults": 0.0, "feed_time": 1.5, "pup_maturity": 15.0,
	"lethality": 1.0,          # multiplies every townsperson's Infection base_rate
	"carry_over": 0.0,         # 0..1 share of last Round's final Colony size
	"round_length": 90.0,
	"unlock_hide": 0.0, "unlock_raid": 0.0, "unlock_fleas": 0.0, "unlock_contagion": 0.0,
}
var year := START_YEAR
var pestilence := 0             # wallet
var bones := 0                  # wallet
var levels := {}                # upgrade id (String) -> bought level (int)
var last_colony_size := 0       # Adults + Pups alive when the last Round ended
var rounds_played := 0
func stat(key: String) -> float               # BASE_STATS[key] + sum of owned effects
func level(id: String) -> int
func cost_of(node: UpgradeNodeDef) -> Vector2i   # (pestilence, bones) for the NEXT level
func is_visible(node: UpgradeNodeDef) -> bool    # every `requires` id has level >= 1
func can_buy(node: UpgradeNodeDef) -> bool
func buy(node: UpgradeNodeDef) -> bool           # spends, levels up, saves, emits
func finish_round(result: Dictionary) -> void    # see below; saves
func start_round() -> void                       # change_scene_to_file district
func open_tree() -> void                         # change_scene_to_file upgrade tree
func all_nodes() -> Array[UpgradeNodeDef]        # loads every res://data/upgrades/*.tres
func reset() -> void                             # wipes the save (used by --fresh)
```
- `result` keys:
  - `pestilence: int` and `bones: int`, both earned this Round;
  - `reason: String`, either `"timer"` or `"lead_rat_died"`;
  - `colony_size: int`.
- **Year:** `finish_round` adds the earnings to the wallet and does `year += 1` **only** when `reason == "lead_rat_died"`.
- **Save format:** ConfigFile. Saving is robust to missing keys, and `--fresh` (a command-line user arg) resets the save.

## Applying stats to a Round (implementer A)
At the start of each Round, the District reads `Run.stat()`:
- **Lead Rat:** `max_speed`.
- **Every Adult's BiteComponent:** range, cooldown, chunk and rate bonus.
- **Colony:** `feed_time`, `pup_maturity` and `start_adults`.
  - Start size = `start_adults` + `floor(carry_over * last_colony_size)`.
  - Carry-over Adults spawn around the Lead Rat.
- **Every townsperson's Infection:** `base_rate = 5.0 * lethality`. This also applies to anyone spawned later.
- **RoundDirector:** `round_length`.
- The unlock stats are read later (M4 Hide/Raid, M7 Fleas/Contagion). Expose `Run.stat("unlock_hide") >= 1.0` and so on; nothing uses them yet.
- `--dev` keeps the old R restart. Existing debug flags keep working and override the Run stats where they overlap (`--start-colony`, `--god`, ...).

## `UpgradeNodeDef`: `scripts/data/upgrade_node_def.gd` (implementer B)
```gdscript
class_name UpgradeNodeDef extends Resource
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
```
- `Run.stat()` = base value + Σ (effects delta × level). If `level_stat` is set, that stat becomes `level_values[level - 1]` instead.
- A node can cost Pestilence only, Bones only, or both. This mirrors Unharvest.

## Starter Upgrade Tree data: `data/upgrades/*.tres` (implementer B)
About 13 nodes, rooted at a central **"Gnaw"** node (Bite cooldown, cheap):
- **Stats:** rat speed; Bite range; Bite cooldown; Bite chunk; starting Colony +1 (`start_adults`); Feeding speed (`feed_time` −); Pup maturity (−); lethality (+0.15 per level).
- **Carry-over:** uses `level_values` 0.2 / 0.5 / 0.7 / 1.0.
- **Unlocks:** Hide and Raid are cheap and early (Pestilence + a few Bones). Fleas and Contagion are expensive and Bones-gated, deeper in the tree.
- **Costs:** a first Round earns roughly 5–15 Pestilence and 2–6 Bones. So the first 2–3 nodes should be affordable after Round 1, and the tree should take roughly 10–15 Rounds to finish.

## Upgrade Tree screen: `scenes/ui/upgrade_tree.tscn` + `scripts/ui/upgrade_tree.gd` (implementer B)
- **Look:** a full-screen parchment page (`Color(0.93,0.88,0.76)`) with ink lines.
  - Each node is an ink-bordered circle with a short title. Under it: its level pips and its cost, e.g. `12 P · 2 B`.
  - Requirements are drawn as ink lines between nodes.
  - Hidden nodes aren't drawn. Nodes you can't afford are drawn faded. Maxed nodes are filled with ink.
- **Header:** the wallet (Pestilence, Bones), the Year, and a **Begin Round** button.
- **Tooltip/panel:** shows the hovered or focused node's description and the next level's effect.
- **Input:**
  - mouse: click to buy, drag or right-drag to pan;
  - gamepad / keyboard: focus moves between nearby nodes, A / Enter buys, Start / Space = Begin Round.
- Red is allowed only where the plague itself is shown, e.g. the lethality and Contagion nodes.

## HUD changes (implementer B)
- The Year comes from `Run.year`.
- The end panel shows this Round's earnings, the reason, and "Year advances to N" when the Lead Rat died. Then the **Continue** button.
- The RoundDirector builds the `result` dictionary. It gets `colony_size` from the `"colony"` group: Adults + Pups. Use 0 if the Lead Rat died.
