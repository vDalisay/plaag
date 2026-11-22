# Plaag: game concept

**Working pitch:** a Black Plague incremental. You start as a single rat in a
medieval town and spread the plague until the whole city is crossed off the map.

Transcribed and organized from handwritten notes. Open questions are kept as
questions, not decisions.

## Inspiration

- **Unharvest**
- **Plague Inc.**: spread and upgrade a disease until everything is infected
- **Vampire Survivors / bullet heaven**: short rounds, automatic attacks, an ever-growing swarm
- **Nodebuster**: incremental upgrade loop between rounds
- **Wanderburg**: worth trying for reference
- **Attack on Titan**: the city layout, with poor districts on the outside and richer ones further in

## Core idea

- You walk around a medieval city as a single rat and spread the black plague.
- You start as one rat and grow into a bigger colony.
- Open question: what is the movement, and is the plague itself part of how you move?

## Game direction (chosen)

A blend of **bullet heaven (Vampire Survivors), Nodebuster and Wanderburg**:
rounds where you infect the people around you, with an incremental upgrade
loop between them.

- Each round, you move through part of the city and infect whoever comes near.
- Between rounds, you spend what you earned on upgrades (incremental layer).
- **Theme first, like Unharvest:** you start out genuinely weak in a harsh
  medieval world, and the power fantasy is the plague slowly taking hold as
  you grow stronger.
- **The world reacts:** ordinary NPCs respond to the spreading plague
  (e.g. hunting you early, fleeing later).
- **Exterminators:** specific NPCs fight back and try to wipe out the plague,
  filling the role of bosses in Vampire Survivors / Nodebuster.

## Prototype decisions (grilling session, 2026-11-22)

Terms are defined in [GLOSSARY.md](../GLOSSARY.md).

**Round loop**
- Rounds last 60–120 s. A Round ends when the timer runs out or the Lead Rat dies.
- The player steers the Lead Rat; the rest of the Colony follows.
- Bites are automatic: the nearest person in range, on a cooldown.
- Districts reset every Round.

**Plague**
- No damage, no HP. Every person, Exterminators included, has an Infection meter from 0 to 100%.
- Once above 0%, the meter rises on its own over time, like a damage-over-time effect. At 100% the person dies.
- Bites don't deal damage: each one adds a small chunk of Infection and raises the rate the meter climbs.
- Ordinary townsfolk never recover. Only Exterminators (and plague doctors, in later Districts) can Cleanse, which lowers Infection.
- Baseline: an infected person dies in about 20 s. A lethality upgrade speeds this up.
- Contagion (infected people infecting others) is unlocked by an upgrade, not available at the start.

**Colony**
- When an Adult Feeds on a corpse, it produces a Pup. Pups travel with the Colony but don't fight. A Pup that Feeds Matures sooner.
- Pups count toward Fear.
- Carry-over is 0% at the start. Upgrades raise it in steps: 20 → 50 → 70 → 100% of the previous Round's Colony size.
- Starting Colony size comes from the Upgrade Tree.
- Succession (another rat taking over when the Lead Rat dies) is a later upgrade.

**Townsfolk**
- Fear rises with the number of rats nearby. At low Fear townsfolk fight back; at high Fear they flee.
- So there are two strategies: a small Colony that doesn't scare people, or a large, weaker Colony that does.
- Guards (richer Districts) attack rats at any Fear level.
- Fear has three bands. Few rats nearby: they Fight. Middling: they're Uneasy and keep their distance. Many: they Flee, which makes them harder to Bite but spreads Contagion further.
- How townsfolk fight back:
  - Everyone: a telegraphed stomp.
  - Broom (slums): a sweep that knocks rats back and kills Pups.
  - Cat (slums): chases single rats, but is scared off by a big Colony.
  - Torch (merchant Guards): leaves a short-lived fire patch.
  - Club (merchant Guards): a slow, heavy stomp over a large radius.
- Ordinary rats die in one hit. The Lead Rat survives 3 hits per Round.

**Houses**
- Hide: the whole Colony enters a house, pursuers lose track, and the rats Bite the people inside. You're forced back out after a few seconds or once everyone inside is infected.
- Raid: on a cooldown, send a few Adults into a nearby house. They infect the people inside and then return.

**Exterminator**
- Appears once 50% of the District is infected. The timer keeps running.
- You beat it the same way as anyone else: its Infection must reach 100%.
- What makes it tough: Bites raise its rate far less, and it keeps Cleansing itself. You need many rats biting it at once.
- Beating it is required to unlock the next District.
- Slums: the **Rat-catcher**. A terrier hunts the Lead Rat while the Rat-catcher lays traps.
- Merchant quarter: the **Plague Doctor**. Cleanses everyone around them, so you have to infect them fast.

**Economy**
- Pestilence is paid once, when a person first becomes infected. Bones are paid on each death.
- Upgrade Tree nodes (Nodebuster-style, drawn on parchment) cost Pestilence, Bones or both, like Unharvest.

**Scroll Map**
- Shown between Rounds. You pick the District here. Beaten Districts are inked over, and the houses killed in your best Round are crossed out.

**Escalation (Risk of Rain style)**
- **Year:** one Year for the whole city, starting in 1347. It advances by 1 each time the Lead Rat dies. A Round that ends on the timer doesn't advance it, so surviving matters.
  - Each Year, townsfolk get better equipment and are cleaner (more Hygiene).
  - The Year unlocks new townsfolk types. For example: stompers first, then brooms, then cats, and eventually Guards patrolling even the slums.
  - The map shows the Year in 3 visual stages: puddles and wells cleaned up, cobbles replacing mud, houses with shutters and lime-wash.
- **Vigilance:** the in-Round difficulty. It rises with time in the Round and starts higher in later Years. The higher it is, the more often the strongest unlocked types spawn.
- **Spawning:** each District starts with a population. More townsfolk walk in through District gates and step out of houses during the Round.
- **No deadline:** the Years only make things harder. The cure is the story ending after the last District, not a way to lose. Upgrade Tree nodes could slow progress down (e.g. "Superstition").
- The result is an arms race: your Upgrade Tree against human progress.

**Controls**
- Keyboard + mouse: WASD to move; click a house to Raid it.
- Gamepad: left stick to move; A to Raid the nearest house.
- On both: walk into a house door to Hide.

**Starter Upgrade Tree** (~13 nodes)
- Stats: rat speed, Bite range, Bite cooldown, Bite chunk, starting Colony +1, Feeding speed, Pup maturity time, lethality, Carry-over 20%.
- Unlocks: Hide and Raid (cheap, early), Fleas (passive aura) and Contagion (big, Bones-gated).

**First prototype scope**
- Built in 3D, top-down, with the existing parchment shader and primitive meshes.
- Two Districts:
  - Slums.
  - Merchant quarter: Hygiene, Guards, and fewer but sturdier townsfolk.
- Full loop: Round → Scroll Map → Upgrade Tree → Round.

## Camera

- Options considered: third person, or switch to an RTS view once the colony grows.
- **Chosen: top-down**, for the "wow" effect of a large swarm.

## Spreading the plague

Infection methods unlock in order:

1. **Biting** people directly.
2. **Flea transfer**: a chance to infect people who walk nearby.
3. **Flea upgrades**: improve how well the plague spreads.

## Threat and growth

- **Small colony:** people try to kill you. You hide in houses.
- **Large colony:** people flee from you instead.
- **Skill:** send rats into houses.

## World and progression

- **Start in the poor slums** (Attack on Titan style: the outer ring).
- **Richer districts are "harder"**, with more:
  - deterrents
  - hygiene
  - guards

## Presentation

- **Scroll map:** a scroll shows the map of the area you're working on.
  Dead houses are crossed out on it.
- **End cinematic:** hands roll up the scroll, while the bourgeoisie work on a cure.
- This fits the parchment-and-ink rendering this project already has
  (see the [README](../README.md)).

## Demo scope

- A **small town**.
- Ends with a dramatic move out of the town to a **bigger city**.

## Open questions

- Is movement tied to the plague mechanic?
- Do the rounds take place in the same top-down view as the scroll map, or does the scroll act as the meta/upgrade screen between rounds?
- How does the round-based direction fit with the open "walk around the city" idea?
