# M1 integration contract (Bite and die)

Shared by both M1 implementers. If you need to change anything here, say so in
your final report. Don't silently diverge.

Read first: `GLOSSARY.md`, `docs/game_concept.md`, `docs/prototype_build_plan.md` (M1),
`scripts/town_props.gd` (prop kit + colour rules), `scenes/main.tscn` (camera + parchment overlay setup).

## Engine
- Godot 4.6.3, GDScript, static typing everywhere (`var x: float`, `-> void`).
- Godot binary (not on PATH): `C:/Users/Home/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe`
- After adding `class_name` scripts, refresh the class cache: `<godot> --headless --path . --editor --quit`.
- Parse check: `<godot> --headless --path . --quit-after 200` (look for `SCRIPT ERROR` / `Parse Error`).
- Leave `scenes/main.tscn`, `scripts/demo_town.gd`, `scripts/parchment_overlay.gd`, `shaders/` and `scripts/town_props.gd` **unchanged**. The demo stays as a style test.

## Folders
- `scenes/game/`, `scenes/ui/`, `scripts/game/`, `scripts/components/`, `scripts/ui/`

## Physics layers (named in project.godot by implementer A)
1 `world` (houses, bounds) · 2 `rats` · 3 `townsfolk`
- Rats: layer 2, mask 1. They walk through people.
- Townsfolk: layer 3, mask 1 + 3.

## Groups
- `"townsfolk"`: every living townsperson (root node). Leaves this group on death.
- `"corpses"`: dead townspeople (they stay in the world as corpses; M2 Feeds on them).
- `"round_director"`: the RoundDirector node.
- `"lead_rat"`: the Lead Rat root.

## InfectionComponent: `scripts/components/infection_component.gd` (implementer B)
```gdscript
class_name InfectionComponent extends Node
signal infected            # first time value goes above 0
signal died                # value reached 100
signal value_changed(value: float)
@export var base_rate := 5.0         # %/s once infected  (≈20 s to death)
@export var gain_multiplier := 1.0   # scales Bite chunk + rate bonus (Exterminators < 1)
@export var cleanse_rate := 0.0      # %/s self-Cleanse (Exterminators > 0)
var value := 0.0                     # 0..100
var bonus_rate := 0.0                # accumulated from Bites
func bite(chunk: float, rate_bonus: float) -> void
func cleanse(amount: float) -> void
func is_infected() -> bool           # value > 0 and not dead
func is_dead() -> bool
```
Each townsperson root has this as a child node named exactly `Infection`.
Rate per second while infected = `base_rate + bonus_rate - cleanse_rate`.

## Townsperson: `scenes/game/townsperson.tscn` (implementer B)
- Root `CharacterBody3D` with `scripts/game/townsperson.gd`, child `Infection`.
- Before `add_child`, the spawner sets `wander_bounds: Rect2` (XZ rectangle, x→X, y→Z) and an optional `rng_seed: int`.
- It builds its own visual in `_ready()` with `const Props := preload("res://scripts/town_props.gd")`.

## BiteComponent: `scripts/components/bite_component.gd` (implementer A)
```gdscript
class_name BiteComponent extends Node3D
signal bit(target: Node3D)
@export var bite_range := 1.6
@export var cooldown := 1.2
@export var chunk := 3.0
@export var rate_bonus := 0.5
```
It auto-targets the nearest node in `"townsfolk"` within range whose `Infection` is not dead,
then calls `target.get_node("Infection").bite(chunk, rate_bonus)`. It's meant to be reused by every Adult rat in M2.

## RoundDirector: `scripts/game/round_director.gd` (implementer B)
```gdscript
class_name RoundDirector extends Node   # in group "round_director"
signal stats_changed
signal round_ended(reason: String)       # "timer" (M1); "lead_rat_died" comes in M2
@export var round_length := 90.0
var time_left: float
var pestilence := 0     # +1 per townsperson on first infection
var bones := 0          # +1 per death
var population := 0     # townsfolk registered this Round
var infected_count := 0 # currently infected (alive)
var dead_count := 0
func district_infection() -> float   # (infected_count + dead_count) / population, 0..1
func register_townsperson(t: Node3D) -> void
```
It registers everything already in `"townsfolk"` in `_ready()` (deferred) and anything added later
(`get_tree().node_added`). When the Round ends, the game world pauses.

## HUD: `scenes/ui/hud.tscn` (implementer B)
- A `CanvasLayer` that finds the director with `get_tree().get_first_node_in_group("round_director")`.
- Shows: Pestilence, Bones, time left, District Infection %.
- End-of-Round panel: totals, plus "Press R / Start to play again", which reloads the current scene.
- Look: ink-brown text (`Color(0.13,0.10,0.08)`) on a translucent parchment panel. No bright UI colours.
- The HUD must keep running while the world is paused (`process_mode = ALWAYS`).

## District scene: `scenes/game/district.tscn` (implementer A)
- Becomes the project's main scene. Contents:
  - environment, sun and camera copied from `scenes/main.tscn`, with the `ParchmentOverlay` child on the camera;
  - `scripts/game/district.gd`, which builds the slum layout with the prop kit and adds collision for houses and bounds;
  - the Lead Rat;
  - a `RoundDirector` node (B's script);
  - a HUD instance (B's scene);
  - about 25 townsfolk instanced from `scenes/game/townsperson.tscn` at random free spots.
- Debug flags (after `--`):
  - `--screenshot=<path>` saves a frame after about 3 s and quits;
  - `--bot` makes the Lead Rat steer itself to the nearest healthy townsperson;
  - `--set=<uniform>=<float>` sets a parchment shader value, same as the demo.
