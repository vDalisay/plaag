# Plaag working guidance

Plaag is a game built with Godot 4 and GDScript. Its design is not yet written down; the planning area will hold it once it exists.

Load guidance progressively. Start with the task's subject, read the local AGENTS.md guidance in the directories you will work in, and open only the relevant supporting sections. The project documentation contains a Plaag knowledge index describing where to find decisions, implementation context and evidence. Discover files by subject and confirm their current contents; navigation guidance uses descriptions rather than direct links or fixed paths.

Before launching Godot in any way, through the engine executable, the test runner or the Godot MCP server, read the Godot tooling guidance in the documentation's guidance area. It names the engine version and executable, which godot-mcp tools are off limits, and how launches stay isolated and serialized.

For implementation planning, gameplay changes or any validation run, first read the Gameplay verification policy in the documentation's guidance area. It preserves the minimal-test, real-game acceptance and isolated-execution requirements. The nearby testing guide supplies runnable commands.
