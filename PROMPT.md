# re.kriate — Complete Seamstress Kria Sequencer

## Objective

Complete all missing kria features for the seamstress platform: extended pages (ratchet, alt-note, glide), direction modes, pattern storage, and mute fix. Success = all features from the spec work end-to-end with full test coverage.

## Spec Pipeline (speckit)

This project uses **speckit** for spec-driven development. All artifacts live in `specs/001-seamstress-kria-features/`:

| Artifact | Path | Purpose |
|----------|------|---------|
| Spec | `spec.md` | Feature specification with 14 user stories and acceptance scenarios |
| Research | `research.md` | Phase 0 research decisions (10 decisions) |
| Data Model | `data-model.md` | Entity definitions, ctx schema, state transitions |
| Contracts | `contracts/module-interfaces.md` | Public API contracts for all lib/ modules |
| Plan | `plan.md` | Implementation plan with 12 tasks across 5 waves |
| Tasks | `tasks.md` | 66 tasks across 11 phases mapped to 14 user stories |
| Decisions | `decisions.md` | 9 architectural decisions with rationale |
| Quickstart | `quickstart.md` | How to run, test, and develop |

**Read `spec.md` and `plan.md` first** for full context.

## Parallel Execution (MultiClaude)

**MultiClaude (`/mc`) is available** for parallel worker dispatch. The plan is structured in waves for parallel execution:

- **Wave 0** (done): CI pipeline
- **Wave 1** (done): Direction module, pattern module, extended track params, voice portamento
- **Wave 2** (in progress): Extended page toggle, sequencer integration, mute fix
- **Wave 3** (in progress): Extended page displays, screen UI, keyboard toggle
- **Wave 4** (pending): Integration tests + coverage verification

Workers run in isolated git worktrees and create PRs. Use `/mc swarm` to dispatch parallel workers, `/mc status` to check progress.

## Key Decisions

1. **Simplified ratchet**: Value 1-7 (subdivisions), not full sub-trigger grid
2. **Alt-note is additive**: `effective_degree = ((note - 1) + (alt_note - 1)) % scale_len + 1`
3. **Per-track direction** (not per-param): forward, reverse, pendulum, drunk, random
4. **Glide via MIDI CC**: CC 65 (portamento on/off) + CC 5 (portamento time)
5. **Muted tracks advance silently**: Playheads move, notes suppressed
6. **No grid scale/pattern pages this phase**: API-only, configured via params/keyboard

## Current State

- **Branch**: `pdd/seamstress-entrypoint`
- **Tests**: 211 passing (busted specs/)
- **Platform**: seamstress v1.4.7 at `/opt/homebrew/opt/seamstress@1/bin/seamstress`
- **Test runner**: `busted` (requires lua5.4 symlink at `/opt/homebrew/opt/lua/bin/lua5.4`)

## Architecture

- `lib/` — shared modules (track, sequencer, grid_ui, scale, direction, pattern, voices/)
- `lib/seamstress/` — seamstress-specific (screen_ui, keyboard)
- `lib/norns/` — norns-specific (nb_voice)
- `specs/` — busted test files
- Single `ctx` table carries all state. No globals except platform hooks.
- Voices injected via `config.voices` in `app.init(config)`

## Acceptance Criteria

1. All 14 user stories from spec.md pass their acceptance scenarios
2. Extended page toggle works (double-press nav key)
3. Direction modes produce correct step sequences
4. Ratchet subdivides notes correctly
5. Alt-note combines additively with primary note
6. Glide sends portamento CC messages
7. Muted tracks advance silently
8. Pattern save/load works via keyboard
9. 100% public function coverage in tests
10. `busted specs/` passes all tests, CI green

## Constraints

- Follow CLAUDE.md conventions (ctx pattern, no custom globals, DI)
- TDD: tests MUST fail before implementation (constitution principle III)
- No external dependencies beyond seamstress runtime
- Mark completed tasks [x] in tasks.md as work lands
