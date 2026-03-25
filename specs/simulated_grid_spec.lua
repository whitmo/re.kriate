-- specs/simulated_grid_spec.lua
-- Tests for simulated grid provider and integration

package.path = package.path .. ";./?.lua"

-- Mock norns grid (needed by grid_provider's monome registration)
rawset(_G, "grid", {
  connect = function(device_num)
    return {
      all = function(self, val) end,
      led = function(self, x, y, brightness) end,
      refresh = function(self) end,
      key = nil,
    }
  end,
})

local grid_provider = require("lib/grid_provider")

describe("simulated grid", function()

  -- ========================================================================
  -- Phase 4: Provider interface compliance (US3)
  -- ========================================================================

  describe("provider registration", function()

    -- T016: list includes "simulated"
    it("appears in grid_provider.list()", function()
      local names = grid_provider.list()
      local found = false
      for _, name in ipairs(names) do
        if name == "simulated" then found = true end
      end
      assert.is_true(found, "simulated not in provider list")
    end)

    -- T017: connect returns full interface
    it("connect returns object with all interface methods", function()
      local g = grid_provider.connect("simulated")
      assert.is_not_nil(g.all)
      assert.is_not_nil(g.led)
      assert.is_not_nil(g.refresh)
      assert.is_not_nil(g.cols)
      assert.is_not_nil(g.rows)
      assert.is_not_nil(g.cleanup)
      assert.is_not_nil(g.get_led)
      assert.is_not_nil(g.get_state)
    end)

  end)

  describe("LED state", function()

    -- T018: led/get_led roundtrip
    it("led(3,5,15) then get_led(3,5) returns 15, get_led(4,5) returns 0", function()
      local g = grid_provider.connect("simulated")
      g:led(3, 5, 15)
      assert.are.equal(15, g:get_led(3, 5))
      assert.are.equal(0, g:get_led(4, 5))
    end)

    -- T019: all() sets and clears
    it("all(10) sets all 128 cells, all(0) clears them", function()
      local g = grid_provider.connect("simulated")
      g:all(10)
      for y = 1, 8 do
        for x = 1, 16 do
          assert.are.equal(10, g:get_led(x, y))
        end
      end
      g:all(0)
      for y = 1, 8 do
        for x = 1, 16 do
          assert.are.equal(0, g:get_led(x, y))
        end
      end
    end)

    -- T020: cleanup resets all LEDs to 0
    it("cleanup() resets all LEDs to 0", function()
      local g = grid_provider.connect("simulated")
      g:led(1, 1, 15)
      g:led(16, 8, 10)
      g:cleanup()
      assert.are.equal(0, g:get_led(1, 1))
      assert.are.equal(0, g:get_led(16, 8))
    end)

  end)

  describe("key callback", function()

    -- T021: key callback receives (x, y, z)
    it("fires key callback with correct (x, y, z)", function()
      local g = grid_provider.connect("simulated")
      local received = {}
      g.key = function(x, y, z)
        received = {x = x, y = y, z = z}
      end
      g.key(5, 3, 1)
      assert.are.equal(5, received.x)
      assert.are.equal(3, received.y)
      assert.are.equal(1, received.z)
    end)

  end)

  describe("dimensions", function()

    -- T022: cols() returns 16, rows() returns 8
    it("cols() returns 16 and rows() returns 8", function()
      local g = grid_provider.connect("simulated")
      assert.are.equal(16, g:cols())
      assert.are.equal(8, g:rows())
    end)

  end)

  -- ========================================================================
  -- Phase 6: Mouse click interaction (US2)
  -- ========================================================================

  describe("mouse click handling", function()

    local grid_render = require("lib/seamstress/grid_render")

    -- T028: left-click at pixel (24,8) → grid key (2,1,1) press, (2,1,0) release
    it("left-click at (24,8) generates key (2,1,1) press and (2,1,0) release", function()
      local g = grid_provider.connect("simulated")
      local events = {}
      g.key = function(x, y, z)
        events[#events + 1] = {x = x, y = y, z = z}
      end
      -- press (state=1, button=1)
      grid_render.handle_click(g, 24, 8, 1, 1)
      -- release (state=0, button=1)
      grid_render.handle_click(g, 24, 8, 0, 1)
      assert.are.equal(2, #events)
      assert.are.equal(2, events[1].x)
      assert.are.equal(1, events[1].y)
      assert.are.equal(1, events[1].z)
      assert.are.equal(2, events[2].x)
      assert.are.equal(1, events[2].y)
      assert.are.equal(0, events[2].z)
    end)

    -- T029: non-left-click is ignored
    it("ignores non-left-click (button 2, 3)", function()
      local g = grid_provider.connect("simulated")
      local events = {}
      g.key = function(x, y, z)
        events[#events + 1] = {x = x, y = y, z = z}
      end
      grid_render.handle_click(g, 24, 8, 1, 2)
      grid_render.handle_click(g, 24, 8, 1, 3)
      assert.are.equal(0, #events)
    end)

    -- T030: click outside grid bounds is ignored
    it("ignores click outside grid bounds (260, 0)", function()
      local g = grid_provider.connect("simulated")
      local events = {}
      g.key = function(x, y, z)
        events[#events + 1] = {x = x, y = y, z = z}
      end
      grid_render.handle_click(g, 260, 0, 1, 1)
      assert.are.equal(0, #events)
    end)

    -- T031: click at boundary pixel (255,127) → cell (16,8)
    it("click at boundary pixel (255,127) maps to cell (16,8)", function()
      local g = grid_provider.connect("simulated")
      local events = {}
      g.key = function(x, y, z)
        events[#events + 1] = {x = x, y = y, z = z}
      end
      grid_render.handle_click(g, 255, 127, 1, 1)
      assert.are.equal(1, #events)
      assert.are.equal(16, events[1].x)
      assert.are.equal(8, events[1].y)
      assert.are.equal(1, events[1].z)
    end)

  end)

end)
