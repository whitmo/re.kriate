# Tasks: Simulated Grid (003)

**Input**: Design documents from `specs/003-simulated-grid/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: TDD is NON-NEGOTIABLE per constitution principle III. Every implementation task MUST be preceded by a test task that writes failing tests first. Tests live in `specs/` directory. Run with: `busted --no-auto-insulate specs/`

**Organization**: Tasks are grouped by user story. Phase 1+2 (grid render module + simulated provider) can run in parallel. Phase 3+4 (mouse input + screen rendering) can run in parallel after Phase 1+2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify baseline and create new module/spec files

- [x] T001 Verify baseline: run `busted --no-auto-insulate specs/` — all 480 tests pass, 0 failures
- [x] T002 [P] Create empty `lib/seamstress/grid_render.lua` module skeleton (return empty table M)
- [x] T003 [P] Create empty `specs/grid_render_spec.lua` test file with package.path setup
- [x] T004 [P] Create empty `specs/simulated_grid_spec.lua` test file with package.path setup

**Checkpoint**: Baseline green, new files exist, `busted` still passes

---

## Phase 2: Foundational — Brightness-to-Color Mapping (Blocking)

**Purpose**: Pure-function color mapping — foundation for both rendering (US1/US4) and provider (US3)

**⚠️ CRITICAL**: US1 and US4 cannot render without this. Must complete before visual stories.

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T005 [P] [US4] Test `brightness_to_rgb(0)` returns (0, 0, 0) in `specs/grid_render_spec.lua`
- [x] T006 [P] [US4] Test `brightness_to_rgb(15)` returns (255, 178, 102) — full warm amber — in `specs/grid_render_spec.lua`
- [x] T007 [P] [US4] Test all 16 brightness levels (0-15) produce numerically distinct RGB tuples in `specs/grid_render_spec.lua`
- [x] T008 [P] [US4] Test brightness levels 4, 10, 15 (dim/active/playhead) are visually distinguishable (R differs by >30) in `specs/grid_render_spec.lua`

### Implementation

- [x] T009 [US4] Implement `brightness_to_rgb(brightness)` in `lib/seamstress/grid_render.lua` — formula: `R=floor(b/15*255)`, `G=floor(b/15*255*0.7)`, `B=floor(b/15*255*0.4)`. All T005-T008 tests must pass.

**Checkpoint**: `brightness_to_rgb` is a pure function with full test coverage. Foundation ready for rendering.

---

## Phase 3: User Story 4 — Brightness-to-Color Fidelity (Priority: P2)

**Goal**: Coordinate conversion utilities that underpin rendering and mouse input

**Independent Test**: Call `pixel_to_grid` and `grid_to_pixel` with known values, verify correct 1-indexed coordinates

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T010 [P] [US4] Test `grid_to_pixel(1, 1)` returns (0, 0) and `grid_to_pixel(16, 8)` returns (240, 112) in `specs/grid_render_spec.lua`
- [x] T011 [P] [US4] Test `pixel_to_grid(0, 0)` returns (1, 1) and `pixel_to_grid(255, 127)` returns (16, 8) in `specs/grid_render_spec.lua`
- [x] T012 [P] [US4] Test `pixel_to_grid` returns nil for out-of-bounds pixels (256, 0), (0, 128), (-1, 0) in `specs/grid_render_spec.lua`
- [x] T013 [P] [US4] Test gap pixels: `pixel_to_grid(14, 0)` and `pixel_to_grid(15, 0)` both map to cell (1, 1) via floor division in `specs/grid_render_spec.lua`

### Implementation

- [x] T014 [US4] Implement `grid_to_pixel(gx, gy)` in `lib/seamstress/grid_render.lua` — returns `((gx-1)*16, (gy-1)*16)`. Tests T010 must pass.
- [x] T015 [US4] Implement `pixel_to_grid(px, py)` in `lib/seamstress/grid_render.lua` — returns `(floor(px/16)+1, floor(py/16)+1)` or nil if out of bounds. Tests T011-T013 must pass.

**Checkpoint**: All coordinate math is tested and implemented. US4 acceptance scenarios 1-4 pass.

---

## Phase 4: User Story 3 — Seamless Provider Integration (Priority: P2)

**Goal**: Register "simulated" as a grid provider implementing full interface, drop-in replacement for virtual/monome

**Independent Test**: `grid_provider.connect("simulated")` returns object with all 8 interface methods; existing grid_ui tests pass unmodified

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T016 [P] [US3] Test `grid_provider.list()` includes "simulated" in `specs/simulated_grid_spec.lua`
- [x] T017 [P] [US3] Test `grid_provider.connect("simulated")` returns object with `all`, `led`, `refresh`, `cols`, `rows`, `cleanup`, `get_led`, `get_state` in `specs/simulated_grid_spec.lua`
- [x] T018 [P] [US3] Test simulated provider `led(3, 5, 15)` then `get_led(3, 5)` returns 15, and `get_led(4, 5)` returns 0 in `specs/simulated_grid_spec.lua`
- [x] T019 [P] [US3] Test simulated provider `all(10)` sets all 128 cells, `all(0)` clears them in `specs/simulated_grid_spec.lua`
- [x] T020 [P] [US3] Test simulated provider `cleanup()` resets all LEDs to 0 in `specs/simulated_grid_spec.lua`
- [x] T021 [P] [US3] Test simulated provider `key` callback: assign callback, invoke, verify (x, y, z) received in `specs/simulated_grid_spec.lua`
- [x] T022 [P] [US3] Test simulated provider `cols()` returns 16, `rows()` returns 8 in `specs/simulated_grid_spec.lua`

### Implementation

- [x] T023 [US3] Register "simulated" provider in `lib/grid_provider.lua` — same LED state pattern as virtual (flat table, `y*cols+x` indexing), with `get_led`, `get_state`, `key` callback. All T016-T022 tests must pass.

**Checkpoint**: Simulated provider passes all interface compliance tests. `grid_provider.connect("simulated")` works.

---

## Phase 5: User Story 1 — Visual Grid Display (Priority: P1) 🎯 MVP

**Goal**: Render 16x8 grid of colored rectangles on seamstress screen, LED brightness mapped to warm amber colors

**Independent Test**: Set LED values via provider, call `grid_render.draw()`, verify screen mock received correct `color()` and `rect_fill()` calls

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T024 [P] [US1] Test `grid_render.draw(grid)` calls `screen.color` and `screen.rect_fill` for each of 128 cells, using mock screen in `specs/grid_render_spec.lua`
- [x] T025 [P] [US1] Test `grid_render.draw(grid)` maps LED brightness 15 at (3, 2) to correct warm amber color and correct pixel position `(32, 16)` in `specs/grid_render_spec.lua`
- [x] T026 [P] [US1] Test `grid_render.draw(grid)` renders cells with brightness 0 as near-black `(0, 0, 0)` in `specs/grid_render_spec.lua`

### Implementation

- [x] T027 [US1] Implement `grid_render.draw(grid)` in `lib/seamstress/grid_render.lua` — iterate 16x8, call `grid:get_led(x,y)`, convert via `brightness_to_rgb`, draw 14x14 `rect_fill` at `grid_to_pixel(x,y)`. Tests T024-T026 must pass.

**Checkpoint**: Grid renderer draws all 128 cells with correct colors. US1 acceptance scenarios 1-4 pass with mock screen.

---

## Phase 6: User Story 2 — Mouse Click Interaction (Priority: P1) 🎯 MVP

**Goal**: Convert mouse left-clicks to grid key events (press z=1 / release z=0)

**Independent Test**: Simulate `screen.click` at known pixel coordinates, verify grid `key` callback fires with correct (x, y, z)

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T028 [P] [US2] Test left-click at pixel (24, 8) generates grid key (2, 1, 1) for press and (2, 1, 0) for release in `specs/simulated_grid_spec.lua`
- [x] T029 [P] [US2] Test non-left-click (button 2, 3) is ignored — no key event fires in `specs/simulated_grid_spec.lua`
- [x] T030 [P] [US2] Test click outside grid bounds (pixel 260, 0) is ignored — no key event fires in `specs/simulated_grid_spec.lua`
- [x] T031 [P] [US2] Test click at grid boundary: pixel (255, 127) maps to cell (16, 8) in `specs/simulated_grid_spec.lua`

### Implementation

- [x] T032 [US2] Implement mouse click handler function in `lib/seamstress/grid_render.lua` — `handle_click(grid, px, py, state, button)`: left-click only (button==1), convert pixel to grid via `pixel_to_grid`, call `grid.key(gx, gy, state)`. Tests T028-T031 must pass.

**Checkpoint**: Mouse clicks on grid cells produce correct key events. US2 acceptance scenarios 1-4 pass.

---

## Phase 7: User Story 1+2 — Seamstress Wiring Integration (Priority: P1)

**Goal**: Wire grid rendering and mouse input into `seamstress.lua` init/redraw cycle

**Independent Test**: Launch app with `grid_provider = "simulated"`, verify grid draws on screen and clicks generate key events

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T033 [US1] Test that `redraw()` calls `grid_render.draw(ctx.g)` when grid provider is "simulated" — mock-based integration test in `specs/simulated_grid_spec.lua`
- [x] T034 [US2] Test that `screen.click` callback is wired in `init()` and delegates to `grid_render.handle_click` in `specs/simulated_grid_spec.lua`

### Implementation

- [x] T035 [US1] Wire `grid_render.draw(ctx.g)` into `seamstress.lua` `redraw()` — draw after black background, before sprites. Conditionally require grid_render when provider is "simulated".
- [x] T036 [US2] Wire `screen.click` callback in `seamstress.lua` `init()` — delegate to `grid_render.handle_click(ctx.g, x, y, state, button)`. Add `grid_provider = "simulated"` config option to `app.init()` call.

**Checkpoint**: Full MVP — simulated grid renders on screen, mouse clicks interact with kria. US1+US2 acceptance scenarios pass end-to-end.

---

## Phase 8: User Story 3 — Behavioral Parity Verification (Priority: P2)

**Goal**: Verify all existing grid_ui behavior works unmodified with simulated provider

**Independent Test**: Run existing `grid_ui_spec.lua` tests using simulated provider instead of virtual

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T037 [US3] Test `app.init({grid_provider = "simulated"})` returns ctx with fully functional grid — all interface methods work in `specs/simulated_grid_spec.lua`
- [x] T038 [US3] Test existing `grid_ui.redraw(ctx)` sets LEDs correctly on simulated provider (verifiable via `get_led`) in `specs/simulated_grid_spec.lua`

### Implementation

- [x] T039 [US3] Verify `grid_ui_spec.lua` tests pass with simulated provider (SC-003). If any fail, fix simulated provider interface to match virtual behavior. No test changes allowed.

**Checkpoint**: SC-003 passes — all existing grid UI tests work with simulated provider. US3 acceptance scenarios 1-3 pass.

---

## Phase 9: User Story 5 — Grid Rendering Performance (Priority: P3)

**Goal**: Validate grid rendering stays under 5ms per frame

**Independent Test**: Time 100 consecutive `grid_render.draw()` calls, verify average < 5ms

### Tests

- [x] T040 [US5] Test 100 consecutive `grid_render.draw()` calls complete in under 500ms total (< 5ms avg) in `specs/grid_render_spec.lua`

### Implementation

- [x] T041 [US5] If T040 fails, optimize `grid_render.draw()` — pre-compute color table, reduce function calls. If T040 passes, no implementation needed.

**Checkpoint**: SC-005 passes — grid rendering adds < 5ms per frame.

---

## Phase 10: Edge Cases & Polish

**Purpose**: Cover all 6 spec edge cases + end-to-end integration

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T042 [P] Test gap click: pixel (15, 15) inside 2px gap area maps to cell (1, 1) via floor division in `specs/grid_render_spec.lua`
- [x] T043 [P] Test drag across cells: press at (24, 8) then release at (100, 50) — only press fires for (2,1), release fires for release position in `specs/simulated_grid_spec.lua`
- [x] T044 [P] Test out-of-bounds `grid:led(17, 9, 5)` on simulated provider is silently ignored (no error) in `specs/simulated_grid_spec.lua`
- [x] T045 [P] Test cleanup mid-render: `grid:cleanup()` resets all LED state, next `draw()` renders all-black in `specs/grid_render_spec.lua`
- [x] T046 [P] Test end-to-end: set LED → draw → click cell → key event fires → state changes → LED updates → draw shows new state in `specs/simulated_grid_spec.lua`

### Implementation

- [x] T047 If T044 fails: add bounds checking to simulated provider `led()` in `lib/grid_provider.lua` — silently ignore x<1 or x>16 or y<1 or y>8
- [x] T048 Verify all edge case tests pass. Run full suite: `busted --no-auto-insulate specs/` — all tests pass, 0 failures.

**Checkpoint**: All 6 spec edge cases covered. Full test suite green.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Brightness Mapping)**: Depends on Phase 1
- **Phase 3 (Coordinate Conversion) + Phase 4 (Simulated Provider)**: Can run in PARALLEL after Phase 2
- **Phase 5 (Visual Display) + Phase 6 (Mouse Input)**: Can run in PARALLEL after Phase 3+4
- **Phase 7 (Seamstress Wiring)**: Depends on Phase 5+6
- **Phase 8 (Behavioral Parity)**: Depends on Phase 4+7
- **Phase 9 (Performance)**: Depends on Phase 5
- **Phase 10 (Edge Cases)**: Depends on all previous phases

### User Story Dependencies

- **US4 (Brightness/Color)**: No dependencies on other stories — pure functions
- **US3 (Provider)**: No dependencies on other stories — extends grid_provider.lua
- **US1 (Visual Display)**: Depends on US4 (color mapping) + US3 (provider for LED state)
- **US2 (Mouse Input)**: Depends on US4 (coordinate conversion) + US3 (provider for key callback)
- **US5 (Performance)**: Depends on US1 (renderer must exist to benchmark)

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Implementation makes tests pass
- Verify full suite still green after each implementation task

### Parallel Opportunities

**Parallel batch 1** (after Phase 1):
- T005-T008 (brightness tests) — all touch `specs/grid_render_spec.lua`

**Parallel batch 2** (after Phase 2):
- T010-T013 (coordinate tests) ∥ T016-T022 (provider tests) — different spec files

**Parallel batch 3** (after Phase 3+4):
- T024-T026 (render tests) ∥ T028-T031 (mouse tests) — different spec files

**Parallel batch 4** (after Phase 7):
- T042-T046 (edge case tests) — mixed files, all [P]

---

## Parallel Example: Phase 3 + Phase 4

```bash
# Worker A: Coordinate conversion (US4) in specs/grid_render_spec.lua
Task T010: grid_to_pixel tests
Task T011: pixel_to_grid tests
Task T012: out-of-bounds tests
Task T013: gap pixel tests
Task T014: implement grid_to_pixel
Task T015: implement pixel_to_grid

# Worker B: Simulated provider (US3) in specs/simulated_grid_spec.lua
Task T016: list includes "simulated"
Task T017: connect returns full interface
Task T018: led/get_led roundtrip
Task T019: all() set/clear
Task T020: cleanup resets
Task T021: key callback
Task T022: cols/rows
Task T023: implement provider
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Brightness mapping (T005-T009)
3. Complete Phase 3+4 in parallel: Coordinates + Provider (T010-T023)
4. Complete Phase 5+6 in parallel: Rendering + Mouse (T024-T032)
5. Complete Phase 7: Wiring (T033-T036)
6. **STOP and VALIDATE**: Launch seamstress with `grid_provider = "simulated"`, interact with full kria UI via mouse

### Incremental Delivery

1. Setup + Foundational → Color math works
2. US4 + US3 → Provider + coordinates ready
3. US1 + US2 → Grid renders, mouse works (MVP!)
4. US3 parity → Verified drop-in replacement
5. US5 → Performance validated
6. Edge cases → All 6 spec edge cases covered

---

## Notes

- Total tasks: 48 (T001-T048)
- Test tasks: 27 (T005-T008, T010-T013, T016-T022, T024-T026, T028-T031, T033-T034, T037-T038, T040, T042-T046)
- Implementation tasks: 17 (T009, T014-T015, T023, T027, T032, T035-T036, T039, T041, T047-T048)
- Setup/verification tasks: 4 (T001-T004)
- New files: 3 (`lib/seamstress/grid_render.lua`, `specs/grid_render_spec.lua`, `specs/simulated_grid_spec.lua`)
- Modified files: 2 (`lib/grid_provider.lua`, `seamstress.lua`)
- SC-003 verification at T039 ensures no behavioral regressions
