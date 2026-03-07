# Tasks: Complete Seamstress Kria Sequencer

**Input**: Design documents from `/specs/001-seamstress-kria-features/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: TDD is NON-NEGOTIABLE per constitution principle III. Every task includes failing tests before implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing. User stories 1-4 (P1) are already implemented -- tasks focus on test coverage verification and missing features.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US11)
- Include exact file paths in descriptions

---

## Phase 1: Setup (CI + Project Verification)

**Purpose**: Establish CI pipeline and verify existing test infrastructure

- [x] T001 Create GitHub Actions CI workflow in .github/workflows/test.yml (Lua 5.4, luarocks, busted, luac -p lint)
- [x] T002 Verify all 87 existing tests pass in CI by pushing to branch and confirming green status
- [x] T003 [P] Add grid_ui tests covering existing functionality in specs/grid_ui_spec.lua (trigger page display, value page display, nav_key, grid_key, loop editing)
- [x] T004 [P] Add scale module tests covering build_scale and to_midi in specs/scale_spec.lua

**Checkpoint**: CI green, all existing lib/ modules have at least basic test coverage

---

## Phase 2: Foundational (New Modules + Extended Track Model)

**Purpose**: Create independent modules that multiple user stories depend on. MUST complete before Wave 2 stories.

- [x] T005 [P] Write failing tests for direction.advance() with 5 modes (forward, reverse, pendulum, drunk, random) in specs/direction_spec.lua
- [x] T006 [P] Implement lib/direction.lua: M.MODES table, M.advance(param, direction) respecting loop bounds, pendulum state via param.advancing_forward
- [x] T007 [P] Write failing tests for pattern save/load/roundtrip in specs/pattern_spec.lua
- [x] T008 [P] Implement lib/pattern.lua: M.new_slots(), M.save(ctx, slot), M.load(ctx, slot), M.is_populated(patterns, slot) with deep-copy
- [x] T009 [P] Write failing tests for extended track params (ratchet, alt_note, glide defaults, direction field) in specs/track_spec.lua
- [x] T010 [P] Add ratchet/alt_note/glide to PARAM_NAMES, add CORE_PARAMS/EXTENDED_PARAMS lists, add direction field in lib/track.lua
- [x] T011 [P] Write failing tests for voice set_portamento(time) CC messages in specs/voice_spec.lua
- [x] T012 [P] Add set_portamento(time) to lib/voices/midi.lua (CC 5 + CC 65) and lib/voices/recorder.lua (capture event)

**Checkpoint**: Four new/updated modules with full test coverage. All tests green. Foundation ready for integration.

---

## Phase 3: US1-4 -- Core Sequencer Verification (Priority: P1) MVP

**Goal**: Verify existing P1 functionality has comprehensive test coverage. These stories are already implemented -- tasks add missing tests and fix any gaps found.

**Independent Test**: `busted specs/` -- all core sequencer behavior (playback, trigger editing, value pages, navigation) passes.

### Tests for US1-4

- [ ] T013 [P] [US1] Add failing tests for sequencer start/stop MIDI silence (CC 123 on stop) in specs/sequencer_spec.lua
- [ ] T014 [P] [US2] Add failing tests for trigger page grid display (brightness levels, playhead, loop region) in specs/grid_ui_spec.lua
- [ ] T015 [P] [US3] Add failing tests for value page grid display and editing (note/octave/duration/velocity bar graphs) in specs/grid_ui_spec.lua
- [ ] T016 [P] [US4] Add failing tests for nav_key track/page selection and loop modifier hold in specs/grid_ui_spec.lua

### Implementation for US1-4

- [ ] T017 [US1] Fix any test failures found in T013 (sequencer stop behavior) in lib/sequencer.lua
- [ ] T018 [US2] Fix any test failures found in T014 (trigger display) in lib/grid_ui.lua
- [ ] T019 [US3] Fix any test failures found in T015 (value page display/editing) in lib/grid_ui.lua
- [ ] T020 [US4] Fix any test failures found in T016 (navigation) in lib/grid_ui.lua

**Checkpoint**: P1 stories fully tested and verified. MVP functional.

---

## Phase 4: US11 -- Extended Page Toggle (Priority: P2)

**Goal**: Fix root cause of "secondary pages don't work" by adding double-press toggle between primary/extended pages (trigger/ratchet, note/alt_note, octave/glide).

**Independent Test**: Press trigger nav button twice -> page switches to ratchet. Press different page -> clears extended. Verify on grid and keyboard.

### Tests for US11

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T021 [P] [US11] Write failing test: press trigger page key twice toggles to ratchet in specs/grid_ui_spec.lua
- [x] T022 [P] [US11] Write failing test: press ratchet key again toggles back to trigger in specs/grid_ui_spec.lua
- [x] T023 [P] [US11] Write failing test: switching to different page clears extended state in specs/grid_ui_spec.lua
- [x] T024 [P] [US11] Write failing test: note double-press toggles to alt_note, octave to glide in specs/grid_ui_spec.lua
- [x] T025 [P] [US11] Write failing test: duration/velocity have no extended page (no toggle) in specs/grid_ui_spec.lua

### Implementation for US11

- [x] T026 [US11] Add EXTENDED_PAGES map and extended_page toggle logic to nav_key in lib/grid_ui.lua
- [x] T027 [US11] Add extended_page field to ctx initialization in lib/app.lua
- [x] T028 [US11] Update redraw() to dispatch to extended page draw functions in lib/grid_ui.lua

**Checkpoint**: Extended page toggle works on grid. Root cause of "secondary pages don't work" resolved.

---

## Phase 5: US5 -- Screen UI Display (Priority: P2)

**Goal**: Show per-track step positions, extended page indicator, and color-coded status on seamstress screen.

**Independent Test**: Run app, verify screen shows track positions, current page (including extended), play state, mute state.

### Tests for US5

- [ ] T029 [P] [US5] Write failing tests for screen_ui.redraw showing per-track step positions in specs/screen_ui_spec.lua
- [ ] T030 [P] [US5] Write failing test for extended page indicator display in specs/screen_ui_spec.lua

### Implementation for US5

- [ ] T031 [US5] Enhance lib/seamstress/screen_ui.lua: per-track step positions (step N/loop_end), extended page indicator, color coding
- [ ] T032 [US5] Update lib/app.lua M.redraw to call screen_ui.redraw for seamstress platform

**Checkpoint**: Screen UI shows comprehensive sequencer state.

---

## Phase 6: US6+7 -- Clock Division + Scale Quantization (Priority: P2)

**Goal**: Verify existing clock division and scale quantization have test coverage.

**Independent Test**: Set different divisions on two tracks, verify advancement rates differ. Change scale, verify note output changes.

### Tests for US6+7

- [ ] T033 [P] [US6] Write failing tests for per-track clock division affecting step rate in specs/sequencer_spec.lua
- [ ] T034 [P] [US7] Write failing tests for scale quantization: root + scale -> correct MIDI notes in specs/scale_spec.lua

### Implementation for US6+7

- [ ] T035 [US6] Fix any test failures found in T033 (clock division) in lib/sequencer.lua
- [ ] T036 [US7] Fix any test failures found in T034 (scale quantization) in lib/scale.lua

**Checkpoint**: Clock division and scale quantization fully tested.

---

## Phase 7: US8 -- Direction Modes (Priority: P3)

**Goal**: Add forward/reverse/pendulum/drunk/random direction modes per track, integrated into sequencer.

**Independent Test**: Set track direction to reverse, step 8 times in a loop 1-8, verify positions go 8,7,6,5,4,3,2,1.

### Tests for US8

- [x] T037 [P] [US8] Write failing test: sequencer uses direction.advance for non-forward tracks in specs/sequencer_spec.lua
- [x] T038 [P] [US8] Write failing test: reverse direction produces 8,7,6,5,4,3,2,1 sequence in specs/sequencer_spec.lua
- [x] T039 [P] [US8] Write failing test: pendulum direction bounces at loop boundaries in specs/sequencer_spec.lua

### Implementation for US8

- [x] T040 [US8] Integrate direction.advance() into sequencer.step_track for all param advances in lib/sequencer.lua
- [ ] T041 [US8] Add direction mode selection to params (per-track) in lib/app.lua

**Checkpoint**: Direction modes work end-to-end. Forward/reverse/pendulum/drunk/random all verified.

---

## Phase 8: US9 -- Track Mute Fix (Priority: P3)

**Goal**: Muted tracks advance playheads silently (match original kria behavior) instead of skipping advancement entirely.

**Independent Test**: Mute track, step N times, unmute -- playhead is at expected advanced position, not stuck at start.

### Tests for US9

- [x] T042 [US9] Write failing test: muted track advances playheads but fires no notes in specs/sequencer_spec.lua

### Implementation for US9

- [x] T043 [US9] Change step_track to advance all params on muted tracks but skip note output in lib/sequencer.lua

**Checkpoint**: Muted tracks advance silently. Unmuting at correct beat position works.

---

## Phase 9: US10 -- Pattern Storage and Recall (Priority: P3)

**Goal**: Save/load all track state to 16 pattern slots.

**Independent Test**: Save pattern, modify tracks, load pattern -- all track data restored to saved state.

### Tests for US10

- [x] T044 [P] [US10] Write failing test: save current tracks to slot, verify deep copy independence in specs/pattern_spec.lua
- [x] T045 [P] [US10] Write failing test: load from slot restores all track state in specs/pattern_spec.lua

### Implementation for US10

- [x] T046 [US10] Add ctx.patterns initialization (16 slots) to lib/app.lua
- [x] T047 [US10] Wire pattern save/load to keyboard shortcuts or params in lib/seamstress/keyboard.lua

**Checkpoint**: Pattern storage works. Save/load verified via tests.

---

## Phase 10: US12-14 -- Extended Pages: Glide, Ratchet, Alt-Note (Priority: P3)

**Goal**: Implement the three extended parameter pages (glide, ratchet, alt-note) with grid display, editing, and sequencer integration.

**Independent Test**: Toggle to ratchet page, set ratchet=3 on step 5, play -- 3 notes fire at step 5. Toggle to alt-note, set value, verify combined pitch. Toggle to glide, set value, verify portamento CC.

### Tests for US12 (Glide)

- [ ] T048 [P] [US12] Write failing test: glide page displays bar graph for glide param in specs/grid_ui_spec.lua
- [x] T049 [P] [US12] Write failing test: sequencer sends portamento CC before notes with non-zero glide in specs/sequencer_spec.lua

### Tests for US13 (Ratchet)

- [ ] T050 [P] [US13] Write failing test: ratchet page displays bar graph for ratchet param in specs/grid_ui_spec.lua
- [x] T051 [P] [US13] Write failing test: ratchet value 3 produces 3 evenly-spaced notes per step in specs/sequencer_spec.lua

### Tests for US14 (Alt-Note)

- [ ] T052 [P] [US14] Write failing test: alt_note page displays bar graph for alt_note param in specs/grid_ui_spec.lua
- [x] T053 [P] [US14] Write failing test: alt_note combines additively with note degree modulo scale length in specs/sequencer_spec.lua

### Implementation for US12-14

- [x] T054 [US12] Add glide value handling to sequencer.step_track: call voice:set_portamento before play_note in lib/sequencer.lua
- [x] T055 [US13] Add ratchet subdivision logic to sequencer.step_track: fire N notes via nested clock.run in lib/sequencer.lua (depends on T054)
- [x] T056 [US14] Add alt_note additive pitch computation to sequencer.step_track in lib/sequencer.lua (depends on T055)
- [ ] T057 [US12] Add draw_glide_page to grid_ui.lua and wire into redraw dispatch in lib/grid_ui.lua
- [ ] T058 [US13] Add draw_ratchet_page to grid_ui.lua and wire into redraw dispatch in lib/grid_ui.lua
- [ ] T059 [US14] Add draw_alt_note_page to grid_ui.lua and wire into redraw dispatch in lib/grid_ui.lua
- [ ] T060 [US12] Update grid_key to handle value editing on extended pages (ratchet, alt_note, glide) in lib/grid_ui.lua

**Checkpoint**: All extended pages display, edit, and produce correct sequencer output.

---

## Phase 11: US11 Keyboard + Polish

**Goal**: Keyboard extended page toggle + cross-cutting cleanup.

**Independent Test**: Press 'q' twice on keyboard -> ratchet page. Press 'w' -> note page (clears extended).

### Tests

- [x] T061 [P] [US11] Write failing test: keyboard double-press 'q' toggles to ratchet in specs/keyboard_spec.lua
- [x] T062 [P] [US11] Write failing test: keyboard pressing different page key clears extended in specs/keyboard_spec.lua

### Implementation

- [x] T063 [US11] Add extended page toggle logic (track last key, double-press detection) to lib/seamstress/keyboard.lua
- [ ] T064 Run full integration test suite: init -> start -> step -> verify all features in specs/integration_spec.lua
- [ ] T065 Verify 100% public function coverage: every public function in lib/ has at least one test
- [ ] T066 Run quickstart.md validation: follow quickstart steps, verify app loads and operates correctly

**Checkpoint**: All features working. Full test coverage. Ready for merge.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies -- start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 CI being green -- BLOCKS integration tasks
- **US1-4 Verification (Phase 3)**: Can start after Phase 1 (independent of Phase 2)
- **US11 Extended Toggle (Phase 4)**: Depends on Phase 2 (needs extended track params from T010)
- **US5 Screen UI (Phase 5)**: Can start after Phase 1 (reads ctx, no new modules needed)
- **US6+7 Clock/Scale (Phase 6)**: Can start after Phase 1 (testing existing code)
- **US8 Direction (Phase 7)**: Depends on Phase 2 (needs direction.lua from T006)
- **US9 Mute Fix (Phase 8)**: Can start after Phase 1 (no new module deps)
- **US10 Patterns (Phase 9)**: Depends on Phase 2 (needs pattern.lua from T008)
- **US12-14 Extended Pages (Phase 10)**: Depends on Phases 2 + 4 (needs extended params + toggle)
- **Polish (Phase 11)**: Depends on all previous phases

### User Story Dependencies

- **US1-4 (P1)**: No dependencies -- already implemented, just needs test verification
- **US5 (P2)**: No story dependencies -- reads ctx
- **US6-7 (P2)**: No story dependencies -- already implemented, needs test verification
- **US11 (P2)**: Depends on extended track params (foundational T010)
- **US8 (P3)**: Depends on direction module (foundational T006)
- **US9 (P3)**: No story dependencies
- **US10 (P3)**: Depends on pattern module (foundational T008)
- **US12-14 (P3)**: Depends on US11 (toggle) + extended params (T010) + voice portamento (T012)

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Foundational modules before integration
- Grid UI before keyboard
- Core logic before display

### Parallel Opportunities (MultiClaude Dispatch)

```
Phase 1:  T003 || T004                            (grid_ui tests || scale tests)
Phase 2:  T005+T006 || T007+T008 || T009+T010 || T011+T012  (4 parallel workers)
Phase 3:  T013 || T014 || T015 || T016            (4 parallel test writers)
Phase 4:  T021-T025 all parallel                   (5 toggle tests in parallel)
Phase 5+6+8: US5 || US6+7 || US9                  (3 parallel workers)
Phase 7:  After Phase 2 direction.lua lands
Phase 10: T048-T053 all parallel                   (6 extended page tests)
          T054 -> T055 -> T056                     (3 sequencer features sequential - same file)
```

---

## Parallel Example: Wave 1 (Foundational)

```bash
# MultiClaude: 4 parallel workers, each runs full TDD cycle via ralph
/mc swarm \
  "TDD lib/direction.lua: write failing tests for 5 direction modes in specs/direction_spec.lua, then implement. Tasks T005+T006." \
  "TDD lib/pattern.lua: write failing tests for save/load/16 slots in specs/pattern_spec.lua, then implement. Tasks T007+T008." \
  "TDD extended track params: write failing tests for ratchet/alt_note/glide/direction in specs/track_spec.lua, then add to lib/track.lua. Tasks T009+T010." \
  "TDD voice portamento: write failing tests for set_portamento CC in specs/voice_spec.lua, then add to midi+recorder voices. Tasks T011+T012."
```

## Parallel Example: Wave 2 (Integration)

```bash
# MultiClaude: 3 parallel workers
/mc swarm \
  "TDD extended page toggle: write failing toggle tests in specs/grid_ui_spec.lua, then implement in lib/grid_ui.lua + lib/app.lua. Tasks T021-T028." \
  "TDD sequencer direction+ratchet+glide: write failing tests in specs/sequencer_spec.lua, then integrate into lib/sequencer.lua. Tasks T037-T040 + T049-T056." \
  "TDD mute fix: write failing test for muted track advancement in specs/sequencer_spec.lua, then fix lib/sequencer.lua. Tasks T042-T043."
```

---

## Implementation Strategy

### MVP First (US1-4 Verification Only)

1. Complete Phase 1: CI Pipeline + existing test gaps
2. Complete Phase 3: US1-4 test verification
3. **STOP and VALIDATE**: All P1 stories fully tested, CI green
4. Demo: sequencer plays, grid works, navigation works

### Incremental Delivery

1. Phase 1 (CI) + Phase 3 (US1-4 verification) -> MVP verified
2. Phase 2 (Foundational modules) -> New modules ready
3. Phase 4 (US11 Extended Toggle) -> "Secondary pages don't work" fixed
4. Phases 5-6 (US5 Screen + US6-7 Clock/Scale) -> P2 complete
5. Phases 7-9 (US8 Direction + US9 Mute + US10 Patterns) -> P3 core
6. Phase 10 (US12-14 Extended Pages) -> P3 extended features
7. Phase 11 (Polish + Integration) -> Ship-ready

### MultiClaude Team Strategy

With 4 parallel workers via `/mc swarm`:

1. **Wave 0**: 1 worker -> CI pipeline (Task 0, T001-T002)
2. **Wave 1**: 4 workers -> direction / pattern / track params / voice portamento (T005-T012)
3. **Wave 2**: 3 workers -> toggle / sequencer integration / mute fix (T021-T028, T037-T043)
4. **Wave 3**: 3 workers -> extended page displays / screen UI / keyboard (T048-T063)
5. **Wave 4**: 1 worker -> integration tests + coverage verification (T064-T066)

Each worker runs ralph internally for the Researcher -> Musician -> Lua Wizard -> Tester -> Musician -> Refactorer hat loop. Each worker's output is a PR against main.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Tests MUST fail before implementing (constitution principle III)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All changes to lib/ MUST have corresponding test changes in specs/
- Total: 66 tasks across 11 phases and 14 user stories
