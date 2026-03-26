# Scratchpad — Specifier Iteration

## 2026-03-24: Quality Hardening Spec

Starting specification for the quality hardening feature. This is a testing/QA-focused feature, not a new user-facing behavior. The spec needs to enumerate specific edge case categories and define acceptance criteria for test coverage completeness.

Feature queue item: "Quality hardening: audit all 442 existing tests for gaps — verify loop boundary edge cases, note retrigger safety, clock stop/start idempotency, pattern save/load roundtrip fidelity, direction mode transitions, mute/unmute timing, scale change mid-playback."

Running /speckit.specify next.

## Result

Spec written to `specs/002-quality-hardening/spec.md`. 8 user stories covering:
1. Loop boundary edge cases (P1)
2. Note retrigger safety (P1)
3. Clock stop/start idempotency (P1)
4. Pattern save/load roundtrip (P2)
5. Direction mode transitions (P2)
6. Mute/unmute timing (P2)
7. Scale change mid-playback (P3)
8. Seamstress load test (P3)

Quality checklist: all items pass. No clarifications needed.
Branch: 002-quality-hardening. Emitting spec.ready.

## 2026-03-24: Quality Hardening Plan (Planner Hat)

Handled spec.ready event. Created implementation plan after deep gap analysis of all 442 tests.

### Gap Analysis Summary
Audited 6 core modules (track, sequencer, voice, pattern, direction, scale) against 8 user stories. Found 39 concrete test gaps across 7 categories + edge cases.

### Plan Structure
10 phases, each targeting a specific user story:
- Phase 1: Loop boundaries (6 tests) — track.advance(), set_loop()
- Phase 2: Note retrigger safety (4 tests) — MIDI voice note-off ordering
- Phase 3: Clock idempotency (4 tests) — start/stop/toggle
- Phase 4: Pattern roundtrip (5 tests) — extended params, direction, slots
- Phase 5: Direction transitions (4 tests) — mid-sequence mode changes
- Phase 6: Mute timing (4 tests) — playhead advancement while muted
- Phase 7: Scale change (3 tests) — degree wrapping, new scale on next note
- Phase 8: Edge cases (8 tests) — cross-module integration scenarios
- Phase 9: Seamstress load test (1 test) — init/run/cleanup
- Phase 10: Regression verification

### Constitution Check
All 5 principles pass. No violations. This feature IS Principle III (Test-First Correctness).

### Artifacts Generated
- plan.md — full implementation plan with phases and risk assessment
- research.md — gap analysis findings and 5 decisions
- data-model.md — no changes needed (test-only)
- quickstart.md — how to run tests

Emitting plan.ready.

## 2026-03-24: Quality Hardening Tasks (Task Maker Hat)

Handled plan.ready event. Generated tasks.md from plan + spec + research artifacts.

### Task Breakdown
43 total tasks across 11 phases:
- T001: Baseline verification (1 task)
- T002-T007: US-1 Loop Boundaries — 6 tests in track_spec.lua
- T008-T011: US-2 Retrigger Safety — 4 tests in voice_spec.lua
- T012-T015: US-3 Clock Idempotency — 4 tests in sequencer_spec.lua
- T016-T020: US-4 Pattern Roundtrip — 5 tests in pattern_spec.lua
- T021-T024: US-5 Direction Transitions — 4 tests in direction_spec.lua
- T025-T028: US-6 Mute Timing — 4 tests in sequencer_spec.lua
- T029-T031: US-7 Scale Change — 3 tests in scale_spec.lua + sequencer_spec.lua
- T032-T039: Edge Cases — 8 tests in integration_spec.lua
- T040: US-8 Seamstress Load — 1 test in seamstress_load_spec.lua (new file)
- T041-T043: Regression verification (3 tasks)

### TDD Compliance
Every task writes failing tests first. No separate "implementation" tasks — the test IS the deliverable. Bug fixes are minimal and inline per research.md Decision 4.

### Parallel Opportunities
6-way parallel: US-1 through US-5 + Edge Cases all touch different spec files. US-6/US-7 share sequencer_spec.lua with US-3, so schedule after.

### Verification
- All 8 user stories mapped to tasks ✓
- All 8 edge cases from spec covered (T032-T039) ✓
- All tasks have checkbox, ID, labels, file paths ✓
- [P] markers on independent tasks ✓
- 39 test cases + 1 seamstress load + 3 verification = 43 tasks ✓

Emitting tasks.ready.

## 2026-03-24: Quality Hardening Analysis (Analyzer Hat)

Handled tasks.ready event. Ran cross-artifact consistency analysis on spec.md, plan.md, tasks.md against constitution v1.2.0.

### Results
- **0 CRITICAL issues** — no constitution violations, no implementation-before-test tasks, no uncovered sequencing logic gaps
- **0 HIGH issues**
- **2 MEDIUM issues**: FR-002 direction-specific loop wrapping relies on existing test coverage (verify during implementation); T029 file placement ambiguous (use sequencer_spec.lua)
- **5 LOW issues**: phase numbering drift, intentional unit/integration duplication, minor underspecification in T040 and T039

### Coverage
- 12/12 functional requirements mapped to tasks (FR-002 partial — 96%)
- 8/8 edge cases covered (100%)
- 8/8 user stories covered (100%)
- 6/6 success criteria mapped
- 43/43 tasks mapped to requirements
- All 5 constitution principles pass

### Advisory Notes for Implementer
1. Before starting US-1, verify existing direction_spec tests cover reverse/pendulum loop boundary wrapping — if gap exists, add 1-2 subtests to T005
2. Place T029 (scale change next-note test) in sequencer_spec.lua
3. T040 seamstress load test should start the sequencer with at least one playing track to satisfy US-8 scenario 2

Emitting analysis.clean.

## 2026-03-24: Implementer Batch 1 — T001-T007

Handled analysis.clean event. Started TDD implementation.

### T001: Baseline Verification
- 442 tests, 0 failures, 0.25s — baseline green ✓

### T002-T007: US-1 Loop Boundary Edge Cases
All 6 tests added to `specs/track_spec.lua` in new "loop boundary edge cases" describe block:
- T002: single-step loop (loop_start == loop_end) — passes ✓
- T003: full-range loop (1-16) cycles 32 steps — passes ✓
- T004: loop boundary change mid-playback clamps pos — passes ✓
- T005: last-two-steps wrapping (15-16) — passes ✓
- T006: polymetric independence (8 params, different lengths, 100 steps) — passes ✓
- T007: set_loop rejects start > end — passes ✓ (existing test also covers this)

All 6 tests pass immediately — track.advance() and set_loop() already handle all these edge cases correctly. No bugs found. Suite: 448 tests, 0 failures.

Committed: `test: add loop boundary edge case tests (T002-T007)`

Emitting batch.done.
