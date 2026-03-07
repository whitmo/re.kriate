<!--
Sync Impact Report
- Version change: 1.2.0 → 1.3.0
- Modified: VIII. Multiplexed Development (ralph inside mc workers, PRs as output)
- Modified: Development Workflow (added Branching & PRs, CI Pipeline sections)
- Templates requiring updates: ✅ constitution.md (this file)
- Follow-up TODOs: Set up GitHub Actions CI, Add Visualizer hat to ralph.yml
-->

# re.kriate Constitution

## Core Principles

### I. No Custom Globals

Globals are reserved exclusively for platform API hooks (`init`, `redraw`, `key`, `enc`, `cleanup`). All custom logic MUST live in modules loaded via `require`. Global hooks in entrypoint scripts MUST be thin wrappers that delegate to modules. No module-level mutable state outside of the `ctx` table.

### II. State via Context Object & Dependency Injection

All application state MUST flow through a single context table (`ctx`) passed through the call chain. Modules MUST receive and operate on `ctx` rather than reaching for global or upvalue state. Platform globals (`clock`, `grid`, `metro`, `params`, `midi`, `screen`) MUST be passed in when instantiating objects rather than referenced from the global namespace whenever possible. Constructors accept dependencies as arguments (e.g. `midi_voice.new(midi_dev, channel)` not `midi_voice.new()` reaching for `midi` global). This makes every module independently testable with mock dependencies.

### III. Test-First: Red Tests First (NON-NEGOTIABLE)

TDD is mandatory with strict red-green-refactor:
1. **Red**: Write a failing test that describes the desired behavior. Commit the failing test.
2. **Green**: Write the minimum code to make the test pass.
3. **Refactor**: Clean up while keeping tests green.

Every new feature, bug fix, or behavior change MUST start with a failing test. Tests run via `busted`. Target 100% coverage of all `lib/` modules — every public function MUST have at least one test. Tests MUST NOT depend on the seamstress or norns runtime; mock all platform globals.

### IV. Dual-Platform Compatibility

The codebase MUST support both norns and seamstress v1.4.7. Shared logic lives in `lib/`. Platform-specific code lives in separate entrypoints (`re_kriate.lua` for norns, `re_kriate_seamstress.lua` for seamstress) and platform-specific module directories (`lib/norns/`, `lib/seamstress/`). The voice abstraction (`ctx.voices`) MUST be the only interface between the sequencer and audio output — entrypoints inject the appropriate backend (nb for norns, MIDI for seamstress, recorder for tests).

### V. Simplicity & YAGNI

Start simple. Do not add features, abstractions, or configuration for hypothetical future needs. Three similar lines of code are better than a premature abstraction. Only add error handling at system boundaries (user input, MIDI devices). Trust internal code and framework guarantees. Each module SHOULD have a single clear responsibility.

### VI. Visual Aids

Create visual aids to help understand what the software is doing. Use the seamstress screen to render sequencer state (step positions, patterns, piano roll). Generate HTML diagrams and illustrations for documentation using the visual-explainer skill. When debugging or reviewing, produce visual output that makes behavior observable — either on-screen in the running app or as standalone artifacts for review.

### VII. Documentation as Acceptance Criteria

Documentation serves as the acceptance criterion. Feature descriptions, spec documents, and inline comments define what "done" means. If a behavior is documented, it MUST work. If it doesn't work, there MUST be a failing test for it. Specs and plans are living documents — update them as implementation reveals new understanding.

### VIII. Multiplexed Development

Use ralph and multiclaude to multiplex, focus, and isolate development:
- **Ralph** orchestrates multi-hat agentic loops for sequential focused work on a single feature.
- **MultiClaude** (`/mc swarm`) fans out independent tasks across isolated worktrees for parallel execution.
- Break work into modular, tested pieces that can be developed in isolation and integrated. Each piece MUST be independently testable and demoable.
- Prefer many small, focused tasks over few large ones — this maximizes parallelism and reduces merge conflicts.

#### Ralph Hats

| Hat | Role | Triggers | Publishes |
|-----|------|----------|-----------|
| **Researcher** | Studies kria references, norns/seamstress platform, tracks feature parity | `work.start`, `refactor.done` | `design.ready` |
| **Musician** | Opinionated domain expert — evaluates design and implementation from a performer's perspective | `design.ready`, `test.passed` | `design.approved`, `music.approved`, `music.fix` |
| **Lua Wizard** | Primary implementer — writes Lua following project conventions, ctx pattern, modular design | `design.approved`, `test.failed`, `music.fix` | `build.done` |
| **Tester** | Validates via busted tests, syntax checks (`luac -p`), structural verification, load tests | `build.done` | `test.passed`, `test.failed` |
| **Refactorer** | Periodic tidying — enforces conventions, simplifies, removes dead code | `music.approved` | `refactor.done` |
| **Visualizer** | Generates HTML diagrams, grid layout illustrations, and screen mockups for review | `design.ready`, `build.done` | `visual.ready` |
| **Video Artist** | Designs and implements cool, functional seamstress screen UI — color, layout, animation, live data visualization (piano roll, step grids, waveforms) | `design.approved`, `music.fix` | `build.done` |

Event flow: `work.start` → Researcher → Musician → Lua Wizard → Tester → Musician → Refactorer → (loop or LOOP_COMPLETE)

#### MultiClaude Patterns

- `/mc swarm` for independent module work (e.g. track.lua + scale.lua + grid_ui.lua tests in parallel)
- `/mc work` for single focused tasks (e.g. "add direction mode to track.lua with tests")
- Each worker gets an isolated worktree with a fresh context window — no merge conflicts during development
- Workers can run ralph inside their worktree for full hat-loop cycles on their isolated task
- Each worker's output is a PR — work is integrated via pull requests, not direct commits to main

## Platform Constraints

- **Language**: Lua 5.4 (seamstress v1.4.7 runtime) / Lua 5.3 (norns runtime)
- **Grid**: Monome 128 (16x8 LED button grid) — the primary interface
- **Screen**: seamstress SDL window (256x128, color) or norns OLED (128x64, grayscale)
- **Audio output**: MIDI via voice abstraction; norns also supports nb/SuperCollider
- **Timing**: `clock.run` + `clock.sync` for all sequencer timing and note-off scheduling
- **Testing**: `busted` test framework with mocked platform globals
- **No external dependencies** beyond what the platform runtime provides

## Development Workflow

### Branching & PRs

- Feature branches from `main`
- All work lands via pull requests — no direct commits to `main`
- Each task or module gets its own branch and PR
- PRs MUST pass CI before merge
- Squash-merge to keep history clean

### CI Pipeline

- **Lint**: `luac -p` syntax check on all `.lua` files
- **Unit tests**: `busted specs/` — all tests must pass
- **Coverage**: verify every public function in `lib/` has at least one test
- CI runs on every push and PR via GitHub Actions
- CI MUST be set up before feature implementation begins

### Daily Process

- **Red tests first**: failing tests committed before implementation code
- Break features into modular tested pieces — each piece gets its own test file or describe block
- Ralph orchestrator for focused single-feature loops (planner/builder/reviewer/tester hats)
- MultiClaude (`/mc swarm`) for parallelizing independent tasks across worktrees
- MultiClaude workers can run ralph inside their worktree for full hat-loop cycles
- All changes to `lib/` MUST have corresponding test changes in `specs/`
- Visual aids (HTML diagrams, screen renderings) produced alongside features for review
- Grid UI changes SHOULD be verified manually on hardware after tests pass

## Governance

This constitution codifies the principles in CLAUDE.md and the project's established patterns. All code contributions MUST comply. Amendments require updating both this file and CLAUDE.md to stay in sync. Complexity beyond these principles MUST be justified in the relevant spec or plan document.

**Version**: 1.3.1 | **Ratified**: 2026-03-06 | **Last Amended**: 2026-03-06
