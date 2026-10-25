---
type: howto
title: Godot tooling guidance
description: Engine version and executable, Godot MCP restrictions, asset import and isolated launches for every Godot run.
---

# Godot tooling guidance

Read this before launching Godot through the executable, the test runner or the Godot MCP server. The testing guide supplies the runner's commands.

## Engine

- Godot **4.6.3 stable**, Windows. The console build lives at `C:/Users/Home/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe`. Set `GODOT_EXE` to it, or pass `-Godot <path>`; the runner falls back to that path when neither is given.
- The `_console.exe` stub spawns the real engine as a child. The runner swaps it for the sibling `Godot_v4.6.3-stable_win64.exe` so its job object owns the engine. Direct launches may use the console build for readable output.
- `project.godot` declares the 4.6 feature set and the Compatibility renderer. Do not open the project with an older editor: it rewrites the `.godot` cache and can downgrade resource formats.

## Godot MCP

The `godot-mcp` server runs its own Godot **4.6.1**, not the project's 4.6.3.

- Never use godot-mcp `run_project`, `launch_editor` or any import against this checkout or a worktree. It would re-import the `.godot` cache with the wrong engine version.
- Use it only for read-only inspection, such as project information or reading scenes. Run the game, checks and imports through the 4.6.3 executable and the test runner.

## Import

- Import once after cloning, after creating a worktree and after adding assets, with no other engine jobs running: `& $env:GODOT_EXE --headless --path . --editor --import`.
- The runner never imports, so it cannot race another import. A worktree may copy `.godot` from an imported checkout of the same commit instead of importing again.
- Folders Godot must not scan carry a `.gdignore`: `docs/`, `builds/` and the test-run output root. Keep one in any new folder of non-game files.

## Launch isolation

- Every launch passes `--audio-driver Dummy` (unless the check is about audio) and an isolated `APPDATA`, so no run touches the player's real settings or saves. The runner sets both, plus `LOCALAPPDATA` and the XDG folders, below a unique `builds/test-runs/` directory.
- At most two headless engine jobs run at once. Rendered, import and performance runs take the machine alone. The runner coordinates this with lock files in `%TEMP%/plaag-godot-test-slots`; a direct launch or open editor does not take a slot, so coordinate it by hand with other sessions on the machine.
- Agents in separate worktrees use the runner rather than opening their own game windows.
