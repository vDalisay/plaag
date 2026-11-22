# M7 integration contract (Scroll Map, Year visuals, Fleas, Contagion)

This builds on all earlier contracts in `docs/dev/`. Terms are defined in `GLOSSARY.md`.
The Merchant quarter was already built in M6.

## Review rules so far
- Red means plague; the Plague Doctor is the one exception. Corpses are dark sepia.
- Gameplay numbers live in data.
- The HUD and UI read other systems with duck typing.
- Every attack is a telegraphed danger zone.

## Flow
```
Round ─end panel─▶ Continue ─▶ Upgrade Tree ─[To the Map]─▶ Scroll Map ─[pick District]─▶ Round
```
- The Upgrade Tree's "Begin Round" button becomes **"To the Map"**. It calls `Run.open_map()`.
- On the Scroll Map you pick an open District. That sets `Run.current_district` and calls `Run.start_round()`.
- `--dev` can still skip straight to a Round.

## Run additions (implementer A)
```gdscript
const BASE_STATS += { "flea_radius": 2.0, "flea_chance": 0.15, "flea_interval": 1.0,
                      "contagion_radius": 1.8, "contagion_chance": 0.10, "contagion_interval": 1.5 }
func open_map() -> void                                  # change_scene_to_file res://scenes/ui/scroll_map.tscn
func store_layout(district_id: String, houses: Array) -> void   # saved; see below
func layout_of(district_id: String) -> Array             # [] if never visited
```
- **Layout entries.** Each house in a stored layout is a Dictionary `{ "index": int, "center": Vector2, "size": Vector2, "rot": float }`, with positions and sizes in District ground units (x→X, y→Z).
- **When it's stored.** The District calls `store_layout` once it has finished building, each Round. The layout is deterministic per District, so storing it is idempotent.
- **What the map shows.** `best_dead_houses[district_id]` from M6 holds the houses to cross out.

## Year visual stages (implementer A, District)
- **Stage source.** The District reads `YearTable.entry_for(Run.year, district).visual_stage` (0..2). `--stage=<n>` overrides it for testing.
- **Only decoration changes.** House positions, sizes, indices, collisions and doors must be identical across stages, because Scroll Map indices depend on them.

| Stage | Look |
| --- | --- |
| 0 | Mud: dark-sepia puddles and refuse heaps, sagging fences, open drains; few cobbles. |
| 1 | Some streets cobbled, puddles fewer, a cleaned well with a bucket and roof, a few window shutters. |
| 2 | Mostly cobbled, no puddles, shutters and window boxes, lime-washed (paler) walls, more lanterns, a water trough or fountain in the slums. |

- **Merchant quarter.** It starts at stage 1 and reaches stage 2 in later Years. **B** adds the merchant `visual_stage` values to the YearTable.
- **Performance.** All decoration goes through MeshBatcher. Keep 60 FPS or better.

## Fleas (implementer A, rats' side)
- **Unlock.** Active when `Run.is_unlocked("unlock_fleas")`. `--dev` turns it on.
- **The aura.** Every `flea_interval`, each Adult (the Lead Rat included) rolls `flea_chance` for each living townsperson within `flea_radius`. On success it calls `Infection.bite(1.0, 0.2)`. The aura doesn't hit Exterminators.
- **Visual.** 2–3 tiny ink specks hop in an arc from the rat to the victim.

## Contagion (implementer B, townsfolk side)
- **Unlock.** Active when `Run.is_unlocked("unlock_contagion")`. `--dev` turns it on.
- **The spread.** Every `contagion_interval`, each *infected, living, outdoor* townsperson rolls `contagion_chance` for each living, uninfected, outdoor townsperson within `contagion_radius`. On success it calls `Infection.bite(1.0, 0.1)` on them.
  - The Pestilence payout already happens on first infection.
  - Contagion doesn't spread to Exterminators.
- **Visual.** A faint red dotted line, drawn for a moment between the two people.
- **Performance.** Use a cheap spatial check, e.g. a grid rebuilt at 2 Hz, so it holds up with 80+ people.

## Scroll Map: `scenes/ui/scroll_map.tscn` + `scripts/ui/scroll_map.gd` (implementer B)
- **The page.** A parchment scroll with rolled ends drawn at the top and bottom, and a hand-drawn city map in ink.
  - Each District is a region placed at `DistrictDef.map_position`, labelled with its title in a blackletter-ish serif.
  - Districts that aren't open are drawn faint, with "Unknown" or a lock.
  - **Beaten Districts are inked over:** a dense hatch fill over the region.
- **District detail.** The selected District shows its stored layout (`Run.layout_of`) as small house footprints. The houses in `best_dead_houses` are **crossed out** with ink Xs.
  - A District that has never been visited shows a sketchy placeholder pattern instead.
- **Header.** The Year, the wallet, and "Choose where the plague goes next".
- **Input.**
  - Mouse: click a District to select it; click again or press "Begin Round" to start.
  - Gamepad/keyboard: left/right to select, A/Enter to begin, B/Esc to go back to the Upgrade Tree.
- **Debug flags.** `--screenshot=`, the same way the other UI scenes do it.
