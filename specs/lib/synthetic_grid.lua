-- specs/lib/synthetic_grid.lua
-- Test helpers for synthetic grid testing
--
-- Provides convenience functions for setting up a synthetic grid with a ctx,
-- simulating key presses, and asserting on LED state.

local track_mod = require("lib/track")
local grid_provider = require("lib/grid_provider")
local grid_ui = require("lib/grid_ui")

local M = {}

--- Create a synthetic grid and a minimal ctx wired together.
--- @param opts table|nil  Options: active_track, active_page, playing, etc.
--- @return table ctx   Context object for grid_ui
--- @return table g     Synthetic grid instance
function M.setup(opts)
  opts = opts or {}
  local g = grid_provider.connect("synthetic")

  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = opts.active_track or 1,
    active_page = opts.active_page or "trigger",
    playing = opts.playing or false,
    loop_held = opts.loop_held or false,
    loop_first_press = nil,
    grid_dirty = true,
    voices = {},
    clock_ids = nil,
    g = g,
  }

  -- Wire up key callback so simulate_key flows through grid_ui
  g.key = function(x, y, z)
    grid_ui.key(ctx, x, y, z)
    ctx.grid_dirty = true
  end

  return ctx, g
end

--- Render the current grid state (calls grid_ui.redraw).
--- @param ctx table  Context
function M.render(ctx)
  grid_ui.redraw(ctx)
end

--- Simulate a single key press (z=1) at position x,y.
--- @param g table  Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
function M.press(g, x, y)
  g:simulate_key(x, y, 1)
end

--- Simulate a single key release (z=0) at position x,y.
--- @param g table  Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
function M.release(g, x, y)
  g:simulate_key(x, y, 0)
end

--- Simulate a full key tap (press then release) at position x,y.
--- @param g table  Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
function M.tap(g, x, y)
  g:simulate_key(x, y, 1)
  g:simulate_key(x, y, 0)
end

--- Simulate a sequence of key taps.
--- @param g table  Synthetic grid
--- @param presses table  Array of {x, y} pairs
function M.tap_sequence(g, presses)
  for _, p in ipairs(presses) do
    M.tap(g, p[1], p[2])
  end
end

-- Note: assertion helpers use Lua's built-in assert() function, which works
-- in both busted test contexts and plain Lua. The error messages are designed
-- to be informative for test failure diagnosis.

--- Assert that LED at position x,y has a specific brightness.
--- @param g table   Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
--- @param expected number  Expected brightness (0-15)
--- @param msg string|nil  Optional message for assertion
function M.assert_led(g, x, y, expected, msg)
  local actual = g:get_led(x, y)
  local default_msg = string.format("LED(%d,%d) expected %d, got %d", x, y, expected, actual)
  local lua_assert = _G.rawassert or error
  if actual ~= expected then
    error(msg or default_msg)
  end
end

--- Assert that LED at position x,y has brightness >= threshold.
--- @param g table   Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
--- @param threshold number  Minimum brightness
--- @param msg string|nil  Optional message
function M.assert_led_gte(g, x, y, threshold, msg)
  local actual = g:get_led(x, y)
  local default_msg = string.format("LED(%d,%d) expected >= %d, got %d", x, y, threshold, actual)
  if actual < threshold then
    error(msg or default_msg)
  end
end

--- Assert that LED at position x,y has brightness < threshold (dim/off).
--- @param g table   Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
--- @param threshold number  Maximum brightness (exclusive)
--- @param msg string|nil  Optional message
function M.assert_led_lt(g, x, y, threshold, msg)
  local actual = g:get_led(x, y)
  local default_msg = string.format("LED(%d,%d) expected < %d, got %d", x, y, threshold, actual)
  if actual >= threshold then
    error(msg or default_msg)
  end
end

--- Assert that LED at position x,y is off (brightness == 0).
--- @param g table   Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
--- @param msg string|nil  Optional message
function M.assert_led_off(g, x, y, msg)
  M.assert_led(g, x, y, 0, msg)
end

--- Assert that LED at position x,y is on (brightness > 0).
--- @param g table   Synthetic grid
--- @param x number  Column (1-16)
--- @param y number  Row (1-8)
--- @param msg string|nil  Optional message
function M.assert_led_on(g, x, y, msg)
  local actual = g:get_led(x, y)
  local default_msg = string.format("LED(%d,%d) expected on (>0), got %d", x, y, actual)
  if actual <= 0 then
    error(msg or default_msg)
  end
end

--- Dump grid state to string for debugging.
--- @param g table  Synthetic grid
--- @return string  Formatted grid dump
function M.dump(g)
  return g:dump()
end

--- Get a row of LED values as a flat table.
--- @param g table   Synthetic grid
--- @param y number  Row (1-8)
--- @return table    Array of brightness values, index 1-16
function M.get_row(g, y)
  local row = {}
  for x = 1, 16 do
    row[x] = g:get_led(x, y)
  end
  return row
end

--- Count how many LEDs in a row meet a brightness threshold.
--- @param g table   Synthetic grid
--- @param y number  Row (1-8)
--- @param threshold number  Minimum brightness
--- @return number   Count of LEDs >= threshold
function M.count_lit(g, y, threshold)
  threshold = threshold or 1
  local count = 0
  for x = 1, 16 do
    if g:get_led(x, y) >= threshold then
      count = count + 1
    end
  end
  return count
end

return M
