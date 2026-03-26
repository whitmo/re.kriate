# Tasks: Swing/Shuffle Per Track

**Input**: Design documents from `specs/007-swing-shuffle/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: TDD is mandatory per constitution principle III. Every implementation task has a preceding test task that writes failing tests first. Tests live in `specs/` directory. Run with: `busted --no-auto-insulate specs/`

**Organization**: Tasks grouped by user story. 4 user stories (2 P1, 2 P2), 3 files modified, 1 new test file.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files or independent describe blocks, no data dependencies)
- **[Story]**: Which user story this task belongs to (US1-US4)
- All test tasks target `specs/swing_shuffle_spec.lua`
- Implementation tasks target `lib/track.lua`, `lib/sequencer.lua`, or `lib/app.lua`

---

## Phase 1: Setup

**Purpose**: Create test file and scaffold for swing/shuffle feature

- [x] T001 Create test file scaffold with require stubs and describe structure in specs/swing_shuffle_spec.lua

---

## Phase 2: Foundational (Track Data Model)

**Purpose**: Add swing field to track model — BLOCKS all user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Test: new_track() includes swing = 0 default for all tracks (RED) in specs/swing_shuffle_spec.lua
- [x] T003 Impl: Add `swing = 0` field to new_track() table in lib/track.lua (GREEN)

**Checkpoint**: Track model has swing field — user story implementation can begin

---

## Phase 3: User Story 1 — Per-Track Swing Timing (Priority: P1) MVP

**Goal**: Sequencer alternates step durations within pairs based on swing amount, producing groove feel

**Independent Test**: Verify swing_duration() returns correct ratios at 0%/50%/100% and track_clock uses swing timing with step counter

### Tests for US1

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T004 [P] [US1] Test: swing_duration() pure function — 0% even split, 50% triplet (2:1), 100% max offset with min floor, fast path shortcut in specs/swing_shuffle_spec.lua
- [x] T006 [US1] Test: track_clock integrates step counter and swing timing — odd/even alternation, independent per-track swing values in specs/swing_shuffle_spec.lua

### Implementation for US1

- [x] T005 [P] [US1] Impl: Add MIN_SWING_RATIO constant (0.01) and swing_duration(div, swing, is_odd) function in lib/sequencer.lua (GREEN for T004)
- [x] T007 [US1] Impl: Modify track_clock() — add local step_count, compute is_odd, replace clock.sync(div) with clock.sync(swing_duration(div, track.swing or 0, is_odd)) in lib/sequencer.lua (GREEN for T006)

**Checkpoint**: Swing timing works end-to-end — core musical feature is functional

---

## Phase 4: User Story 2 — Swing Parameter Control (Priority: P1)

**Goal**: Expose per-track swing parameter (0-100) in the params system

**Independent Test**: Set swing param, verify track.swing field updates

### Tests for US2

- [x] T008 [P] [US2] Test: per-track swing_N params registered with range 0-100, default 0, set_action updates ctx.tracks[t].swing in specs/swing_shuffle_spec.lua

### Implementation for US2

- [x] T009 [US2] Impl: Add per-track swing_N number params with set_action in lib/app.lua (after direction params block) (GREEN for T008)

**Checkpoint**: Swing is user-controllable via param system

---

## Phase 5: User Story 3 — Swing Preserved in Patterns (Priority: P2)

**Goal**: Verify swing round-trips through pattern save/load (no implementation needed — deep_copy handles it)

**Independent Test**: Save pattern with swing values, load it, verify restoration

### Verification Tests for US3

- [x] T010 [P] [US3] Test: pattern save/load round-trip preserves per-track swing values in specs/swing_shuffle_spec.lua
- [x] T011 [P] [US3] Test: backward compatibility — loading pattern without swing field defaults tracks to 0 in specs/swing_shuffle_spec.lua

**Checkpoint**: Patterns preserve groove settings across save/load cycles

---

## Phase 6: User Story 4 — Swing with Other Timing Features (Priority: P2)

**Goal**: Verify swing composes correctly with ratchet, division, direction, and mute (no implementation needed)

**Independent Test**: Enable swing alongside each feature, verify no interference

### Verification Tests for US4

- [x] T012 [P] [US4] Test: swing with ratchet — subdivisions occur within swing-adjusted step duration in specs/swing_shuffle_spec.lua
- [x] T013 [P] [US4] Test: swing with non-default division — offsets scale proportionally in specs/swing_shuffle_spec.lua
- [x] T014 [P] [US4] Test: swing with pendulum direction — direction affects step order, swing affects timing independently in specs/swing_shuffle_spec.lua
- [x] T015 [P] [US4] Test: muted track with swing advances step counter, maintains alignment on unmute in specs/swing_shuffle_spec.lua

**Checkpoint**: Swing composes with all existing timing features without interference

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Regression check and validation

- [x] T016 Run full test suite regression — `busted specs/` passes all existing + new swing tests (SC-001)
- [x] T017 Validate quickstart.md scenarios — verify key swing values table (0/50/75/100) matches implementation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on T003 (track.swing field exists)
- **US2 (Phase 4)**: Depends on T003 (track.swing field exists), can run parallel with US1
- **US3 (Phase 5)**: Depends on T003 (track.swing for pattern deep_copy)
- **US4 (Phase 6)**: Depends on T007 (track_clock swing integration)
- **Polish (Phase 7)**: Depends on all phases complete

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Pure function tests before integration tests
- Implementation follows test failure verification

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — no other story dependencies
- **US2 (P1)**: Depends on Foundational only — independent of US1
- **US3 (P2)**: Depends on Foundational only — verification tests pass once swing field exists
- **US4 (P2)**: Depends on US1 complete (T007) — needs track_clock swing integration

### Parallel Opportunities

#### Swarm 1: Test Writing (after T001)

```
T002 (foundational test, specs/swing_shuffle_spec.lua — describe "track swing default")
T004 (US1 swing_duration test, specs/swing_shuffle_spec.lua — describe "swing_duration")
T008 (US2 param test, specs/swing_shuffle_spec.lua — describe "swing params")
```

All write independent describe blocks to the test file. No data dependencies.

#### Swarm 2: Implementation (after Swarm 1 merged)

```
T003 (track model, lib/track.lua)
T005 (swing_duration, lib/sequencer.lua)
T009 (swing params, lib/app.lua)
```

Three different files, no cross-dependencies. Each makes its preceding test GREEN.

#### Swarm 3: Integration Test + Verification (after Swarm 2 merged)

```
T006 (US1 track_clock integration test, specs/swing_shuffle_spec.lua)
T010 (US3 pattern round-trip test, specs/swing_shuffle_spec.lua)
T011 (US3 backward compat test, specs/swing_shuffle_spec.lua)
```

T006 writes RED test for track_clock. T010/T011 write verification tests (expected GREEN).

#### Swarm 4: Final Implementation + Composition Tests (after Swarm 3 merged)

```
T007 (track_clock impl, lib/sequencer.lua)
T012 (US4 ratchet test, specs/swing_shuffle_spec.lua)
T013 (US4 division test, specs/swing_shuffle_spec.lua)
T014 (US4 direction test, specs/swing_shuffle_spec.lua)
T015 (US4 mute test, specs/swing_shuffle_spec.lua)
```

T007 modifies sequencer.lua. T012-T015 write independent verification tests.

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002-T003)
3. Complete Phase 3: US1 (T004-T007)
4. **STOP and VALIDATE**: `busted specs/swing_shuffle_spec.lua` — swing timing works
5. All core musical behavior is functional

### Incremental Delivery

1. Setup + Foundational -> swing field exists
2. US1 -> swing timing works -> **Core groove feel available**
3. US2 -> param control -> **User can adjust swing**
4. US3 -> pattern verification -> **Swing persists in patterns**
5. US4 -> composition verification -> **Swing plays nice with everything**
6. Polish -> regression + validation -> **Ship it**

### Parallel Strategy (Swarm Dispatch)

With worktree isolation:

1. Swarm 1: Write all test scaffolds in parallel (T002 + T004 + T008)
2. Swarm 2: Implement all three files in parallel (T003 + T005 + T009)
3. Swarm 3: Integration tests + verification tests (T006 + T010 + T011)
4. Swarm 4: Final impl + composition tests (T007 + T012-T015)
5. Sequential: Polish (T016-T017)

**Estimated total**: ~30-50 lines of implementation across 3 files, 15-20 tests in 1 test file

---

## Requirement Traceability

| Requirement | Tasks | Verified By |
|-------------|-------|-------------|
| FR-001: Per-track swing 0-100 | T002, T003 | T002 |
| FR-002: Swing 0 = even spacing | T004, T005 | T004 (0% case) |
| FR-003: Alternating durations | T004, T005, T006, T007 | T004, T006 |
| FR-004: Triplet feel at 50% | T004, T005 | T004 (50% case) |
| FR-005: Max offset with floor | T004, T005 | T004 (100% case) |
| FR-006: Independent per track | T006, T007 | T006 (two-track test) |
| FR-007: Param system exposure | T008, T009 | T008 |
| FR-008: Default 0 on init | T002, T003, T008 | T002, T008 |
| FR-009: Pattern preservation | T010, T011 | T010, T011 |
| FR-010: Composition correctness | T012-T015 | T012-T015 |
| SC-001: No regressions | T016 | T016 |
| SC-002: 2:1 ratio at 50% | T004 | T004 |
| SC-003: Independent per track | T006 | T006 |
| SC-004: Composition correct | T012-T015 | T012-T015 |
| SC-005: No platform files | — | Verify via git diff |

---

## Notes

- [P] tasks = different files or independent describe blocks, no data dependencies
- [Story] label maps task to specific user story for traceability
- US3 and US4 are verification-only — no implementation code needed
- Pattern round-trip works via deep_copy; backward compat via `track.swing or 0` fallback
- Step counter is local to track_clock coroutine (resets on stop/start)
- Swing formula: `odd_dur = pair / (2 - S/100)`, verified at 0%/50%/100%
