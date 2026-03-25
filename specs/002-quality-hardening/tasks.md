# Tasks: Quality Hardening — Test Gap Audit & Edge Case Coverage

**Input**: Design documents from `/specs/002-quality-hardening/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: TDD is mandatory per constitution principle III. Every task writes failing tests first, then applies minimal fixes for any bugs exposed. The test IS the deliverable.

**Organization**: Tasks grouped by user story. Each story's tests can be implemented independently after baseline verification.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- All tests run with: `busted --no-auto-insulate specs/`
- TDD cycle: write failing test → verify failure → minimal fix (if needed) → verify pass → verify no regressions

---

## Phase 1: Setup (Baseline Verification)

**Purpose**: Confirm existing test suite is green before adding new tests

- [x] T001 Run `busted --no-auto-insulate specs/` and verify all 442 tests pass with 0 failures in under 5 seconds

**Checkpoint**: Baseline green — new test work can begin

---

## Phase 2: User Story 1 — Loop Boundary Edge Cases (Priority: P1) 🎯 MVP

**Goal**: Verify sequencer loops behave correctly at single-step, full-range, wrapping, and mid-playback boundary conditions for all param types

**Independent Test**: `busted --no-auto-insulate specs/track_spec.lua`

**Acceptance**: FR-001, FR-002 from spec. Scenarios 1-5 from US-1.

### Tests & Fixes for User Story 1

> **TDD**: Write each test, verify it FAILS, then fix if needed

- [x] T002 [P] [US1] Add single-step loop test (loop_start == loop_end) — advance N times, verify playhead stays on that step and returns same value each time. File: `specs/track_spec.lua` describe block: "advance" or new "loop boundary edge cases"
- [x] T003 [P] [US1] Add full-range loop test (1-16) — advance 32 times, verify playhead cycles through all 16 steps exactly twice. File: `specs/track_spec.lua`
- [x] T004 [US1] Add loop boundary change mid-playback test — set loop 1-8, position at step 3, change loop to 5-12, advance, verify playhead clamps to step 5. File: `specs/track_spec.lua`
- [x] T005 [US1] Add last-two-steps wrapping test (loop 15-16) — verify wrapping returns to step 15 not step 1. File: `specs/track_spec.lua`
- [x] T006 [US1] Add polymetric independence test — all 8 param types with different loop lengths on same track, advance 100 steps, verify each param wraps independently. File: `specs/track_spec.lua`
- [x] T007 [US1] Add loop_start > loop_end rejection test — verify explicit error or swap behavior. File: `specs/track_spec.lua`

**Checkpoint**: All loop boundary edge cases covered. Run `busted specs/track_spec.lua` — all pass, zero regressions.

---

## Phase 3: User Story 2 — Note Retrigger Safety (Priority: P1)

**Goal**: Verify MIDI voice sends note-off before note-on on retrigger, handles same-note retrigger, rapid sequences, and cleanup

**Independent Test**: `busted --no-auto-insulate specs/voice_spec.lua`

**Acceptance**: FR-003, FR-010 from spec. Scenarios 1-4 from US-2.

### Tests & Fixes for User Story 2

- [x] T008 [P] [US2] Add note-off ordering test — play C4, retrigger with D4 before duration expires, verify recorder events show note-off(C4) before note-on(D4). File: `specs/voice_spec.lua` under "midi voice" describe
- [x] T009 [P] [US2] Add same-note retrigger test — play C4, retrigger C4, verify note-off(C4) then fresh note-on(C4) in event log. File: `specs/voice_spec.lua`
- [x] T010 [US2] Add rapid 16-step all-trigger test — create track with triggers on all 16 steps, long duration, fast advance, verify every step has exactly one note-on preceded by note-off for any active note, zero orphaned notes at end. File: `specs/voice_spec.lua`
- [x] T011 [US2] Add cleanup all_notes_off test — start sequencer, play notes, call stop/cleanup, verify all_notes_off is sent and no active notes remain. File: `specs/voice_spec.lua`

**Checkpoint**: All retrigger safety scenarios covered. Run `busted specs/voice_spec.lua` — all pass.

---

## Phase 4: User Story 3 — Clock Stop/Start Idempotency (Priority: P1)

**Goal**: Verify double-start, double-stop, rapid toggle, and stop-then-start resume all behave correctly without crashes or resource leaks

**Independent Test**: `busted --no-auto-insulate specs/sequencer_spec.lua`

**Acceptance**: FR-004, FR-005 from spec. Scenarios 1-4 from US-3.

### Tests & Fixes for User Story 3

- [x] T012 [P] [US3] Add double-start coroutine test — start sequencer, start again, verify no duplicate clock coroutines and no doubled note output. File: `specs/sequencer_spec.lua` under "start/stop" describe
- [x] T013 [P] [US3] Add double-stop safety test — stop sequencer (already stopped), verify no error and state remains stopped. File: `specs/sequencer_spec.lua`
- [x] T014 [US3] Add rapid start/stop 50x toggle test — toggle start/stop 50 times, verify sequencer ends in consistent state with no orphaned coroutines or resource leaks. File: `specs/sequencer_spec.lua`
- [x] T015 [US3] Add stop-then-start resume test — start, advance to step 5, stop, start again, verify playhead resumes from step 5 (not reset to 1). File: `specs/sequencer_spec.lua`

**Checkpoint**: All clock idempotency scenarios covered. Run `busted specs/sequencer_spec.lua` — all pass.

---

## Phase 5: User Story 4 — Pattern Save/Load Roundtrip (Priority: P2)

**Goal**: Verify pattern save/load preserves all params, extended params, direction modes, and handles slot overwrite and empty slot load

**Independent Test**: `busted --no-auto-insulate specs/pattern_spec.lua`

**Acceptance**: FR-006 from spec. Scenarios 1-5 from US-4.

### Tests & Fixes for User Story 4

- [x] T016 [P] [US4] Add extended params roundtrip test — set non-default ratchet, alt_note, glide values on tracks, save, load, assert all extended param values match. File: `specs/pattern_spec.lua`
- [x] T017 [P] [US4] Add direction mode roundtrip test — set different direction modes (reverse, pendulum, drunk, random) on 4 tracks, save, load, assert each track's direction preserved. File: `specs/pattern_spec.lua`
- [x] T018 [US4] Add all-params-all-tracks comprehensive roundtrip test — set custom values for all 8 params × 4 tracks including loop boundaries and positions, save, load, deep-compare every field. File: `specs/pattern_spec.lua`
- [x] T019 [US4] Add slot overwrite test — save slot A, modify tracks, save slot B, load slot A, verify original state restored (modifications discarded). File: `specs/pattern_spec.lua`
- [x] T020 [US4] Add empty/default slot load test — load a slot that was never saved, verify no error and sequencer has default values. File: `specs/pattern_spec.lua`

**Checkpoint**: All pattern roundtrip scenarios covered. Run `busted specs/pattern_spec.lua` — all pass.

---

## Phase 6: User Story 5 — Direction Mode Transitions (Priority: P2)

**Goal**: Verify mid-sequence direction changes produce correct step sequences without crashes

**Independent Test**: `busted --no-auto-insulate specs/direction_spec.lua`

**Acceptance**: FR-007 from spec. Scenarios 1-4 from US-5.

### Tests & Fixes for User Story 5

- [x] T021 [P] [US5] Add forward-to-reverse mid-sequence test — play forward to step 8, change to reverse, verify next step is 7. File: `specs/direction_spec.lua`
- [x] T022 [P] [US5] Add pendulum-to-forward transition test — play in pendulum mode, change to forward mid-bounce, verify playhead continues forward from current position. File: `specs/direction_spec.lua`
- [x] T023 [US5] Add single-step loop direction change test — set single-step loop, change direction to each mode (reverse, pendulum, drunk, random), verify playhead stays on that step. File: `specs/direction_spec.lua`
- [x] T024 [US5] Add drunk mid-change boundary test — play forward, change to drunk, advance multiple times, verify all steps stay within loop bounds. File: `specs/direction_spec.lua`

**Checkpoint**: All direction transition scenarios covered. Run `busted specs/direction_spec.lua` — all pass.

---

## Phase 7: User Story 6 — Mute/Unmute Timing (Priority: P2)

**Goal**: Verify muted tracks advance playheads silently and unmute resumes from correct position

**Independent Test**: `busted --no-auto-insulate specs/sequencer_spec.lua`

**Acceptance**: FR-008 from spec. Scenarios 1-4 from US-6.

### Tests & Fixes for User Story 6

- [x] T025 [P] [US6] Add mute-advance-unmute position test — mute track at step 5, advance 3 steps, unmute, verify next note plays from step 8. File: `specs/sequencer_spec.lua` under "mute fix" describe
- [x] T026 [P] [US6] Add double-mute safety test — mute an already-muted track, verify it remains muted with no error. File: `specs/sequencer_spec.lua`
- [x] T027 [US6] Add all-tracks-muted test — mute all 4 tracks, play for several beats, verify zero notes output but all playheads advance correctly. File: `specs/sequencer_spec.lua`
- [x] T028 [US6] Add muted playhead position verification test — mute track, advance N steps, check each track's playhead position matches expected advance count. File: `specs/sequencer_spec.lua`

**Checkpoint**: All mute timing scenarios covered. Run `busted specs/sequencer_spec.lua` — all pass.

---

## Phase 8: User Story 7 — Scale Change Mid-Playback (Priority: P3)

**Goal**: Verify scale changes affect next note-on, handle degree wrapping with shorter scales, and do not retroactively re-pitch sounding notes

**Independent Test**: `busted --no-auto-insulate specs/scale_spec.lua` and `busted --no-auto-insulate specs/sequencer_spec.lua`

**Acceptance**: FR-009 from spec. Scenarios 1-3 from US-7.

### Tests & Fixes for User Story 7

- [x] T029 [P] [US7] Add scale change next-note test — play with major scale, change to minor, trigger next note, verify it uses minor scale quantization. File: `specs/sequencer_spec.lua` or `specs/scale_spec.lua` (whichever tests the sequencer→scale integration)
- [x] T030 [P] [US7] Add degree wrapping with shorter scale test — set note value to 7 (7th degree), change to a scale with fewer than 7 degrees, verify degree wraps correctly without error. File: `specs/scale_spec.lua`
- [x] T031 [US7] Add already-sounding notes not re-pitched test — play a note, change scale while note is sounding, verify no retroactive pitch change (only new note-ons use new scale). File: `specs/sequencer_spec.lua`

**Checkpoint**: All scale change scenarios covered. Run `busted specs/scale_spec.lua` and `busted specs/sequencer_spec.lua` — all pass.

---

## Phase 9: Edge Cases & Cross-Module Integration

**Goal**: Cover all 8 edge cases from spec's Edge Cases section with focused integration tests

**Independent Test**: `busted --no-auto-insulate specs/integration_spec.lua`

**Acceptance**: SC-005 from spec — 100% of edge cases have at least one covering test.

### Tests & Fixes for Edge Cases

- [x] T032 [P] Add loop_start > loop_end handling test — verify rejection or swap behavior in integration context. File: `specs/integration_spec.lua`
- [x] T033 [P] Add all-zero triggers track test — set all 16 trigger values to 0, advance, verify playhead still advances but no notes fire. File: `specs/integration_spec.lua`
- [x] T034 [P] Add load-never-saved-slot test — call pattern.load on a slot that was never saved, verify defaults loaded gracefully with no error. File: `specs/integration_spec.lua`
- [x] T035 [P] Add 4-tracks-random-direction-single-step test — set all 4 tracks to direction=random with single-step loops, advance multiple times, verify no crash. File: `specs/integration_spec.lua`
- [x] T036 [P] Add 1-degree scale test — set scale to single degree, play notes, verify all notes map to single pitch. File: `specs/integration_spec.lua`
- [x] T037 [P] Add extreme clock tempo test — set clock division to min and max values, advance sequencer, verify it still functions. File: `specs/integration_spec.lua`
- [x] T038 Add cleanup-mid-step test — trigger a note-on (with pending note-off), call cleanup, verify all notes are silenced via all_notes_off. File: `specs/integration_spec.lua`
- [x] T039 Add muted-track-grid-editing test — mute a track, edit step values, verify the data reflects edits even though no sound is produced. File: `specs/integration_spec.lua`

**Checkpoint**: All 8 edge cases from spec covered. Run `busted specs/integration_spec.lua` — all pass.

---

## Phase 10: User Story 8 — Seamstress Load Test (Priority: P3)

**Goal**: Verify the script initializes and cleans up without errors or resource leaks in real seamstress runtime

**Independent Test**: Requires seamstress v1.4.7 at `/opt/homebrew/opt/seamstress@1/bin/seamstress`

**Acceptance**: FR-012, SC-004 from spec. Scenarios 1-3 from US-8.

### Tests & Fixes for User Story 8

- [x] T040 Create seamstress load test — launch seamstress with `-s re_kriate`, verify init completes without errors, run for 30 seconds, verify cleanup runs and no resources are leaked. File: `specs/seamstress_load_spec.lua` (new file, gated on seamstress availability)

**Checkpoint**: Seamstress load test passes when runtime is available.

---

## Phase 11: Regression Verification & Polish

**Purpose**: Validate all new tests pass alongside existing 442, verify performance budget

- [x] T041 Run full test suite `busted --no-auto-insulate specs/` — verify all 442 + ~39 new tests pass with 0 failures
- [x] T042 Verify test suite completes in under 5 seconds (SC-006)
- [x] T043 Run `busted specs/` one final time and record exact test count, confirming SC-002 (at least 30 new tests added)

**Checkpoint**: All success criteria met. Feature complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — run immediately to verify baseline
- **US-1 through US-7 (Phases 2-8)**: All depend on Phase 1 baseline verification
  - US-1 through US-7 can proceed **in parallel** (different spec files, independent test areas)
  - Exception: US-6 and US-3 both touch `sequencer_spec.lua` — run sequentially or coordinate carefully
- **Edge Cases (Phase 9)**: Can start after Phase 1, but benefits from phases 2-8 completing first (any bug fixes in lib/ modules may affect edge case behavior)
- **US-8 Seamstress (Phase 10)**: Independent — requires seamstress runtime, not busted results
- **Regression (Phase 11)**: Depends on ALL previous phases completing

### User Story Dependencies

- **US-1 (P1)**: Independent — `track_spec.lua` only
- **US-2 (P1)**: Independent — `voice_spec.lua` only
- **US-3 (P1)**: Independent — `sequencer_spec.lua` only
- **US-4 (P2)**: Independent — `pattern_spec.lua` only
- **US-5 (P2)**: Independent — `direction_spec.lua` only
- **US-6 (P2)**: Shares `sequencer_spec.lua` with US-3 — schedule after US-3 or coordinate
- **US-7 (P3)**: Shares `sequencer_spec.lua` with US-3/US-6 and `scale_spec.lua` — schedule after US-3/US-6
- **Edge Cases**: Shares `integration_spec.lua` — independent from US tasks but may need lib/ fixes from earlier phases

### Within Each User Story

1. Write failing test(s) for the scenario
2. Verify tests fail (expected — edge case not yet covered)
3. If test exposes a real bug in lib/, apply minimal fix
4. Verify test passes
5. Run full module spec to verify no regressions
6. Commit: test + fix in same atomic commit

### Parallel Opportunities

**Maximum parallelism** (6 independent spec files):
```
Worker A: US-1 (track_spec.lua)        — T002-T007
Worker B: US-2 (voice_spec.lua)        — T008-T011
Worker C: US-3 (sequencer_spec.lua)    — T012-T015
Worker D: US-4 (pattern_spec.lua)      — T016-T020
Worker E: US-5 (direction_spec.lua)    — T021-T024
Worker F: Edge Cases (integration_spec.lua) — T032-T039
```

**After Worker C completes**: US-6 (T025-T028) and US-7 (T029-T031) can proceed on `sequencer_spec.lua`

**Sequential only**: US-8 (seamstress runtime), Regression (Phase 11)

---

## Parallel Example: US-1 Loop Boundaries

```bash
# These 4 tasks touch different test scenarios in the same file but have no code dependencies:
Task T002: "Single-step loop test in specs/track_spec.lua"
Task T003: "Full-range loop test in specs/track_spec.lua"
Task T005: "Last-two-steps wrapping test in specs/track_spec.lua"
Task T007: "loop_start > loop_end rejection test in specs/track_spec.lua"

# These 2 depend on understanding the existing advance/set_loop behavior:
Task T004: "Loop boundary change mid-playback test" (after T002/T003 confirm base behavior)
Task T006: "Polymetric independence test" (after T002/T003 confirm single-param loops work)
```

---

## Implementation Strategy

### MVP First (P1 User Stories Only)

1. Complete Phase 1: Baseline verification (T001)
2. Complete Phase 2: US-1 Loop Boundaries (T002-T007) — 6 tests
3. Complete Phase 3: US-2 Retrigger Safety (T008-T011) — 4 tests
4. Complete Phase 4: US-3 Clock Idempotency (T012-T015) — 4 tests
5. **STOP and VALIDATE**: 14 new tests covering all P1 stories, full suite green

### Incremental Delivery

1. P1 stories (14 tests) → validate → commit
2. P2 stories: US-4 Pattern (5) + US-5 Direction (4) + US-6 Mute (4) → 13 tests → validate → commit
3. P3 stories: US-7 Scale (3) + Edge Cases (8) → 11 tests → validate → commit
4. US-8 Seamstress (1 test) → validate → commit
5. Final regression run (T041-T043) → confirm all success criteria

---

## Notes

- All tests use recorder voice (no real MIDI) per research.md Decision 3
- Bug fixes are minimal and targeted — no refactoring per research.md Decision 4
- Seamstress load test is in separate file, gated on runtime availability per research.md Decision 2
- New tests go into existing spec files per research.md Decision 1 (except seamstress_load_spec.lua)
- Total: 43 tasks, 39 test cases + 1 seamstress load test + 3 verification tasks
