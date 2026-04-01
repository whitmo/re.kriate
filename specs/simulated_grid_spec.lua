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

  -- ========================================================================
  -- Phase 7: Seamstress wiring integration (US1+US2)
  -- ========================================================================

  describe("wiring integration", function()

    local grid_render = require("lib/seamstress/grid_render")

    -- T033: redraw() path — grid_render.draw works with simulated provider
    it("grid_render.draw renders simulated provider LED state to mock screen", function()
      local g = grid_provider.connect("simulated")
      g:led(1, 1, 15)
      g:led(8, 4, 10)
      local calls = {}
      local mock_screen = {
        color = function(r, gc, b, a) calls[#calls + 1] = {type = "color", r = r, g = gc, b = b} end,
        move = function(x, y) calls[#calls + 1] = {type = "move", x = x, y = y} end,
        rect_fill = function(w, h) calls[#calls + 1] = {type = "rect_fill", w = w, h = h} end,
      }
      grid_render.draw(g, mock_screen)
      -- 128 cells drawn (color + move + rect_fill per cell = 384 calls)
      local colors = 0
      for _, c in ipairs(calls) do if c.type == "color" then colors = colors + 1 end end
      assert.are.equal(128, colors)
      -- Cell (1,1) should have yellow theme bright color (brightness 15)
      assert.are.equal(255, calls[1].r)
      assert.are.equal(250, calls[1].g)
    end)

    -- T034: screen.click path — handle_click delegates to simulated provider key callback
    it("handle_click fires simulated provider key callback with correct coordinates", function()
      local g = grid_provider.connect("simulated")
      local events = {}
      g.key = function(x, y, z) events[#events + 1] = {x = x, y = y, z = z} end
      grid_render.handle_click(g, 0, 0, 1, 1)   -- press at (1,1)
      grid_render.handle_click(g, 0, 0, 0, 1)   -- release at (1,1)
      assert.are.equal(2, #events)
      assert.are.equal(1, events[1].x)
      assert.are.equal(1, events[1].y)
      assert.are.equal(1, events[1].z)
      assert.are.equal(0, events[2].z)
    end)

  end)

  -- ========================================================================
  -- Phase 8: Behavioral parity verification (US3)
  -- ========================================================================

  describe("behavioral parity", function()

    -- T037: app.init with simulated provider returns functional grid context
    -- (Requires full app mocking — test simulated provider has same interface as virtual)
    it("simulated provider has identical interface to virtual provider", function()
      local sim = grid_provider.connect("simulated")
      local virt = grid_provider.connect("virtual")
      -- Both have the same methods
      for _, method in ipairs({"all", "led", "refresh", "cols", "rows", "cleanup", "get_led", "get_state"}) do
        assert.are.equal(type(virt[method]), type(sim[method]),
          "method mismatch: " .. method)
      end
      -- Same dimensions
      assert.are.equal(virt:cols(), sim:cols())
      assert.are.equal(virt:rows(), sim:rows())
    end)

    -- T038: grid_ui.redraw sets LEDs correctly on simulated provider
    it("grid_ui.redraw sets LEDs on simulated provider identically to virtual", function()
      -- Mock clock for grid_ui
      rawset(_G, "clock", rawget(_G, "clock") or {
        get_beats = function() return 0 end,
        run = function(fn) return 1 end,
        cancel = function(id) end,
        sync = function() end,
      })
      local track_mod = require("lib/track")
      local grid_ui = require("lib/grid_ui")

      -- Create matching contexts for both providers
      local function make_ctx(provider_name)
        local g = grid_provider.connect(provider_name)
        return {
          tracks = track_mod.new_tracks(),
          active_track = 1,
          active_page = "trigger",
          playing = false,
          loop_held = false,
          loop_first_press = nil,
          grid_dirty = true,
          scale_notes = {},
          g = g,
        }
      end

      local ctx_sim = make_ctx("simulated")
      local ctx_virt = make_ctx("virtual")

      -- Set some step data so there's something to draw
      ctx_sim.tracks[1].params.trigger.steps[1] = 1
      ctx_virt.tracks[1].params.trigger.steps[1] = 1

      grid_ui.redraw(ctx_sim)
      grid_ui.redraw(ctx_virt)

      -- Compare LED state
      for y = 1, 8 do
        for x = 1, 16 do
          assert.are.equal(
            ctx_virt.g:get_led(x, y),
            ctx_sim.g:get_led(x, y),
            string.format("LED mismatch at (%d,%d)", x, y)
          )
        end
      end
    end)

  end)

  -- ========================================================================
  -- Phase 10: Edge cases
  -- ========================================================================

  describe("edge cases", function()

    local grid_render = require("lib/seamstress/grid_render")

    -- T043: drag across cells — press at one cell, release at another
    it("drag: press at (24,8) and release at (100,50) fire separate events", function()
      local g = grid_provider.connect("simulated")
      local events = {}
      g.key = function(x, y, z) events[#events + 1] = {x = x, y = y, z = z} end
      grid_render.handle_click(g, 24, 8, 1, 1)   -- press at cell (2,1)
      grid_render.handle_click(g, 100, 50, 0, 1)  -- release at cell (7,4)
      assert.are.equal(2, #events)
      assert.are.equal(2, events[1].x)
      assert.are.equal(1, events[1].y)
      assert.are.equal(1, events[1].z)
      assert.are.equal(7, events[2].x)
      assert.are.equal(4, events[2].y)
      assert.are.equal(0, events[2].z)
    end)

    -- T044: out-of-bounds led() is silently ignored
    it("led(17,9,5) on simulated provider is silently ignored", function()
      local g = grid_provider.connect("simulated")
      -- These should not error
      g:led(17, 9, 5)
      g:led(0, 0, 5)
      g:led(-1, 1, 5)
      g:led(1, -1, 5)
      -- Valid cell should still work
      g:led(1, 1, 10)
      assert.are.equal(10, g:get_led(1, 1))
    end)

    -- T046: end-to-end — set LED → draw → click → key fires → state change → redraw
    it("end-to-end: LED set, draw, click, key fires, state verified", function()
      local g = grid_provider.connect("simulated")
      -- Set an LED
      g:led(5, 3, 12)
      assert.are.equal(12, g:get_led(5, 3))
      -- Draw to mock screen
      local draw_calls = {}
      local mock_screen = {
        color = function(r, gc, b, a) draw_calls[#draw_calls + 1] = "color" end,
        move = function(x, y) draw_calls[#draw_calls + 1] = "move" end,
        rect_fill = function(w, h) draw_calls[#draw_calls + 1] = "rect" end,
      }
      grid_render.draw(g, mock_screen)
      assert.are.equal(384, #draw_calls)  -- 128 color + 128 move + 128 rect
      -- Click on cell (5,3) — pixel (64, 32)
      local key_event = nil
      g.key = function(x, y, z) key_event = {x = x, y = y, z = z} end
      grid_render.handle_click(g, 64, 32, 1, 1)
      assert.is_not_nil(key_event)
      assert.are.equal(5, key_event.x)
      assert.are.equal(3, key_event.y)
      assert.are.equal(1, key_event.z)
      -- Update LED state in response
      g:led(5, 3, 0)
      assert.are.equal(0, g:get_led(5, 3))
    end)

  end)

end)
