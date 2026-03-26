# Feature Specification: Simulated Grid

**Feature Branch**: `003-simulated-grid`
**Created**: 2026-03-24
**Status**: Draft
**Input**: User description: "Add simulated grid: render an interactive 16x8 grid in the seamstress window using screen drawing primitives (rect_fill for buttons, brightness-mapped colors). Mirror the real grid state — LED brightness maps to button color intensity. Mouse clicks on grid cells generate the same key events as a physical grid (x, y, z=1 on press, z=0 on release). Enables full kria interaction without hardware."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visual Grid Display (Priority: P1)

A musician opens re.kriate in seamstress without a physical monome grid connected. The seamstress window displays a 16x8 grid of rectangular buttons that visually mirror the sequencer's LED state. Each button's color intensity reflects the grid brightness level (0-15), using warm amber tones reminiscent of monome LED aesthetics. As the sequencer plays, the grid display updates in real time — playhead positions light up, active steps glow, and navigation row indicators are visible. The musician can see the full sequencer state at a glance without any hardware.

**Why this priority**: Without visual display, the simulated grid has no value. This is the foundational capability that all other stories build on.

**Independent Test**: Can be tested by launching the app with a simulated grid provider, setting various LED brightness values, and verifying the screen renders colored rectangles at the correct positions with correct color intensities.

**Acceptance Scenarios**:

1. **Given** the app is initialized with the simulated grid provider, **When** the grid LED at position (3, 2) is set to brightness 15, **Then** a filled rectangle is drawn at the corresponding screen position with maximum warm-amber intensity.
2. **Given** the app is initialized with the simulated grid provider, **When** all LEDs are set to brightness 0, **Then** all grid cells appear dark (near-black).
3. **Given** the sequencer is playing, **When** the playhead advances, **Then** the grid display updates to reflect the new LED state within the same redraw cycle.
4. **Given** the app is initialized with the simulated grid provider, **When** LED brightness is set to 8 (mid-range), **Then** the cell color is visually distinguishable from both brightness 0 and brightness 15.

---

### User Story 2 - Mouse Click Interaction (Priority: P1)

A musician clicks on grid cells in the seamstress window to interact with the sequencer. Left-clicking a cell generates the same key event as pressing a physical grid button: a press event (z=1) on mouse-down and a release event (z=0) on mouse-up, with the correct grid coordinates (x=1-16, y=1-8). The musician can toggle trigger steps, select tracks, change pages, start/stop playback, and edit patterns — the full kria interaction model — using only the mouse.

**Why this priority**: Co-equal with visual display. A grid you can see but not interact with is not useful. Together, US-1 and US-2 form the minimum viable simulated grid.

**Independent Test**: Can be tested by simulating mouse click events at known pixel coordinates and verifying that the grid key callback fires with the correct (x, y, z) values.

**Acceptance Scenarios**:

1. **Given** the simulated grid is displayed, **When** the user left-clicks at pixel position (24, 8) (inside cell x=2, y=1), **Then** the grid key callback fires with (x=2, y=1, z=1).
2. **Given** the user has pressed the mouse button on a cell, **When** the mouse button is released, **Then** the grid key callback fires with the same (x, y) coordinates and z=0.
3. **Given** the simulated grid is displayed, **When** the user clicks cell (16, 8) on the navigation row, **Then** the play/stop toggle fires, identical to pressing the physical grid button at that position.
4. **Given** the simulated grid is displayed, **When** the user clicks outside the grid bounds (e.g., beyond column 16 or row 8), **Then** no grid key event is generated.

---

### User Story 3 - Seamless Provider Integration (Priority: P2)

A musician or developer configures re.kriate to use the simulated grid by setting a configuration option. The simulated grid registers as a standard grid provider, implementing the same interface as hardware grid providers (monome, midigrid, virtual). All existing grid UI logic — page navigation, step editing, loop selection, track switching — works identically without any modification. Switching between simulated and hardware grid requires only a config change, not code changes.

**Why this priority**: Ensures the simulated grid is a drop-in replacement, not a parallel system. Builds on the existing provider pattern and guarantees behavioral parity.

**Independent Test**: Can be tested by running the full existing grid UI test suite against the simulated grid provider and verifying all tests pass without modification.

**Acceptance Scenarios**:

1. **Given** the app is configured with `grid_provider = "simulated"`, **When** `app.init()` is called, **Then** the returned context contains a grid object implementing `all()`, `led()`, `refresh()`, `cols()`, `rows()`, `cleanup()`, and `get_led()`.
2. **Given** the simulated grid provider is active, **When** `grid_ui.redraw(ctx)` is called, **Then** LED state is correctly set on the simulated grid (verifiable via `get_led()`).
3. **Given** the simulated grid provider is active, **When** `grid_ui.key(ctx, x, y, z)` is called, **Then** behavior is identical to calling it with a hardware grid — same state changes, same page transitions, same track selections.

---

### User Story 4 - Brightness-to-Color Fidelity (Priority: P2)

A musician can distinguish between different brightness levels on the simulated grid. The 16 brightness levels (0-15) map to a perceptually distinct color gradient — from near-black at 0 to full warm amber at 15. Intermediate levels (e.g., dim indicators at brightness 4, active regions at brightness 10, playhead at brightness 15) are visually distinguishable from each other, matching the aesthetic feel of monome grid LEDs.

**Why this priority**: Visual clarity is essential for usability. If brightness levels are not distinguishable, the grid display loses critical information (active vs. inactive, playhead vs. loop region, selected vs. unselected).

**Independent Test**: Can be tested by rendering all 16 brightness levels side by side and verifying that each produces a distinct RGB color value with a warm amber hue profile.

**Acceptance Scenarios**:

1. **Given** brightness level 0, **When** converted to color, **Then** the result is near-black (all RGB channels near 0).
2. **Given** brightness level 15, **When** converted to color, **Then** the result is full warm amber (high red, moderate green, low blue).
3. **Given** any two adjacent brightness levels (e.g., 7 and 8), **When** both are converted to color, **Then** the resulting RGB values are numerically distinct.
4. **Given** brightness levels used in the kria UI (4 for dim, 10 for active, 15 for playhead), **When** displayed together, **Then** the three levels are visually distinguishable from each other.

---

### User Story 5 - Grid Rendering Performance (Priority: P3)

The simulated grid renders smoothly without causing frame drops or input lag. The grid display updates at the same refresh rate as the existing grid metro (~30 Hz). Drawing 128 cells (16x8) per frame does not introduce perceptible latency in mouse interaction or sequencer timing.

**Why this priority**: Performance is important but expected to be straightforward given the small number of primitives (128 rectangles per frame). Validating it ensures no surprises.

**Independent Test**: Can be tested by measuring render time for a full grid redraw and verifying it stays well under the frame budget (33ms at 30 Hz).

**Acceptance Scenarios**:

1. **Given** the simulated grid is active and the sequencer is playing, **When** 100 consecutive redraws are performed, **Then** average render time per frame is under 5ms.
2. **Given** the simulated grid is active, **When** the user clicks a cell, **Then** the key event is processed and the grid display updates within the next redraw cycle (no perceptible delay).

---

### Edge Cases

- What happens when the user clicks exactly on the gap between two cells (the 2px padding area)? The click maps to the cell whose filled region is closest, following standard floor-division coordinate math (the gap belongs to the cell above/left).
- What happens when the seamstress window is resized? The grid rendering uses fixed pixel coordinates (256x128 grid area). If the window is larger, the grid remains at its fixed size. The grid does not scale dynamically.
- What happens when the user right-clicks or middle-clicks on the grid? Only left-click (button 1) generates grid key events. Other mouse buttons are ignored.
- What happens when the user clicks and drags across multiple cells? Each cell boundary crossing does not generate additional events. Only the initial press cell and the final release cell produce key events (press on mouse-down cell, release on mouse-up regardless of position — matching physical grid behavior where each button is independent).
- What happens when the simulated grid provider is cleaned up while LEDs are set? Cleanup resets all LED state to 0 and no further rendering occurs.
- What happens when `grid:led()` is called with out-of-bounds coordinates on the simulated provider? Out-of-bounds coordinates are silently ignored, consistent with existing virtual provider behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST register a "simulated" grid provider that implements the standard grid provider interface (`all`, `led`, `refresh`, `cols`, `rows`, `cleanup`, `get_led`, `key` callback).
- **FR-002**: System MUST render the simulated grid as a 16x8 matrix of filled rectangles on the seamstress screen, with each cell sized at 14x14 pixels plus 2px gap (16px pitch).
- **FR-003**: System MUST map grid LED brightness (0-15) to warm amber RGB colors, with brightness 0 producing near-black and brightness 15 producing peak intensity.
- **FR-004**: System MUST convert mouse left-click events to grid key events: press (z=1) on mouse-down and release (z=0) on mouse-up, with pixel-to-grid coordinate conversion using 16px cell pitch.
- **FR-005**: System MUST ignore mouse clicks outside the 16x8 grid area (pixels beyond column 16 or row 8).
- **FR-006**: System MUST ignore non-left-button mouse clicks (right-click, middle-click).
- **FR-007**: System MUST update the grid display during each screen redraw cycle by reading LED state from the simulated provider and drawing colored rectangles.
- **FR-008**: System MUST support configuring the simulated grid via the existing `grid_provider` config option (e.g., `grid_provider = "simulated"`).
- **FR-009**: System MUST allow existing grid UI logic to work without modification when using the simulated grid provider — all page navigation, step editing, loop editing, track selection, and transport controls function identically.
- **FR-010**: System MUST support `get_led(x, y)` on the simulated provider to allow reading individual LED brightness values for rendering and testing.

### Key Entities

- **Simulated Grid Provider**: A grid backend that stores LED state in memory, implements the standard grid interface, and exposes LED state for screen rendering. Key attributes: 16x8 LED state matrix (brightness 0-15 per cell), key callback for input events.
- **Grid Renderer**: A module that reads LED state from the simulated grid provider and draws the visual representation to the seamstress screen. Key attributes: cell size, gap size, brightness-to-color mapping function.
- **Coordinate Mapper**: Logic that converts between screen pixel coordinates and grid cell coordinates (1-indexed, 16x8). Conversion formula: `grid_x = floor(pixel_x / cell_pitch) + 1`, `grid_y = floor(pixel_y / cell_pitch) + 1`.

### Assumptions

- The seamstress screen resolution is 256x128 pixels or larger. The grid occupies the full 256x128 area (16 columns x 16px pitch = 256px, 8 rows x 16px pitch = 128px).
- The existing `virtual` grid provider can serve as a foundation or reference for the simulated provider's LED state management, since it already implements `get_led()` and `get_state()`.
- Warm amber color mapping follows the profile: R scales linearly, G scales at ~70% of R, B scales at ~40% of R. This approximates monome grid LED color temperature.
- The simulated grid is seamstress-only. Norns uses a physical grid; it does not need a screen-rendered grid simulation.
- Mouse drag behavior matches physical grid: only press (mouse-down) and release (mouse-up) events fire. No drag-across-cell events are generated.
- The grid renderer draws before or after existing screen content (sprites, text UI). Drawing order is: clear screen, draw simulated grid, draw any overlay UI.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can interact with all kria sequencer functions (step editing, page navigation, track selection, loop editing, play/stop) using only the mouse on the simulated grid, with no behavioral difference from a physical grid.
- **SC-002**: All 16 brightness levels (0-15) produce visually distinct colors when rendered on screen.
- **SC-003**: All existing grid UI tests pass without modification when run against the simulated grid provider.
- **SC-004**: Coordinate conversion between screen pixels and grid cells is accurate for all 128 cells (16x8), verified by unit tests covering boundary positions (cell corners, edges, gaps).
- **SC-005**: Grid rendering adds less than 5ms per frame to the redraw cycle.
- **SC-006**: The simulated grid can be activated with a single config change (`grid_provider = "simulated"`) — no code changes required.
