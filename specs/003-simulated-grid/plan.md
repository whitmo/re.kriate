# Implementation Plan: Simulated Grid

**Branch**: `003-simulated-grid` | **Date**: 2026-03-24 | **Spec**: `specs/003-simulated-grid/spec.md`
**Input**: Feature specification from `specs/003-simulated-grid/spec.md`

## Summary

Add a screen-rendered interactive grid for seamstress that mirrors hardware monome grid behavior. The simulated grid registers as a standard grid provider, renders LED state as warm-amber colored rectangles on the 256x128 seamstress screen, and converts mouse clicks to grid key events. This enables full kria interaction without hardware. The implementation extends the existing grid provider plugin system with a new "simulated" backend, adds a grid renderer module, and wires mouse input in the seamstress entrypoint.

## Technical Context

**Language/Version**: Lua 5.4 (seamstress runtime, busted test runner)
**Primary Dependencies**: seamstress v1.4.7 (screen drawing, mouse callbacks, metro)
**Storage**: N/A (in-memory LED state matrix, no persistence)
**Testing**: busted (unit + integration specs in `specs/`)
**Target Platform**: seamstress v1.4.7 (macOS/Linux desktop)
**Project Type**: Norns/seamstress sequencer script
**Performance Goals**: Grid render < 5ms per frame at 30 Hz (128 rectangles)
**Constraints**: Seamstress-only feature; norns uses hardware grid. No new external dependencies.
**Scale/Scope**: 16x8 grid (128 cells), ~3 new modules, ~15-20 new tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Phase 0

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-Centric Architecture | PASS | Simulated grid provider stored on `ctx.g` like all other providers. Renderer reads from `ctx.g`. Mouse handler delegates to `ctx.g.key`. No new globals. |
| II. Platform-Parity Behavior | PASS | Simulated grid is a seamstress-only adapter (like keyboard.lua, sprite_render.lua). Sequencing behavior is provider-agnostic — all grid_ui logic works identically. Platform-specific nature documented in spec. |
| III. Test-First Sequencing Correctness | PASS | Coordinate conversion, brightness mapping, and provider interface compliance will have failing tests before implementation. Existing grid_ui_spec tests verify behavioral parity. |
| IV. Deterministic Timing and Safe Degradation | PASS | Grid renderer runs in existing 30 Hz screen metro. No new timing mechanisms. Mouse events processed synchronously. Performance budget: < 5ms/frame for 128 rects (well within 33ms budget). |
| V. Spec-Driven Delivery | PASS | Full speckit pipeline: spec.md (done) → plan.md (this) → tasks.md → analyze → implement → verify. |

No violations. Complexity tracking not needed.

## Project Structure

### Documentation (this feature)

```text
specs/003-simulated-grid/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── module-interfaces.md
├── checklists/          # Specifier output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── grid_provider.lua          # MODIFY: register "simulated" provider
├── seamstress/
│   ├── grid_render.lua        # NEW: grid LED → screen renderer
│   └── (existing: screen_ui.lua, sprite_render.lua, keyboard.lua)
├── (existing: app.lua, grid_ui.lua, etc.)

seamstress.lua                 # MODIFY: wire mouse handler + grid rendering

specs/
├── grid_render_spec.lua       # NEW: brightness mapping + coordinate conversion tests
├── simulated_grid_spec.lua    # NEW: provider interface + integration tests
├── (existing: grid_provider_spec.lua, grid_ui_spec.lua)
```

**Structure Decision**: Follows existing project layout. The simulated provider is registered inline in `grid_provider.lua` (consistent with monome, midigrid, virtual providers). The renderer is a new seamstress-specific module in `lib/seamstress/`. Mouse handling is wired in `seamstress.lua` (consistent with how keyboard input is wired).

## Phase Design

### Phase 1: Grid Render Module (Foundation)

**Goal**: Brightness-to-color mapping and coordinate conversion utilities.

**Files**: `lib/seamstress/grid_render.lua` (new), `specs/grid_render_spec.lua` (new)

**Tasks**:
- T001: `brightness_to_rgb(brightness)` — maps 0-15 to warm amber RGB. Pure function, fully unit-testable.
- T002: `pixel_to_grid(px, py)` — converts screen pixel to grid cell (1-indexed). Returns nil for out-of-bounds. Pure function.
- T003: `grid_to_pixel(gx, gy)` — converts grid cell to top-left screen pixel. Pure function.
- T004: `draw(grid)` — reads LED state from grid provider, draws 128 colored rectangles. Requires screen mock.

**Dependencies**: None (pure functions + screen API)
**Constitution gate**: Tests for T001-T003 are pure math — write failing tests, then implement.

### Phase 2: Simulated Grid Provider

**Goal**: Register "simulated" provider implementing full grid interface with LED state management.

**Files**: `lib/grid_provider.lua` (modify), `specs/simulated_grid_spec.lua` (new)

**Tasks**:
- T005: Register "simulated" provider in grid_provider.lua. Reuses virtual provider's LED state pattern (flat table, y*cols+x indexing). Adds `get_led()` and `get_state()`.
- T006: Interface compliance — verify all 8 interface methods (all, led, refresh, cols, rows, cleanup, get_led, key callback).
- T007: Existing grid_provider_spec patterns verify the new provider appears in `list()` and passes interface assertions.

**Dependencies**: None (extends existing module)
**Constitution gate**: Provider is identical behavior to virtual — no sequencing logic affected.

### Phase 3: Mouse Input Wiring

**Goal**: Convert seamstress mouse clicks to grid key events.

**Files**: `seamstress.lua` (modify), `specs/simulated_grid_spec.lua` (extend)

**Tasks**:
- T008: Wire `screen.click` callback in seamstress.lua `init()`. Left-click only, bounds-checked, delegates to `ctx.g.key(gx, gy, state)`.
- T009: Test pixel→grid coordinate conversion for boundary positions (cell corners, edges, gaps).
- T010: Test non-left-click rejection (button != 1 ignored).
- T011: Test out-of-bounds click rejection (beyond 256x128 grid area).

**Dependencies**: Phase 1 (coordinate conversion), Phase 2 (provider with key callback)
**Constitution gate**: Mouse handler is seamstress-specific adapter, no sequencing logic.

### Phase 4: Screen Rendering Integration

**Goal**: Draw simulated grid in seamstress redraw cycle.

**Files**: `seamstress.lua` (modify)

**Tasks**:
- T012: Call `grid_render.draw(ctx.g)` in seamstress `redraw()` when grid provider is "simulated". Draw before sprites (grid is background).
- T013: Verify grid display updates when LED state changes (set LED → next redraw shows new color).
- T014: Verify cleanup resets LED state (all cells dark after cleanup).

**Dependencies**: Phase 1 (renderer), Phase 2 (provider)
**Constitution gate**: Rendering is display-only, no state mutation.

### Phase 5: Config Integration & Behavioral Parity

**Goal**: Single config switch activates simulated grid. All existing grid_ui behavior works unmodified.

**Files**: `seamstress.lua` (modify), `specs/simulated_grid_spec.lua` (extend)

**Tasks**:
- T015: Verify `app.init({grid_provider = "simulated"})` produces a working grid with all interface methods.
- T016: Run existing grid_ui_spec tests with simulated provider (behavioral parity check — SC-003).
- T017: End-to-end: click cell → grid_ui.key fires → state changes → LED updates → renderer shows new state.

**Dependencies**: All previous phases
**Constitution gate**: SC-003 (existing tests pass unmodified) is the key parity verification.

### Phase 6: Edge Cases & Performance

**Goal**: Cover all 6 spec edge cases and performance criteria.

**Tasks**:
- T018: Gap click (2px padding) maps to correct cell via floor division.
- T019: Drag across cells — only press/release events, no intermediate events.
- T020: Out-of-bounds LED calls silently ignored.
- T021: Cleanup mid-render resets state safely.
- T022: Performance: 100 redraws < 500ms total (< 5ms avg per frame).

**Dependencies**: All previous phases

## Parallel Opportunities

- **Phase 1 + Phase 2** can run in parallel (no dependencies between renderer and provider).
- **Phase 3 + Phase 4** can run in parallel after Phase 1+2 complete (mouse and rendering are independent wiring).
- **Phase 5 + Phase 6** are sequential (parity check first, then edge cases).

## Complexity Tracking

No constitutional violations to justify. All changes follow existing patterns:
- Provider registration matches monome/midigrid/virtual pattern
- Renderer follows sprite_render.lua pattern
- Mouse handler follows keyboard.lua wiring pattern
- Tests follow existing grid_provider_spec.lua patterns

## Post-Phase 1 Constitution Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-Centric Architecture | PASS | Provider on ctx.g, renderer reads ctx.g, mouse delegates to ctx.g.key. No new globals or module-level state. |
| II. Platform-Parity Behavior | PASS | Seamstress-only adapter. grid_ui.lua unchanged. SC-003 verifies parity. |
| III. Test-First Sequencing Correctness | PASS | Pure function tests for coordinate/color math. Provider interface compliance tests. Integration tests for click→event→LED flow. |
| IV. Deterministic Timing and Safe Degradation | PASS | Renderer in existing 30Hz metro. No new timing. Performance validated by T022. |
| V. Spec-Driven Delivery | PASS | Full pipeline executed. All artifacts generated. |
