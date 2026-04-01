-- specs/synthetic_grid_spec.lua
-- Tests for the synthetic grid provider and test helpers

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer, required indirectly by grid_ui)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local grid_provider = require("lib/grid_provider")
local grid_ui = require("lib/grid_ui")
local synth_grid = require("specs/lib/synthetic_grid")

describe("synthetic grid provider", function()

  -- ========================================================================
  -- Provider registration and creation
  -- ========================================================================

  describe("registration", function()

    it("is registered as a built-in provider", function()
      local names = grid_provider.list()
      local found = false
      for _, name in ipairs(names) do
        if name == "synthetic" then found = true end
      end
      assert.is_true(found, "should have synthetic provider")
    end)

    it("creates without hardware dependencies", function()
      local g = grid_provider.connect("synthetic")
      assert.is_not_nil(g)
    end)

    it("has correct default dimensions", function()
      local g = grid_provider.connect("synthetic")
      assert.are.equal(16, g:cols())
      assert.are.equal(8, g:rows())
    end)

    it("supports custom dimensions", function()
      local g = grid_provider.connect("synthetic", { cols = 8, rows = 4 })
      assert.are.equal(8, g:cols())
      assert.are.equal(4, g:rows())
    end)

  end)

  -- ========================================================================
  -- LED state tracking
  -- ========================================================================

  describe("LED state tracking", function()

    it("starts with all LEDs off", function()
      local g = grid_provider.connect("synthetic")
      for y = 1, 8 do
        for x = 1, 16 do
          assert.are.equal(0, g:get_led(x, y))
        end
      end
    end)

    it("tracks individual LED changes", function()
      local g = grid_provider.connect("synthetic")
      g:led(5, 3, 12)
      assert.are.equal(12, g:get_led(5, 3))
      assert.are.equal(0, g:get_led(6, 3))
    end)

    it("tracks multiple LED changes", function()
      local g = grid_provider.connect("synthetic")
      g:led(1, 1, 15)
      g:led(16, 8, 8)
      g:led(8, 4, 3)
      assert.are.equal(15, g:get_led(1, 1))
      assert.are.equal(8, g:get_led(16, 8))
      assert.are.equal(3, g:get_led(8, 4))
    end)

    it("overwrites LED state on update", function()
      local g = grid_provider.connect("synthetic")
      g:led(5, 3, 12)
      g:led(5, 3, 4)
      assert.are.equal(4, g:get_led(5, 3))
    end)

    it("all(brightness) sets all LEDs", function()
      local g = grid_provider.connect("synthetic")
      g:all(10)
      assert.are.equal(10, g:get_led(1, 1))
      assert.are.equal(10, g:get_led(16, 8))
      assert.are.equal(10, g:get_led(8, 4))
    end)

    it("all(0) clears all LEDs", function()
      local g = grid_provider.connect("synthetic")
      g:led(5, 3, 12)
      g:led(10, 7, 8)
      g:all(0)
      assert.are.equal(0, g:get_led(5, 3))
      assert.are.equal(0, g:get_led(10, 7))
    end)

    it("get_state returns full matrix", function()
      local g = grid_provider.connect("synthetic")
      g:led(1, 1, 5)
      g:led(16, 8, 12)
      local state = g:get_state()
      assert.is_table(state)
      assert.are.equal(8, #state)
      assert.are.equal(16, #state[1])
      assert.are.equal(5, state[1][1])
      assert.are.equal(12, state[8][16])
      assert.are.equal(0, state[4][8])
    end)

    it("clear_state resets all LEDs", function()
      local g = grid_provider.connect("synthetic")
      g:led(5, 3, 12)
      g:clear_state()
      assert.are.equal(0, g:get_led(5, 3))
    end)

    it("cleanup clears LED state", function()
      local g = grid_provider.connect("synthetic")
      g:led(5, 3, 12)
      g:cleanup()
      assert.are.equal(0, g:get_led(5, 3))
    end)

  end)

  -- ========================================================================
  -- Key simulation
  -- ========================================================================

  describe("key simulation", function()

    it("fires key callback on simulate_key", function()
      local g = grid_provider.connect("synthetic")
      local captured = {}
      g.key = function(x, y, z)
        captured = { x = x, y = y, z = z }
      end
      g:simulate_key(5, 3, 1)
      assert.are.equal(5, captured.x)
      assert.are.equal(3, captured.y)
      assert.are.equal(1, captured.z)
    end)

    it("fires press and release separately", function()
      local g = grid_provider.connect("synthetic")
      local events = {}
      g.key = function(x, y, z)
        events[#events + 1] = { x = x, y = y, z = z }
      end
      g:simulate_key(3, 1, 1)
      g:simulate_key(3, 1, 0)
      assert.are.equal(2, #events)
      assert.are.equal(1, events[1].z)
      assert.are.equal(0, events[2].z)
    end)

    it("does not error when no key callback is set", function()
      local g = grid_provider.connect("synthetic")
      -- Should not error
      g:simulate_key(1, 1, 1)
    end)

  end)

  -- ========================================================================
  -- State dump formatting
  -- ========================================================================

  describe("dump", function()

    it("returns a string", function()
      local g = grid_provider.connect("synthetic")
      local result = g:dump()
      assert.is_string(result)
    end)

    it("includes header with column numbers", function()
      local g = grid_provider.connect("synthetic")
      local result = g:dump()
      local first_line = result:match("([^\n]+)")
      -- Header should contain column numbers 1-16
      assert.truthy(first_line:match("1"))
      assert.truthy(first_line:match("16"))
    end)

    it("shows dots for off LEDs", function()
      local g = grid_provider.connect("synthetic")
      local result = g:dump()
      -- All LEDs are off, so every data row should be full of dots
      for line in result:gmatch("[^\n]+") do
        if line:match("^%s*%d+:") then
          -- Count dots in data rows
          local dots = 0
          for _ in line:gmatch("%.") do dots = dots + 1 end
          assert.are.equal(16, dots)
        end
      end
    end)

    it("shows correct brightness characters", function()
      local g = grid_provider.connect("synthetic")
      g:led(1, 1, 0)   -- .
      g:led(2, 1, 1)   -- 1
      g:led(3, 1, 8)   -- 8
      g:led(4, 1, 10)  -- A
      g:led(5, 1, 12)  -- C
      g:led(6, 1, 15)  -- F
      local result = g:dump()
      -- Find row 1
      local row1
      for line in result:gmatch("[^\n]+") do
        if line:match("^%s*1:") then
          row1 = line
          break
        end
      end
      assert.is_not_nil(row1)
      -- Verify characters appear in the right positions
      assert.truthy(row1:match("%..*1.*8.*A.*C.*F"))
    end)

    it("has 8 data rows", function()
      local g = grid_provider.connect("synthetic")
      local result = g:dump()
      local data_rows = 0
      for line in result:gmatch("[^\n]+") do
        if line:match("^%s*%d+:") then
          data_rows = data_rows + 1
        end
      end
      assert.are.equal(8, data_rows)
    end)

    it("has header plus 8 data rows (9 lines total)", function()
      local g = grid_provider.connect("synthetic")
      local result = g:dump()
      local line_count = 0
      for _ in result:gmatch("[^\n]+") do
        line_count = line_count + 1
      end
      assert.are.equal(9, line_count)
    end)

  end)

  -- ========================================================================
  -- Test helpers
  -- ========================================================================

  describe("test helpers", function()

    it("setup creates wired ctx and grid", function()
      local ctx, g = synth_grid.setup()
      assert.is_not_nil(ctx)
      assert.is_not_nil(g)
      assert.are.equal(g, ctx.g)
      assert.is_not_nil(ctx.tracks)
      assert.are.equal(4, #ctx.tracks)
      assert.are.equal("trigger", ctx.active_page)
      assert.are.equal(1, ctx.active_track)
    end)

    it("setup accepts options", function()
      local ctx, g = synth_grid.setup({
        active_track = 2,
        active_page = "note",
        playing = true,
      })
      assert.are.equal(2, ctx.active_track)
      assert.are.equal("note", ctx.active_page)
      assert.is_true(ctx.playing)
    end)

    it("render calls grid_ui.redraw", function()
      local ctx, g = synth_grid.setup()
      synth_grid.render(ctx)
      -- After render, nav row should have LEDs set
      assert.is_true(g:get_led(1, 8) > 0, "nav track 1 should be lit after render")
    end)

    it("press fires key with z=1", function()
      local ctx, g = synth_grid.setup()
      local events = {}
      local orig_key = g.key
      g.key = function(x, y, z)
        events[#events + 1] = { z = z }
        orig_key(x, y, z)
      end
      synth_grid.press(g, 5, 1)
      assert.are.equal(1, #events)
      assert.are.equal(1, events[1].z)
    end)

    it("release fires key with z=0", function()
      local ctx, g = synth_grid.setup()
      local events = {}
      local orig_key = g.key
      g.key = function(x, y, z)
        events[#events + 1] = { z = z }
        orig_key(x, y, z)
      end
      synth_grid.release(g, 5, 1)
      assert.are.equal(1, #events)
      assert.are.equal(0, events[1].z)
    end)

    it("tap fires press then release", function()
      local ctx, g = synth_grid.setup()
      local events = {}
      local orig_key = g.key
      g.key = function(x, y, z)
        events[#events + 1] = { z = z }
        orig_key(x, y, z)
      end
      synth_grid.tap(g, 5, 1)
      assert.are.equal(2, #events)
      assert.are.equal(1, events[1].z)
      assert.are.equal(0, events[2].z)
    end)

    it("tap_sequence fires multiple taps", function()
      local ctx, g = synth_grid.setup()
      local event_count = 0
      local orig_key = g.key
      g.key = function(x, y, z)
        event_count = event_count + 1
        orig_key(x, y, z)
      end
      synth_grid.tap_sequence(g, {{5, 1}, {6, 1}, {7, 1}})
      assert.are.equal(6, event_count) -- 3 taps * 2 events each
    end)

    it("assert_led passes on correct brightness", function()
      local _, g = synth_grid.setup()
      g:led(5, 3, 12)
      -- Should not error
      synth_grid.assert_led(g, 5, 3, 12)
    end)

    it("assert_led_gte passes when above threshold", function()
      local _, g = synth_grid.setup()
      g:led(5, 3, 12)
      synth_grid.assert_led_gte(g, 5, 3, 8)
      synth_grid.assert_led_gte(g, 5, 3, 12) -- equal is ok
    end)

    it("assert_led_lt passes when below threshold", function()
      local _, g = synth_grid.setup()
      g:led(5, 3, 3)
      synth_grid.assert_led_lt(g, 5, 3, 8)
    end)

    it("assert_led_off passes for off LED", function()
      local _, g = synth_grid.setup()
      synth_grid.assert_led_off(g, 5, 3)
    end)

    it("assert_led_on passes for lit LED", function()
      local _, g = synth_grid.setup()
      g:led(5, 3, 1)
      synth_grid.assert_led_on(g, 5, 3)
    end)

    it("get_row returns 16 values", function()
      local _, g = synth_grid.setup()
      g:led(3, 2, 8)
      g:led(7, 2, 15)
      local row = synth_grid.get_row(g, 2)
      assert.are.equal(16, #row)
      assert.are.equal(8, row[3])
      assert.are.equal(15, row[7])
      assert.are.equal(0, row[1])
    end)

    it("count_lit counts LEDs above threshold", function()
      local _, g = synth_grid.setup()
      g:led(1, 1, 8)
      g:led(2, 1, 3)
      g:led(3, 1, 12)
      g:led(4, 1, 1)
      assert.are.equal(4, synth_grid.count_lit(g, 1, 1))   -- all >= 1
      assert.are.equal(2, synth_grid.count_lit(g, 1, 8))   -- only 8 and 12
      assert.are.equal(1, synth_grid.count_lit(g, 1, 10))  -- only 12
    end)

    it("dump returns formatted string", function()
      local _, g = synth_grid.setup()
      local result = synth_grid.dump(g)
      assert.is_string(result)
    end)

  end)

  -- ========================================================================
  -- Integration: render trigger page, verify LED positions
  -- ========================================================================

  describe("integration with grid_ui: trigger page", function()

    it("shows trigger steps as bright LEDs", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      -- Track 1 default pattern has triggers at steps 1,3,5,7,9,11,13,15
      synth_grid.render(ctx)
      -- Step 1 of track 1 has trigger=1, should be brightness 8
      synth_grid.assert_led_gte(g, 1, 1, 8, "step 1 track 1 trigger should be lit")
      -- Step 2 of track 1 has trigger=0, should be dim (loop indicator) or off
      synth_grid.assert_led_lt(g, 2, 1, 8, "step 2 track 1 trigger should be dim")
    end)

    it("shows all 4 tracks simultaneously", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      synth_grid.render(ctx)
      -- Each track row should have some lit LEDs
      for t = 1, 4 do
        local lit = synth_grid.count_lit(g, t, 8)
        assert.is_true(lit > 0, "track " .. t .. " should have some triggers lit")
      end
    end)

    it("shows nav row with correct selections", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })
      synth_grid.render(ctx)
      -- Track 1 button (x=1, y=8) should be bright (selected = 12)
      synth_grid.assert_led(g, 1, 8, 12, "track 1 nav should be selected")
      -- Track 2 button should be dim (unselected = 3)
      synth_grid.assert_led(g, 2, 8, 3, "track 2 nav should be unselected")
      -- Trigger page button (x=6, y=8) should be bright (selected = 12)
      synth_grid.assert_led(g, 6, 8, 12, "trigger page nav should be selected")
      -- Note page button (x=7, y=8) should be dim (unselected = 3)
      synth_grid.assert_led(g, 7, 8, 3, "note page nav should be unselected")
    end)

    it("shows loop region as dim LEDs", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      -- Default loop is 1-16, all steps in loop get at least brightness 2
      synth_grid.render(ctx)
      -- Step 2 (trigger=0, in loop) should have brightness 2 for track 1
      synth_grid.assert_led(g, 2, 1, 2, "off step in loop should have brightness 2")
    end)

    it("shows playhead at full brightness when playing", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger", playing = true })
      -- Playhead starts at position 1
      synth_grid.render(ctx)
      -- Position 1 for all tracks should be at max brightness (15)
      synth_grid.assert_led(g, 1, 1, 15, "playhead on track 1 should be full bright")
    end)

    it("dump shows recognizable trigger pattern", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      synth_grid.render(ctx)
      local result = synth_grid.dump(g)
      -- The dump should contain brightness 8 characters for trigger steps
      assert.truthy(result:match("8"), "dump should contain brightness 8 for active triggers")
      -- The dump should contain nav row with C (brightness 12) for selected items
      assert.truthy(result:match("C"), "dump should contain C for selected nav items")
    end)

  end)

  -- ========================================================================
  -- Integration: simulate key press, verify state change
  -- ========================================================================

  describe("integration with grid_ui: key presses", function()

    it("toggling trigger changes track state", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      -- Track 1, step 2 starts with trigger=0
      assert.are.equal(0, ctx.tracks[1].params.trigger.steps[2])
      -- Tap step 2 on track 1 (row 1)
      synth_grid.tap(g, 2, 1)
      -- Should now be 1
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[2])
      -- Tap again to toggle off
      synth_grid.tap(g, 2, 1)
      assert.are.equal(0, ctx.tracks[1].params.trigger.steps[2])
    end)

    it("toggling trigger updates LED display", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      -- Step 2 track 1: initially off
      synth_grid.render(ctx)
      synth_grid.assert_led_lt(g, 2, 1, 8, "step 2 initially dim")
      -- Toggle on
      synth_grid.tap(g, 2, 1)
      synth_grid.render(ctx)
      synth_grid.assert_led_gte(g, 2, 1, 8, "step 2 now lit after toggle")
    end)

    it("switching tracks via nav row", function()
      local ctx, g = synth_grid.setup({ active_track = 1 })
      -- Tap track 2 button (x=2, y=8)
      synth_grid.tap(g, 2, 8)
      assert.are.equal(2, ctx.active_track)
      -- Verify nav display updates
      synth_grid.render(ctx)
      synth_grid.assert_led(g, 2, 8, 12, "track 2 nav should be selected")
      synth_grid.assert_led(g, 1, 8, 3, "track 1 nav should be unselected")
    end)

    it("switching pages via nav row", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      -- Tap note page button (x=7, y=8)
      synth_grid.tap(g, 7, 8)
      assert.are.equal("note", ctx.active_page)
      synth_grid.render(ctx)
      synth_grid.assert_led(g, 7, 8, 12, "note page should be selected")
      synth_grid.assert_led(g, 6, 8, 3, "trigger page should be unselected")
    end)

    it("setting note value via grid", function()
      local ctx, g = synth_grid.setup({ active_page = "note", active_track = 1 })
      -- Tap row 2, col 3 -> value = 8 - 2 = 6
      synth_grid.tap(g, 3, 2)
      assert.are.equal(6, ctx.tracks[1].params.note.steps[3])
    end)

    it("loop editing via hold + press", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })
      -- Hold loop button (x=11, y=8)
      synth_grid.press(g, 11, 8)
      assert.is_true(ctx.loop_held)
      -- Press loop start (step 3)
      synth_grid.press(g, 3, 1)
      -- Press loop end (step 8)
      synth_grid.press(g, 8, 1)
      -- Release loop button
      synth_grid.release(g, 11, 8)
      -- Verify loop was set
      assert.are.equal(3, ctx.tracks[1].params.trigger.loop_start)
      assert.are.equal(8, ctx.tracks[1].params.trigger.loop_end)
    end)

    it("before/after state visible in dump", function()
      local ctx, g = synth_grid.setup({ active_page = "trigger" })
      synth_grid.render(ctx)
      local before = synth_grid.dump(g)
      -- Toggle a trigger
      synth_grid.tap(g, 2, 1)
      synth_grid.render(ctx)
      local after = synth_grid.dump(g)
      -- Dumps should be different
      assert.are_not.equal(before, after, "dump should change after toggle")
    end)

    it("full sequence: set triggers, switch page, set note, verify", function()
      local ctx, g = synth_grid.setup()
      -- Set a trigger on track 1 step 4
      synth_grid.tap(g, 4, 1)
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[4])
      -- Switch to note page
      synth_grid.tap(g, 7, 8)
      assert.are.equal("note", ctx.active_page)
      -- Set note value at step 4 to 5 (row 3 = value 5)
      synth_grid.tap(g, 4, 3)
      assert.are.equal(5, ctx.tracks[1].params.note.steps[4])
      -- Render and verify LED state
      synth_grid.render(ctx)
      -- Step 4, row 3 (value 5) should be the value marker (bright)
      synth_grid.assert_led_gte(g, 4, 3, 4, "note value LED should be lit")
    end)

  end)

end)
