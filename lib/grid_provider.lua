-- lib/grid_provider.lua
-- Plugin interface for alternative grid controllers
--
-- Provides a unified grid abstraction that allows swapping between:
--   - monome grid (hardware, via norns grid.connect())
--   - midigrid (MIDI controller emulating grid, github.com/jaggednz/midigrid)
--   - virtual grid (software/remote grid, e.g. driven by remote API)
--   - any custom provider implementing the grid interface
--
-- The grid interface contract:
--   provider:all(brightness)          -- set all LEDs
--   provider:led(x, y, brightness)    -- set single LED (1-indexed, 16x8)
--   provider:refresh()                -- push LED state to device
--   provider.key = function(x, y, z)  -- callback: key press/release
--   provider:cols()                   -- returns number of columns (default 16)
--   provider:rows()                   -- returns number of rows (default 8)
--   provider:cleanup()                -- optional teardown
--
-- Usage in app.lua:
--   local grid_provider = require("lib/grid_provider")
--   ctx.g = grid_provider.connect(config.grid_provider or "monome", config.grid_opts)

local M = {}

-- Registry of provider factories, keyed by name
local providers = {}

--- Register a grid provider factory.
--- @param name string  Provider name (e.g. "monome", "midigrid", "virtual")
--- @param factory function  Factory function(opts) -> grid object
function M.register(name, factory)
  providers[name] = factory
end

--- List registered provider names.
--- @return table  Array of name strings
function M.list()
  local names = {}
  for name in pairs(providers) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- Connect to a grid using the named provider.
--- @param name string|nil  Provider name (default "monome")
--- @param opts table|nil   Provider-specific options
--- @return table  Grid object implementing the interface
function M.connect(name, opts)
  name = name or "monome"
  local factory = providers[name]
  if not factory then
    error("unknown grid provider: " .. tostring(name) .. " (registered: " .. table.concat(M.list(), ", ") .. ")")
  end
  local g = factory(opts or {})
  -- Ensure minimum interface compliance
  assert(g.all, "grid provider must implement :all(brightness)")
  assert(g.led, "grid provider must implement :led(x, y, brightness)")
  assert(g.refresh, "grid provider must implement :refresh()")
  return g
end

------------------------------------------------------------------------
-- Built-in provider: monome (hardware grid via norns grid.connect)
------------------------------------------------------------------------

M.register("monome", function(opts)
  local device_num = opts.device or 1
  local g = grid.connect(device_num)
  -- Wrap with cols/rows/cleanup for interface consistency
  if not g.cols then
    g.cols = function() return 16 end
  end
  if not g.rows then
    g.rows = function() return 8 end
  end
  if not g.cleanup then
    g.cleanup = function() end
  end
  return g
end)

------------------------------------------------------------------------
-- Built-in provider: midigrid (MIDI controller grid emulation)
------------------------------------------------------------------------

M.register("midigrid", function(opts)
  -- midigrid is a drop-in replacement for norns grid
  -- It must be installed on the norns device at ~/dust/code/midigrid/
  local ok, midigrid = pcall(function()
    return include("midigrid/lib/mg_128")
  end)
  if not ok then
    -- Fallback: try require
    ok, midigrid = pcall(require, "midigrid")
  end
  if not ok then
    error("midigrid not found — install from github.com/jaggednz/midigrid")
  end
  local g = midigrid.connect()
  -- Ensure interface consistency
  if not g.cols then
    g.cols = function() return 16 end
  end
  if not g.rows then
    g.rows = function() return 8 end
  end
  if not g.cleanup then
    g.cleanup = function()
      g:all(0)
      g:refresh()
    end
  end
  return g
end)

------------------------------------------------------------------------
-- Built-in provider: virtual (in-memory grid for remote UIs / testing)
------------------------------------------------------------------------

M.register("virtual", function(opts)
  local cols = opts.cols or 16
  local rows = opts.rows or 8
  local leds = {}

  local g = {
    key = nil, -- callback: set by app.lua

    all = function(self, brightness)
      leds = {}
      if brightness and brightness > 0 then
        for y = 1, rows do
          for x = 1, cols do
            leds[y * cols + x] = brightness
          end
        end
      end
    end,

    led = function(self, x, y, brightness)
      leds[y * cols + x] = brightness
    end,

    refresh = function(self)
      -- Notify callback if registered (for remote UIs to poll state)
      if self.on_refresh then
        self:on_refresh()
      end
    end,

    cols = function() return cols end,
    rows = function() return rows end,

    -- Read LED state (for remote UIs and testing)
    get_led = function(self, x, y)
      return leds[y * cols + x] or 0
    end,

    -- Get full LED state as flat table (for remote API snapshot)
    get_state = function(self)
      local state = {}
      for y = 1, rows do
        state[y] = {}
        for x = 1, cols do
          state[y][x] = leds[y * cols + x] or 0
        end
      end
      return state
    end,

    cleanup = function(self)
      leds = {}
    end,
  }

  return g
end)

------------------------------------------------------------------------
-- Built-in provider: synthetic (testing grid with dump & key simulation)
------------------------------------------------------------------------
-- Extends "virtual" with:
--   :dump()                -> formatted text string of LED state
--   :get_led(x, y)        -> brightness at position (0-15)
--   :simulate_key(x, y, z) -> fire key callback as if hardware button pressed
--   :get_state()           -> full LED state as rows[y][x]
--   :clear_state()         -> reset all LEDs to 0
--
-- LED brightness display in dump():
--   .  = 0 (off)
--   1-9 = brightness 1-9
--   A  = 10, B = 11, C = 12, D = 13, E = 14, F = 15

M.register("synthetic", function(opts)
  local cols = opts.cols or 16
  local rows = opts.rows or 8
  local leds = {}

  -- Brightness-to-character mapping for dump()
  local brightness_char = {
    [0] = ".", [1] = "1", [2] = "2", [3] = "3", [4] = "4",
    [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9",
    [10] = "A", [11] = "B", [12] = "C", [13] = "D", [14] = "E", [15] = "F",
  }

  local g = {
    key = nil, -- callback: set by app.lua or test code

    all = function(self, brightness)
      leds = {}
      if brightness and brightness > 0 then
        for y = 1, rows do
          for x = 1, cols do
            leds[y * cols + x] = brightness
          end
        end
      end
    end,

    led = function(self, x, y, brightness)
      leds[y * cols + x] = brightness
    end,

    refresh = function(self)
      if self.on_refresh then
        self:on_refresh()
      end
    end,

    cols = function() return cols end,
    rows = function() return rows end,

    -- Read LED state at position
    get_led = function(self, x, y)
      return leds[y * cols + x] or 0
    end,

    -- Get full LED state as table: state[y][x] = brightness
    get_state = function(self)
      local state = {}
      for y = 1, rows do
        state[y] = {}
        for x = 1, cols do
          state[y][x] = leds[y * cols + x] or 0
        end
      end
      return state
    end,

    -- Format LED state as readable text for test assertions
    dump = function(self)
      local lines = {}
      -- Header row with column numbers
      local header = "    "
      for x = 1, cols do
        header = header .. string.format("%2d ", x)
      end
      lines[#lines + 1] = header
      -- Data rows
      for y = 1, rows do
        local row = string.format("%2d: ", y)
        for x = 1, cols do
          local b = leds[y * cols + x] or 0
          -- Clamp to valid range
          if b < 0 then b = 0 end
          if b > 15 then b = 15 end
          row = row .. string.format(" %s ", brightness_char[b])
        end
        lines[#lines + 1] = row
      end
      return table.concat(lines, "\n")
    end,

    -- Simulate a key press/release (fires the key callback)
    simulate_key = function(self, x, y, z)
      if self.key then
        self.key(x, y, z)
      end
    end,

    -- Reset all LEDs to 0
    clear_state = function(self)
      leds = {}
    end,

    cleanup = function(self)
      leds = {}
    end,
  }

  return g
end)

return M
