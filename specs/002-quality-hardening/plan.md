# Implementation Plan: Quality Hardening — Test Gap Audit & Edge Case Coverage

**Branch**: `002-quality-hardening` | **Date**: 2026-03-24 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-quality-hardening/spec.md`

## Summary

Audit all 442 existing tests for coverage gaps across 7 edge-case categories (loop boundaries, note retrigger safety, clock stop/start idempotency, pattern save/load roundtrip, direction mode transitions, mute/unmute timing, scale change mid-playback). Write failing tests for each uncovered edge case, then fix any bugs found. Run a seamstress load test to verify initialization and cleanup. Target: 30+ new tests, zero regressions, suite still under 5 seconds.

This is a **test-only feature** — no new user-facing functionality. All changes are in `specs/` test files and, where tests expose bugs, minimal targeted fixes in `lib/` modules.

## Technical Context

**Language/Version**: Lua 5.4 (via busted test runner, seamstress runtime)
**Primary Dependencies**: busted (test framework), seamstress v1.4.7, musicutil (norns/seamstress scale utilities)
**Storage**: N/A (in-memory patterns, no persistence layer)
**Testing**: busted (`busted specs/ --no-auto-insulate`), 442 tests passing in 0.25s
**Target Platform**: seamstress (macOS), norns (Linux ARM)
**Project Type**: Embedded Lua application (norns/seamstress sequencer script)
**Performance Goals**: Full test suite < 5 seconds (currently 0.25s)
**Constraints**: No new external dependencies; tests must use recorder voice (no real MIDI); seamstress load test uses short-duration headless approach
**Scale/Scope**: 14 spec files, 6 lib modules under audit, ~30-50 new test cases

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Context-Centric Architecture** | PASS | No architectural changes. New tests use existing `ctx` pattern. |
| **II. Platform-Parity Behavior** | PASS | Tests verify shared sequencing behavior. Seamstress load test is platform-specific but documented. No behavioral divergence introduced. |
| **III. Test-First Sequencing Correctness** | PASS | This feature IS the test-first effort — every gap gets a failing test before any fix. TDD is the entire point. |
| **IV. Deterministic Timing and Safe Degradation** | PASS | Clock idempotency tests (US-3) directly verify this principle. No timing changes, only timing assertions. |
| **V. Spec-Driven Delivery** | PASS | Full speckit pipeline: spec.md → plan.md → tasks.md → implement. Feature tracked in feature-queue.md. |

No violations. No complexity tracking needed.

## Test Coverage Audit

### Current State (442 tests across 14 spec files)

| Module | Tests | Loop Edges | State Mutation | Boundaries | Error Handling |
|--------|-------|------------|----------------|------------|----------------|
| track | 17 | Partial | Weak | Partial | Partial |
| sequencer | 29 | Partial | Partial | Partial | Partial |
| voice (MIDI+recorder) | 35+ | Weak | Partial | Good | Partial |
| pattern | 15 | Weak | Partial | Partial | Partial |
| direction | 15+ | Good | Partial | Good | Partial |
| scale | 18+ | Weak | Weak | Good | Partial |

### Identified Gaps by User Story

**US-1: Loop Boundary Edge Cases** (6 gaps)
- Single-step loop (loop_start == loop_end) — iterate and verify value repeats
- Full-range loop (1-16) — verify 32 advances produces exactly 2 full cycles
- Loop boundary change mid-playback with position clamping
- All 8 param types with independent loop lengths on same track (100-step polymetric test)
- Loop wrapping for last-two-steps config (15-16)
- loop_start > loop_end rejection (partially covered, needs explicit assertion)

**US-2: Note Retrigger Safety** (4 gaps)
- Note-off sent before note-on on retrigger (ordering guarantee)
- Same-note retrigger (C4 → C4)
- Rapid 16-step all-trigger fast-tempo: verify no orphaned notes
- Cleanup/stop sends all_notes_off clearing active notes

**US-3: Clock Stop/Start Idempotency** (4 gaps)
- Double-start: no duplicate coroutines (partially covered, needs stronger assertion)
- Double-stop: no error (partially covered)
- Rapid start/stop 50x toggle: consistent end state, no resource leaks
- Stop-then-start: clean resume from current playheads

**US-4: Pattern Save/Load Roundtrip** (5 gaps)
- Extended params (ratchet, alt_note, glide) roundtrip
- Direction mode roundtrip per track
- All 8 params × 4 tracks × loop boundaries + positions
- Save slot A, modify, save slot B, load slot A: original restored
- Load empty/default slot: no error, no corruption

**US-5: Direction Mode Transitions** (4 gaps)
- Forward→reverse mid-sequence: next step is current-1
- Pendulum→forward: continues forward from current position
- Any direction on single-step loop: stays on that step
- Drunk: stays within bounds (partially covered, needs explicit mid-change test)

**US-6: Mute/Unmute Timing** (4 gaps)
- Mute→advance 3 steps→unmute: next note from step+3
- Double-mute: remains muted, no error
- All 4 tracks muted: all playheads advance, zero notes output
- Muted track playhead advancement verification (position check after N steps)

**US-7: Scale Change Mid-Playback** (3 gaps)
- Change scale: next note uses new scale
- Scale with fewer degrees than current note value: wrapping
- Already-sounding notes not retroactively re-pitched

**US-8: Seamstress Load Test** (1 gap)
- Launch seamstress, init, run 30s, cleanup: no errors, no leaks

**Edge Cases from Spec** (8 gaps)
- loop_start > loop_end handling
- All-zero triggers track: playhead still advances
- Load never-saved slot: defaults gracefully
- 4 tracks × random direction × single-step loops: no crash
- Muted track grid editing: visual state reflects edits
- 1-degree scale: all notes map to single pitch
- Extreme clock tempo (min/max): sequencer still functions
- Cleanup mid-step (note-on sent, note-off pending): all notes silenced

**Total identified gaps**: ~39 test cases needed across 7 areas + edge cases

## Project Structure

### Documentation (this feature)

```text
specs/002-quality-hardening/
├── plan.md              # This file
├── research.md          # Phase 0: gap analysis findings
├── data-model.md        # Phase 1: N/A (test-only, no model changes)
├── quickstart.md        # Phase 1: how to run the hardening tests
└── tasks.md             # Phase 2: TDD-ordered task list
```

### Source Code (repository root)

```text
lib/                         # Modules under audit (no structural changes expected)
├── track.lua                # Loop boundary, param independence
├── sequencer.lua            # Clock, mute, step, ratchet, alt-note, glide
├── pattern.lua              # Save/load roundtrip
├── direction.lua            # Mode transitions
├── scale.lua                # Scale change, degree mapping
└── voices/
    ├── midi.lua             # Note retrigger, all_notes_off
    └── recorder.lua         # Test helper voice

specs/                       # Test files — new tests added to existing files
├── track_spec.lua           # +6 loop boundary tests
├── sequencer_spec.lua       # +8 clock/mute/integration tests
├── voice_spec.lua           # +4 retrigger safety tests
├── pattern_spec.lua         # +5 roundtrip tests
├── direction_spec.lua       # +4 transition tests
├── scale_spec.lua           # +3 scale change tests
├── integration_spec.lua     # +8 edge case + cross-module tests
└── seamstress_load_spec.lua # +1 seamstress load test (new file)
```

**Structure Decision**: All new tests go into existing spec files organized by module. One new file (`seamstress_load_spec.lua`) for the load test since it requires the seamstress runtime and cannot run under plain busted. Edge cases that span multiple modules go in `integration_spec.lua`.

## Implementation Phases

### Phase 1: Loop Boundary & Track Tests (US-1)
**Target**: 6 new tests in `track_spec.lua` and `integration_spec.lua`
**Modules**: `lib/track.lua`
**Approach**: Test single-step loops, full-range cycling, mid-playback loop changes, param independence. These are pure unit tests on `track.advance()` and `track.set_loop()`.

### Phase 2: Note Retrigger Safety (US-2)
**Target**: 4 new tests in `voice_spec.lua`
**Modules**: `lib/voices/midi.lua`, `lib/voices/recorder.lua`
**Approach**: Verify note-off→note-on ordering on retrigger, same-note retrigger, rapid-fire 16-step test, cleanup sends all_notes_off.

### Phase 3: Clock Stop/Start Idempotency (US-3)
**Target**: 4 new tests in `sequencer_spec.lua`
**Modules**: `lib/sequencer.lua`
**Approach**: Double-start, double-stop, rapid toggle 50x, stop→start resume. Uses mock clock to verify no duplicate coroutines.

### Phase 4: Pattern Save/Load Roundtrip (US-4)
**Target**: 5 new tests in `pattern_spec.lua`
**Modules**: `lib/pattern.lua`
**Approach**: Save/load with extended params, direction modes, all params×tracks, slot overwrite, empty slot load.

### Phase 5: Direction Mode Transitions (US-5)
**Target**: 4 new tests in `direction_spec.lua`
**Modules**: `lib/direction.lua`
**Approach**: Mid-sequence mode changes, single-step loops, pendulum→forward transitions. Pure unit tests on `direction.advance()`.

### Phase 6: Mute/Unmute Timing (US-6)
**Target**: 4 new tests in `sequencer_spec.lua`
**Modules**: `lib/sequencer.lua`
**Approach**: Mute→advance→unmute position check, double-mute, all-tracks-muted, muted playhead advancement.

### Phase 7: Scale Change Mid-Playback (US-7)
**Target**: 3 new tests in `scale_spec.lua` and `sequencer_spec.lua`
**Modules**: `lib/scale.lua`, `lib/sequencer.lua`
**Approach**: Rebuild scale_notes, step next note, verify new scale used. Test degree wrapping with shorter scale.

### Phase 8: Edge Cases & Integration (Spec Edge Cases)
**Target**: 8 new tests in `integration_spec.lua`
**Modules**: Cross-module
**Approach**: Cover all 8 edge cases from the spec's Edge Cases section. Each is a focused scenario test.

### Phase 9: Seamstress Load Test (US-8)
**Target**: 1 test (may be a separate script if seamstress runtime unavailable in CI)
**Modules**: `lib/app.lua`, full stack
**Approach**: Launch script in seamstress, verify init completes, run 30s, verify cleanup. This test is gated on seamstress availability.

### Phase 10: Regression Verification
**Target**: 0 new tests — validate all 442 + ~39 new tests pass
**Approach**: Run full suite, verify < 5s, verify zero failures. Fix any regressions introduced by edge-case fixes.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Edge case tests expose real bugs requiring code fixes | High | Medium | TDD discipline: fix minimally, verify no regressions |
| Seamstress load test flaky in CI | Medium | Low | Gate on seamstress availability; skip gracefully if absent |
| Test suite time exceeds 5s | Low | Low | 39 tests at ~0.006s each adds ~0.24s; budget is ample |
| Mocking clock behavior is fragile | Medium | Medium | Use existing mock patterns from sequencer_spec.lua |

## Dependencies

- **busted** test framework (already installed)
- **lua5.4** symlink at `/opt/homebrew/opt/lua/bin/lua5.4` (already configured)
- **seamstress v1.4.7** at `/opt/homebrew/opt/seamstress@1/bin/seamstress` (for US-8 only)
- No new dependencies required
