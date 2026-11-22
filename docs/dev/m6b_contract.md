# M6b contract (boss balance pass: danger zones + swarming)

The problem from the M6 review: in bot runs, neither boss can be beaten.
- **Rat-catcher:** one sweep kills most of the Colony, because followers trail the Lead Rat and never get out of telegraphs.
- **Plague Doctor:** only 1–5 rats ever reach him, because followers keep their flocking slots instead of swarming.

## Danger zones (implementer B: every telegraph you own)
Every telegraphed attack area joins group `"danger_zones"` while it's active, i.e. from the start of the wind-up until impact or expiry, and leaves the group afterwards. This covers:
- stomp, broom arc, club ring, the torch landing circle and the burning fire patch;
- the Rat-catcher sweep and spring traps (armed traps count the whole time);
- the Plague Doctor's incense cloud;
- the terrier lunge ring.

Each danger zone has:
```gdscript
var danger_center: Vector3        # world, on the ground
var danger_radius: float          # bounding radius (for cheap culling)
var danger_time_left: float       # seconds until impact; -1 = persistent (fire patch, trap)
func danger_contains(p: Vector3) -> bool   # exact test (arc for broom/sweep)
```

## Rats avoid danger (implementer A)
- **Followers.** If a follower is inside a zone's bounding radius and `danger_contains()` is true, it steers out by the shortest way and ignores its flock slot until it's clear.
  - This overrides Feeding detours.
  - Pups do the same, but slower.
  - Scan the zones at about 10 Hz; there are rarely more than ~10.
- **`--bot` Lead Rat.** It sidesteps out of any zone whose `danger_time_left` is below 0.5 s, then resumes. That lets the bot stand in for a human who dodges.

## Swarm the target (implementer A)
- When the Lead Rat is within 7 u of a node in `"exterminator"` (or of any townsperson it's currently Biting, if that's cheap), followers drop their wake slots. They surround that target in a ring at Bite range, spread around it.
- When the Lead Rat moves more than 9 u away, they go back to normal flocking.
- Danger avoidance still wins over swarming.

## Spawner fix (implementer A)
`alive_outdoors()` excludes the `"exterminator"` group and the terrier. The terrier joins the `"exterminator_pets"` group (B adds it).

## Tuning target (B second pass, integrated after A lands)
Bot runs with `--god --force-exterminator`:
| District | Colony size | Goal |
| --- | --- | --- |
| slums | 25 | beats the Rat-catcher in 30–60 s, keeping at least 30% of the Colony |
| merchant | 35 | beats the Plague Doctor in 40–75 s |
| merchant | 12 | should *not* beat the Plague Doctor |
