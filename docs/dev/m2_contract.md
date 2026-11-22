# M2 integration contract (Colony, Fear, fighting back)

This builds on `docs/dev/m1_contract.md`; everything there still holds unless changed here.
Terms are defined in `GLOSSARY.md`.

## Review rules carried over from M1 (both implementers)
- **Red ink means plague.** Saturated red is reserved for Infection, Bite marks and blood. Don't use red for roofs, props or UI decoration.
  Warnings that aren't plague (stomp wind-up rings etc.) are drawn in INK.
- The camera is now at pitch 70° and distance 26 (set in `district.tscn`). Keep it.
- Balance starts *weak*: the Colony begins as the Lead Rat alone (start size is an export; default 0 followers).

## Groups (additions)
- `"rats"`: every living rat, Lead Rat included, Pups included. Fear counts this group.
- `"colony"`: the single Colony node.

## Rat API (implementer A)
Every node in `"rats"` has:
```gdscript
var is_pup: bool               # Pups don't Bite and don't Feed-to-breed
func hit() -> void             # a townsperson's attack landed on this rat
```
- Colony rats die from one `hit()`; they play a small squash or flatten, leave a tiny ink smear, then `queue_free`.
- Lead Rat: `@export var max_hits := 3`, `var hits_left: int`, `signal hurt(hits_left: int)`, `signal died`.
  When it is hit, it gets 0.8 s of invulnerability and its visual flickers. At 0 hits it emits `died`.

## Colony: `scripts/game/colony.gd` (implementer A)
```gdscript
class_name Colony extends Node3D        # in group "colony"
signal changed                           # rat added/removed, Pup matured
@export var start_adults := 0            # followers at Round start (Upgrade Tree sets this in M3)
@export var pup_maturity := 15.0         # s
@export var feed_time := 1.5             # s standing on a corpse per meal
@export var breed_cooldown := 4.0        # s per Adult between Pups
@export var pup_feed_bonus := 5.0        # s of maturity removed per meal a Pup eats
var adult_count: int                     # includes the Lead Rat
var pup_count: int
```
- **Followers** flock behind the Lead Rat:
  - each seeks a loose slot around it, with separation between rats;
  - they move a little faster than the Lead Rat so they keep up;
  - collision is layer 2, mask 1.
- **Adults** have a `BiteComponent`. **Pups** have none.
- **Feeding:**
  - Feeding is automatic. A rat within ~2.5 u of a corpse that has meals left detours to it, but only if the Lead Rat is within ~6 u.
  - After `feed_time` on the corpse it takes 1 meal.
  - Adult takes a meal → it spawns a Pup next to itself, then waits `breed_cooldown` before breeding again.
  - Pup takes a meal → its maturity time drops by `pup_feed_bonus`.
  - The Lead Rat Feeds too, but only while it stands still or nearly still within 1 u of a corpse. This is the risky choice.
- A Pup Matures into an Adult when its timer runs out. It grows from scale 0.55 to 0.9 and gains a BiteComponent.
- **Visual scales:** Lead Rat 1.4, Adult 0.9, Pup 0.55.

## Corpses (implementer B, in townsperson.gd)
```gdscript
var meals_left := 3                       # only meaningful once dead
func take_meal() -> bool                  # false if not dead or no meals left
```
As meals are eaten, the corpse visually shrinks or flattens a little each time. At 0 meals it stays as an ink smear but leaves group `"corpses"`.

## Fear: `scripts/components/fear_component.gd` (implementer B)
```gdscript
class_name FearComponent extends Node
enum Band { FIGHT, UNEASY, FLEE }
signal band_changed(band: int)
@export var radius := 6.0
@export var uneasy_at := 4                # rats nearby (Pups count)
@export var flee_at := 12
@export var hysteresis := 1
var band: int = Band.FIGHT
var rats_near: int
```
It updates at about 5 Hz, not every frame. Each townsperson has one as a child named `Fear`.

## Fighting back (implementer B)
- **`scripts/data/weapon_def.gd`:** `class_name WeaponDef extends Resource`. Fields: `id`, `windup`, `radius`, `cooldown`, `reach`, `kills_pups_only`.
  Stomp lives in `data/weapons/stomp.tres` (windup 0.6, radius 1.1, cooldown 2.5, reach 1.4). M5 adds more.
- **`scripts/components/weapon_component.gd`:** `class_name WeaponComponent extends Node3D`, with `@export var weapon: WeaponDef`.
  - Within `reach` of a rat it starts a telegraphed attack.
  - During the wind-up it shows an INK ring on the ground at the strike point.
  - On impact it calls `hit()` on every node in `"rats"` within `radius` of that point. A dodge is possible.
- **Townsperson behaviour by Fear band:**
  - **FIGHT:** walk at 2.2 u/s towards the nearest rat within the Fear radius and attack.
  - **UNEASY:** keep about 5 u away from the nearest rats, sidestepping. No attacks.
  - **FLEE:** run directly away from the rats at 3.2 u/s for at least 2 s.
  - Infected people still behave by band but at 0.55× speed and with 1.5× wind-up.
  - The dead do nothing.

## Round end (implementer B)
- RoundDirector connects to the Lead Rat's `died` signal (group `"lead_rat"`) and calls `end_round("lead_rat_died")`.
- The end panel shows the reason: "The Lead Rat was crushed" or "The Round is over".

## HUD additions (implementer B)
- Below the currencies: `Colony  <adults> (+<pups> pups)`, read from the node in group `"colony"`.
- The Lead Rat's hits left are shown as 3 small ink marks, filled or empty. Use the `hurt` signal or poll `hits_left`.
- Every value shows "—" if its source is missing.

## District additions (implementer A)
- **Occlusion cutaway.** If a house sits between the camera and the Lead Rat, squash that house's visual towards a footprint: tween scale.y to about 0.12 over 0.2 s. Restore it once it has stopped occluding for 0.5 s. Collision is unchanged.
  - Use a camera→rat ray, or segment tests, against the house collision boxes, at about 10 Hz.
  - Keep a mapping from each house body to its visual root.
- **Debug flags:**
  - `--start-colony=<n>` spawns n Adult followers at the start;
  - `--pups=<n>` spawns n Pups;
  - `--god` makes the Lead Rat ignore hits.
