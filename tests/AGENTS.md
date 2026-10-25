# Validation guidance

Read the Gameplay verification policy and the Godot tooling guidance in the documentation's guidance area before changing or running checks. The testing guide contains the current runner commands, isolation setup and route selection.

Use the existing PowerShell runner and native Godot components. Register a new check explicitly in the runner; there is deliberately no filesystem discovery. Choose checks by affected behavior, not by the number of scripts.
