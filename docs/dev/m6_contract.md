# M6 integration contract (Exterminators + the Merchant quarter)

This builds on the M1–M5 contracts in `docs/dev/`, which all still hold. Terms are defined in `GLOSSARY.md`.
M6 also takes the **Merchant quarter District** from M7, so M7 is left with the Scroll Map, the Year visuals, Fleas and Contagion.

## Review rules so far
- Red means plague. Corpses are dark sepia. Gameplay numbers live in data. The HUD reads other systems with duck typing.
- One exception to the red rule: the **Plague Doctor** wears red, as in the reference manuscript. That fits, because he belongs to the plague.

## Districts (implementer A)
### `scripts/data/district_def.gd` + `data/districts/slums.tres`, `data/districts/merchant.tres`
```gdscript
class_name DistrictDef extends Resource
@export var id := "slums"
@export var title := "The Slums"
@export var layout_style := "slums"          # slums | merchant
@export var requires := ""                   # district id that must be beaten first ("" = open)
@export var exterminator_scene: PackedScene  # res://scenes/game/rat_catcher.tscn / plague_doctor.tscn
@export var exterminator_title := "The Rat-catcher"
@export var wanderers := 25                  # outdoor townsfolk at Round start
@export var residents_per_house := Vector2i(0, 3)
@export var map_position := Vector2.ZERO     # for the M7 Scroll Map
```

### Merchant quarter layout
- Wider cobbled streets around a central square, with market stalls, the well and lamp posts.
- Taller houses (2–3 storeys) with lime-washed walls, more timber detail and more lit windows.
- About 24 houses, fewer than the slums.
- `wanderers` is 16, with 1–2 residents per house: fewer people, but sturdier ones (via the YearTable).
- Same collision, door, cutaway and batching rules as the slums.

### Run additions
```gdscript
var current_district := "slums"
var beaten := {}                                   # district id -> true
func district_defs() -> Array[DistrictDef]         # loads data/districts/*.tres
func is_district_open(id: String) -> bool
func beat_district(id: String) -> void             # saves
```
- **New Round result:** `finish_round(result)` accepts `reason == "exterminator_beaten"`. It marks `current_district` as beaten and does **not** advance the Year. When the next District opens, `current_district` switches to it automatically. (M7 will add a Scroll Map for choosing.)
- **Best Round per District:** add `record_dead_houses(district_id, house_indices: Array[int])`. It keeps the Round with the most dead houses, stored as `best_dead_houses[district_id]`. A house index is its stable build order in the layout. The District sends this at Round end, in `result.dead_houses`.
- **New flag:** `--district=<id>` overrides the District for one session.

### Exterminator arrival (implementer A, in the spawner)
- The first time `RoundDirector.district_infection() >= 0.5`, the Exterminator from `DistrictDef.exterminator_scene` is instanced at the gate farthest from the Lead Rat. This happens once per Round.
- The Exterminator is in group `"exterminator"`.

## Exterminators (implementer B)
### Shared base: `scripts/game/exterminator.gd` (`class_name Exterminator extends CharacterBody3D`)
- **Groups:** it's in `"exterminator"` *and* in `"townsfolk"`, so rats Bite it automatically.
- **Infection:** it has an `Infection` child. Its InfectionComponent starts already infected at 0%: `gain_multiplier` is about 0.2 and `cleanse_rate` is about 1.5 %/s, both tuned per boss. Bites still have to push it up. Fear doesn't apply to it.
- **Signals:** `arrived` and `beaten`. `beaten` fires on Infection `died`. It then collapses into a big sepia corpse and stays in the world.
- **Title:** `@export var title := "The Rat-catcher"`, used by the HUD.
- **Arrival:** it walks in from the gate, and a banner appears.

### Rat-catcher: `scenes/game/rat_catcher.tscn` (slums)
- **Look:** a long coat, a wide hat, a pole carried over the shoulder, and a cage of dead rats on his back. Built with the Props kit plus strips, in ink and sepia.
- **Pole sweep:** a telegraphed long arc (radius 3, 120°) that kills any rat it catches. The Lead Rat loses one hit.
- **Spring traps:** every 6 s he drops a trap about 2 u ahead along the Lead Rat's path. A trap is a small ink jaw-ring.
  - A rat that steps on it is `hit()` and the trap is used up.
  - Traps last 20 s, with at most 4 at a time.
- **Terrier:** a scene of its own, `scenes/game/terrier.tscn`.
  - It always hunts the **Lead Rat**, running at 6.5 u/s. On contact the Lead Rat gets `hit()`, followed by a 2.5 s pause.
  - The Colony doesn't scare it.
  - It's bitable and infectable, with normal gain, and dies like a person. It doesn't count towards population.

### Plague Doctor: `scenes/game/plague_doctor.tscn` (merchant)
- **Look:** the red "doctor" figure from the prop kit, with the beak mask and a cane.
- **Cleanse pulse:** every 3 s an ink ring expands to radius 6 and Cleanses 15 Infection from every living townsperson inside it.
- **Self-Cleanse:** about 2.5 %/s.
- **Incense cloud:** a telegraphed cloud of radius 2.5. It knocks back every rat inside it and kills Pups.
- This forces burst play: you need a big Colony biting him at the same moment.

### Round end on victory (implementer B)
- The RoundDirector **doesn't** count `"exterminator"` nodes (or the terrier) in population, Pestilence or Bones.
- When `beaten` fires, the RoundDirector:
  - adds a **+10 Bones** bonus;
  - sets `result.reason = "exterminator_beaten"`;
  - calls `end_round("exterminator_beaten")`.
- The result also includes `dead_houses: Array[int]`, collected from the `"houses"` group as each house's `index` (A adds `var index: int` to House).
- **End panel:** "<title> has fallen", then "<next district title> lies open", or "The city is yours" if there's no next District.

### Boss HUD (implementer B)
- **Banner:** when the Exterminator arrives, "The Rat-catcher has come" fades in and out in the centre.
- **Bar:** while it's alive, its title and an Infection bar sit under the Vigilance meter. The bar fills red and shows a faint marker for the cleanse rate. It hides once the Exterminator is beaten.

### YearTable per District (implementer B)
- **Lookup:** `YearTable.entry_for(year: int, district_id := "slums")` returns the latest entry with that district_id and `from_year <= year`. If there's none, it falls back to the slums.
- **Merchant entries:**
  - Guards (always_fight, torch or club) from the start, Hygiene 0.25, Speed 1.1, `start_vigilance` 0.3;
  - later Years push Hygiene to 0.5.
- **Spawner (A):** passes `Run.current_district` to `entry_for()`.
