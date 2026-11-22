# M4 integration contract (Houses: Hide and Raid)

This builds on the M1–M3 contracts in `docs/dev/`, which all still hold. Terms are defined in `GLOSSARY.md`.

## Review rules so far
- Red means plague. Corpses are dark sepia. Gameplay numbers live in data (`Run.BASE_STATS` or Resources).
- Hide and Raid only work when `Run.is_unlocked("unlock_hide")` / `("unlock_raid")` is true.
  The `--dev` flag unlocks both.

## Houses: `scripts/game/house.gd` (implementer A)
```gdscript
class_name House extends StaticBody3D       # the existing per-house collision body gets this script; group "houses"
signal occupants_changed
signal house_died                            # every resident is dead (fires once)
var door_position: Vector3                   # world point just outside the door, on the ground
var door_normal: Vector3                     # points out of the house
var residents: Array[Node3D] = []            # townsfolk whose home is this house (set at spawn)
var occupants: Array[Node3D] = []            # townsfolk currently inside
func enter(person: Node3D) -> void           # called by Townsperson.go_inside
func leave(person: Node3D) -> void           # called by Townsperson.come_outside
func living_occupants() -> Array[Node3D]
func is_dead_house() -> bool
```
- When `house_died` fires, draw an **ink X across the roof**: two thin dark strips on the roof planes, drawn as an ink stroke. The X squashes along with the cutaway. M7's Scroll Map will reuse this "dead house" state.
- The District (A) gives each house 0–3 residents. They spawn **indoors** (`Townsperson.start_indoors(house)`), and their `home` is set before `add_child`. The outdoor wanderers from M1 keep a `home` too: their nearest house.
- **Population** = residents + outdoor townsfolk. Everyone registers with the RoundDirector as before.

## Townsperson indoor state (implementer B)
```gdscript
var home: House                       # set by the spawner before add_child (may be null)
var is_indoors := false
var current_house: House
func start_indoors(house: House) -> void   # spawn already inside (no walking)
func go_inside(house: House) -> void        # walk to door_position, then vanish inside
func come_outside() -> void                 # appear at door_position + door_normal * 0.8
```
- **While indoors:**
  - `visible = false`, collision off, Fear and Weapon disabled;
  - the person leaves group `"townsfolk"` and joins `"indoors"`;
  - Infection keeps ticking.
- **Dying indoors:** the person stays hidden inside as a corpse and doesn't join `"corpses"`. They still count as dead in the director's stats.
- **Routine:**
  - Every 20–40 s, an outdoor person with a home walks home and stays in for 10–25 s.
  - People who start indoors come out after a random 5–30 s.
- **Fleeing:** in the FLEE band, if their home or any house door is within 10 u, the person runs inside and stays 8–15 s.

## Hide (implementer A)
- **Entering:** with Hide unlocked, the Lead Rat touching a house's door (within ~1 u of `door_position`) hides the **whole Colony** in that house.
  - The rats become hidden and invulnerable.
  - They leave group `"rats"` while hidden, so Fear and stomps ignore them, and join `"hidden_rats"`.
- **Biting inside:** every Adult Bites a random living occupant on its normal Bite cooldown. Use the Adult's BiteComponent stats and call `Infection.bite()` directly.
- **Leaving:** the Colony is forced out at the door after `Run.stat("hide_duration")` seconds (default 6), or as soon as every occupant is infected or dead. A house with no living occupants can still be used to break pursuit, but only for half the duration.
- **Cooldown:** after leaving, Hide is on cooldown for 3 s, so leaving can't immediately re-enter.

## Raid (implementer A)
- **Choosing a house:**
  - Mouse: the `raid` action at the cursor raycasts against layer 1 to find a House.
  - Gamepad: the `raid` action picks the nearest house within 10 u of the Lead Rat.
  - The chosen house is highlighted with an ink ring at its door while the raid is in progress.
- **The raid itself:**
  - It sends `Run.stat("raid_size")` Adults (default 3), followers only and never the Lead Rat, at most the available followers.
  - They run to the door and vanish inside (they leave `"rats"` while inside).
  - Inside, they Bite occupants for `Run.stat("raid_duration")` (default 4 s), then come out and rejoin the flock.
- **Cooldown:** `Run.stat("raid_cooldown")` (default 10 s). A raid needs at least one follower Adult.
- **New stats:** add `hide_duration`, `raid_size`, `raid_duration` and `raid_cooldown` to `Run.BASE_STATS` (A owns run.gd). B may add upgrade nodes that use them: optional "Deep Burrow" and "Rat King" nodes.

## Colony state for the HUD (implementer A, read by B)
On the node in group `"colony"`:
```gdscript
var hide_unlocked: bool
var raid_unlocked: bool
var is_hidden: bool
var hidden_time_left: float
var raid_cooldown_left: float     # 0 = ready
var raiders_inside: int
```

## HUD (implementer B)
- **Bottom-left, ink on parchment:**
  - `Raid  ready` / `Raid  7s` / `Raid  (need followers)`, shown only when Raid is unlocked;
  - `Hidden  4s` while the Colony is hidden.
- **First-time hint:** when Hide is unlocked and the Lead Rat is near a door, show `Enter a door to Hide` once per session.

## Debug flags (implementer A)
- `--dev` unlocks Hide and Raid.
- `--bot` now also tries a Raid whenever it's off cooldown and a house is within 10 u, and Hides when hit with 1 hit left.
