---
type: howto
title: Gameplay verification policy
description: Required evidence, minimal written checks and isolated execution for implementation planning and gameplay validation.
---

# Gameplay verification policy

Read this policy when planning implementation, changing gameplay or running validation. The testing guide in the project documentation supplies current commands and route selection.

Keep written tests to a minimum. The primary evidence of correctness is a working system exercised in playable scenes with real game state and the actual gameplay components.

Use quick headless checks for the development feedback loop, then the affected headless component checks. Headless means native Godot running real GDScript/state/services without a window; do not duplicate gameplay rules in another language or replace them with mocks. Quick checks should avoid constructing the whole game world and aim for about 30 seconds after import. A broader headless suite should aim for five minutes. These are measured runtime budgets, not reasons to skip integrity failures.

Before handing off a completed gameplay change, run the affected flow in the actual game or an existing development scene. Headless success cannot establish rendering, physical input feel, audio quality or final visual acceptance. Reuse one final integration run across related changes instead of launching the game for every small assertion.

- Validate the affected flow in the game or an existing development scene; record the setup, actions and observed result in the handoff. Reuse scenes rather than creating a separate test scene for every feature.
- Add only the smallest useful written check for an important invariant, a regression, or an edge case that is difficult to verify through play. There is no test-count or coverage target and no requirement to add a test for every change.
- Do not build test frameworks, mock systems, fixture factories, test-discovery infrastructure or extensive suites. Reuse native Godot checks and the small validation script when needed.
- Preserve validation of ownership, payments, progression and save integrity once those systems exist. Passing written checks does not replace demonstrating that the system works in the game.
- Prefer a thin real transaction through production interfaces over many checks of implementation details. Make setup explicit: granting an item is setup, not proof that acquiring it works; accelerated completion is not a human-paced playthrough.
- Default to concise textual results, durations and useful failure context. Capture screenshots only on demand or when a visual/UI failure needs them.
- Keep each test invocation's saves, settings, logs and exchange files isolated from both real player data and other invocations. Run at most two headless jobs; serialize rendered/game/performance checks and asset imports.
- Remove superseded checks after preserving their unique useful behavior or recording the specific manual acceptance that replaces them. Git retains retired scripts.

Apply this policy throughout implementation plans. Named acceptance cases describe behavior to verify, not a requirement for a separate automated test.
