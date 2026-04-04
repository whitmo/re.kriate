-- specs/grid_render_spec.lua
-- Tests for lib/seamstress/grid_render.lua

package.path = package.path .. ";./?.lua"

local grid_render = require("lib/seamstress/grid_render")

-- ========================================================================
-- Helpers
-- ========================================================================

local function make_mock_grid(cols, rows)
  cols = cols or 16
  rows = rows or 8
  local leds = {}
  return {
    get_led = function(self, x, y) return leds[y * cols + x] or 0 end,
    led = function(self, x, y, b) leds[y * cols + x] = b end,
    all = function(self, b)
      leds = {}
      if b and b > 0 then
        for y2 = 1, rows do
          for x2 = 1, cols do leds[y2 * cols + x2] = b end
        end
      end
    end,
    cols = function() return cols end,
    rows = function() return rows end,
    key = nil,
    _keys = {},
  }
end

local function with_key_log(grid)
  grid._keys = {}
  grid.key = function(x, y, z)
    grid._keys[#grid._keys + 1] = {x = x, y = y, z = z}
  end
  return grid
end

local function make_mock_screen()
  local calls = {}
  return {
    calls = calls,
    color = function(r, g, b, a)
      calls[#calls + 1] = {type = "color", r = r, g = g, b = b, a = a}
    end,
    move = function(x, y)
      calls[#calls + 1] = {type = "move", x = x, y = y}
    end,
    rect_fill = function(w, h)
      calls[#calls + 1] = {type = "rect_fill", w = w, h = h}
    end,
  }
end

local function make_perf_screen()
  local noop = function() end
  return {color = noop, move = noop, rect_fill = noop}
end

-- ========================================================================
-- Tests
-- ========================================================================

describe("grid_render", function()

  before_each(function()
    grid_render.reset()
  end)

  -- ======================================================================
  -- Configuration
  -- ======================================================================

  describe("configure", function()

    it("defaults to 128 / yellow / mext", function()
      local c = grid_render.get_config()
      assert.are.equal(128, c.size)
      assert.are.equal("yellow", c.theme)
      assert.are.equal("mext", c.protocol)
      assert.are.equal(16, c.cols)
      assert.are.equal(8, c.rows)
    end)

    it("accepts valid size presets", function()
      grid_render.configure({size = 64})
      local c = grid_render.get_config()
      assert.are.equal(64, c.size)
      assert.are.equal(8, c.cols)
      assert.are.equal(8, c.rows)

      grid_render.configure({size = 256})
      c = grid_render.get_config()
      assert.are.equal(256, c.size)
      assert.are.equal(16, c.cols)
      assert.are.equal(16, c.rows)
    end)

    it("ignores invalid size", function()
      grid_render.configure({size = 999})
      assert.are.equal(128, grid_render.get_config().size)
    end)

    it("accepts valid themes", function()
      for _, name in ipairs(grid_render.THEME_ORDER) do
        grid_render.configure({theme = name})
        assert.are.equal(name, grid_render.get_config().theme)
      end
    end)

    it("ignores invalid theme", function()
      grid_render.configure({theme = "neon"})
      assert.are.equal("yellow", grid_render.get_config().theme)
    end)

    it("accepts protocol modes", function()
      grid_render.configure({protocol = "40h"})
      assert.are.equal("40h", grid_render.get_config().protocol)
    end)

    it("reset restores defaults", function()
      grid_render.configure({size = 64, theme = "red", protocol = "40h"})
      grid_render.reset()
      local c = grid_render.get_config()
      assert.are.equal(128, c.size)
      assert.are.equal("yellow", c.theme)
      assert.are.equal("mext", c.protocol)
    end)

  end)

  -- ======================================================================
  -- Screen dimensions
  -- ======================================================================

  describe("screen dimensions", function()

    it("128 = 256x128", function()
      assert.are.equal(256, grid_render.screen_width())
      assert.are.equal(128, grid_render.screen_height())
    end)

    it("64 = 192x192", function()
      grid_render.configure({size = 64})
      assert.are.equal(192, grid_render.screen_width())
      assert.are.equal(192, grid_render.screen_height())
    end)

    it("256 = 192x192", function()
      grid_render.configure({size = 256})
      assert.are.equal(192, grid_render.screen_width())
      assert.are.equal(192, grid_render.screen_height())
    end)

  end)

  -- ======================================================================
  -- Brightness-to-color mapping
  -- ======================================================================

  describe("brightness_to_rgb", function()

    it("brightness 0 returns theme dark color", function()
      local r, g, b = grid_render.brightness_to_rgb(0)
      assert.are.equal(22, r)
      assert.are.equal(22, g)
      assert.are.equal(21, b)
    end)

    it("brightness 15 returns theme bright color", function()
      local r, g, b = grid_render.brightness_to_rgb(15)
      assert.are.equal(255, r)
      assert.are.equal(250, g)
      assert.are.equal(142, b)
    end)

    it("produces 16 numerically distinct RGB tuples for brightness 0-15", function()
      local seen = {}
      for brightness = 0, 15 do
        local r, g, b = grid_render.brightness_to_rgb(brightness)
        local key = string.format("%d,%d,%d", r, g, b)
        assert.is_nil(seen[key], "brightness " .. brightness .. " duplicates " .. key)
        seen[key] = brightness
      end
    end)

    it("monotonically increases R from brightness 0 to 15", function()
      local prev_r = -1
      for brightness = 0, 15 do
        local r = grid_render.brightness_to_rgb(brightness)
        assert.is_true(r > prev_r, "R should increase at brightness " .. brightness)
        prev_r = r
      end
    end)

    it("spans wide R range from 0 to 15", function()
      local r0 = grid_render.brightness_to_rgb(0)
      local r15 = grid_render.brightness_to_rgb(15)
      assert.is_true(r15 - r0 > 200, "R range " .. (r15 - r0) .. " should exceed 200")
    end)

  end)

  -- ======================================================================
  -- Visual themes
  -- ======================================================================

  describe("themes", function()

    it("each theme produces different bright color", function()
      local brights = {}
      for _, name in ipairs(grid_render.THEME_ORDER) do
        grid_render.configure({theme = name})
        local r, g, b = grid_render.brightness_to_rgb(15)
        local key = string.format("%d,%d,%d", r, g, b)
        assert.is_nil(brights[key], name .. " bright duplicates another theme")
        brights[key] = name
      end
    end)

    it("red theme has warm red bright color", function()
      grid_render.configure({theme = "red"})
      local r, g, b = grid_render.brightness_to_rgb(15)
      assert.are.equal(255, r)
      assert.are.equal(175, g)
      assert.are.equal(30, b)
    end)

    it("white theme has cool white bright color", function()
      grid_render.configure({theme = "white"})
      local r, g, b = grid_render.brightness_to_rgb(15)
      assert.are.equal(255, r)
      assert.are.equal(255, g)
      assert.are.equal(207, b)
    end)

  end)

  -- ======================================================================
  -- Protocol modes
  -- ======================================================================

  describe("protocol modes", function()

    it("mext provides 16 distinct levels", function()
      grid_render.configure({protocol = "mext"})
      local seen = {}
      for b = 0, 15 do
        local r, g, bb = grid_render.brightness_to_rgb(b)
        seen[r] = true
      end
      local count = 0
      for _ in pairs(seen) do count = count + 1 end
      assert.are.equal(16, count)
    end)

    it("40h collapses to binary (off or full)", function()
      grid_render.configure({protocol = "40h"})
      local r0, g0, b0 = grid_render.brightness_to_rgb(0)
      local r1, g1, b1 = grid_render.brightness_to_rgb(1)
      local r8, g8, b8 = grid_render.brightness_to_rgb(8)
      local r15, g15, b15 = grid_render.brightness_to_rgb(15)
      -- 0 is dark
      assert.are.equal(22, r0)
      -- 1 through 15 all map to full brightness
      assert.are.equal(r15, r1)
      assert.are.equal(r15, r8)
      assert.are.equal(g15, g1)
      assert.are.equal(b15, b1)
    end)

    it("series collapses to binary like 40h", function()
      grid_render.configure({protocol = "series"})
      local r0 = grid_render.brightness_to_rgb(0)
      local r1 = grid_render.brightness_to_rgb(1)
      local r15 = grid_render.brightness_to_rgb(15)
      assert.are.equal(22, r0)
      assert.are.equal(r15, r1)
    end)

  end)

  -- ======================================================================
  -- Coordinate conversion
  -- ======================================================================

  describe("grid_to_pixel", function()

    it("converts (1,1) to (0,0) for default 128 size", function()
      local px, py = grid_render.grid_to_pixel(1, 1)
      assert.are.equal(0, px)
      assert.are.equal(0, py)
    end)

    it("converts (16,8) to (240,112) for default 128 size", function()
      local px, py = grid_render.grid_to_pixel(16, 8)
      assert.are.equal(240, px)
      assert.are.equal(112, py)
    end)

    it("uses size-specific pitch for 64", function()
      grid_render.configure({size = 64})
      local px, py = grid_render.grid_to_pixel(2, 3)
      assert.are.equal(24, px)  -- (2-1) * 24
      assert.are.equal(48, py)  -- (3-1) * 24
    end)

    it("uses size-specific pitch for 256", function()
      grid_render.configure({size = 256})
      local px, py = grid_render.grid_to_pixel(2, 3)
      assert.are.equal(12, px)  -- (2-1) * 12
      assert.are.equal(24, py)  -- (3-1) * 12
    end)

  end)

  describe("pixel_to_grid", function()

    it("converts (0,0) to (1,1) and (255,127) to (16,8)", function()
      local gx1, gy1 = grid_render.pixel_to_grid(0, 0)
      assert.are.equal(1, gx1)
      assert.are.equal(1, gy1)
      local gx2, gy2 = grid_render.pixel_to_grid(255, 127)
      assert.are.equal(16, gx2)
      assert.are.equal(8, gy2)
    end)

    it("returns nil for out-of-bounds pixels", function()
      assert.is_nil(grid_render.pixel_to_grid(256, 0))
      assert.is_nil(grid_render.pixel_to_grid(0, 128))
      assert.is_nil(grid_render.pixel_to_grid(-1, 0))
    end)

    it("maps gap pixels to correct cell via floor division", function()
      local gx, gy = grid_render.pixel_to_grid(15, 0)
      assert.are.equal(1, gx)
      assert.are.equal(1, gy)
    end)

    it("respects 64 size bounds", function()
      grid_render.configure({size = 64})
      local gx, gy = grid_render.pixel_to_grid(0, 0)
      assert.are.equal(1, gx)
      assert.are.equal(1, gy)
      -- col 9 is out of bounds for 8x8
      assert.is_nil(grid_render.pixel_to_grid(192, 0))
    end)

    it("respects 256 size bounds (16 rows)", function()
      grid_render.configure({size = 256})
      local gx, gy = grid_render.pixel_to_grid(0, 180)
      assert.are.equal(1, gx)
      assert.are.equal(16, gy)
      -- row 17 out of bounds
      assert.is_nil(grid_render.pixel_to_grid(0, 192))
    end)

  end)

  -- ======================================================================
  -- Drawing
  -- ======================================================================

  describe("draw", function()

    it("calls screen.color and rect_fill for edge + fill per cell (128 = 16x8)", function()
      local mock_grid = make_mock_grid()
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      local color_count, rect_count = 0, 0
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "color" then color_count = color_count + 1 end
        if call.type == "rect_fill" then rect_count = rect_count + 1 end
      end
      -- 2 per cell (edge + fill): 128 cells * 2 = 256
      assert.are.equal(256, color_count)
      assert.are.equal(256, rect_count)
    end)

    it("draws 64 cells for 64 size (8x8)", function()
      grid_render.configure({size = 64})
      local mock_grid = make_mock_grid(8, 8)
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      local rect_count = 0
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "rect_fill" then rect_count = rect_count + 1 end
      end
      assert.are.equal(128, rect_count)  -- 64 cells * 2 (edge + fill)
    end)

    it("draws 256 cells for 256 size (16x16)", function()
      grid_render.configure({size = 256})
      local mock_grid = make_mock_grid(16, 16)
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      local rect_count = 0
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "rect_fill" then rect_count = rect_count + 1 end
      end
      assert.are.equal(512, rect_count)  -- 256 cells * 2 (edge + fill)
    end)

    it("brightness 15 at (3,2) uses theme bright color at inset position", function()
      local mock_grid = make_mock_grid()
      mock_grid:led(3, 2, 15)
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      local found = false
      -- Fill is inset 1px from cell origin: (32+1, 16+1) = (33, 17)
      for i, call in ipairs(mock_screen.calls) do
        if call.type == "move" and call.x == 33 and call.y == 17 then
          local color_call = mock_screen.calls[i - 1]
          assert.are.equal("color", color_call.type)
          assert.are.equal(255, color_call.r)
          assert.are.equal(250, color_call.g)
          assert.are.equal(142, color_call.b)
          found = true
        end
      end
      assert.is_true(found, "expected fill move to (33, 17) with yellow bright color")
    end)

    it("renders brightness 0 cells as theme dark color (fill after edge)", function()
      local mock_grid = make_mock_grid()
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      -- First cell: calls[1]=edge color, [2]=edge move, [3]=edge rect,
      --             calls[4]=fill color, [5]=fill move, [6]=fill rect
      local fill_color = mock_screen.calls[4]
      assert.are.equal("color", fill_color.type)
      assert.are.equal(22, fill_color.r)
      assert.are.equal(22, fill_color.g)
      assert.are.equal(21, fill_color.b)
    end)

    it("renders edge border darker than theme dark color", function()
      local mock_grid = make_mock_grid()
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      -- First color call is the edge color
      local edge = mock_screen.calls[1]
      assert.are.equal("color", edge.type)
      local er, eg, eb = grid_render.edge_rgb()
      assert.are.equal(er, edge.r)
      assert.are.equal(eg, edge.g)
      assert.are.equal(eb, edge.b)
      -- Edge must be darker than theme dark
      assert.is_true(er < 22, "edge R should be darker than dark")
      assert.is_true(eg < 22, "edge G should be darker than dark")
    end)

    it("draws lock dot indicators for locked keys", function()
      local mock_grid = with_key_log(make_mock_grid())
      -- Lock a key via gesture
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(mock_grid, 32, 0, 1, 1) -- cell (3,1)
      grid_render.set_modifier("ctrl", false)
      grid_render.set_modifier("shift", false)

      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)

      -- Should have extra color+move+rect_fill calls for the dot
      local dot_colors = 0
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "color" and call.r == 255 and call.g == 255 and call.b == 255 and call.a == 200 then
          dot_colors = dot_colors + 1
        end
      end
      assert.are.equal(1, dot_colors, "expected 1 lock dot indicator")
    end)

  end)

  -- ======================================================================
  -- Click handling — momentary
  -- ======================================================================

  describe("handle_click — momentary", function()

    it("fires key press and release on normal click", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.handle_click(grid, 0, 0, 1, 1)   -- press (1,1)
      grid_render.handle_click(grid, 0, 0, 0, 1)   -- release (1,1)
      assert.are.equal(2, #grid._keys)
      assert.are.same({x = 1, y = 1, z = 1}, grid._keys[1])
      assert.are.same({x = 1, y = 1, z = 0}, grid._keys[2])
    end)

    it("ignores clicks outside grid", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.handle_click(grid, 300, 0, 1, 1)
      assert.are.equal(0, #grid._keys)
    end)

    it("ignores middle mouse button", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.handle_click(grid, 0, 0, 1, 3)
      assert.are.equal(0, #grid._keys)
    end)

  end)

  -- ======================================================================
  -- Click handling — hold gesture (Ctrl+click)
  -- ======================================================================

  describe("handle_click — hold gesture", function()

    it("Ctrl+click holds key down, ignores mouse release", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.handle_click(grid, 0, 0, 1, 1)   -- press
      grid_render.handle_click(grid, 0, 0, 0, 1)   -- release (ignored in hold mode)
      assert.are.equal(1, #grid._keys)
      assert.are.same({x = 1, y = 1, z = 1}, grid._keys[1])
    end)

    it("Ctrl+click multiple keys holds all simultaneously", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.handle_click(grid, 0, 0, 1, 1)    -- hold (1,1)
      grid_render.handle_click(grid, 16, 0, 1, 1)   -- hold (2,1)
      grid_render.handle_click(grid, 32, 0, 1, 1)   -- hold (3,1)
      assert.are.equal(3, #grid._keys)
      -- All are presses
      for _, k in ipairs(grid._keys) do
        assert.are.equal(1, k.z)
      end
    end)

    it("releasing Ctrl releases all held keys", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.handle_click(grid, 0, 0, 1, 1)   -- hold (1,1)
      grid_render.handle_click(grid, 16, 0, 1, 1)  -- hold (2,1)
      grid_render.set_modifier("ctrl", false)       -- release all
      -- 2 presses + 2 releases
      assert.are.equal(4, #grid._keys)
      local releases = 0
      for _, k in ipairs(grid._keys) do
        if k.z == 0 then releases = releases + 1 end
      end
      assert.are.equal(2, releases)
    end)

    it("held keys appear in get_held_keys while Ctrl is down", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.handle_click(grid, 0, 0, 1, 1)
      local held = grid_render.get_held_keys(grid)
      local count = 0
      for _ in pairs(held) do count = count + 1 end
      assert.are.equal(1, count)
      grid_render.set_modifier("ctrl", false)
      held = grid_render.get_held_keys(grid)
      count = 0
      for _ in pairs(held) do count = count + 1 end
      assert.are.equal(0, count)
    end)

  end)

  -- ======================================================================
  -- Click handling — lock gesture (Ctrl+Shift+click)
  -- ======================================================================

  describe("handle_click — lock gesture", function()

    it("Ctrl+Shift+click locks key (press on first click)", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(grid, 0, 0, 1, 1) -- lock (1,1)
      assert.are.equal(1, #grid._keys)
      assert.are.same({x = 1, y = 1, z = 1}, grid._keys[1])
      local locks = grid_render.get_locked_keys(grid)
      assert.is_true(locks["1:1"] == true)
    end)

    it("Ctrl+Shift+click again unlocks key (release)", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(grid, 0, 0, 1, 1) -- lock
      grid_render.handle_click(grid, 0, 0, 1, 1) -- unlock
      assert.are.equal(2, #grid._keys)
      assert.are.same({x = 1, y = 1, z = 0}, grid._keys[2])
      local locks = grid_render.get_locked_keys(grid)
      assert.is_nil(locks["1:1"])
    end)

    it("locked keys survive Ctrl release", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(grid, 0, 0, 1, 1) -- lock
      grid_render.set_modifier("ctrl", false)
      grid_render.set_modifier("shift", false)
      -- Only the lock press, no release
      assert.are.equal(1, #grid._keys)
      local locks = grid_render.get_locked_keys(grid)
      assert.is_true(locks["1:1"] == true)
    end)

    it("Esc releases all locked keys", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(grid, 0, 0, 1, 1)   -- lock (1,1)
      grid_render.handle_click(grid, 16, 0, 1, 1)  -- lock (2,1)
      grid_render.set_modifier("ctrl", false)
      grid_render.set_modifier("shift", false)
      grid_render.release_locked_keys(grid)
      -- 2 lock presses + 2 Esc releases
      assert.are.equal(4, #grid._keys)
      local locks = grid_render.get_locked_keys(grid)
      local count = 0
      for _ in pairs(locks) do count = count + 1 end
      assert.are.equal(0, count)
    end)

    it("lock and hold work together", function()
      local grid = with_key_log(make_mock_grid())
      -- Lock a key
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(grid, 0, 0, 1, 1) -- lock (1,1)
      grid_render.set_modifier("shift", false)
      -- Now hold another key (Ctrl still down, shift off)
      grid_render.handle_click(grid, 16, 0, 1, 1) -- hold (2,1)
      -- Release Ctrl → held key releases, locked key stays
      grid_render.set_modifier("ctrl", false)
      local locks = grid_render.get_locked_keys(grid)
      assert.is_true(locks["1:1"] == true, "locked key should survive Ctrl release")
      local held = grid_render.get_held_keys(grid)
      local held_count = 0
      for _ in pairs(held) do held_count = held_count + 1 end
      assert.are.equal(0, held_count, "held keys should be released")
    end)

  end)

  -- ======================================================================
  -- Nav button latch (existing behavior)
  -- ======================================================================

  describe("nav button latch", function()

    it("nav loop button (11,8) toggles on press", function()
      local grid = with_key_log(make_mock_grid())
      local px, py = grid_render.grid_to_pixel(11, 8)
      grid_render.handle_click(grid, px, py, 1, 1) -- toggle on
      assert.are.same({x = 11, y = 8, z = 1}, grid._keys[1])
      grid_render.handle_click(grid, px, py, 1, 1) -- toggle off
      assert.are.same({x = 11, y = 8, z = 0}, grid._keys[2])
    end)

    it("nav pattern button (12,8) toggles on press", function()
      local grid = with_key_log(make_mock_grid())
      local px, py = grid_render.grid_to_pixel(12, 8)
      grid_render.handle_click(grid, px, py, 1, 1)
      assert.are.same({x = 12, y = 8, z = 1}, grid._keys[1])
    end)

    it("KEY 1 button (5,8) toggles on press", function()
      local grid = with_key_log(make_mock_grid())
      local px, py = grid_render.grid_to_pixel(5, 8)
      grid_render.handle_click(grid, px, py, 1, 1) -- toggle on
      assert.are.same({x = 5, y = 8, z = 1}, grid._keys[1])
      grid_render.handle_click(grid, px, py, 1, 1) -- toggle off
      assert.are.same({x = 5, y = 8, z = 0}, grid._keys[2])
    end)

    it("nav latch works with right-click too", function()
      local grid = with_key_log(make_mock_grid())
      local px, py = grid_render.grid_to_pixel(11, 8)
      grid_render.handle_click(grid, px, py, 1, 2) -- right-click toggle on
      assert.are.same({x = 11, y = 8, z = 1}, grid._keys[1])
    end)

  end)

  -- ======================================================================
  -- Modifier state
  -- ======================================================================

  describe("modifier state", function()

    it("tracks ctrl and shift independently", function()
      grid_render.set_modifier("ctrl", true)
      assert.is_true(grid_render.get_modifier("ctrl"))
      assert.is_false(grid_render.get_modifier("shift"))
      grid_render.set_modifier("shift", true)
      assert.is_true(grid_render.get_modifier("shift"))
    end)

    it("reset clears modifiers", function()
      grid_render.set_modifier("ctrl", true)
      grid_render.reset()
      assert.is_false(grid_render.get_modifier("ctrl"))
    end)

  end)

  -- ======================================================================
  -- Performance
  -- ======================================================================

  describe("performance", function()

    it("100 draws of 128 grid complete in under 1000ms", function()
      local mock_grid = make_mock_grid()
      mock_grid:all(8)
      local mock_screen = make_perf_screen()
      local start = os.clock()
      for _ = 1, 100 do
        grid_render.draw(mock_grid, mock_screen)
      end
      local elapsed = (os.clock() - start) * 1000
      assert.is_true(elapsed < 1000, "100 draws took " .. elapsed .. "ms (> 1000ms limit)")
    end)

  end)

  -- ======================================================================
  -- Edge cases
  -- ======================================================================

  describe("edge cases", function()

    it("gap pixel maps to correct cell", function()
      local gx, gy = grid_render.pixel_to_grid(15, 15)
      assert.are.equal(1, gx)
      assert.are.equal(1, gy)
    end)

    it("cleanup resets LED state so next draw renders all dark", function()
      local mock_grid = make_mock_grid()
      mock_grid:led(5, 3, 15)
      mock_grid:all(0)
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      -- Every other color call (with a==255) is a fill; check those are dark
      local color_idx = 0
      local er = grid_render.edge_rgb()
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "color" and call.a == 255 then
          color_idx = color_idx + 1
          if color_idx % 2 == 0 then  -- fill colors (even)
            assert.are.equal(22, call.r, "expected R=22 (dark) after cleanup")
          else  -- edge colors (odd)
            assert.are.equal(er, call.r, "expected edge R after cleanup")
          end
        end
      end
    end)

    it("handle_click with nil button defaults to left", function()
      local grid = with_key_log(make_mock_grid())
      grid_render.handle_click(grid, 0, 0, 1, nil)
      assert.are.equal(1, #grid._keys)
    end)

    it("per-grid state isolation", function()
      local g1 = with_key_log(make_mock_grid())
      local g2 = with_key_log(make_mock_grid())
      grid_render.set_modifier("ctrl", true)
      grid_render.set_modifier("shift", true)
      grid_render.handle_click(g1, 0, 0, 1, 1) -- lock on g1
      grid_render.set_modifier("ctrl", false)
      grid_render.set_modifier("shift", false)
      local locks1 = grid_render.get_locked_keys(g1)
      local locks2 = grid_render.get_locked_keys(g2)
      assert.is_true(locks1["1:1"] == true)
      local count2 = 0
      for _ in pairs(locks2) do count2 = count2 + 1 end
      assert.are.equal(0, count2, "g2 should have no locked keys")
    end)

  end)

end)
