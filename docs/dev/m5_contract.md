# M5 integration contract (Escalation: Year and Vigilance)

This builds on the M1–M4 contracts in `docs/dev/`, which all still hold. Terms are defined in `GLOSSARY.md`, and
the design is in `docs/game_concept.md` under "Escalation (Risk of Rain style)".

## Review rules so far
- Red means plague. Corpses are dark sepia. Gameplay numbers live in data.
- The HUD reads other systems with duck typing and shows "—" when something is missing.

## Data (implementer B)
### `scripts/data/townsfolk_def.gd`
```gdscript
class_name TownsfolkDef extends Resource
@export var id := ""
@export var look := "plain"            # visual variant: plain | red | broom | torch | club | guard
@export var weapon: WeaponDef          # may be null (null = basic stomp)
@export var walk_speed := 1.6
@export var hp_note := ""              # free text for designers, unused
@export var tier := 0                  # 0 weak … 3 strong; Vigilance favours higher tiers
@export var base_weight := 1.0         # spawn weight before Vigilance
@export var always_fight := false      # Guards: attack whatever their Fear
@export var gain_multiplier := 1.0     # Infection gain (multiplied further by Year Hygiene)
```

### `scripts/data/year_table.gd` + `data/year_table.tres`
```gdscript
class_name YearTable extends Resource
@export var entries: Array[YearEntry] = []   # sorted by from_year
func entry_for(year: int) -> YearEntry       # last entry with from_year <= year
```

### `scripts/data/year_entry.gd`
```gdscript
class_name YearEntry extends Resource
@export var from_year := 1347
@export var district_id := "slums"           # M7 adds "merchant"
@export var types: Array[TownsfolkDef] = []  # what can spawn
@export var hygiene := 0.0                   # 0..0.6; Infection gain *= (1 - hygiene)
@export var speed_mult := 1.0                # townsfolk walk speed
@export var windup_mult := 1.0               # <1 = faster attacks
@export var start_vigilance := 0.0           # added to Vigilance at Round start
@export var visual_stage := 0                # 0..2, used by M7 visuals
```

### Starter progression (slums)
| Year | Townsfolk added | Hygiene | Speed | Wind-up | Start Vigilance | Visual stage |
| --- | --- | --- | --- | --- | --- | --- |
| 1347 | plain (stomp) | 0 | 1.0 | 1.0 | 0 | 0 |
| 1348 | broom | | | | | |
| 1349 | cat | 0.05 | 1.05 | | 0.1 | |
| 1351 | — | 0.12 | 1.1 | 0.9 | 0.2 | 1 |
| 1353 | torch (Guards patrolling the slums) | 0.2 | | 0.85 | 0.35 | |
| 1356 | club | 0.3 | | | 0.5 | 2 |

Blank cells keep the previous Year's value. Tune as needed, but keep it monotonic.

## Weapons (implementer B, extending WeaponComponent and WeaponDef)
- **stomp** (exists): a telegraphed circle at a point.
- **broom:** a telegraphed 100° arc in front of the person, radius 2.0. It kills Pups and knocks Adults back about 3 u (`knockback()` on the rat if it has the method, else `hit()` for Pups only). The Lead Rat is knocked back, not hurt.
- **torch:** throws a fire patch at the rats (telegraphed). The patch is an AMBER emissive disc that burns for 3 s and calls `hit()` on any rat that stands in it for more than 0.25 s.
- **club:** a slow, heavy stomp: radius 2.0, wind-up 1.0, cooldown 3.5.
- **cat** is not a weapon. It's its own NPC, `scenes/game/cat.tscn` + `scripts/game/cat.gd`:
  - a small solid-ink figure that hunts the nearest single rat (sprint 7 u/s), kills it on contact, then pauses 2 s;
  - it runs away whenever 8 or more rats are within 5 u;
  - cats spawn like townsfolk, from the YearTable type `cat` (look "cat");
  - they are not infectable and don't count towards population.
- New WeaponDef fields as needed (`kind`, `arc_deg`, `knockback`, `burn_time`). Keep `stomp.tres` working.

## Rats: `knockback(from: Vector3, strength: float)` (implementer A)
Every node in `"rats"` gets it: a short shove away from `from`. Lead Rat and Adults take no damage; a Pup dies.

## Townsperson (implementer B)
- `func setup(def: TownsfolkDef, year_entry: YearEntry) -> void` is called by the spawner before `add_child`. It sets the look, weapon, speed, `always_fight` and the Infection gain.
- Infection gain = `def.gain_multiplier * (1.0 - year_entry.hygiene)`.
- Without a `setup()` call it behaves exactly as now, so residents and old spawns still work.
- **Looks**, built with the Props kit plus a few extra strips:
  - broom: a stick with a bristle head;
  - torch: a stick with an AMBER emissive flame;
  - club: a thick short stick;
  - guard: a TIMBER helmet and a tabard.
  - None of them use red.

## Vigilance (implementer B, in RoundDirector)
```gdscript
var vigilance := 0.0     # 0 at Round start (+ year_entry.start_vigilance), rises over the Round
signal vigilance_changed(v: float)
```
- `vigilance = start_vigilance + elapsed / 60.0 * (1.0 + 0.1 * (Run.year - 1347))`. It's uncapped and grows faster in later Years.
- The HUD shows it top-centre under the timer as a word plus a thin ink bar, in four tiers: `Calm` / `Wary` / `Alarmed` / `Hunting`.

## Spawner: `scripts/game/spawner.gd` (implementer A)
- Lives in the District and reads `RoundDirector.vigilance` and `YearTable.entry_for(Run.year)`.
  The YearTable is loaded from `res://data/year_table.tres`; fall back to "plain only" if it's missing.
- **Spawn interval:** `lerp(9.0, 1.5, clamp(vigilance / 2.0, 0, 1))` seconds.
- **Type weight:** `base_weight * (1 + vigilance * tier)`, so Vigilance makes strong types (higher tier) more common, as in Risk of Rain.
- **Spawn points:**
  - gates: open street ends at the District bounds, as Marker3Ds or computed;
  - house doors: a new person steps out of a living house.
  - Never spawn within 6 u of the Lead Rat.
- **Cap:** 45 alive outdoor townsfolk. Above the cap, don't spawn.
- Residents (M4) are untouched. Their look comes from the Year: a resident has a 30% chance of getting a Year type.

## Performance (implementer A leads)
- Add a `--perf` flag that prints FPS, rat count and townsfolk count every 2 s.
- **Target:** 60 FPS at 1280×720 with 45 outdoor townsfolk, 40 rats and 50 residents (`--start-colony=40`).
- If the target is missed, profile the A-side hot spots first. Likely ones:
  - BiteComponent scanning `"townsfolk"` every physics frame per rat;
  - rat flocking O(n²);
  - per-rat MeshInstance count.
- Fix them with throttling (Bite scans at 5–10 Hz), a shared spatial grid, or cheaper rat visuals.
- List any B-side hot spots (Fear scans, figure mesh count) in your report rather than editing B's files.
