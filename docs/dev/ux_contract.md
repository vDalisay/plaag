# UX pass contract (in-Round feel + meta screens)

This builds on all earlier contracts in `docs/dev/`. Terms are defined in `GLOSSARY.md`.

**Goal:** make Plaag read and feel like the games it borrows from.
- **Vampire Survivors / bullet heavens:** one glance tells you how you're doing, the player character is obvious, pickups fly to counters, a big boss bar, a results screen that tallies the run.
- **Nodebuster:** a pannable, zoomable upgrade tree with unmistakable node states, juicy purchases, and nodes revealed as you buy.
- **Risk of Rain:** a difficulty strip that names the danger as it climbs, a stage title card, and visible proof that the world moves on each Year.

All of it stays in the parchment-and-ink manuscript look.

## Already in place (orchestrator; read, don't rewrite)
| File | What |
| --- | --- |
| `scripts/ui/ui_kit.gd` (`UiKit`) | palette, `body_font()` / `display_font()`, sizes, `label()` / `label_settings()` with a parchment outline, `panel_box()`, `theme()` (buttons with hover / pressed / disabled and an amber focus ring), `prompt(action)` glyph text, `punch(control)`, `shake_scale()`, `reduce_motion()` |
| `scripts/ui/prompt_hint.gd` (`PromptHint`) | `PromptHint.make("ui_accept", "Continue")`: key cap + verb, switches with the last device |
| `scripts/ui/ui_icons.gd` (`UiIcons`), `scripts/ui/icon_rect.gd` (`IconRect`) | ink icons: pestilence, bones, rat, pup, skull, house, eye, hourglass, door, raid |
| `scripts/ui/settings.gd` (autoload `Settings`) | `screen_shake` 0..1, `damage_numbers`, `reduce_motion`, `fullscreen`, `hud_scale` 0.8..1.4, `set_value(key, v)`, signal `changed`; `last_device` / `is_gamepad()`, signal `device_changed`. Debug: `--reduce-motion`, `--no-numbers`, `--pad` |
| `project.godot` | stretch `canvas_items` / `expand` at 1280x720 base; new action `pause` (Esc, P, Start); `Settings` autoload |

You may add small helpers to `ui_kit.gd` / `ui_icons.gd` if you really need them. Append only, never change existing signatures, and say so in your report.

## Rules for every screen
1. **Use the kit.** Colours, fonts, panels and buttons come from `UiKit`. Don't add new palette constants; replace the per-file copies in the files you own.
2. **Colour meaning.**
   - RED is plague only (Infection, Pestilence, plague nodes); the Plague Doctor is the one exception.
   - AMBER means "you can act on this" (affordable, ready, focused), used sparingly.
   - Everything else is ink and sepia.
3. **Prompts.** Every input hint is a `PromptHint`. Never hard-code "Enter", "A" or "Click".
4. **Text over the world** has an outline (`outline` 4–6). Body text is at least `SIZE_SMALL` (14 at base), and important numbers are at least `SIZE_LARGE`.
5. **Controller-complete.**
   - Every menu works with d-pad/stick + A/B (and the keyboard), with initial focus set.
   - B/Esc always goes back one level. No dead ends.
   - Mouse hover and keyboard/gamepad focus look the same.
6. **Motion.**
   - Feedback animations are ≤ 0.4 s and never block input.
   - Anything longer (the results tally) can be skipped with accept.
   - With `reduce_motion`: no punches, shakes or flying icons. Fades stay.
   - Camera shake is multiplied by `UiKit.shake_scale()`.
7. **Layout.**
   - Use anchors and containers at the 1280x720 base.
   - Keep a safe margin of 24 px at base.
   - The HUD root scales by `Settings.hud_scale`.
   - Check every screen at 1280x720 *and* 1920x1080.
8. **Duck typing.** Read other systems with duck typing, as before; a missing value shows "—". Gameplay numbers stay in data.
9. **Performance.**
   - 60+ FPS with 40 rats and 80 townsfolk (`--perf`).
   - Pool floating labels and draw the many small bars in one `_draw`.
10. **Nothing new under red-means-plague.** Corpses stay dark sepia.

## Implementer A: the Round (HUD, world feedback, pause, results)
**Owns:**
- `scripts/ui/hud.gd`, `scenes/ui/hud.tscn`
- new `scripts/ui/world_overlay.gd`, `scripts/ui/pause_menu.gd`, `scripts/ui/results_panel.gd` (and scenes if you want them)
- `scripts/game/round_director.gd`, `scripts/game/run.gd`, `scripts/game/lead_rat.gd`, `scripts/game/follow_camera.gd`
- `scripts/game/district.gd`: only to hook these up
- `scripts/components/infection_component.gd`: only to add a signal

**Does not touch:** anything listed under B.

### HUD layout (bullet-heaven conventions)
- **Top centre.** A wide **District Infection bar** (about 560 px, the XP-bar slot).
  - Red fill, an ink frame, and the label "The Slums · 34%".
  - A tick at 50% (the Exterminator threshold) with a small skull and the Warden's name. The tick fades once the Exterminator has come.
- **Under it.** The **timer** (large), and a **Vigilance strip** in Risk of Rain style.
  - Four named segments: Calm | Wary | Alarmed | Hunting, using the existing tier bounds.
  - A marker slides across it, and the current segment is inked solid.
  - When the tier changes, the strip punches and a toast appears.
  - **The last 10 s:** the timer punches every second.
- **Boss bar.** While an Exterminator is alive, a big bar sits below the strip (about 480 px wide).
  - Its name is in the display font, with a red fill and the existing self-Cleanse band.
  - Its arrival banner stays, restyled with the kit.
- **Top left: the wallet.**
  - `IconRect` pestilence and bones with the numbers at `SIZE_LARGE`.
  - The shown value only rises when a flying icon lands (see below), and then punches.
  - Under it: a rat icon with the Adult count and a "+2" Pup note; the Lead Rat's 3 pips; and the Year, small.
- **Bottom centre: the ability bar.** One slot per *unlocked* ability: Raid and Hide.
  - Each slot is a 56 px parchment square with its icon ("raid" / "door").
  - A radial ink sweep shows the cooldown, with a countdown number.
  - A `PromptHint` sits under it. Hide's hint is the verb "door", since you walk in.
  - When a slot becomes ready it gets a one-time amber ring pulse.
  - While Hidden, Hide's slot shows the time left.
  - Replaces the old bottom-left text.
- **Toasts** sit on the right edge, under the top bar.
  - At most 3 at a time, each sliding in over 200 ms, showing 3 s and fading over 300 ms.
  - Repeats of the same kind merge ("3 houses have fallen").
  - **Events:** a Vigilance tier change, a house falling, a Pup maturing (merged, low priority), the Exterminator arriving (the banner covers this; no toast), and Raid ready.
- **The door hint** stays, using `PromptHint` / kit styling.

### World feedback (`world_overlay.gd`, a full-screen Control under the HUD panels)
- **Infection bars over heads.**
  - Each living, infected, outdoor, on-screen townsperson gets a 30×4 px red bar with an ink frame, positioned by `camera.unproject_position` above the head.
  - The bar fades in on infection. Above 80% it gets a thin pulse.
  - Exterminators are excluded (they have the boss bar).
  - All bars are drawn in one `_draw`.
- **Bite numbers** (when `Settings.damage_numbers` is on).
  - `InfectionComponent` gets `signal bitten(chunk: float)`, emitted in `bite()`.
  - Per target, Bites are summed over 0.35 s windows, then shown as "+7" in sepia with an outline: rising 20 px and fading over 0.7 s.
  - At most 24 alive, pooled.
- **Flying payouts (Nodebuster).**
  - The RoundDirector emits `payout(kind: String, amount: int, world_pos: Vector3)`: "pestilence" on a first infection and "bones" on a death.
  - The Exterminator bounty is one big "bones" payout at the boss.
  - An icon pops at the person and flies on a curve to its wallet counter in about 0.6 s.
  - Cap 12 in flight; beyond that, add to the newest in-flight icon of that kind.
  - With `reduce_motion` the counter just ticks up.
- **Off-screen arrow.** When the Exterminator is off-screen, an ink arrow sits at the screen edge (inside the safe margin) pointing at it, with a small skull.
- **Lead Rat hit.**
  - An ink vignette flashes at the screen edges (0.35 s).
  - Camera shake: `follow_camera.shake(strength)`, multiplied by `UiKit.shake_scale()`.
  - Hit-stop: `Engine.time_scale` 0.05 for 60 ms of real time.
  - The pips punch.
- **Lead Rat marker** (`lead_rat.gd`).
  - A thin near-black ground ring around the Lead Rat, which the shader draws as an ink circle.
  - It's always on, so you can find yourself in the swarm, and it flashes when hit.
- **Round title card (Risk of Rain).**
  - At Round start, centred: the District title (display font, `SIZE_HUGE`) and "Year of Our Lord 1349".
  - For the first 3 Rounds of a Run only (`Run.rounds_played < 3`), an objective line: "Spread the plague. Reach 50% to draw out the Rat-catcher."
  - Timing: 0.4 s in, 1.8 s hold, 0.6 s out. It never blocks input.

### Pause menu (`pause` action; not after the Round has ended)
- Pauses the tree, with an ink-dimmed backdrop.
- **Left column buttons:**
  - Resume (initial focus).
  - Settings: instances `res://scenes/ui/settings_panel.tscn` if it exists and waits for its `closed` signal.
  - End the Round: asks to confirm, then ends with reason `"timer"`; earnings are kept and the Year doesn't change.
  - Quit to Title: asks to confirm, then `Transition.go("res://scenes/ui/title.tscn")` (or `change_scene_to_file`). This Round's earnings are lost; say so in the confirm.
- **Right column: a Vampire Survivors-style stat sheet.**
  - Run stats from `Run.stat()`: Lead Rat speed, Bite range / cooldown / strength, Lethality, Carry-over, plus the unlocked abilities.
  - "This Round": time, infected, dead, houses fallen.
- `pause` or B/Esc on the top level resumes.

### Results screen (`results_panel.gd`, replaces the end panel)
- **Title by reason:**
  - timer: "The bells toll"
  - lead_rat_died: "The Lead Rat is dead"
  - exterminator_beaten: "\<Warden> has fallen"
- **Stat rows count up one at a time** (0.25 s each; accept skips to the end):
  - time survived, townsfolk infected, townsfolk dead, houses fallen, peak Colony, Bites, Pups born.
- **Earnings:**
  - Pestilence +N and Bones +N (bounty on its own line).
  - Then the wallet before → after.
- **Best Round:** a small "Best Round" seal when houses fallen beats the District's previous best. `Run.best_stats[district]` is saved; add it, plus `peak_colony` and `infection`.
- **The Year block** (Risk of Rain made visible), built from the YearTable.
  - If the Lead Rat died: "The Year turns: 1349 → 1350". Then up to 4 lines of what changes, from `Run.year_preview(from, to, district) -> Array[String]`, which diffs the `YearEntry` rows:
    - new townsfolk types ("Townsfolk now carry brooms");
    - Hygiene up ("Wells are cleaner: Infection gains −10%");
    - start Vigilance up;
    - visual stage up ("Cobbles are being laid").
  - Otherwise: "The Year holds at 1349".
- **The next-District note** is kept, as today.
- **Continue:** a `PromptHint` for `ui_accept` → `Run.finish_round()` then `Run.open_tree()`. R restart stays dev-only.
- **RoundDirector** tracks `bites`, `peak_colony`, `pups_born`, `houses_fallen` and `elapsed`, and puts them under `result["stats"]`.

### Run changes (A)
- `open_tree()`, `open_map()` and `start_round()` go through `/root/Transition.go(path)` when that autoload exists, and `change_scene_to_file` otherwise.
- Add `best_stats` (saved) and `year_preview()`.
- Add `has_save() -> bool` (B's title screen uses it).

### A's debug flags
- `--results-test=<reason>` ends the Round after 6 s with that reason.
- `--pause-test` opens the pause menu after 2 s.
- `--toast-test` fires one of each toast.

## Implementer B: the meta screens (Upgrade Tree, Scroll Map, title, settings, transitions)
**Owns:**
- `scripts/ui/upgrade_tree.gd`, `scenes/ui/upgrade_tree.tscn`
- `scripts/ui/scroll_map.gd`, `scenes/ui/scroll_map.tscn`
- new `scripts/ui/title.gd` + `scenes/ui/title.tscn`
- new `scripts/ui/settings_panel.gd` + `scenes/ui/settings_panel.tscn`
- new `scripts/ui/transition.gd` (autoload `Transition`)
- `project.godot`: only the `[application] run/main_scene` line and adding `Transition` to `[autoload]`

**Does not touch:** anything listed under A.

### Upgrade Tree (Nodebuster)
- **Zoom.**
  - Mouse wheel zooms around the cursor; gamepad LT/RT (joy axes 4/5) zoom around the centre.
  - Range 0.55–1.6.
  - Zoom and pan persist across visits in a static var, so returning to the tree doesn't reset them (a common Nodebuster complaint).
  - **Recenter:** Home / Y, onto the focused node.
- **Node states must be unmistakable at a glance:**
  - **Teaser:** not yet visible, but it `requires` a visible node. A dashed ink circle with "?" and no name or cost. The tree visibly has more to give.
  - **Can't afford:** normal ink. The cost line shows the lacking currency faded, with a short underline.
  - **Affordable:** a soft AMBER halo that breathes slowly, and a one-time bounce when it *becomes* affordable.
  - **Requirement unmet:** faded, with a tiny lock icon.
  - **Maxed:** filled with ink, parchment text, "MAX" instead of the cost, and no halo.
- **Header:** the wallet with `IconRect` icons, plus "N upgrades within reach" (the affordable count).
  - When N is 0, the "To the Map" button breathes amber, to nudge you on.
- **Buying.**
  - Click / A buys.
  - **Hold to keep buying:** after 0.35 s, one level every 0.2 s while it stays affordable.
  - **Juice:**
    - the node punches;
    - an ink ring splashes outward;
    - "−4" floats up beside the wallet;
    - the wallet rolls down.
  - **Newly revealed children** ink in along their line over 0.4 s, then fade in.
  - **A failed buy:** the node shakes and the lacking wallet counter flashes.
- **Tooltip** (replaces the fixed top-right panel).
  - Anchored beside the hovered or focused node and kept on screen.
  - Hover delay 0.12 s; instant for focus.
  - **Contents:**
    - the name (display font) and level n / max;
    - the description;
    - current → next value;
    - the cost with icons, plus "(need 3 more Bones)" when short;
    - a `PromptHint` for "Buy", and "hold to buy more" when there's more than one level left.
  - Teasers show "Buy *Gnaw* to reveal".
- **Bottom hint bar** of `PromptHint`s: Buy, Pan (drag / right stick), Zoom, Recenter, To the Map.

### Scroll Map
- **Hover / focus:** a thicker ink outline and a slight lift (shadow) on the District region; the selected one gets a wax-seal-style ink marker.
- **District card:**
  - Its Warden, and status: "Still holding out" / "Taken".
  - The best Round from `Run.best_stats` if present: houses fallen, infection %, peak Colony.
  - What this Year looks like there.
  - A "Newly opened" seal the first time a District is open and unvisited.
- **Hints:** a `PromptHint` row replaces the static help text.
- **Opening:** the scroll unrolls (0.5 s); with reduced motion it's a fade instead.

### Title screen (`scenes/ui/title.tscn`, the new main scene)
- **Backdrop.** The demo town in the parchment look, behind a slowly drifting camera.
  - Instancing `res://scenes/main.tscn` is fine. First check its script's command-line handling, so that `--screenshot` etc. on the title don't trigger the demo's own screenshot / quit; otherwise build a small backdrop.
  - Don't edit the style files.
- **Title.** "Plaag" in the display font at about 96 px, with a subtitle line.
- **Menu buttons:**
  - **Continue,** with the details "Year 1349 · 54 P · 24 B"; only when `Run.has_save()`. It opens the Upgrade Tree.
  - **New Plague.** If a save exists, confirm first ("Burn the old Run? This cannot be undone."), then `Run.reset()` and straight into a Round in the slums, as Vampire Survivors does.
  - **Settings.**
  - **Quit.**
  - Initial focus is on the first button.
- **Debug flags must keep working.** If the title is the main scene and `OS.get_cmdline_user_args()` holds any argument except the title's own (`--screenshot=`, `--screenshot-delay=`, `--title`), it goes straight to the District. That keeps every documented debug flag (`--bot`, `--dev`, `--year=` …) working. Launching it explicitly as `res://scenes/ui/title.tscn` (that path is in `OS.get_cmdline_args()`), or passing `--title`, always shows the title.

### Settings panel (`scenes/ui/settings_panel.tscn`, used by the title and A's pause menu)
- **Rows:**
  - Screen shake: slider 0–100%.
  - Damage numbers: toggle.
  - Reduce motion: toggle.
  - HUD size: slider 80–140%.
  - Fullscreen: toggle.
  - Back.
- Every change goes through `Settings.set_value`, and the panel emits `closed`.
- It works while paused (`process_mode` always) and is fully controller-navigable. B/Esc means Back.

### Transition (autoload `Transition`)
- `go(path: String)`:
  1. An ink blot grows from the centre to cover the screen (0.3 s).
  2. `change_scene_to_file`.
  3. The blot shrinks or fades back to the new scene (0.3 s).
- With reduced motion it's a 0.2 s parchment fade.
- Unpauses the tree, ignores input while running, and is safe to call twice: the second call is ignored while one is running.

### B's debug flags
- Title: `--screenshot=`.
- `--settings-test` opens the settings panel on the title.
- `--dev-hover=<id>` shows the tooltip for that node.
- `--dev-zoom=<z>`.

## Done means (both)
- `--headless --editor --quit` and headless runs print no errors.
- Screenshots of every screen you own at 1280x720 and 1920x1080, checked by eye.
- Your report lists:
  - files changed;
  - new flags;
  - anything that deviates from this contract;
  - for A, the `--perf` FPS with `--start-colony=40 --fill`.
