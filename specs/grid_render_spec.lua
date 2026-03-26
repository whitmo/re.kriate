-- specs/grid_render_spec.lua
-- Tests for lib/seamstress/grid_render.lua

package.path = package.path .. ";./?.lua"

local grid_render = require("lib/seamstress/grid_render")

describe("grid_render", function()

  -- ========================================================================
  -- Phase 2: Brightness-to-color mapping (US4)
  -- ========================================================================

  describe("brightness_to_rgb", function()

    -- T005: brightness 0 → black
    it("returns (0, 0, 0) for brightness 0", function()
      local r, g, b = grid_render.brightness_to_rgb(0)
      assert.are.equal(0, r)
      assert.are.equal(0, g)
      assert.are.equal(0, b)
    end)

    -- T006: brightness 15 → full warm amber
    it("returns (255, 178, 102) for brightness 15", function()
      local r, g, b = grid_render.brightness_to_rgb(15)
      assert.are.equal(255, r)
      assert.are.equal(178, g)
      assert.are.equal(102, b)
    end)

    -- T007: all 16 levels produce distinct RGB tuples
    it("produces 16 numerically distinct RGB tuples for brightness 0-15", function()
      local seen = {}
      for brightness = 0, 15 do
        local r, g, b = grid_render.brightness_to_rgb(brightness)
        local key = string.format("%d,%d,%d", r, g, b)
        assert.is_nil(seen[key], "brightness " .. brightness .. " duplicates " .. key)
        seen[key] = brightness
      end
    end)

    -- T008: dim/active/playhead are visually distinguishable (R differs by >30)
    it("brightness 4, 10, 15 have R values differing by >30", function()
      local r4 = grid_render.brightness_to_rgb(4)
      local r10 = grid_render.brightness_to_rgb(10)
      local r15 = grid_render.brightness_to_rgb(15)
      assert.is_true(r10 - r4 > 30, "r10 - r4 should differ by >30")
      assert.is_true(r15 - r10 > 30, "r15 - r10 should differ by >30")
    end)

  end)

  -- ========================================================================
  -- Phase 3: Coordinate conversion (US4)
  -- ========================================================================

  describe("grid_to_pixel", function()

    -- T010: boundary values
    it("converts (1,1) to (0,0) and (16,8) to (240,112)", function()
      local px1, py1 = grid_render.grid_to_pixel(1, 1)
      assert.are.equal(0, px1)
      assert.are.equal(0, py1)
      local px2, py2 = grid_render.grid_to_pixel(16, 8)
      assert.are.equal(240, px2)
      assert.are.equal(112, py2)
    end)

  end)

  describe("pixel_to_grid", function()

    -- T011: boundary values
    it("converts (0,0) to (1,1) and (255,127) to (16,8)", function()
      local gx1, gy1 = grid_render.pixel_to_grid(0, 0)
      assert.are.equal(1, gx1)
      assert.are.equal(1, gy1)
      local gx2, gy2 = grid_render.pixel_to_grid(255, 127)
      assert.are.equal(16, gx2)
      assert.are.equal(8, gy2)
    end)

    -- T012: out-of-bounds returns nil
    it("returns nil for out-of-bounds pixels", function()
      assert.is_nil(grid_render.pixel_to_grid(256, 0))
      assert.is_nil(grid_render.pixel_to_grid(0, 128))
      assert.is_nil(grid_render.pixel_to_grid(-1, 0))
    end)

    -- T013: gap pixels map to correct cell via floor division
    it("maps gap pixels (14,0) and (15,0) to cell (1,1)", function()
      local gx1, gy1 = grid_render.pixel_to_grid(14, 0)
      assert.are.equal(1, gx1)
      assert.are.equal(1, gy1)
      local gx2, gy2 = grid_render.pixel_to_grid(15, 0)
      assert.are.equal(1, gx2)
      assert.are.equal(1, gy2)
    end)

  end)

  -- ========================================================================
  -- Phase 5: Visual display — grid_render.draw() (US1)
  -- ========================================================================

  local function make_mock_grid()
    local leds = {}
    return {
      get_led = function(self, x, y) return leds[y * 16 + x] or 0 end,
      led = function(self, x, y, b) leds[y * 16 + x] = b end,
      all = function(self, b)
        leds = {}
        if b and b > 0 then
          for y2 = 1, 8 do
            for x2 = 1, 16 do leds[y2 * 16 + x2] = b end
          end
        end
      end,
      cols = function() return 16 end,
      rows = function() return 8 end,
    }
  end

  local function make_mock_screen()
    local calls = {}
    return {
      calls = calls,
      color = function(self, r, g, b)
        calls[#calls + 1] = {type = "color", r = r, g = g, b = b}
      end,
      rect_fill = function(self, x, y, w, h)
        calls[#calls + 1] = {type = "rect_fill", x = x, y = y, w = w, h = h}
      end,
    }
  end

  describe("draw", function()

    -- T024: draw calls screen.color and screen.rect_fill for each of 128 cells
    it("calls screen.color and screen.rect_fill for each of 128 cells", function()
      local mock_grid = make_mock_grid()
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      local color_count = 0
      local rect_count = 0
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "color" then color_count = color_count + 1 end
        if call.type == "rect_fill" then rect_count = rect_count + 1 end
      end
      assert.are.equal(128, color_count)
      assert.are.equal(128, rect_count)
    end)

    -- T025: brightness 15 at (3,2) → correct color and position
    it("maps LED brightness 15 at (3,2) to correct color and pixel position", function()
      local mock_grid = make_mock_grid()
      mock_grid:led(3, 2, 15)
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      -- Find the color+rect pair for cell (3,2) — pixel (32, 16)
      local found_color, found_rect = false, false
      for i, call in ipairs(mock_screen.calls) do
        if call.type == "rect_fill" and call.x == 32 and call.y == 16 then
          found_rect = true
          -- The color call should be immediately before
          local prev = mock_screen.calls[i - 1]
          assert.are.equal("color", prev.type)
          assert.are.equal(255, prev.r)
          assert.are.equal(178, prev.g)
          assert.are.equal(102, prev.b)
          found_color = true
        end
      end
      assert.is_true(found_rect, "expected rect_fill at (32, 16)")
      assert.is_true(found_color, "expected warm amber color for brightness 15")
    end)

    -- T026: brightness 0 renders as near-black (0, 0, 0)
    it("renders cells with brightness 0 as black (0, 0, 0)", function()
      local mock_grid = make_mock_grid()
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      -- All cells are brightness 0 → all colors should be (0,0,0)
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "color" then
          assert.are.equal(0, call.r)
          assert.are.equal(0, call.g)
          assert.are.equal(0, call.b)
        end
      end
    end)

  end)

  -- ========================================================================
  -- Phase 9: Performance (US5)
  -- ========================================================================

  describe("performance", function()

    -- T040: 100 consecutive draws complete in under 500ms
    it("100 draws complete in under 500ms (< 5ms avg)", function()
      local mock_grid = make_mock_grid()
      mock_grid:all(8) -- set some non-zero brightness
      local mock_screen = make_mock_screen()
      local start = os.clock()
      for _ = 1, 100 do
        grid_render.draw(mock_grid, mock_screen)
      end
      local elapsed = (os.clock() - start) * 1000  -- ms
      assert.is_true(elapsed < 500, "100 draws took " .. elapsed .. "ms (> 500ms limit)")
    end)

  end)

  -- ========================================================================
  -- Phase 10: Edge cases
  -- ========================================================================

  describe("edge cases", function()

    -- T042: gap click — pixel (15,15) inside gap area maps to cell (1,1)
    it("gap pixel (15,15) maps to cell (1,1) via floor division", function()
      local gx, gy = grid_render.pixel_to_grid(15, 15)
      assert.are.equal(1, gx)
      assert.are.equal(1, gy)
    end)

    -- T045: cleanup mid-render — cleanup resets LED state, next draw renders all-black
    it("cleanup resets LED state so next draw renders all-black", function()
      local mock_grid = make_mock_grid()
      mock_grid:led(5, 3, 15)
      mock_grid:led(10, 7, 10)
      -- Cleanup
      mock_grid:all(0)
      -- Draw should now produce all-black
      local mock_screen = make_mock_screen()
      grid_render.draw(mock_grid, mock_screen)
      for _, call in ipairs(mock_screen.calls) do
        if call.type == "color" then
          assert.are.equal(0, call.r, "expected R=0 after cleanup")
          assert.are.equal(0, call.g, "expected G=0 after cleanup")
          assert.are.equal(0, call.b, "expected B=0 after cleanup")
        end
      end
    end)

  end)

end)
