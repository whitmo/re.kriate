-- lib/seamstress/grid_render.lua
-- Grid LED → screen renderer for simulated grid
--
-- Renders a configurable grid on the seamstress screen with:
--   - Three sizes: 64 (8x8), 128 (16x8), 256 (16x16)
--   - Four visual themes with exponential brightness curves
--   - Hold (Ctrl+click) and lock (Ctrl+Shift+click) gestures
--   - Mext varibright and non-varibright protocol modes
--
-- Modeled after monome-rack VCV virtual grid.

local M = {}

-- ========================================================================
-- Size presets
-- ========================================================================

M.SIZES = {
  [64]  = {cols = 8,  rows = 8,  cell_size = 22, cell_pitch = 24},
  [128] = {cols = 16, rows = 8,  cell_size = 15, cell_pitch = 16},
  [256] = {cols = 16, rows = 16, cell_size = 11, cell_pitch = 12},
}

-- ========================================================================
-- Theme definitions — modeled after monome-rack hardware eras
-- ========================================================================
-- Each theme defines bright (level 15) and dark (level 0) RGB endpoints.
-- Intermediate levels use exponential interpolation between them.

M.THEMES = {
  yellow = {bright = {255, 250, 142}, dark = {22, 22, 21}},
  red    = {bright = {255, 175, 30},  dark = {20, 15, 5}},
  orange = {bright = {255, 210, 75},  dark = {15, 15, 0}},
  white  = {bright = {255, 255, 207}, dark = {30, 22, 22}},
}

M.THEME_ORDER = {"yellow", "red", "orange", "white"}

-- ========================================================================
-- Protocol modes
-- ========================================================================

M.PROTOCOLS = {"mext", "series", "40h"}

-- ========================================================================
-- Module state
-- ========================================================================

local config = {size = 128, theme = "yellow", protocol = "mext"}
local grid_cols = 16
local grid_rows = 8
local cell_size = 14
local cell_pitch = 16

-- Exponential brightness curve constant (negative = quick rise at low levels,
-- matching monome-rack's approach for screen-visible dim LEDs)
local CURVE_K = -2.7

-- Cell edge inset (pixels) — 1px border around each cell for definition
local EDGE_INSET = 1

-- Modifier keys (global — one keyboard shared across grids)
local modifier_state = {ctrl = false, shift = false}

-- Per-grid weak-keyed state tables
local nav_latch   = setmetatable({}, {__mode = "k"})
local held_keys   = setmetatable({}, {__mode = "k"})
local locked_keys = setmetatable({}, {__mode = "k"})

-- Nav button positions (for existing latch behavior)
local NAV_KEY1_X = 5      -- Ansible KEY 1: time modifier
local NAV_LOOP_X = 11
local NAV_PATTERN_X = 12
local NAV_PROB_X = 14     -- probability modifier
local NAV_Y = 8

-- ========================================================================
-- Configuration
-- ========================================================================

--- Configure the grid renderer. Call before creating grids.
--- @param opts table  {size=64|128|256, theme=string, protocol=string}
function M.configure(opts)
  if opts.size and M.SIZES[opts.size] then
    config.size = opts.size
    local p = M.SIZES[opts.size]
    grid_cols, grid_rows = p.cols, p.rows
    cell_size, cell_pitch = p.cell_size, p.cell_pitch
  end
  if opts.theme and M.THEMES[opts.theme] then
    config.theme = opts.theme
  end
  if opts.protocol then
    config.protocol = opts.protocol
  end
end

--- Reset to defaults (for testing).
function M.reset()
  config = {size = 128, theme = "yellow", protocol = "mext"}
  local p = M.SIZES[128]
  grid_cols, grid_rows = p.cols, p.rows
  cell_size, cell_pitch = p.cell_size, p.cell_pitch
  modifier_state = {ctrl = false, shift = false}
  nav_latch = setmetatable({}, {__mode = "k"})
  held_keys = setmetatable({}, {__mode = "k"})
  locked_keys = setmetatable({}, {__mode = "k"})
end

--- Get current configuration.
--- @return table  {size, theme, protocol, cols, rows, cell_size, cell_pitch}
function M.get_config()
  return {
    size = config.size, theme = config.theme, protocol = config.protocol,
    cols = grid_cols, rows = grid_rows,
    cell_size = cell_size, cell_pitch = cell_pitch,
  }
end

--- Screen width in pixels for the current size.
function M.screen_width()  return grid_cols * cell_pitch end

--- Screen height in pixels for the current size.
function M.screen_height() return grid_rows * cell_pitch end

-- ========================================================================
-- Modifier tracking (called from seamstress.lua screen.key)
-- ========================================================================

--- Update modifier key state. Releasing Ctrl auto-releases all held keys.
--- @param name string  "ctrl" or "shift"
--- @param pressed boolean
function M.set_modifier(name, pressed)
  local was = modifier_state[name]
  modifier_state[name] = pressed
  if name == "ctrl" and was and not pressed then
    M._release_all_held()
  end
end

--- Read current modifier state (for testing).
function M.get_modifier(name)
  return modifier_state[name] or false
end

-- ========================================================================
-- Edge color (darker than LED-off for visible cell framing)
-- ========================================================================

local function compute_edge_rgb()
  local t = M.THEMES[config.theme] or M.THEMES.yellow
  return math.max(0, math.floor(t.dark[1] * 0.4)),
         math.max(0, math.floor(t.dark[2] * 0.4)),
         math.max(0, math.floor(t.dark[3] * 0.4))
end

--- Get the current theme's cell edge color (for testing/introspection).
--- @return number, number, number  R, G, B values (0-255)
function M.edge_rgb()
  return compute_edge_rgb()
end

-- ========================================================================
-- Brightness mapping
-- ========================================================================

local function exp_curve(x, k)
  if x <= 0 then return 0 end
  if x >= 1 then return 1 end
  return (math.exp(k * x) - 1) / (math.exp(k) - 1)
end

--- Map grid brightness (0-15) to theme-aware RGB color.
--- Non-varibright protocols collapse to binary (off/full).
--- @param brightness number  Brightness level 0-15
--- @return number, number, number  R, G, B values (0-255)
function M.brightness_to_rgb(brightness)
  if config.protocol ~= "mext" then
    brightness = brightness > 0 and 15 or 0
  end
  local t = M.THEMES[config.theme] or M.THEMES.yellow
  local ratio = exp_curve(brightness / 15, CURVE_K)
  local r = math.floor(t.dark[1] + ratio * (t.bright[1] - t.dark[1]))
  local g = math.floor(t.dark[2] + ratio * (t.bright[2] - t.dark[2]))
  local b = math.floor(t.dark[3] + ratio * (t.bright[3] - t.dark[3]))
  return r, g, b
end

-- ========================================================================
-- Coordinate conversion
-- ========================================================================

--- Convert grid cell to top-left screen pixel position.
--- @param gx number  Grid column (1-indexed)
--- @param gy number  Grid row (1-indexed)
--- @return number, number  Pixel x, y
function M.grid_to_pixel(gx, gy)
  return (gx - 1) * cell_pitch, (gy - 1) * cell_pitch
end

--- Convert screen pixel to grid cell coordinates.
--- @param px number  Pixel x
--- @param py number  Pixel y
--- @return number|nil, number|nil  Grid x, y (1-indexed) or nil if out of bounds
function M.pixel_to_grid(px, py)
  if px < 0 or py < 0 then return nil end
  local gx = math.floor(px / cell_pitch) + 1
  local gy = math.floor(py / cell_pitch) + 1
  if gx < 1 or gx > grid_cols or gy < 1 or gy > grid_rows then return nil end
  return gx, gy
end

-- ========================================================================
-- Drawing
-- ========================================================================

--- Draw the simulated grid to the screen.
--- @param grid table  Grid provider with get_led(x, y)
--- @param scr table  Screen object with color(), move(), rect_fill()
--- @param opts table|nil  Optional {loop_start=N, loop_end=N} for boundary indicators
function M.draw(grid, scr, opts)
  local locks = locked_keys[grid]
  local er, eg, eb = compute_edge_rgb()
  local fill_size = cell_size - EDGE_INSET * 2
  for y = 1, grid_rows do
    for x = 1, grid_cols do
      local brightness = grid:get_led(x, y)
      local r, g, b = M.brightness_to_rgb(brightness)
      local px, py = M.grid_to_pixel(x, y)
      -- Cell edge border (dark frame around each cell)
      scr.color(er, eg, eb, 255)
      scr.move(px, py)
      scr.rect_fill(cell_size, cell_size)
      -- Cell fill (inset for edge visibility)
      scr.color(r, g, b, 255)
      scr.move(px + EDGE_INSET, py + EDGE_INSET)
      scr.rect_fill(fill_size, fill_size)
      -- Lock dot indicator (lower-left corner of cell)
      if locks and locks[x .. ":" .. y] then
        local dot = math.max(2, math.floor(cell_size / 5))
        scr.color(255, 255, 255, 200)
        scr.move(px + 2, py + cell_size - dot - 2)
        scr.rect_fill(dot, dot)
      end
    end
  end
  -- Loop boundary indicators (light grey vertical lines)
  if opts and opts.loop_start and opts.loop_end then
    local indicator_h = (grid_rows - 1) * cell_pitch
    -- Left edge of loop_start column
    scr.color(100, 100, 100, 255)
    scr.move((opts.loop_start - 1) * cell_pitch, 0)
    scr.rect_fill(1, indicator_h)
    -- Right edge of loop_end column
    scr.color(100, 100, 100, 255)
    scr.move((opts.loop_end - 1) * cell_pitch + cell_size, 0)
    scr.rect_fill(1, indicator_h)
  end
end

-- ========================================================================
-- Click handling with hold/lock gestures
-- ========================================================================

local function fire_key(grid, x, y, z)
  if grid.key then grid.key(x, y, z) end
end

local function ensure_state(grid)
  if not nav_latch[grid] then nav_latch[grid] = {} end
  if not held_keys[grid] then held_keys[grid] = {} end
  if not locked_keys[grid] then locked_keys[grid] = {} end
end

--- Handle mouse click on the simulated grid.
--- Gesture modes:
---   Normal click = momentary press/release
---   Ctrl+click   = hold (keys stay down until Ctrl released)
---   Ctrl+Shift+click = lock/toggle (stays until clicked again or Esc)
--- @param grid table  Grid provider with key callback
--- @param px number  Pixel x
--- @param py number  Pixel y
--- @param state number  1 for press, 0 for release
--- @param button number  Mouse button (1=left, 2=right)
function M.handle_click(grid, px, py, state, button)
  button = button or 1
  if button ~= 1 and button ~= 2 then return end
  local gx, gy = M.pixel_to_grid(px, py)
  if not gx then return end

  ensure_state(grid)

  -- Nav modifier buttons (loop, pattern): toggle/latch on any click
  if gy == NAV_Y and (gx == NAV_KEY1_X or gx == NAV_LOOP_X or gx == NAV_PATTERN_X or gx == NAV_PROB_X) and grid_rows >= 8 then
    if state ~= 1 then return end
    local key = gx .. ":" .. gy
    local currently = nav_latch[grid][key] == true
    nav_latch[grid][key] = not currently
    fire_key(grid, gx, gy, currently and 0 or 1)
    return
  end

  -- Right-click on non-nav cells: reserved
  if button == 2 then return end

  local key = gx .. ":" .. gy

  -- Ctrl+Shift+Click = lock/toggle
  if modifier_state.ctrl and modifier_state.shift then
    if state == 1 then
      if locked_keys[grid][key] then
        locked_keys[grid][key] = nil
        fire_key(grid, gx, gy, 0)
      else
        locked_keys[grid][key] = true
        fire_key(grid, gx, gy, 1)
      end
    end
    return
  end

  -- Ctrl+Click = hold (stays pressed until Ctrl released)
  if modifier_state.ctrl then
    if state == 1 then
      held_keys[grid][key] = {x = gx, y = gy}
      fire_key(grid, gx, gy, 1)
    end
    -- Ignore mouse release in hold mode
    return
  end

  -- Normal click = momentary
  fire_key(grid, gx, gy, state)
end

-- ========================================================================
-- Key release
-- ========================================================================

--- Release all Ctrl-held keys across all grids (called on Ctrl release).
function M._release_all_held()
  for grid, keys in pairs(held_keys) do
    for _, pos in pairs(keys) do
      fire_key(grid, pos.x, pos.y, 0)
    end
    held_keys[grid] = {}
  end
end

--- Release all locked keys for a specific grid (Esc handler).
--- @param grid table  Grid provider
function M.release_locked_keys(grid)
  local keys = locked_keys[grid]
  if not keys then return end
  for k in pairs(keys) do
    local x, y = k:match("(%d+):(%d+)")
    if x and y then
      fire_key(grid, tonumber(x), tonumber(y), 0)
    end
  end
  locked_keys[grid] = {}
end

--- Get locked key state for a grid (for testing/introspection).
function M.get_locked_keys(grid)
  return locked_keys[grid] or {}
end

--- Get held key state for a grid (for testing/introspection).
function M.get_held_keys(grid)
  return held_keys[grid] or {}
end

return M
