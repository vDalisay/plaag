# Testing the game with a small feedback loop

Use native Godot checks while editing, then exercise the affected flow in the game before handing off a completed gameplay change. A headless engine runs actual GDScript, state and physics without a game window. It cannot establish appearance, input feel, audio quality or controller usability. Read the Godot tooling guidance first; it owns the engine path, Godot MCP restrictions and isolation rules.

## Local commands

Requires Windows, PowerShell 7.2+ and an imported Godot 4.6.3 checkout. Import once with other engine jobs stopped; the runner deliberately does not import.

```powershell
$env:GODOT_EXE = 'C:/Users/Home/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $env:GODOT_EXE --headless --path . --editor --import
./tests/run_tests.ps1                    # quick suite
./tests/run_tests.ps1 -Check run_checks  # one named check
./tests/run_tests.ps1 -Check run_checks -Rendered  # same check with a window
./tests/run_tests.ps1 -List
```

| Route | Purpose | When to use it |
|---|---|---|
| `quick` (default) | Small real-state contracts and a boot of the main scene | Normal edit feedback |
| A named `-Check` | One affected component or diagnostic route | Changes with a specific risk; use `-List` for names |
| `-Rendered` | The same check in a window at `-Resolution` (default 1920x1080) | Presentation checks; takes the machine alone |

Each invocation writes logs and private user data beneath a unique `builds/test-runs/` directory (`-OutputRoot` changes it). The runner keeps a `.gdignore` in `builds/` and the output root so the editor never imports run output. It sets `APPDATA`, `LOCALAPPDATA` and the XDG folders before Godot starts, so a check cannot overwrite the player's settings or saves, and passes `--audio-driver Dummy` unless `-Audible` is given.

At most two headless engine processes run concurrently through the runner; rendered runs are exclusive. The runner bounds lock waits and execution, returns nonzero on failure, and kills its child engines on timeout or exit. A script printing PASS before crashing is still a failed run: the runner scans the engine log and both output streams, and any `ERROR:`, `SCRIPT ERROR:` or parse error fails the check. Warnings are counted and shown.

## Adding or changing a check

A check is a `tests/<name>.gd` script that `extends SceneTree`, prints one summary line and calls `quit(failures)`. Register its name in the runner's `$suites` or `$extra` list; there is no discovery. Keep one small check only when it protects an important invariant, concrete regression or difficult edge case, and use real production scenes and components rather than mocks.

For the handoff, record starting state, command or actions, observed result, process exit, duration, log location and remaining limitations. Run the affected flow in the actual game at the end.
