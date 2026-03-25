# Data Model: Simulated Grid (003)

**Feature**: 003-simulated-grid | **Date**: 2026-03-24

## Entities

### Simulated Grid Provider

The grid provider backend that stores LED state and implements the standard grid interface. Registered as `"simulated"` in `grid_provider.lua`.

| Field | Type | Description |
|-------|------|-------------|
| `leds` | `table` (flat) | LED brightness values, keyed by `y * cols + x`. Values 0-15. Default 0. |
| `key` | `function\|nil` | Callback `function(x, y, z)` set by app.lua for input events. |
| `on_refresh` | `function\|nil` | Optional callback fired on `refresh()` (for remote UIs). |

**Methods** (grid interface contract):

| Method | Signature | Description |
|--------|-----------|-------------|
| `all` | `(self, brightness)` | Set all 128 LEDs to `brightness` (0-15). Resets flat table. |
| `led` | `(self, x, y, brightness)` | Set LED at (x, y) to `brightness`. 1-indexed, 16x8. |
| `refresh` | `(self)` | Push state. Fires `on_refresh` if set. |
| `cols` | `()` | Returns 16. |
| `rows` | `()` | Returns 8. |
| `cleanup` | `(self)` | Reset all LED state to 0. |
| `get_led` | `(self, x, y)` | Returns brightness at (x, y). 0 if unset. |
| `get_state` | `(self)` | Returns 8×16 nested table of brightness values. |

**State transitions**:
- `init` → all LEDs 0, key nil
- `led(x, y, b)` → leds[y*16+x] = b
- `all(b)` → all 128 entries set to b
- `cleanup()` → all LEDs 0

### Grid Render Constants

Layout parameters for screen rendering. These are module-level constants in `grid_render.lua`.

| Constant | Value | Description |
|----------|-------|-------------|
| `CELL_SIZE` | 14 | Filled rectangle size in pixels |
| `CELL_PITCH` | 16 | Cell-to-cell distance (14px cell + 2px gap) |
| `GRID_COLS` | 16 | Number of grid columns |
| `GRID_ROWS` | 8 | Number of grid rows |

### Brightness Color Map

Pure function mapping grid brightness (0-15) to RGB color values.

| Brightness | R | G | B | Visual |
|-----------|-----|-----|-----|--------|
| 0 | 0 | 0 | 0 | Black |
| 1 | 17 | 11 | 6 | Very dim amber |
| 4 | 68 | 47 | 27 | Dim amber (indicators) |
| 8 | 136 | 95 | 54 | Mid amber (active regions) |
| 10 | 170 | 119 | 68 | Bright amber (selected) |
| 15 | 255 | 178 | 102 | Full amber (playhead) |

Formula: `R = floor(b/15 * 255)`, `G = floor(b/15 * 255 * 0.7)`, `B = floor(b/15 * 255 * 0.4)`

### Coordinate Mapping

Conversion between screen pixel space and grid cell space.

**Pixel → Grid** (mouse input):
```
grid_x = floor(pixel_x / CELL_PITCH) + 1
grid_y = floor(pixel_y / CELL_PITCH) + 1
Valid when: 1 <= grid_x <= 16 AND 1 <= grid_y <= 8
```

**Grid → Pixel** (rendering):
```
pixel_x = (grid_x - 1) * CELL_PITCH
pixel_y = (grid_y - 1) * CELL_PITCH
Rectangle drawn at (pixel_x, pixel_y) with size CELL_SIZE × CELL_SIZE
```

## Context Object Changes

The simulated grid feature adds no new fields to `ctx`. It uses existing fields:

| Field | Type | Set By | Used By |
|-------|------|--------|---------|
| `ctx.g` | grid provider | `app.init()` via `grid_provider.connect()` | `grid_ui`, `grid_render`, mouse handler |
| `ctx.grid_dirty` | boolean | `grid_ui.key()`, sequencer | `grid_metro` event |

The grid provider type is determined by `config.grid_provider` passed to `app.init()`. No ctx-level flag needed to distinguish simulated from hardware — the renderer reads LED state via `get_led()` which all providers supporting rendering must implement.

## Relationship to Existing Entities

```
app.init(config)
  └─ grid_provider.connect("simulated")  →  ctx.g (simulated provider)
       ├─ grid_ui.redraw(ctx)  →  ctx.g:led(), ctx.g:refresh()  (LED state set)
       ├─ grid_render.draw(ctx.g)  →  ctx.g:get_led()  (LED state read, screen drawn)
       └─ screen.click  →  pixel_to_grid()  →  ctx.g.key(x, y, z)  (input injection)
```

The simulated provider is a drop-in replacement for any other provider. `grid_ui.lua` is completely unaware of which provider is active.
