# Plaag knowledge index

Choose the subject relevant to the task, then search document titles or headings in that area. Read deeper only when a decision or dependency needs it. This index describes locations and responsibilities; it does not track completion status.

## Decisions and implementation

- The planning area holds requirements, contracts, architecture and later owner decisions, numbered in the order they were made. Consult the relevant plan before changing a gameplay rule, and check explicit supersession statements before treating an older plan as current.
- The gameplay source has local guidance describing where behavior lives. Scene composition and authored data complement that source; inspect the production component relevant to the task.

## Tooling and validation

- Godot tooling guidance lives in the documentation's guidance area. Read it before any engine launch: it names the engine version and executable, the Godot MCP restrictions, asset import and launch isolation.
- Gameplay verification policy lives in the same guidance area. Read it when planning implementation, changing gameplay or running checks.
- The testing guide describes quick feedback, affected checks, isolated execution and final game acceptance, with the runner's exact commands.

## Evidence

- Handoffs record setup, actions, observations and unresolved acceptance for individual changes; consult the one matching the affected feature.
