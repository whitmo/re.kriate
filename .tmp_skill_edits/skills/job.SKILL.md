---
name: job
description: Run and manage background shell jobs from within Claude Code. Use when the user wants to kick off a long-running command, check on running processes, or manage background tasks. Trigger on phrases like "run this in the background", "start a build", "check on that process", "what's running", or any /job invocation.
argument-hint: <run|list|status|stop|log> [args]
---

# Job Manager

Manage background shell jobs from within Claude Code. Parse the user's argument to determine the subcommand:

## Subcommands

### `job run <command>` (aliases: `r`, no subcommand)

Run a command in the background using the Bash tool with `run_in_background: true`.

- If the user just writes `/job <command>` without a subcommand keyword, treat it as `run`
- Before launching, briefly confirm what you're about to run and in which directory
- Use the Bash tool with `run_in_background: true` to launch the command
- Report the task ID back to the user so they can reference it later
- If the command looks like it needs specific environment setup (e.g., virtualenv, nvm, specific directory), mention that

**Examples:**
- `/job run npm test`
- `/job make build`
- `/job docker compose up`
- `/job pytest -x --timeout=300`

### `job list` (aliases: `ls`, `ps`)

List all active background tasks.

- Use the TaskOutput tool with `block: false` to check status of known tasks
- Present a concise table: task ID, command (truncated), status (running/done/failed), duration
- If no tasks are tracked, say so

### `job status <task-id>` (aliases: `s`, `check`)

Check on a specific background task.

- Use TaskOutput with `block: false` and the given task ID
- Show: status, elapsed time, and the tail of the output (last ~20 lines)
- If the task is done, show the exit status and final output

### `job log <task-id>` (aliases: `l`, `output`)

Get the full output of a completed or running task.

- Use TaskOutput with `block: false` and the given task ID
- Display the complete output
- If the output is very long (>200 lines), ask if the user wants the full thing or just head/tail

### `job stop <task-id>` (aliases: `kill`, `k`)

Stop a running background task.

- Use the TaskStop tool with the given task ID
- Confirm the task was stopped

### `job wait <task-id>` (aliases: `w`)

Block until a background task completes, then show its output.

- Use TaskOutput with `block: true` and the given task ID
- Display the result when done

## Behavior notes

- When the user provides a bare command without a subcommand keyword, infer intent: if it looks like a shell command, treat as `run`. If it looks like a task ID, treat as `status`.
- Keep responses terse — this is a utility, not a conversation. Just confirm the action and show the result.
- If a `run` command fails immediately (bad command, missing binary), report the error clearly.
- For `run`, always use the working directory the user is currently in unless they specify otherwise.
