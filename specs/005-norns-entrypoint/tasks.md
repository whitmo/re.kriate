# Tasks: Norns Platform Entrypoint

**Input**: Design documents from `/specs/005-norns-entrypoint/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: TDD is NON-NEGOTIABLE per constitution principle III. Every implementation task is preceded by test tasks that write failing tests first. Tests live in `specs/norns_entrypoint_spec.lua`. Run with: `busted --no-auto-insulate specs/`

**Organization**: Tasks grouped by user story. 5 user stories from spec.md mapped to 7 phases.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files or independent test contexts)
- **[Story]**: Which user story (US1-US5) from spec.md
- Exact file paths included in all task descriptions

---

## Phase 1: Setup

**Purpose**: Baseline verification and test infrastructure

- [x] T001 Verify baseline: run `busted --no-auto-insulate specs/` confirms 536+ passing, 0 failures
- [x] T002 Create `specs/norns_entrypoint_spec.lua` with test helpers: mock norns APIs (params, metro, grid, screen, clock, util, nb) using patterns from existing `specs/test_helpers.lua`, require `lib/norns/nb_voice` and set up describe blocks for each user story

---

## Phase 2: User Story 1 — Script Initialization (Priority: P1) 🎯 MVP

**Goal**: Norns user loads re.kriate; script initializes with 4 nb voices, monome grid, screen metro at 15fps, and all params registered.

**Independent Test**: Call init() in tests, verify ctx has 4 voices, grid_provider is "monome", screen_metro is running.

**Covers**: FR-001, FR-002, FR-010, SC-001, SC-002

### Tests for US1

> **Write these tests FIRST — they MUST FAIL before implementation (T006)**

- [x] T003 [US1] Write test: init() creates ctx with exactly 4 nb voice instances (ctx.voices[1..4] each have play_note, note_on, note_off, all_notes_off methods) in `specs/norns_entrypoint_spec.lua`
- [x] T004 [P] [US1] Write test: init() passes `grid_provider = "monome"` to app.init config — spy on app.init and assert config.grid_provider == "monome" in `specs/norns_entrypoint_spec.lua`
- [x] T005 [P] [US1] Write test: init() starts a screen metro at 15fps (ctx.screen_metro exists and metro.init was called with 1/15 interval) in `specs/norns_entrypoint_spec.lua`

### Implementation for US1

- [x] T006 [US1] Enhance init() in `re_kriate.lua`: add `grid_provider = "monome"` to app.init config, create screen_metro via metro.init at 1/15 interval that calls redraw(), store metro on ctx.screen_metro, start metro

**Checkpoint**: init() creates full context with voices, monome grid, and screen refresh

---

## Phase 3: User Story 2 — Key and Encoder Interaction (Priority: P1)

**Goal**: K2 play/stop, K3 reset, E1 track select, E2 page select — all delegate to app module.

**Independent Test**: Call key(n,z) and enc(n,d) in tests, verify app module functions are called with correct args.

**Covers**: FR-003, FR-004, SC-002

### Tests for US2 (Verification — delegation already exists)

> **These tests verify existing behavior. They may pass immediately — that confirms correctness.**

- [x] T007 [P] [US2] Write test: key(n, z) delegates to app.key(ctx, n, z) for all key combinations (K2 press/release, K3 press/release) in `specs/norns_entrypoint_spec.lua`
- [x] T008 [P] [US2] Write test: enc(n, d) delegates to app.enc(ctx, n, d) for encoders 1-3 with positive and negative deltas in `specs/norns_entrypoint_spec.lua`
- [x] T009 [P] [US2] Write test: redraw() delegates to app.redraw(ctx) in `specs/norns_entrypoint_spec.lua`

**Checkpoint**: All 5 norns hooks verified to delegate correctly to app module

---

## Phase 4: User Story 3 — Glide Support via nb Voices (Priority: P2)

**Goal**: nb_voice.set_portamento(time) passes glide instructions to nb player's set_slew, no-oping gracefully when unsupported.

**Independent Test**: Create nb_voice, call set_portamento(time), verify player:set_slew called or gracefully skipped.

**Covers**: FR-006, SC-003

### Tests for US3

> **Write these tests FIRST — they MUST FAIL before implementation (T013)**

- [x] T010 [P] [US3] Write test: set_portamento(0.5) calls player:set_slew(0.5) when player supports it — mock params:lookup_param to return a player with set_slew spy in `specs/norns_entrypoint_spec.lua`
- [x] T011 [P] [US3] Write test: set_portamento(0.5) no-ops without error when player lacks set_slew method in `specs/norns_entrypoint_spec.lua`
- [x] T012 [P] [US3] Write test: set_portamento(0.5) no-ops without error when get_player() returns nil in `specs/norns_entrypoint_spec.lua`

### Implementation for US3

- [x] T013 [US3] Add set_portamento(time) method to nb_voice.new() return table in `lib/norns/nb_voice.lua`: call self param lookup → get_player → player:set_slew(time) if player and player.set_slew exist, else no-op

**Checkpoint**: nb_voice has full voice interface parity (play_note, note_on, note_off, all_notes_off, set_portamento)

---

## Phase 5: User Story 4 — Clean Shutdown (Priority: P2)

**Goal**: cleanup() stops sequencer, silences voices, stops screen metro, delegates to app.cleanup. Guards against nil ctx.

**Independent Test**: Call cleanup() after init(), verify screen_metro stopped, app.cleanup called, nil ctx handled.

**Covers**: FR-005, SC-002

### Tests for US4

> **Write these tests FIRST — they MUST FAIL before implementation (T017)**

- [x] T014 [P] [US4] Write test: cleanup() stops ctx.screen_metro (screen_metro:stop() called) in `specs/norns_entrypoint_spec.lua`
- [x] T015 [P] [US4] Write test: cleanup() delegates to app.cleanup(ctx) in `specs/norns_entrypoint_spec.lua`
- [x] T016 [P] [US4] Write test: cleanup() with nil ctx does not error (guard against nil ctx before any operations) in `specs/norns_entrypoint_spec.lua`

### Implementation for US4

- [x] T017 [US4] Enhance cleanup() in `re_kriate.lua`: add nil ctx guard at top, stop ctx.screen_metro before app.cleanup(ctx)

**Checkpoint**: Script unload is safe, resource-leak-free, and handles edge cases

---

## Phase 6: User Story 5 — Logging Integration (Priority: P3)

**Goal**: init() calls log.session_start(), cleanup() calls log.close() after all other cleanup. Grid key callback wrapping handled by app.lua (Decision 5 in research.md).

**Independent Test**: Spy on log.session_start and log.close, verify called in correct lifecycle order.

**Covers**: FR-007, FR-008, SC-002

### Tests for US5

> **Write these tests FIRST — they MUST FAIL before implementation (T020)**

- [x] T018 [P] [US5] Write test: init() calls log.session_start() in `specs/norns_entrypoint_spec.lua`
- [x] T019 [P] [US5] Write test: cleanup() calls log.close() after app.cleanup(ctx) in `specs/norns_entrypoint_spec.lua`

### Implementation for US5

- [x] T020 [US5] Add log.session_start() at end of init() and log.close() at end of cleanup() (after app.cleanup and screen_metro stop) in `re_kriate.lua`

**Checkpoint**: Logging lifecycle active for diagnostics on norns platform

---

## Phase 7: Verification & Edge Cases

**Purpose**: Structural compliance, exclusion checks, edge cases, and full regression

**Covers**: FR-009, FR-010, SC-004, SC-005, SC-006, all 5 edge cases

- [x] T021 [P] Write structural check test: re_kriate.lua source defines exactly 5 globals (init, redraw, key, enc, cleanup) — parse file for `^function ` declarations in `specs/norns_entrypoint_spec.lua`
- [x] T022 [P] Write exclusion check test: re_kriate.lua does NOT reference OSC, sprite, keyboard, simulated grid, or MIDI channel params (FR-009) — scan file content for forbidden terms in `specs/norns_entrypoint_spec.lua`
- [x] T023 [P] Write edge case test: no grid connected — monome grid.connect() returns stub device, init completes without error, ctx exists in `specs/norns_entrypoint_spec.lua`
- [x] T024 [P] Write edge case test: rapid script switching — init() → cleanup() → init() cycle completes without error, second ctx is independent in `specs/norns_entrypoint_spec.lua`
- [x] T025 Full regression: run `busted --no-auto-insulate specs/` — all 536+ existing tests pass PLUS new norns entrypoint tests (SC-004: at least 10 new, SC-005: 0 regressions)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **US1 (Phase 2)**: Depends on T002 (test file creation)
- **US2 (Phase 3)**: Depends on T002 — **can run in parallel with US1**
- **US3 (Phase 4)**: Depends on T002 — **can run in parallel with US1/US2** (different file: lib/norns/nb_voice.lua)
- **US4 (Phase 5)**: Depends on T006 (screen metro must exist to test stopping it)
- **US5 (Phase 6)**: Depends on T017 (cleanup order matters — log.close is last)
- **Verification (Phase 7)**: Depends on all implementation tasks complete (T006, T013, T017, T020)

### User Story Dependencies

- **US1 (P1)**: Foundational — no story dependencies
- **US2 (P1)**: No story dependencies (delegation already exists)
- **US3 (P2)**: No story dependencies (independent file: nb_voice.lua)
- **US4 (P2)**: Depends on US1 (screen_metro created in init)
- **US5 (P3)**: Depends on US4 (cleanup ordering: app.cleanup → screen_metro stop → log.close)

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Implementation task makes tests pass (red → green)
- Commit after each test group (red) and implementation (green)

### Parallel Opportunities

- **Phase 2 ∥ Phase 3 ∥ Phase 4**: US1 (re_kriate.lua init), US2 (verification tests), US3 (nb_voice.lua) touch different files
- **T003/T004/T005**: US1 test tasks are [P] (independent test cases)
- **T007/T008/T009**: US2 test tasks are [P] (independent test cases)
- **T010/T011/T012**: US3 test tasks are [P] (independent test cases)
- **T014/T015/T016**: US4 test tasks are [P] (independent test cases)
- **T018/T019**: US5 test tasks are [P] (independent test cases)
- **T021/T022/T023/T024**: Verification tests are all [P]

---

## Parallel Example: Phases 2-4

```bash
# After T002 (test file created), launch US1/US2/US3 test tasks in parallel:

# Worker A (US1 tests → T003, T004, T005):
Task: "Write init tests in specs/norns_entrypoint_spec.lua (US1 describe block)"

# Worker B (US2 tests → T007, T008, T009):
Task: "Write delegation tests in specs/norns_entrypoint_spec.lua (US2 describe block)"

# Worker C (US3 tests → T010, T011, T012):
Task: "Write set_portamento tests in specs/norns_entrypoint_spec.lua (US3 describe block)"
```

---

## Implementation Strategy

### MVP First (US1 + US2 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: US1 — init with voices, grid, screen metro (T003-T006)
3. Complete Phase 3: US2 — verify delegation (T007-T009)
4. **STOP and VALIDATE**: Script initializes and responds to input

### Incremental Delivery

1. Setup + US1 + US2 → Script loads and responds (MVP)
2. Add US3 → Glide/portamento works via nb voices
3. Add US4 → Clean shutdown with screen metro stop
4. Add US5 → Logging for diagnostics
5. Verification → Structural compliance and regression-free

---

## Notes

- [P] tasks = different files or independent test contexts, no dependencies
- [Story] label maps task to specific user story for traceability
- All tests in single file `specs/norns_entrypoint_spec.lua` using describe blocks per story
- Only 2 source files modified: `re_kriate.lua`, `lib/norns/nb_voice.lua`
- FR-008 (grid key log.wrap) already handled by app.lua (research Decision 5) — no task needed
- US2 tests may pass immediately since delegation exists — this is expected verification
- Screen metro pattern follows seamstress.lua's ctx.screen_metro approach
