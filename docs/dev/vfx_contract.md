# Graphics and VFX pass contract

This pass builds on every earlier contract in `docs/dev/`; terms are in `GLOSSARY.md`.

**Goal:** a District should look as rich as the style demo (`scenes/main.tscn`, `docs/preview_v4.png`), and every gameplay event should have a hand-drawn effect.

**What is wrong today:**
- In the 62° game camera, roofs and bare mud fill most of the screen as blank hatch.
- Nothing moves in the world except the actors.
- Events show only as a few ad-hoc tweened meshes that are created and freed on every event: `WeaponComponent._puff` / `_arc_puff`, `Townsperson._cough` / `_smear`, `ColonyRat._leave_smear`, `PlagueDoctor._pulse_ring`, and the Fleas and Contagion specks.

## The style decides how effects are made

The whole picture goes through `shaders/parchment_ink.gdshader`, a full-screen post-process. It picks a look from the rendered colour and inks the depth and normal edges. Effects must work with it, not around it:

- **Opaque 3D shapes get the hand-drawn look for free.**
  - A pale, low-saturation sphere becomes a parchment blob with an ink outline: a cartoon dust puff.
  - A near-black shape becomes solid ink.
  - A saturated red / green / blue shape becomes a wash of that ink.
- **Use opaque meshes (or alpha scissor) to get outlines.** Alpha-blended meshes write no depth or normals, so they get no outline.
  - Fading by alpha is fine for the last ~30% of a life.
  - Shrinking to zero scale reads better in this style, so prefer it.
- **No 2D particle overlays in the world.** They would sit on top of the paper grain and look pasted on. The HUD's `WorldOverlay` (bars, numbers, flying pickups) stays as it is.
- **No textures from disk.** Shapes are geometry or procedural shaders, like the rest of the project.

## Colour rules (unchanged, now also for effects)
| Colour | Used for in effects |
| --- | --- |
| RED (`Props.RED`) | plague only: Bite spatter, infection miasma, cough clouds, Contagion, the plague cross on a fallen house's door, the Exterminator-beaten bloom |
| Near-black ink | rat deaths, flies, fleas, impact stars, crows, cracks |
| Pale parchment | dust, smoke, steam, plaster |
| Sage GREEN | Plague Doctor herbs and Cleanse only; moss and grass in scenery |
| AMBER, emissive | fire, lantern and window light only (amber in the HUD still means "actionable") |
| BLUE | water, slate roofs in the Merchant quarter, the well |

Never use red for weapon hits, dust or scenery. Roofs are never red (rule from M6).

## Rules for every effect
1. **Readability first.**
   - Nothing may hide the Lead Rat or a DangerZone telegraph for more than 0.2 s.
   - Bursts stay ≤ 0.8 u tall near the ground and last ≤ 1.0 s.
   - Only decals and ambient effects persist.
2. **Pooled, not spawned.**
   - Frequent events (Bites, deaths, dust) must not create nodes or Tweens. Use MultiMesh pools (CPU-updated) or `GPUParticles3D.emit_particle()` on one emitter per effect kind.
   - Rare events (house falls, Exterminator) may create nodes.
   - Every pool has a hard cap, and the oldest entry is recycled.
3. **Budget.**
   - Measure with `--perf --fill --start-colony=40` at 1920x1080 in both Districts.
   - Today it runs at 149–236 FPS. After your work it must stay ≥ 120 FPS.
   - Report FPS before and after.
4. **Time and pause.**
   - Effects use the normal scaled `delta`, so they freeze during the HUD hit-stop and the pause menu. Don't set `process_mode = ALWAYS`.
5. **Settings.**
   - Agent A adds an Effects setting with values Full and Reduced (see A.0).
   - At Reduced: pools are half size, bursts are half count, and there are no flies, run dust or ambient mist.
   - With reduce motion on: no camera-relative motion and no flashing. Small bursts are fine.
6. **The style demo must not break.**
   - `scenes/main.tscn` (built by `demo_town.gd` and `town_props.gd`) must still run and look the same or better.
   - The title screen uses it as a backdrop.
   - Effects find the Vfx node lazily and do nothing when there is no District.
7. **Static typing, composition, data where it is tuning.** The usual project rules. Keep each new file under ~500 lines.

## File ownership (two agents work at the same time — never edit the other's files)

| Agent A — event VFX | Agent B — world look and ambient life |
| --- | --- |
| new `scripts/vfx/` (all files), new `shaders/vfx_*.gdshader` | new `scripts/world/` (all files) |
| `scripts/components/*` | `scripts/town_props.gd` (append-only API; demo must still work) |
| `scripts/game/townsperson.gd`, `colony.gd`, `colony_rat.gd`, `lead_rat.gd` | `scripts/game/district.gd`, `district_decor.gd`, `mesh_batcher.gd` |
| `scripts/game/house.gd`, `fleas.gd`, `plague_doctor.gd`, `rat_catcher.gd`, `terrier.gd`, `cat.gd`, `exterminator.gd`, `spawner.gd`, `round_director.gd` | `shaders/parchment_ink.gdshader`, `scripts/parchment_overlay.gd` |
| `scripts/ui/settings.gd`, `settings_panel.gd`, `ui_kit.gd` (append only) | `scenes/game/district.tscn`, `scenes/main.tscn` (only if needed) |

If you need a change in the other agent's file, don't make it. Work around it (signals, groups, metadata), or note it in your report and I'll do it.

**Shared hooks between the two agents (both build to these):**
- `Settings.effects_level: int`: 1 = Full (default), 0 = Reduced.
  - Agent A adds it.
  - Agent B reads it duck-typed, e.g. `int(Settings.get("effects_level")) if Settings.get("effects_level") != null else 1`, and listens to `Settings.changed`.
- `House.house_died` already exists.
  - Agent A draws the plague cross on the door.
  - Agent B darkens that house's lit windows and stops its chimney smoke. B connects from the District side to houses in group `houses`.
- Weapon strikes and Lead Rat hits are a scare for crows. Agent A emits through the Vfx node: `Vfx` has `signal disturbance(point: Vector3, radius: float)`.
  - A sends it on weapon strikes, Lead Rat hits, trap snaps and Exterminator arrival.
  - B's crows connect to it. B finds the node with the same lazy lookup, in group `vfx`, and treats it as optional.
- RoundDirector: `district_infection()` returns 0..100 and `stats_changed` already exist. B drives the plague stain from them.

## Agent A — event VFX

**A.0 Infrastructure.**
- `scripts/vfx/vfx.gd`: a Node3D in group `vfx`.
  - `static func get_vfx(tree: SceneTree) -> Node` returns the node and creates it under `tree.current_scene` on first use, but only when the current scene has a node in group `round_director` or `lead_rat`. Otherwise it returns null and every caller does nothing.
  - Use `preload` constants, not `class_name`, to avoid class-cache races between the two agents. If you do add a class_name, refresh the cache (see Testing).
- Pools:
  - `burst(kind, pos, dir := Vector3.ZERO, scale := 1.0)` for one-shot particles.
  - `decal(kind, pos, rot, size, life)` for flat ground marks: ink blots, cracks, splats, scorch. Draw them as thin opaque meshes 0.02–0.04 u above ground. One MultiMesh per kind, ring buffer, cap about 160 in total. They shrink away at the end of their life.
  - `attach(kind, node)` for effects that follow a node until it is freed or the effect is detached, such as flies.
- Settings: add `Settings.effects_level` (saved like the others) and an "Effects: Full / Reduced" row in `settings_panel.gd`. Optionally add `UiKit.effects_scale()`.
- Debug flags:
  - `--vfx-test` plays every effect in a ring around the Lead Rat, one kind every 0.4 s, looping. Label each with `print("VFX", kind)`.
  - `--effects=reduced`.

**A.1 Bite.** On `InfectionComponent.bitten(chunk)`:
- 3–6 small red droplets spray away from the biter, scaled by chunk.
- Plus one quick ink "snap" tick: two tiny crossing strokes, 0.15 s.
- The victim shivers (an existing tween is fine).

**A.2 Infection.**
- First infection: a soft red puff ring at chest height.
- Above 60% Infection: 2–4 flies orbit the head. Flies are tiny ink specks with jittery paths in one shared MultiMesh; cap 200.
- Above 85%: a cough cloud every few seconds, a pale puff with one red fleck drifting forward. This replaces `_cough`.

**A.3 Death.**
- On the topple: a ground dust puff.
- A dark sepia blot decal spreads under the body over 0.6 s.
- Flies settle on the corpse and stay while it is in group `corpses`.
- When the corpse is eaten clean, `_smear` becomes a proper splat decal: an irregular blob plus satellite drops.

**A.4 Rats.**
- `ColonyRat.hit()`: an ink splat (radial droplets plus a splat decal) replaces `_leave_smear`.
- Lead Rat hurt: a bigger ink burst and an ink ring.
- Lead Rat death: a large splat.
- Feeding: tiny dark nibble flecks.
- Pup born: a pale puff and three ink sparkle ticks.
- Pup matures: a small ring pop.
- Run dust: small sparse pale puffs behind the swarm, on unpaved ground only. Ask `district_decor` / the District with duck typing, or skip it if there's no simple way to tell.

**A.5 Weapons and bosses.** Replace `_puff` / `_arc_puff` and the pulse ring with pooled effects.

| Source | Effect |
| --- | --- |
| Stomp | a ring of 8–10 dust puffs and a crack decal |
| Broom | a dust arc along the sweep and straw flecks |
| Club | an ink impact star (spikes) and dust |
| Torch fire patch | flickering amber emissive flame tongues, rising pale smoke, and a scorch decal when it ends |
| Cat pounce | dust |
| Rat-catcher trap snap | an ink star |
| Terrier | run dust |
| Plague Doctor | sage-green herb smoke swirling around the cleanse aura; green flecks rising from healed townsfolk; a pulse ring made of green puffs; incense swing trails |
| Exterminator arrival | a dust burst at the gate; emit a `disturbance` |
| Exterminator beaten | a big red miasma bloom |
| Fleas | hop arcs through the pool, replacing the current specks if that's simpler |
| Contagion | red cough clouds drifting from one person to the next |

**A.6 Houses.**
- Rats entering or leaving for Hide or Raid: a dust puff at the door.
- `House.show_bite`: plaster dust falls from the eaves.
- `house_died`: a red plague cross is painted on the door. It's permanent and squashes with the cutaway. Historically this cross was painted on plague houses' doors. Add a short red miasma puff from the roof as well.

## Agent B — world look and ambient life

**B.1 Ground.**
- Break up the bare mud and paving, by District and Year stage. Build everything as MultiMesh or batched geometry, visual only with no collision, and keep it off door points and gates.
- **Slums:**
  - stage 0: wheel ruts (pairs of shallow strips), scattered stones, straw wisps, grass tufts (sage green) along wall bases and fences, puddles (blue), refuse;
  - later stages: tidier.
- **Merchant quarter:** gutters, kerb stones, planters, scattered petals or leaves.

**B.2 Roofs.** With the camera at 62° they fill roughly half the screen.
- **Slums:**
  - missing or patched tiles that show black rafter holes, sagging ridges and moss patches (sage);
  - chimneys on more houses;
  - stage 2 repairs them.
- **Merchant quarter:**
  - slate roofs, about half of them with a blue ink wash (manuscript azure, a sign of wealth);
  - dormers and chimney pots.

All of this goes through the prop kit, so the demo can use it too. The demo's own red roofs are fine; the never-red rule is for the game only.

**B.3 Chimney smoke.**
- Rising pale puffs from the chimneys of living houses; the Merchant quarter has more.
- Smoke stops on `house_died`: a dead house is cold.

**B.4 Crows.**
- Ink birds perched on roof ridges and fences. They hop and peck.
- They scatter when rats come within 3 u, or on a `Vfx.disturbance`, then fly a loop and land elsewhere.
- Extra crows gather on fallen houses.
- At most 16 crows.

**B.5 Fallen houses.**
- Lit (amber) windows go dark ink, and the chimney stops (B.3).
- The plague cross on the door is A's.

**B.6 Plague stain.**
- Add a shader uniform `plague_stain` 0..1, driven by District Infection.
- A red-brown wash blooms in from the page edges, noise-shaped, under the ink lines, and never over the centre ~60% of the screen.
- `--stain=<0..1>` previews it.
- The README tuning section documents it.

**B.7 Ambient motion.**
- Flickering lanterns: emission energy wobble, no flashing.
- Laundry lines across some alleys with swaying cloth (pale; never red).
- Hanging shop signs that swing in the Merchant quarter.
- Ripples in the well and fountain (blue rings).
- Optionally, low drifting mist in the Slums at stage 0 (off at Reduced).

**B.8 Debug.** `--ambient-test` puts crows next to the Lead Rat and makes them scatter after 2 s.

## Testing (both)
- **Godot:** `C:/Users/Home/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe`.
  - Refresh the class cache with `--headless --path . --editor --quit`, only when needed.
- **Always pass `--year=<n>`** (it doesn't save) so the real save stays untouched. Don't write other `user://` files.
- **Screenshots:** `--resolution 1600x900 -- … --screenshot=<png> --screenshot-delay=<s>`.
  - Use `--bot --dev --god --start-colony=18`.
  - Take them in the Slums (stage 0 and 2) and the Merchant quarter (`--district=merchant --force-exterminator`).
  - Put them in your folder in the scratchpad.
  - Look at your own screenshots and judge them against `docs/preview_v4.png`.
- **Must run clean:** headless runs of the District with `--bot --dev`, of `scenes/main.tscn`, and of the title, with no errors and no new warnings.
- **Report:**
  - files changed;
  - what each effect looks like;
  - FPS before and after;
  - anything you couldn't do;
  - any change you need in the other agent's files.
