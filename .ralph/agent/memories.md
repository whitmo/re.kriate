# Memories

## Patterns

### mem-1773025663-2505
> Spec-kit consistency rule: contract filenames in specs/001 quickstart should match current entity names (e.g., decomposition-slice.schema.json) so validation steps don't carry legacy automation terms.
<!-- tags: review, planning, spec-kit | created: 2026-03-09 -->

## Decisions

### mem-1773025545-6042
> Diagram-backed scope drift pattern: branch-gap artifacts can supersede decomposition-first assumptions; keep PR #11 closure-first with salvage fallback and treat 002 as primary simplification line in spec/plan docs.
<!-- tags: review, planning, spec-kit | created: 2026-03-09 -->

## Fixes

### mem-1773025698-1994
> failure: cmd=rg validation with backticks in double-quoted pattern, exit=0 with shell error, error=zsh command substitution attempted on , next=use single-quoted rg patterns when matching markdown backticks
<!-- tags: tooling, error-handling, spec-kit | created: 2026-03-09 -->

### mem-1773018122-7ad7
> failure: cmd=rg stale-scope validation on narrowed support artifacts, exit=1, error=pattern matched negative mentions of removed CI/speech scope in research.md and quickstart.md, next=use narrower legacy-term checks that target implementation phrases or scripts instead of descriptive exclusions
<!-- tags: tooling, error-handling, spec-kit | created: 2026-03-09 -->

### mem-1773017834-d9e3
> failure: cmd=rg stale-scope scan on specs/001-branch-review-followups/plan.md and tasks.md, exit=1, error=validation pattern matched the intentional phrase 'CI/task speech workflows' inside T016, next=avoid using stale-scope keywords in validation-task prose or narrow the scan to disallowed implementation content only
<!-- tags: tooling, error-handling, spec-kit | created: 2026-03-09 -->

### mem-1773017600-2b4a
> failure: cmd=rg -n "HOOOOOORAY|DONE \{task number\}|CI-pass|voice rotation|Celebration Event|Task Completion Event" specs/001-branch-review-followups/spec.md, exit=1, error=no matches found during negative-scope verification, next=wrap future negative rg checks with shell logic so expected no-match results do not register as failures
<!-- tags: tooling, error-handling | created: 2026-03-09 -->

### mem-1773017433-fc0e
> failure: cmd=sed -n '1,220p' .ralph/agent/scratchpad.md, exit=1, error=No such file or directory, next=recreate scratchpad before continuing Ralph loop work
<!-- tags: ralph, error-handling | created: 2026-03-09 -->

### mem-1772990322-ac52
> failure: cmd=parallel ralph tools task add x2, exit=0, error=both adds returned task-1772990313-34f7, next=add Ralph runtime tasks serially to avoid duplicate IDs from same-second creation
<!-- tags: ralph, tooling, error-handling | created: 2026-03-08 -->

### mem-1772990196-1df0
> failure: cmd=sed -n '1,240p' /Users/whit/.codex/skills/ralph-tools/SKILL.md, exit=1, error=No such file or directory, next=use the injected Ralph tools reference or <ralph-tools-skill>
> # Ralph Tools
> 
> Quick reference for `ralph tools task` and `ralph tools memory` commands used during orchestration.
> 
> ## Two Task Systems
> 
> | System | Command | Purpose | Storage |
> |--------|---------|---------|---------|
> | **Runtime tasks** | `ralph tools task` | Track work items during runs | `.agent/tasks.jsonl` |
> | **Code tasks** | `ralph task` | Implementation planning | `tasks/*.code-task.md` |
> 
> This skill covers **runtime tasks**. For code tasks, see `/code-task-generator`.
> 
> ## Task Commands
> 
> ```bash
> ralph tools task add "Title" -p 2 -d "description" --blocked-by id1,id2
> ralph tools task list [--status open|in_progress|closed] [--format table|json|quiet]
> ralph tools task ready                    # Show unblocked tasks
> ralph tools task close <task-id>
> ralph tools task show <task-id>
> ```
> 
> **Task ID format:** `task-{timestamp}-{4hex}` (e.g., `task-1737372000-a1b2`)
> 
> **Priority:** 1-5 (1 = highest, default 3)
> 
> ### Task Rules
> - One task = one testable unit of work (completable in 1-2 iterations)
> - Break large features into smaller tasks BEFORE starting implementation
> - On your first iteration, check `ralph tools task ready` — prior iterations may have created tasks
> - ONLY close tasks after verification (tests pass, build succeeds)
> 
> ### First thing every iteration
> ```bash
> ralph tools task ready    # What's open? Pick one. Don't create duplicates.
> ```
> 
> ## Interact Commands
> 
> ```bash
> ralph tools interact progress "message"
> ```
> 
> Send a non-blocking progress update via the configured RObot (Telegram).
> 
> ## Skill Commands
> 
> ```bash
> ralph tools skill list
> ralph tools skill load <name>
> ```
> 
> List available skills or load a specific skill by name.
> 
> ## Memory Commands
> 
> ```bash
> ralph tools memory add "content" -t pattern --tags tag1,tag2
> ralph tools memory list [-t type] [--tags tags]
> ralph tools memory search "query" [-t type] [--tags tags]
> ralph tools memory prime --budget 2000    # Output for context injection
> ralph tools memory show <mem-id>
> ralph tools memory delete <mem-id>
> ```
> 
> **Memory types:**
> 
> | Type | Flag | Use For |
> |------|------|---------|
> | pattern | `-t pattern` | "Uses barrel exports", "API routes use kebab-case" |
> | decision | `-t decision` | "Chose Postgres over SQLite for concurrent writes" |
> | fix | `-t fix` | "ECONNREFUSED on :5432 means run docker-compose up" |
> | context | `-t context` | "ralph-core is shared lib, ralph-cli is binary" |
> 
> **Memory ID format:** `mem-{timestamp}-{4hex}` (e.g., `mem-1737372000-a1b2`)
> 
> **NEVER use echo/cat to write tasks or memories** — always use CLI tools.
> 
> ### When to Search Memories
> 
> **Search BEFORE starting work when:**
> - Entering unfamiliar code area → `ralph tools memory search "area-name"`
> - Encountering an error → `ralph tools memory search -t fix "error message"`
> - Making architectural decisions → `ralph tools memory search -t decision "topic"`
> - Something feels familiar → there might be a memory about it
> 
> **Search strategies:**
> - Start broad, narrow with filters: `search "api"` → `search -t pattern --tags api`
> - Check fixes first for errors: `search -t fix "ECONNREFUSED"`
> - Review decisions before changing architecture: `search -t decision`
> 
> ### When to Create Memories
> 
> **Create a memory when:**
> - You discover how this codebase does things (pattern)
> - You make or learn why an architectural choice was made (decision)
> - You solve a problem that might recur (fix)
> - You learn project-specific knowledge others need (context)
> - Any non-zero command, missing dependency/skill, or blocked step (fix + task if unresolved)
> 
> **Do NOT create memories for:**
> - Session-specific state (use tasks instead)
> - Obvious/universal practices
> - Temporary workarounds
> 
> ### Failure Capture (Generic Rule)
> 
> If any command fails (non-zero exit), or you hit a missing dependency/skill, or you are blocked:
> 1. **Record a fix memory** with the exact command, error, and intended fix.
> 2. **Open a task** if it won't be resolved in the same iteration.
> 
> ```bash
> ralph tools memory add \
>   "failure: cmd=<command>, exit=<code>, error=<message>, next=<intended fix>" \
>   -t fix --tags tooling,error-handling
> 
> ralph tools task add "Fix: <short description>" -p 2
> ```
> 
> ### Discover Available Tags
> 
> Before searching or adding, check what tags already exist:
> 
> ```bash
> ralph tools memory list
> grep -o 'tags: [^|]*' .agent/memories.md | sort -u
> ```
> 
> Reuse existing tags for consistency. Common tag patterns:
> - Component names: `api`, `auth`, `database`, `cli`
> - Concerns: `testing`, `performance`, `error-handling`
> - Tools: `docker`, `postgres`, `redis`
> 
> ### Memory Best Practices
> 
> 1. **Be specific**: "Uses barrel exports in each module" not "Has good patterns"
> 2. **Include why**: "Chose X because Y" not just "Uses X"
> 3. **One concept per memory**: Split complex learnings
> 4. **Tag consistently**: Reuse existing tags when possible
> 
> ## Decision Journal
> 
> Use `.ralph/agent/decisions.md` to capture consequential decisions and their
> confidence scores. Follow the template at the top of the file and keep IDs
> sequential (DEC-001, DEC-002, ...).
> 
> Confidence thresholds:
> - **>80**: Proceed autonomously.
> - **50-80**: Proceed, but document the decision in `.ralph/agent/decisions.md`.
> - **<50**: Choose the safest default and document the decision in `.ralph/agent/decisions.md`.
> 
> Template fields:
> - Decision
> - Chosen Option
> - Confidence (0-100)
> - Alternatives Considered
> - Reasoning
> - Reversibility
> - Timestamp (UTC ISO 8601)
> 
> ## Output Formats
> 
> All commands support `--format`:
> - `table` (default) - Human-readable
> - `json` - Machine-parseable
> - `quiet` - IDs only (for scripting)
> - `markdown` - Memory prime only
> 
> ## Common Workflows
> 
> ### Track dependent work
> ```bash
> ralph tools task add "Setup auth" -p 1
> # Returns: task-1737372000-a1b2
> 
> ralph tools task add "Add user routes" --blocked-by task-1737372000-a1b2
> ralph tools task ready  # Only shows unblocked tasks
> ```
> 
> ### Store a discovery
> ```bash
> ralph tools memory add "Parser requires snake_case keys" -t pattern --tags config,yaml
> ```
> 
> ### Find relevant memories
> ```bash
> ralph tools memory search "config" --tags yaml
> ralph tools memory prime --budget 1000 -t pattern  # For injection
> ```
> 
> ### Memory examples
> ```bash
> # Pattern: discovered codebase convention
> ralph tools memory add "All API handlers return Result<Json<T>, AppError>" -t pattern --tags api,error-handling
> 
> # Decision: learned why something was chosen
> ralph tools memory add "Chose JSONL over SQLite: simpler, git-friendly, append-only" -t decision --tags storage,architecture
> 
> # Fix: solved a recurring problem
> ralph tools memory add "cargo test hangs: kill orphan postgres from previous run" -t fix --tags testing,postgres
> 
> # Context: project-specific knowledge
> ralph tools memory add "The /legacy folder is deprecated, use /v2 endpoints" -t context --tags api,migration
> ```
> 
> </ralph-tools-skill> instead of assuming a local Codex skill path
<!-- tags: ralph, tooling, error-handling | created: 2026-03-08 -->

### mem-1772989936-a308
> failure: cmd=rg -n "grid|midi|arrow|voice|pattern|track|modifier" README.md docs lib lua specs -g '!docs/grid-interface.html', exit=2, error=rg: lua: No such file or directory (os error 2), next=search only existing repo paths such as README.md docs lib and specs
<!-- tags: tooling, error-handling | created: 2026-03-08 -->

### mem-1772989850-da34
> failure: cmd=sed -n '1,220p' .ralph/agent/scratchpad.md, exit=1, error=No such file or directory, next=recreate scratchpad before continuing Ralph loop work
<!-- tags: ralph, error-handling | created: 2026-03-08 -->

## Context

### mem-1773025371-53cc
> Loop primary-20260309-030108 starts with spec 001 artifacts already narrowed; next actions are drift-correction and consistency validation using docs/code-review.html, docs/branch-gap-analysis.html, and 2026-03-08 diagram snapshots.
<!-- tags: review, planning, spec-kit | created: 2026-03-09 -->

### mem-1773018167-546d
> Spec 001 support artifacts now validate against the narrowed evidence set: research/data-model/quickstart/contracts all describe decomposition planning, and the PR #11 salvage-vs-superseded disagreement is recorded as a pass-with-conflicts result.
<!-- tags: review, planning, spec-kit | created: 2026-03-09 -->

### mem-1773017834-e05e
> Spec 001 plan.md and tasks.md now align with the narrowed decomposition-planning scope: only PR #11 and branch 002-modifiers-meta-config-presets remain active, and both artifacts cite the canonical review docs plus diagram snapshots as evidence inputs.
<!-- tags: review, planning, spec-kit | created: 2026-03-09 -->

### mem-1773017621-c326
> Spec 001 is now narrowed to decomposition planning for PR #11 and branch 002, using the canonical review docs and /Users/whit/.agent/diagrams snapshots as evidence; speech/celebration workflow scope was removed as out-of-objective.
<!-- tags: review, planning, spec-kit | created: 2026-03-09 -->

### mem-1772998713-50fc
> origin/multiclaude/witty-badger is fully subsumed by main: commit e767dcd adds spec-kit templates + specs/remote-api design docs, all identical on main; git cherry reports '-' prefix; safe to delete remote branch
<!-- tags: git, review, planning | created: 2026-03-08 -->

### mem-1772990530-1d9c
> origin/work/proud-wolf's docs drift was resolved by correcting docs/voices.html on main; for stale docs-only branches, prefer repairing the canonical document and treat the remote branch as superseded rather than merging inaccurate prose.
<!-- tags: git, review, docs | created: 2026-03-08 -->

### mem-1772990313-3339
> origin/work/proud-wolf is unique to main as 86e5a29 but should not merge until docs/voices.html is corrected: it calls extended-page switching a double-tap while lib/grid_ui.lua uses a second-press toggle, and its track 2/4 duration prose drifts from lib/track.lua defaults.
<!-- tags: git, review, docs | created: 2026-03-08 -->

### mem-1772990144-bc64
> origin/work/proud-eagle is already merged on main via commit 526ba0c/PR #13; validate old-base tooling branches with git merge-base plus git cherry before reading raw diffs.
<!-- tags: git, review, planning | created: 2026-03-08 -->

### mem-1772990029-f234
> origin/multiclaude/clever-deer is already merged on main via commit 4125f5e/PR #12; use git cherry before attempting remote branch merges.
<!-- tags: git, review, planning | created: 2026-03-08 -->

### mem-1772989850-da35
> Current branch review order favors focused docs/tooling branches before code-heavy or mixed branches; PR #11 and 002-modifiers-meta-config-presets require decomposition review before merge.
<!-- tags: git, review, planning | created: 2026-03-08 -->
