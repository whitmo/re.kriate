-- specs/grid_provider_spec.lua
-- Tests for lib/grid_provider.lua: plugin interface for alternative grid controllers

package.path = package.path .. ";./?.lua"

-- Mock norns grid (used by "monome" provider)
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

-- Mock midigrid (used by "midigrid" provider test)
-- We'll intercept the require/include for testing below

local grid_provider = require("lib/grid_provider")

describe("grid_provider", function()

  -- ========================================================================
  -- Provider registry
  -- ========================================================================

  describe("registry", function()

    it("lists built-in providers", function()
      local names = grid_provider.list()
      local found = {}
      for _, name in ipairs(names) do found[name] = true end
      assert.is_true(found["monome"], "should have monome provider")
      assert.is_true(found["virtual"], "should have virtual provider")
      assert.is_true(found["midigrid"], "should have midigrid provider")
    end)

    it("registers a custom provider", function()
      grid_provider.register("test_custom", function(opts)
        return {
          all = function(self, b) end,
          led = function(self, x, y, b) end,
          refresh = function(self) end,
        }
      end)
      local names = grid_provider.list()
      local found = false
      for _, name in ipairs(names) do
        if name == "test_custom" then found = true end
      end
      assert.is_true(found, "should register custom provider")
    end)

    it("errors on unknown provider", function()
      assert.has_error(function()
        grid_provider.connect("nonexistent")
      end, nil)
    end)

  end)

  -- ========================================================================
  -- Monome provider
  -- ========================================================================

  describe("monome provider", function()

    it("connects via grid.connect()", function()
      local g = grid_provider.connect("monome")
      assert.is_not_nil(g)
      assert.is_function(g.all)
      assert.is_function(g.led)
      assert.is_function(g.refresh)
    end)

    it("is the default when no name given", function()
      local g = grid_provider.connect()
      assert.is_not_nil(g)
    end)

    it("adds cols/rows/cleanup if missing", function()
      local g = grid_provider.connect("monome")
      assert.is_function(g.cols)
      assert.is_function(g.rows)
      assert.are.equal(16, g.cols())
      assert.are.equal(8, g.rows())
      assert.is_function(g.cleanup)
    end)

    it("passes device option to grid.connect", function()
      local captured_num
      rawset(_G, "grid", {
        connect = function(n)
          captured_num = n
          return {
            all = function(self, val) end,
            led = function(self, x, y, b) end,
            refresh = function(self) end,
          }
        end,
      })
      grid_provider.connect("monome", { device = 2 })
      assert.are.equal(2, captured_num)
      -- Restore default mock
      rawset(_G, "grid", {
        connect = function()
          return {
            all = function(self, val) end,
            led = function(self, x, y, b) end,
            refresh = function(self) end,
            key = nil,
          }
        end,
      })
    end)

  end)

  -- ========================================================================
  -- Virtual provider
  -- ========================================================================

  describe("virtual provider", function()

    it("creates a virtual grid with default dimensions", function()
      local g = grid_provider.connect("virtual")
      assert.is_not_nil(g)
      assert.are.equal(16, g:cols())
      assert.are.equal(8, g:rows())
    end)

    it("supports custom dimensions", function()
      local g = grid_provider.connect("virtual", { cols = 8, rows = 16 })
      assert.are.equal(8, g:cols())
      assert.are.equal(16, g:rows())
    end)

    it("implements all() to set all LEDs", function()
      local g = grid_provider.connect("virtual")
      g:all(10)
      -- Spot check a few positions
      assert.are.equal(10, g:get_led(1, 1))
      assert.are.equal(10, g:get_led(16, 8))
      assert.are.equal(10, g:get_led(8, 4))
    end)

    it("all(0) clears all LEDs", function()
      local g = grid_provider.connect("virtual")
      g:led(5, 3, 12)
      g:all(0)
      assert.are.equal(0, g:get_led(5, 3))
    end)

    it("implements led() to set single LEDs", function()
      local g = grid_provider.connect("virtual")
      g:led(3, 5, 15)
      assert.are.equal(15, g:get_led(3, 5))
      -- Other positions still 0
      assert.are.equal(0, g:get_led(4, 5))
    end)

    it("implements get_state() for full LED dump", function()
      local g = grid_provider.connect("virtual")
      g:all(0)
      g:led(1, 1, 5)
      g:led(16, 8, 12)
      local state = g:get_state()
      assert.is_table(state)
      assert.are.equal(5, state[1][1])
      assert.are.equal(12, state[8][16])
      assert.are.equal(0, state[4][8])
    end)

    it("implements refresh() without error", function()
      local g = grid_provider.connect("virtual")
      -- Should not error
      g:refresh()
    end)

    it("calls on_refresh callback when refresh() is called", function()
      local g = grid_provider.connect("virtual")
      local refreshed = false
      g.on_refresh = function() refreshed = true end
      g:refresh()
      assert.is_true(refreshed)
    end)

    it("supports key callback assignment", function()
      local g = grid_provider.connect("virtual")
      local captured = {}
      g.key = function(x, y, z)
        captured = { x = x, y = y, z = z }
      end
      g.key(5, 3, 1)
      assert.are.equal(5, captured.x)
      assert.are.equal(3, captured.y)
      assert.are.equal(1, captured.z)
    end)

    it("cleanup clears LED state", function()
      local g = grid_provider.connect("virtual")
      g:led(5, 3, 12)
      g:cleanup()
      assert.are.equal(0, g:get_led(5, 3))
    end)

  end)

  -- ========================================================================
  -- Interface compliance validation
  -- ========================================================================

  describe("interface validation", function()

    it("rejects provider missing all()", function()
      grid_provider.register("bad_no_all", function(opts)
        return {
          led = function() end,
          refresh = function() end,
        }
      end)
      assert.has_error(function()
        grid_provider.connect("bad_no_all")
      end)
    end)

    it("rejects provider missing led()", function()
      grid_provider.register("bad_no_led", function(opts)
        return {
          all = function() end,
          refresh = function() end,
        }
      end)
      assert.has_error(function()
        grid_provider.connect("bad_no_led")
      end)
    end)

    it("rejects provider missing refresh()", function()
      grid_provider.register("bad_no_refresh", function(opts)
        return {
          all = function() end,
          led = function() end,
        }
      end)
      assert.has_error(function()
        grid_provider.connect("bad_no_refresh")
      end)
    end)

  end)

  -- ========================================================================
  -- Custom provider end-to-end
  -- ========================================================================

  describe("custom provider", function()

    it("works end-to-end with grid_ui", function()
      -- Register a provider that records LED calls
      local led_calls = {}
      grid_provider.register("recording", function(opts)
        return {
          all = function(self, b) end,
          led = function(self, x, y, b)
            led_calls[#led_calls + 1] = { x = x, y = y, b = b }
          end,
          refresh = function(self) end,
        }
      end)

      local g = grid_provider.connect("recording")
      assert.is_not_nil(g)

      -- Simulate what grid_ui would do
      g:led(5, 3, 15)
      assert.are.equal(1, #led_calls)
      assert.are.equal(5, led_calls[1].x)
      assert.are.equal(3, led_calls[1].y)
      assert.are.equal(15, led_calls[1].b)
    end)

  end)

end)
