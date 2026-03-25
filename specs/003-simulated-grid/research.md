# Research: Simulated Grid (003)

**Feature**: 003-simulated-grid | **Date**: 2026-03-24
**Source**: `specs/simulated-grid-research.md` (prior research), seamstress v1.4.7 API exploration

## Decision 1: Grid Provider Architecture

**Decision**: Register "simulated" as a new built-in provider in `grid_provider.lua`, using the same inline registration pattern as monome/midigrid/virtual.

**Rationale**: The simulated provider's LED state management is identical to the virtual provider (flat table, `y*cols+x` indexing, `get_led()`). Adding it inline keeps provider registration consistent and avoids a new directory structure. The rendering and mouse handling are separate concerns in `lib/seamstress/grid_render.lua` and `seamstress.lua` respectively.

**Alternatives considered**:
- Separate file `lib/grid_providers/simulated.lua`: Creates a new directory convention not used by other providers. Unnecessary indirection for ~30 lines of state management.
- Alias "simulated" to "virtual": Would work for LED state, but naming clarity matters for config documentation. Users expect `grid_provider = "simulated"` to mean "screen-rendered grid".
- Extend virtual provider with rendering: Violates separation of concerns — virtual is for testing/remote UIs, simulated is for screen rendering.

## Decision 2: Brightness-to-Color Mapping

**Decision**: Warm amber profile with linear R, ~70% G, ~40% B scaling:
```lua
local function brightness_to_rgb(brightness)
  local t = brightness / 15
  local r = math.floor(t * 255)
  local g = math.floor(t * 255 * 0.7)
  local b = math.floor(t * 255 * 0.4)
  return r, g, b
end
```

**Rationale**: Matches monome grid LED color temperature. Linear scaling across all channels ensures all 16 levels are numerically distinct. The 70%/40% ratios create a recognizable warm amber that distinguishes the grid from other UI elements.

**Alternatives considered**:
- Monochrome white: Loses the monome aesthetic feel.
- Gamma-corrected curve: More perceptually uniform but adds complexity. Linear is sufficient for 16 discrete levels on an OLED-like display.
- Per-channel lookup tables: Overkill for 16 values with a simple formula.

## Decision 3: Cell Sizing and Layout

**Decision**: Fixed 16px pitch (14px cell + 2px gap), 256x128 grid area, no dynamic scaling.

**Rationale**: Pixel-perfect fit: 16 cols × 16px = 256px width, 8 rows × 16px = 128px height. Exactly fills the seamstress default screen. No offsets, no fractional pixels, no rounding issues. The 2px gap provides visual separation between cells.

**Alternatives considered**:
- Dynamic scaling based on window size: Adds complexity, fractional pixel rounding, and coordinate conversion edge cases. Window resize behavior is explicitly out of scope per spec edge cases.
- Larger cells with smaller grid: Wastes screen space, reduces information density.
- No gap (16px cells touching): Harder to visually distinguish individual cells, especially at low brightness.

## Decision 4: Mouse Event Model

**Decision**: Left-click only. `screen.click(x, y, state, button)` with `state=1` for press, `state=0` for release. No drag events.

**Rationale**: Matches physical grid behavior — each button is independent, press/release only. The seamstress `screen.click` callback provides button discrimination (button 1 = left click). Floor division (`math.floor(px / 16) + 1`) converts pixels to 1-indexed grid coordinates.

**Alternatives considered**:
- Support right-click for secondary actions: Spec explicitly excludes non-left buttons (FR-006). Physical grid has no button types.
- Drag-across events: Physical grid buttons are independent — pressing one button and sliding to another doesn't trigger the second. Matching this behavior avoids surprising interaction differences.

## Decision 5: Rendering Integration Point

**Decision**: Grid rendering happens in `seamstress.lua` `redraw()`, called by existing 30 Hz screen metro. Grid draws first, sprites overlay on top.

**Rationale**: The screen metro at 30 Hz already drives `redraw()`. Adding grid rendering there keeps timing consistent and avoids a second refresh loop. Drawing the grid first (before sprites) means visual effects overlay naturally on the grid background.

**Alternatives considered**:
- Separate rendering metro: Unnecessary overhead, potential double-buffering issues. One redraw loop is cleaner.
- Grid draws on top of sprites: Would obscure visual feedback from sprite voices. Grid-as-background is the natural layer order.
- Conditional rendering only when grid_dirty: Already handled — the grid metro in app.lua sets `grid_dirty`, and `grid_ui.redraw()` pushes LED state. The screen metro always renders current LED state, which is correct.

## Decision 6: Renderer Module Location

**Decision**: `lib/seamstress/grid_render.lua` — new module in the seamstress-specific directory.

**Rationale**: Grid rendering is seamstress-only (uses `screen.color`, `screen.move`, `screen.rect_fill`). Placing it alongside `sprite_render.lua` and `screen_ui.lua` follows the established pattern for platform-specific display modules.

**Alternatives considered**:
- Inline in seamstress.lua: Makes the entrypoint too complex and untestable.
- In lib/ root: Would suggest cross-platform use, which is incorrect.
- Combined with simulated provider: Violates separation — provider manages state, renderer draws it.
