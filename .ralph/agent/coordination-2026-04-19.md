# Coordination Plan — 2026-04-19

Branch: `autoresearch/spring-clean-20260418`
Status: clean tree, green baseline (`1615 successes / 0 failures / 0 errors / 1 pending`)

## Goal
Keep the branch stable while two agents work in parallel without stepping on each other.

## Source of truth
- Coordination file: `.ralph/agent/coordination-2026-04-19.md`
- Live claims / handoffs: `.ralph/agent/scratchpad.md`

## Roles

### Agent A — Merge/Review Prep
Owns:
- PR summary
- change audit
- test/baseline verification notes
- reviewer-facing documentation

Allowed files:
- `.ralph/agent/coordination-2026-04-19.md`
- `.ralph/agent/scratchpad.md`
- `.ralph/agent/summary.md`
- `README.md` or docs **only if explicitly needed for review notes**

Do not modify:
- `lib/**`
- `specs/**`
- autoresearch result files unless correcting factual errors

Deliverables:
1. concise branch summary
2. list of commits and rationale
3. exact validation command + result
4. merge risks / reviewer notes

### Agent B — Recon / Next-Step Planning
Owns:
- reconnaissance only
- next feature selection proposal
- stash/branch/worktree audit
- optional follow-up issue notes

Allowed files:
- `.ralph/agent/coordination-2026-04-19.md`
- `.ralph/agent/scratchpad.md`
- `.ralph/agent/handoff.md`
- planning notes under `.ralph/agent/`

Do not modify:
- `lib/**`
- `specs/**`
- `.autoresearch/**`
- branch content intended for merge

Deliverables:
1. next recommended task after spring-clean
2. any abandoned-work findings
3. risk notes if the branch should *not* be merged yet

## Hard rules
1. No functional code changes on this branch.
2. No edits to `lib/**` or `specs/**` by either agent.
3. Before editing any shared note file, add a claim in `scratchpad.md`.
4. If a file is already claimed, wait.
5. Commit in tiny units with clear prefixes:
   - `agent-a: ...`
   - `agent-b: ...`
6. Re-run baseline check before final handoff:
   - `busted specs/ 2>&1 | grep -E 'successes|failures|errors|pending'`

## Claim format
Append to `.ralph/agent/scratchpad.md`:

```md
## 2026-04-19 HH:MM UTC — agent-a
Claim: <task>
Files: <comma-separated paths>
Status: in progress

## 2026-04-19 HH:MM UTC — agent-a
Handoff: <what changed>
Tests: <commands/results>
Next: <next safe step>
```

## Suggested sequence
1. Agent A claims `.ralph/agent/summary.md` and writes merge-ready summary.
2. Agent B claims `.ralph/agent/handoff.md` and writes next-step recommendation.
3. One agent re-runs baseline test command.
4. Final handoff in `scratchpad.md`.

## Message to the other agent
Please avoid touching tracked product code on this branch. This branch is already green and clean. Limit work to review/handoff/planning notes under `.ralph/agent/`. Claim files in `scratchpad.md` before editing, keep commits small, and do not change `lib/`, `specs/`, or `.autoresearch/`.
