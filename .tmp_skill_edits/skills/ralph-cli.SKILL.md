---
name: ralph
description: "Run ralph-orchestrator to execute multi-hat agentic loops. Use /ralph to start a run, check status, manage hats, or view events. Ralph drives claude (or other backends) through a hat-based event loop with planner/builder/reviewer/tester roles."
argument-hint: <run|preflight|status|hats|events|plan|clean|init> [args]
---

# Ralph Orchestrator Skill

Drive ralph-orchestrator from within Claude Code. Ralph runs an event-driven loop where specialized "hats" (planner, builder, reviewer, tester) take turns processing work. Each hat is a Claude Code session with focused instructions.

Binary: `/opt/homebrew/bin/ralph`
Config: `ralph.yml` in the project root (or `$RALPH_CONFIG`)

## Subcommands

### `ralph run [prompt-file]` (aliases: `r`, bare invocation)

Start a ralph orchestration loop.

```bash
ralph run
```

- Reads `ralph.yml` from the project root for hat definitions and event loop config
- Default prompt file: `PROMPT.md` (configurable in ralph.yml `event_loop.prompt_file`)
- Runs in foreground by default — this is a long-running orchestration loop
- Use `run_in_background: true` if the user wants to continue working while ralph runs

**Flags:**
- `-c ralph.yml` — explicit config path
- `-H hats.yml` — override hat collection
- `--max-iterations N` — cap iterations (overrides config)

**Examples:**
- `/ralph` — start the default loop
- `/ralph run` — same as above
- `/ralph run -c custom-ralph.yml` — use alternate config

### `ralph preflight` (aliases: `pf`, `check`)

Validate configuration and environment before starting a run.

```bash
ralph preflight
```

- Checks: config syntax, hat definitions, prompt file exists, backend available, git state
- Run this before `/ralph run` to catch issues early
- Shows warnings and errors with actionable fixes

### `ralph hats` (aliases: `h`)

List and inspect configured hats.

```bash
ralph hats
```

- Shows all hats from ralph.yml: name, triggers, publishes, description
- Useful for understanding the current orchestration topology

### `ralph events` (aliases: `ev`, `log`)

View the event history for the current or most recent run.

```bash
ralph events
```

- Shows the event log: timestamps, event names, hat activations, payloads
- Useful for debugging why a hat didn't fire or understanding the run flow

### `ralph plan` (aliases: `p`)

Start a Prompt-Driven Development planning session.

```bash
ralph plan
```

- Interactive planning mode — generates a PROMPT.md from conversation
- Useful for bootstrapping a new ralph run from scratch

### `ralph init`

Initialize a new ralph.yml in the current directory.

```bash
ralph init
```

- Interactive config generator
- Creates a starter ralph.yml with common hat patterns
- Good for new projects that don't have ralph configured yet

### `ralph clean`

Clean up ralph artifacts from `.ralph/agent/`.

```bash
ralph clean
```

- Removes worktrees, event logs, and temporary files from previous runs
- Safe to run — does not touch source code or git history

### `ralph loops` (aliases: `l`)

Manage parallel loops.

```bash
ralph loops
```

- List active parallel loops
- Useful when ralph is running multiple concurrent hat sessions

### `ralph web`

Launch the ralph web dashboard.

```bash
ralph web
```

- Opens a local web UI showing run status, events, hat activations
- Foreground operation — use `run_in_background: true` if desired

## Integration with /mc

Ralph and MultiClaude serve different purposes:

| Aspect | /mc | /ralph |
|--------|-----|--------|
| Model | Fan-out: N independent workers | Event loop: hats take turns |
| Coordination | Coordinator dispatches, workers are independent | Event-driven: hat output triggers next hat |
| Best for | Parallel independent tasks (tests, migrations, refactors) | Sequential pipelines (plan -> build -> review -> test) |
| Output | N separate PRs | Single cohesive result |

**Combining them:** Use `/ralph` for the orchestration loop (plan/build/review/test cycle) and `/mc swarm` for parallelizing work within a single builder hat phase.

## Behavior Notes

- **Bare invocation = run.** `/ralph` without a subcommand starts `ralph run`.
- **Config awareness.** Always check for `ralph.yml` in the project root before running. If missing, suggest `/ralph init`.
- **Background runs.** Ralph loops can run for many iterations. Default to `run_in_background: true` for `/ralph run` unless the user wants to watch it.
- **Event-driven.** Ralph's power is the hat handoff pattern. Don't try to replicate this with raw `/mc` — use ralph when you need sequential quality gates (review after build, test after review).
- **PROMPT.md is the contract.** Ralph's prompt file defines what the loop works on. If speckit artifacts exist, use `/ralph` (the project-level speckit skill) to generate PROMPT.md from tasks.md.
- **Keep it terse.** Report what you launched, show status when asked. Don't narrate the orchestration — ralph handles that.
