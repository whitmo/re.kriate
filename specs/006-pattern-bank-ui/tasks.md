# Tasks: Pattern Bank Visual Feedback

**Input**: Design documents from `specs/006-pattern-bank-ui/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: TDD is NON-NEGOTIABLE per constitution principle III. Every implementation task MUST be preceded by a test task that writes failing tests first.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Baseline verification and test file creation

- [x] T001 Verify test baseline: run `busted --no-auto-insulate specs/` and confirm 555+ pass, 0 fail
- [x] T002 Create test file `specs/pattern_bank_ui_spec.lua` with screen mock, helper imports, and empty describe block

---

## Phase 2: User Story 1 - Active Pattern Indicator (Priority: P1) 🎯 MVP

**Goal**: Track which pattern slot is active and display it visually. Save sets active, load of populated slot sets active, load of empty slot is no-op.

**Independent Test**: Save to slot 3, verify ctx.active_pattern == 3. Load populated slot 5, verify ctx.active_pattern == 5. Load empty slot, verify ctx.active_pattern unchanged.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T003 [P] [US1] Test: save pattern sets ctx.active_pattern in `specs/pattern_bank_ui_spec.lua` — ctrl+N save → ctx.active_pattern == N (FR-003, US1 scenario 2)
- [x] T004 [P] [US1] Test: load populated slot sets ctx.active_pattern in `specs/pattern_bank_ui_spec.lua` — shift+N load of populated slot → ctx.active_pattern == N (FR-004, US1 scenario 3)
- [x] T005 [P] [US1] Test: load empty slot does NOT change ctx.active_pattern in `specs/pattern_bank_ui_spec.lua` — shift+N load of empty slot → ctx.active_pattern unchanged (FR-005, edge case 1)
- [x] T006 [P] [US1] Test: no active pattern on startup in `specs/pattern_bank_ui_spec.lua` — fresh ctx has ctx.active_pattern == nil (US1 scenario 1)
- [x] T007 [P] [US1] Test: active pattern moves on subsequent save in `specs/pattern_bank_ui_spec.lua` — save slot 3 then save slot 7 → ctx.active_pattern == 7 (US1 scenario 4)

### Implementation for User Story 1

- [x] T008 [US1] Implement active pattern tracking in `lib/seamstress/keyboard.lua` — after pattern.save(): set ctx.active_pattern = slot; after pattern.load() of populated slot: set ctx.active_pattern = slot; empty slot load: no change (FR-003, FR-004, FR-005)

**Checkpoint**: ctx.active_pattern is correctly set by keyboard save/load actions. T003-T007 pass.

---

## Phase 3: User Story 2 - Populated Slot Indicators (Priority: P1)

**Goal**: Render 9 slot indicators on screen showing empty/populated/active states as filled rectangles with 3 color levels.

**Independent Test**: Create ctx with patterns saved to slots 1,3,5 and active_pattern=3, call screen_ui.redraw, verify 9 rectangles rendered with correct color levels.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T009 [P] [US2] Test: 9 slot indicators rendered in `specs/pattern_bank_ui_spec.lua` — redraw renders exactly 9 rect_fill calls for slot indicators (FR-001)
- [x] T010 [P] [US2] Test: empty slots render dim color in `specs/pattern_bank_ui_spec.lua` — all-empty ctx.patterns → all 9 indicators use dim color (US2 scenario 1)
- [x] T011 [P] [US2] Test: populated slots render medium color in `specs/pattern_bank_ui_spec.lua` — save to slots 1,3,5 → those indicators use medium color, others dim (FR-002, US2 scenario 2)
- [x] T012 [P] [US2] Test: active slot renders bright color in `specs/pattern_bank_ui_spec.lua` — ctx.active_pattern=3 with populated slot 3 → slot 3 uses bright color (FR-002)
- [x] T013 [P] [US2] Test: nil ctx.patterns renders all-empty without error in `specs/pattern_bank_ui_spec.lua` — ctx.patterns=nil → 9 dim indicators, no crash (edge case 5)

### Implementation for User Story 2

- [x] T014 [US2] Implement draw_pattern_slots() in `lib/seamstress/screen_ui.lua` — local function rendering 9 filled rectangles with 3 color levels (dim/medium/bright) based on ctx.patterns populated state and ctx.active_pattern, called from M.redraw(); defensive nil check on ctx.patterns (FR-001, FR-002, R-004)

**Checkpoint**: Screen shows 9 slot indicators with correct visual states. T009-T013 pass.

---

## Phase 4: User Story 3 - Transient Save/Load Feedback (Priority: P2)

**Goal**: Show temporary "saved N" / "loaded N" confirmation message that auto-clears after ~1.5 seconds.

**Independent Test**: Save to slot 3, call redraw, verify "saved 3" text appears. Advance os.clock() past 1.5s, call redraw, verify message cleared.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T015 [P] [US3] Test: save sets ctx.pattern_message in `specs/pattern_bank_ui_spec.lua` — ctrl+N save → ctx.pattern_message.text == "saved N" and ctx.pattern_message.time set (FR-006)
- [x] T016 [P] [US3] Test: load sets ctx.pattern_message in `specs/pattern_bank_ui_spec.lua` — shift+N load of populated slot → ctx.pattern_message.text == "loaded N" (FR-007)
- [x] T017 [P] [US3] Test: load empty slot does NOT set message in `specs/pattern_bank_ui_spec.lua` — shift+N load of empty slot → ctx.pattern_message unchanged (FR-005, edge case 1)
- [x] T018 [P] [US3] Test: transient message rendered on screen in `specs/pattern_bank_ui_spec.lua` — ctx.pattern_message with recent time → text appears in screen buffer (FR-006, US3 scenario 1)
- [x] T019 [P] [US3] Test: expired message cleared during redraw in `specs/pattern_bank_ui_spec.lua` — ctx.pattern_message with time > 1.5s ago → message not rendered, ctx.pattern_message set to nil (FR-008, US3 scenario 3)
- [x] T020 [P] [US3] Test: new action replaces message and resets timer in `specs/pattern_bank_ui_spec.lua` — save slot 3, then immediately load slot 1 → ctx.pattern_message.text == "loaded 1" (FR-009, US3 scenario 4, edge case 3)

### Implementation for User Story 3

- [x] T021 [US3] Implement pattern message setting in `lib/seamstress/keyboard.lua` — after pattern.save(): set ctx.pattern_message = {text="saved "..slot, time=os.clock()}; after pattern.load() of populated slot: set ctx.pattern_message = {text="loaded "..slot, time=os.clock()}; empty slot: no message (FR-006, FR-007, FR-009, R-001, R-003)
- [x] T022 [US3] Implement transient message rendering in `lib/seamstress/screen_ui.lua` — in M.redraw(): check ctx.pattern_message, if os.clock() - time < 1.5 render text near slot indicators, else clear to nil (FR-008, R-001)

**Checkpoint**: Save/load shows confirmation message that auto-clears. T015-T020 pass.

---

## Phase 5: User Story 4 - Seamstress-Only Scope (Priority: P1) + Verification

**Goal**: Verify architectural integrity — no changes to norns entrypoint, shared app module, or pattern storage module. Full regression pass.

**Independent Test**: Inspect file change set; run full test suite.

### Verification Tests

- [x] T023 [P] [US4] Test: re_kriate.lua contains no pattern indicator code in `specs/pattern_bank_ui_spec.lua` — read re_kriate.lua, assert no "active_pattern" or "pattern_message" strings (SC-005, US4 scenario 1)
- [x] T024 [P] [US4] Test: lib/app.lua contains no screen rendering or pattern UI logic in `specs/pattern_bank_ui_spec.lua` — read lib/app.lua, assert no "draw_pattern" or "pattern_message" strings (SC-005, US4 scenario 2)
- [x] T025 [P] [US4] Test: slot 9 boundary works identically in `specs/pattern_bank_ui_spec.lua` — save to slot 9, verify active_pattern == 9 and message == "saved 9" (edge case 2)
- [x] T026 [US4] Full regression: run `busted --no-auto-insulate specs/` and confirm 555+ existing tests still pass plus all new tests (SC-004, US4 scenario 3)

**Checkpoint**: All tests pass, no regressions, architectural boundaries intact.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **US1 (Phase 2)**: Depends on T002 (test file exists)
- **US2 (Phase 3)**: Depends on T008 (ctx.active_pattern set by keyboard) for active color tests
- **US3 (Phase 4)**: Depends on T002 (test file exists); US3 implementation (T021) can parallel with US2 implementation (T014) since they modify different files (keyboard.lua vs screen_ui.lua)
- **US4 (Phase 5)**: Depends on all US1-US3 implementation complete

### User Story Dependencies

- **US1 (P1)**: Can start after T002 — no dependencies on other stories
- **US2 (P1)**: T009-T013 can start after T002; T014 depends on T008 (active pattern must be settable for active color to work)
- **US3 (P2)**: T015-T020 can start after T002; T021 modifies keyboard.lua (same file as T008, should be sequential); T022 modifies screen_ui.lua (same file as T014, should be sequential)
- **US4 (P1)**: Verification only — depends on all implementation complete

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- T003-T007 (red) → T008 (green)
- T009-T013 (red) → T014 (green)
- T015-T020 (red) → T021 + T022 (green)
- T023-T025 (verification) → T026 (regression)

### Parallel Opportunities

- T003-T007 all [P] within US1 (same test file, independent test cases)
- T009-T013 all [P] within US2 (same test file, independent test cases)
- T015-T020 all [P] within US3 (same test file, independent test cases)
- T023-T025 all [P] within US4 (verification tests)
- US1 tests (T003-T007) ∥ US2 tests (T009-T013) ∥ US3 tests (T015-T020) — all write to same test file but are independent describe blocks

---

## Parallel Example: User Story 1

```bash
# Launch all US1 tests together (all [P]):
Task T003: "Test save sets ctx.active_pattern"
Task T004: "Test load populated slot sets ctx.active_pattern"
Task T005: "Test load empty slot no change"
Task T006: "Test no active pattern on startup"
Task T007: "Test active pattern moves on save"

# Then implement (single task, both behaviors in keyboard.lua):
Task T008: "Implement active pattern tracking in keyboard.lua"
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: US1 Active Pattern (T003-T008) — keyboard.lua tracks active slot
3. Complete Phase 3: US2 Slot Indicators (T009-T014) — screen_ui.lua renders visual feedback
4. **STOP and VALIDATE**: 9 slot indicators visible with active tracking

### Incremental Delivery

1. US1 → active pattern tracked on ctx (keyboard.lua only, no visual yet)
2. US2 → slot indicators rendered (screen_ui.lua reads ctx.active_pattern + ctx.patterns)
3. US3 → transient messages (keyboard.lua sets message, screen_ui.lua renders + expires)
4. US4 → verification + regression

### Batch Strategy

- **Batch 1** (T001-T008): Setup + US1 tests + US1 impl
- **Batch 2** (T009-T014): US2 tests + US2 impl
- **Batch 3** (T015-T022): US3 tests + US3 impl
- **Batch 4** (T023-T026): US4 verification + regression

---

## Notes

- [P] tasks = different files or independent test cases, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable after its implementation task
- TDD: all test tasks (red) MUST precede their implementation task (green)
- Only 2 source files modified: `lib/seamstress/keyboard.lua`, `lib/seamstress/screen_ui.lua`
- No changes to: `re_kriate.lua`, `lib/app.lua`, `lib/pattern.lua` (FR-010/SC-005)
- Test command: `busted --no-auto-insulate specs/`
