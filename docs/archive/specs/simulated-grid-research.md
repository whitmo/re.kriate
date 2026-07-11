# Simulated Grid Research — Seamstress v1.4.7

Research for implementing a visual interactive grid in the seamstress window.

## Seamstress Mouse API

Seamstress v1.4.7 provides mouse callbacks as `screen` global properties:

- `screen.click(x, y, state, button)` — mouse click (state: 1=press, 0=release; button: 1=left)
- `screen.mouse(x, y)` — mouse movement
- `screen.wheel(x, y)` — scroll wheel

Same pattern as `screen.key` already wired in seamstress.lua.

## Screen Drawing Primitives

- `screen.rect_fill(width, height)` — filled rectangle at current position
- `screen.color(r, g, b, a)` — RGBA color (0-255)
- `screen.move(x, y)` — position cursor
- `screen.circle_fill(radius)` — filled circle
- `screen.clear()` — clear screen
- `screen.text(str)` — render text
- `screen.refresh()` — flip buffer

Screen resolution: 256x128 pixels, full color, resizable.

## Grid Brightness → RGB Mapping

Monome grid uses 0-15 brightness (4-bit). Warm white/amber LED feel:

```lua
local function brightness_to_rgb(brightness)
  local intensity = (brightness / 15) * 255
  return math.floor(intensity),
         math.floor(intensity * 0.7),
         math.floor(intensity * 0.4)
end
```

## Cell Sizing Math

16x8 grid in 256x128 screen:
- Cell size 14px + 2px gap = 16px per cell
- Width: 16 cells × 16px = 256px ✓
- Height: 8 cells × 16px = 128px ✓

Pixel-perfect fit with no offsets needed.

## Architecture: Grid Provider Backend

The existing `grid_provider.lua` already supports pluggable backends. The simulated
grid registers as a new provider implementing the same interface:

**Required interface:**
- `grid:all(brightness)` — set all LEDs
- `grid:led(x, y, brightness)` — set single LED (1-indexed)
- `grid:refresh()` — flush state (triggers redraw)
- `grid.key = function(x, y, z)` — callback set by app.lua
- `grid:cols()` → 16
- `grid:rows()` → 8
- `grid:cleanup()` — teardown
- `grid:get_led(x, y)` → brightness (needed for rendering)

**New modules:**
- `lib/grid_providers/simulated.lua` — grid provider backend (LED state + interface)
- `lib/seamstress/grid_render.lua` — draws grid to screen (reads LED state, maps to colors)

**Mouse handler** (in seamstress.lua):
```lua
screen.click = log.wrap(function(x, y, state, button)
  if button == 1 then
    local gx = math.floor(x / 16) + 1
    local gy = math.floor(y / 16) + 1
    if gx >= 1 and gx <= 16 and gy >= 1 and gy <= 8 then
      ctx.g.key(gx, gy, state)
    end
  end
end, "grid_click")
```

**Rendering** (in seamstress.lua redraw, before or after sprites):
```lua
grid_render.draw(ctx)  -- reads ctx.g LED state, draws colored rects
```

## Coexistence with Sprites

Current rendering order in seamstress.lua:
1. `screen.clear()` → black
2. `screen.rect_fill(256, 128)` → black canvas
3. `sprite_render.draw(ctx)` → visual sprites

Grid render can replace or coexist — the grid IS the main display when no
hardware grid is present. Sprites overlay on top.

## Config Integration

```lua
ctx = app.init({
  grid_provider = "simulated",  -- or "grid" for hardware
  grid_opts = { cell_size = 14, padding = 2 },
  ...
})
```

## Testing Strategy

- Unit tests for coordinate conversion (screen px → grid cell, grid cell → screen px)
- Unit tests for brightness→RGB mapping
- Integration tests: simulated click → grid.key fires → state changes → LED updates
- Reuse existing `specs/grid_ui_spec.lua` patterns — all grid behavior should be provider-agnostic
