---
name: codex
description: "Dispatch work to OpenAI Codex CLI as a parallel agent. Use /codex to run a task non-interactively, review code, or manage Codex sessions. Codex runs in its own sandbox with its own model — useful for second opinions, parallel execution, or tasks that benefit from a different model."
argument-hint: <exec|review|interactive|apply|resume> [args]
---

# Codex CLI Skill

Dispatch tasks to OpenAI's Codex CLI from within Claude Code. Codex runs as an independent agent with its own sandbox — useful for parallel work, second opinions, or leveraging different models.

Binary: `/opt/homebrew/bin/codex`

## Subcommands

### `codex exec "<prompt>"` (aliases: `e`, `run`, bare string)

Run Codex non-interactively on a task. This is the primary dispatch mode.

```bash
codex exec --full-auto "<prompt>"
```

- Default: `--full-auto` (workspace-write sandbox, on-request approval)
- Use `run_in_background: true` for long tasks so Claude Code isn't blocked
- If the user specifies a model: `codex exec -m o3 "<prompt>"`
- If working in a different directory: `codex exec -C /path/to/repo "<prompt>"`
- Report what was launched and how to check on it

**Examples:**
- `/codex "add tests for the auth module"`
- `/codex exec -m o3 "refactor the database layer"`
- `/codex run "find and fix all TODO comments"`

### `codex review` (aliases: `rev`, `cr`)

Run a code review via Codex against the current repo.

```bash
codex exec review
```

- Reviews the current working tree diff or staged changes
- Output the review findings to the user
- Can target a specific model: `/codex review -m o3`

### `codex interactive "<prompt>"` (aliases: `i`, `chat`)

Launch Codex in interactive mode (takes over the terminal).

```bash
codex "<prompt>"
```

- This is a foreground operation — warn the user it will take over their terminal
- Useful when the user wants to have a back-and-forth with Codex directly
- Do NOT use `run_in_background` for this

### `codex apply` (aliases: `a`)

Apply the latest diff produced by a Codex session.

```bash
codex apply
```

- Applies changes from the most recent Codex run as a `git apply`
- Show the user what was applied

### `codex resume` (aliases: `r`)

Resume a previous Codex session.

```bash
codex resume --last
```

- `--last` resumes the most recent session
- Without `--last`, opens a picker (interactive — warn user)

## Behavior Notes

- **Bare string = exec.** `/codex "do something"` without a subcommand runs `codex exec --full-auto`.
- **Background by default for exec.** Long-running `exec` tasks should use `run_in_background: true` unless the user asks to wait.
- **Model selection.** If the user doesn't specify a model, let Codex use its configured default. Mention that `-m o3` or `-m o4-mini` are options.
- **Working directory.** Use `-C <path>` when dispatching to a different repo. Default is the current working directory.
- **Sandbox modes.** `--full-auto` is the safe default (workspace-write). Never use `--dangerously-bypass-approvals-and-sandbox` unless the user explicitly asks.
- **Keep it terse.** This is a dispatch utility. Confirm what you launched, report results when done.
- **Codex is a peer, not a subordinate.** It has its own context window and tools. Give it complete, self-contained prompts — it can't see your conversation.
