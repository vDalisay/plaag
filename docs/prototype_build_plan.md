# Plaag: prototype build plan

This plan builds the first playable prototype described in
[game_concept.md](game_concept.md). Words in capitals (Round, Colony, Infection,
Vigilance, …) are defined in [GLOSSARY.md](../GLOSSARY.md).

Every milestone ends with something you can play. Each one adds to the last,
so you can stop after any milestone and still judge how the game feels.

## What we reuse

- **Parchment look.** [shaders/parchment_ink.gdshader](../shaders/parchment_ink.gdshader)
  is a full-screen post-process that hangs off the camera. Any new scene gets
  the look by copying the camera, overlay and environment setup from
  [scenes/main.tscn](../scenes/main.tscn).
- **Prop kit.** [scripts/town_props.gd](../scripts/town_props.gd) already
  builds houses, wells, figures (plain / red / doctor), rats, barrels and
  stalls out of primitives. Gameplay scenes call it for visuals. The game logic
  lives in separate nodes.
- **Colour rules.** The shader decides how things are drawn from their colour:
  - Pale colours become parchment.
  - Saturated red, amber, green or blue becomes an ink wash of that hue.
  - Near-black becomes solid ink.

  So Infection can be shown by blending a person's cloak towards red as the
  meter fills. Death shows as solid ink. Both cost nothing extra.

## Architecture

Entities are built by composition: a body node plus small child components.
No deep class trees.

| Piece | Kind | Holds |
| --- | --- | --- |
| `Run` | autoload | Year, Pestilence, Bones, bought Upgrade Tree nodes, unlocked Districts, best Round per District. Saved to `user://`. |
| `RoundDirector` | node in District scene | Round timer, Vigilance, spawning, District Infection %, Exterminator trigger, Round end |
| `InfectionComponent` | component | meter 0–100, rate, `bite(chunk, rate_bonus)`, `cleanse(amount)`, signals `infected` / `died` |
| `FearComponent` | component | counts rats nearby and outputs a Fear band: Fight / Uneasy / Flee |
| `WeaponComponent` | component | stomp, broom, cat, torch or club behaviour, set by a `WeaponDef` resource |
| `Colony` | node | list of rats, follow/flocking, Feed → Pup → Mature, Carry-over |
| `TownsfolkDef`, `WeaponDef`, `UpgradeNodeDef`, `DistrictDef`, `YearTable` | `Resource`s | all the tuning numbers, so balancing means editing data, not code |

**Performance:** each prop-kit figure is about 40 mesh instances, and each rat
about 10. That's fine for dozens. For hundreds of rats, switch rat visuals to a
`MultiMeshInstance3D` (planned for M2 if it's needed).

## Milestones

### M1 — Bite and die (core feel)
- **District scene:**
  - A flat slum street built with the prop kit.
  - A top-down camera that follows the Lead Rat; steeper than the demo's 47°.
  - The parchment overlay.
- **Input map:** `move_*` (WASD + left stick) and `raid` (mouse click + A).
- **Lead Rat:** a `CharacterBody3D` with automatic Bite: nearest person in range, on a cooldown.
- **Townsfolk:** wander around, with an `InfectionComponent`.
  - A Bite adds a chunk of Infection and raises the rate.
  - The meter keeps climbing on its own, and the person dies at 100% (baseline about 20 s).
  - The corpse stays behind.
- **Payouts:** Pestilence on first infection, Bones on death.
- **HUD:** currencies, Round timer, District Infection %.
- *Playable:* run around and spread the plague for 90 seconds.

### M2 — Colony, Fear and fighting back
- **Colony:** follower rats flock behind the Lead Rat, and every Adult Bites.
- **Feeding:** an Adult Feeding on a corpse produces a Pup. A Pup that Feeds Matures faster.
- **Fear:** a `FearComponent` gives each townsperson a band (Fight / Uneasy / Flee) from nearby rats, Pups included.
- **Fighting back:** a telegraphed stomp.
  - It kills any rat in its radius.
  - The Lead Rat survives 3 hits; on the 3rd the Round ends.
- *Playable:* compare the small-Colony and big-Colony strategies.

### M3 — The meta loop
- **`Run` autoload:** currencies, Year, purchases, and saving.
- **Year:** advances by 1 when the Lead Rat dies; ending on the timer doesn't advance it.
- **Upgrade Tree screen:** drawn on parchment, built from `UpgradeNodeDef` data.
  - Nodes can cost Pestilence, Bones or both.
  - It starts with the starter set from the concept doc.
- **Loop:** Round → Upgrade Tree → Round.
- **Carry-over:** the next Round's Colony size = starting size + Carry-over % of the last Round's final size.
- *Playable:* the full Nodebuster-style loop in one District.

### M4 — Houses
- **Houses:** each house has occupants inside.
- **Hide:** walk into a door and the whole Colony enters.
  - Pursuers lose track, and the rats Bite the people inside.
  - You're forced back out after a few seconds, or once everyone inside is infected.
- **Raid:**
  - Mouse: click a house. Gamepad: A targets the nearest house.
  - A few Adults go in, infect the people inside and come back. On a cooldown.
- Hide and Raid are unlocked through the Upgrade Tree.

### M5 — Escalation (Risk of Rain)
- **Vigilance:** set by time in the Round plus the Year.
- **Spawning:** new townsfolk come in through District gates and house doors.
  - The `YearTable` decides which types exist.
  - Vigilance makes the strongest types spawn more often.
- **Weapons:** broom, cat, torch and club, each as a `WeaponDef`.
- **Year raises:** townsfolk stats and Hygiene.
- *Playable:* each death makes the next Round noticeably tougher.

### M6 — Exterminators
- **Arrival:** an Exterminator turns up at 50% District Infection, while the timer keeps running.
- **Toughness:** reduced gain from Bites, and it keeps Cleansing itself.
- **Rat-catcher (slums):** a terrier hunts the Lead Rat while the Rat-catcher lays traps.
- **Plague Doctor (merchant quarter):** a Cleanse aura that also heals the townsfolk around them.
- **Reward:** Infection reaching 100% on the Exterminator unlocks the next District.

### M7 — Second District, Scroll Map and the look of the Years
- **Merchant quarter:** Hygiene, Guards with torches and clubs, and fewer but sturdier townsfolk.
- **Scroll Map screen:**
  - Pick a District here.
  - Beaten Districts are inked over.
  - The houses killed in your best Round are crossed out.
- **Year visuals:** 3 stages per District, built with the prop kit.
  - Mud becomes cobbles.
  - Wells get cleaned up.
  - Houses get shutters and lime-wash.
- **Big unlocks:** Fleas (passive aura) and Contagion.

## Open tuning numbers (start values, adjust in play)

| What | Start value |
| --- | --- |
| Round length | 90 s |
| Bite chunk / rate bonus | +3% / +0.5%/s per Bite |
| Baseline death time | about 20 s |
| Exterminator trigger | 50% District Infection |
| Lead Rat hits | 3 |
| Pup maturity | 15 s, shortened by Feeding |
| Fear bands (rats nearby) | Fight < 4 ≤ Uneasy < 12 ≤ Flee |

## Status (2026-11-22)

M1–M7 are built and integrated on the `prototype` branch:
- The per-milestone interface contracts are in `docs/dev/`.
- M6b is the boss balance pass: danger zones, followers dodging, and swarming the boss.
- The Merchant quarter moved from M7 into M6.

A UX pass followed. The contract is in `docs/dev/ux_contract.md`.
- **In the Round:**
  - a bullet-heaven HUD: Infection bar with the Exterminator mark, a Risk of Rain-style Vigilance strip, the boss bar and an ability bar;
  - Pestilence and Bones icons that fly to the counters;
  - Infection bars and Bite numbers over heads;
  - a Lead Rat ring;
  - hit feedback;
  - a District title card;
  - a pause menu with a stat sheet;
  - a results screen that tallies the Round and previews the next Year.
- **Upgrade Tree** in Nodebuster style:
  - zoom, plus distinct node states: affordable, locked, maxed and "?" teasers;
  - hold-to-buy and a tooltip beside the node.
- **Polish on the Scroll Map.**
- **New screens and systems:**
  - a title screen;
  - a settings panel;
  - ink-blot scene transitions;
  - gamepad and keyboard prompts that follow the last device used.

Everything has been verified with headless runs, scripted tests and bot-driven screenshots.
It has **not** been play-tested by hand yet, so difficulty and feel are unconfirmed.
