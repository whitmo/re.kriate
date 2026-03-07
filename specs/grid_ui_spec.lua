-- specs/grid_ui_spec.lua
-- Tests for lib/grid_ui.lua

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer, which grid_ui requires for play/stop)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local grid_ui = require("lib/grid_ui")

-- Spy grid: captures all led() calls so we can assert brightness values
local function mock_grid()
  local leds = {}  -- leds[x][y] = brightness
  local g = {
    leds = leds,
    all_val = nil,
    refreshed = false,
    led = function(self, x, y, val)
      if not leds[x] then leds[x] = {} end
      leds[x][y] = val
    end,
    all = function(self, val)
      self.all_val = val
      -- Clear leds to simulate hardware behavior
      for k in pairs(leds) do leds[k] = nil end
    end,
    refresh = function(self)
      self.refreshed = true
    end,
  }
  return g
end

-- Helper to read an LED value from the spy grid
local function led_at(g, x, y)
  return (g.leds[x] and g.leds[x][y]) or 0
end

-- Helper: create a minimal ctx with mocked grid
local function make_ctx()
  local g = mock_grid()
  return {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    loop_first_press = nil,
    g = g,
    grid_dirty = false,
    voices = {},
    clock_ids = nil,
  }
end

describe("grid_ui", function()

  describe("PAGES", function()
    it("contains all five page names", function()
      assert.are.same(grid_ui.PAGES, {"trigger", "note", "octave", "duration", "velocity"})
    end)
  end)

  describe("redraw", function()

    it("returns early if ctx.g is nil", function()
      local ctx = make_ctx()
      ctx.g = nil
      -- Should not error
      grid_ui.redraw(ctx)
    end)

    it("calls g:all(0) to clear grid", function()
      local ctx = make_ctx()
      grid_ui.redraw(ctx)
      assert.are.equal(ctx.g.all_val, 0)
    end)

    it("calls g:refresh() at the end", function()
      local ctx = make_ctx()
      grid_ui.redraw(ctx)
      assert.is_true(ctx.g.refreshed)
    end)

    it("delegates to draw_trigger_page on trigger page", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      -- Set a known trigger so we can verify it was drawn
      ctx.tracks[1].params.trigger.steps[1] = 1
      grid_ui.redraw(ctx)
      -- Step 1 of track 1 has trigger=1, should be brightness 8
      assert.are.equal(led_at(ctx.g, 1, 1), 8)
    end)

    it("delegates to draw_value_page on note page", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      ctx.active_track = 1
      -- Set note step 1 to value 3 (row = 8-3 = 5)
      ctx.tracks[1].params.note.steps[1] = 3
      grid_ui.redraw(ctx)
      -- Row 5 (value 3) at column 1 should be lit
      assert.is_true(led_at(ctx.g, 1, 5) > 0)
    end)

    it("delegates to draw_value_page for all non-trigger pages", function()
      for _, page in ipairs({"note", "octave", "duration", "velocity"}) do
        local ctx = make_ctx()
        ctx.active_page = page
        -- Should not error
        grid_ui.redraw(ctx)
        -- Nav row should be drawn
        assert.is_true(led_at(ctx.g, 1, 8) > 0, page .. " page should draw nav row")
      end
    end)

  end)

  describe("draw_trigger_page", function()

    it("shows brightness 0 for steps outside loop", function()
      local ctx = make_ctx()
      local g = mock_grid()
      -- Set loop to 1-4 for track 1
      ctx.tracks[1].params.trigger.loop_start = 1
      ctx.tracks[1].params.trigger.loop_end = 4
      -- All steps = 0 (no triggers)
      for i = 1, 16 do ctx.tracks[1].params.trigger.steps[i] = 0 end
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 5 is outside loop, should be 0
      assert.are.equal(led_at(g, 5, 1), 0)
      -- Step 10 outside loop
      assert.are.equal(led_at(g, 10, 1), 0)
    end)

    it("shows brightness 2 for in-loop steps without trigger", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.tracks[1].params.trigger.loop_start = 1
      ctx.tracks[1].params.trigger.loop_end = 8
      for i = 1, 16 do ctx.tracks[1].params.trigger.steps[i] = 0 end
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 3 is in loop, no trigger -> brightness 2
      assert.are.equal(led_at(g, 3, 1), 2)
    end)

    it("shows brightness 8 for active trigger steps", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.tracks[1].params.trigger.steps[5] = 1
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 5 has trigger=1, should be 8
      assert.are.equal(led_at(g, 5, 1), 8)
    end)

    it("shows brightness 15 for playhead when playing", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = true
      ctx.tracks[1].params.trigger.pos = 3
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 3 is playhead -> brightness 15
      assert.are.equal(led_at(g, 3, 1), 15)
    end)

    it("does not show playhead brightness when not playing", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = false
      ctx.tracks[1].params.trigger.pos = 3
      ctx.tracks[1].params.trigger.steps[3] = 1
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 3 is playhead but not playing, should be 8 (trigger active), not 15
      assert.are.equal(led_at(g, 3, 1), 8)
    end)

    it("draws all 4 tracks on rows 1-4", function()
      local ctx = make_ctx()
      local g = mock_grid()
      -- Set triggers on different steps for each track
      for t = 1, 4 do
        for i = 1, 16 do ctx.tracks[t].params.trigger.steps[i] = 0 end
        ctx.tracks[t].params.trigger.steps[t] = 1
      end
      grid_ui.draw_trigger_page(ctx, g)
      for t = 1, 4 do
        assert.are.equal(led_at(g, t, t), 8, "track " .. t .. " trigger at step " .. t)
      end
    end)

    it("playhead overrides trigger brightness", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = true
      ctx.tracks[2].params.trigger.pos = 7
      ctx.tracks[2].params.trigger.steps[7] = 1
      grid_ui.draw_trigger_page(ctx, g)
      -- Even though trigger is active (8), playhead (15) wins
      assert.are.equal(led_at(g, 7, 2), 15)
    end)

  end)

  describe("draw_value_page", function()

    it("shows active value row at brightness 10 when in loop", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 1
      ctx.tracks[1].params.note.steps[1] = 5
      ctx.tracks[1].params.note.loop_start = 1
      ctx.tracks[1].params.note.loop_end = 16
      grid_ui.draw_value_page(ctx, g, "note")
      -- Value 5 is at row 8-5=3
      assert.are.equal(led_at(g, 1, 3), 10)
    end)

    it("shows active value row at brightness 4 when outside loop", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 1
      ctx.tracks[1].params.note.steps[5] = 3
      ctx.tracks[1].params.note.loop_start = 1
      ctx.tracks[1].params.note.loop_end = 4
      grid_ui.draw_value_page(ctx, g, "note")
      -- Step 5 is outside loop, value 3 at row 5
      assert.are.equal(led_at(g, 5, 5), 4)
    end)

    it("shows bar graph below value row at brightness 3 when in loop", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 1
      ctx.tracks[1].params.note.steps[1] = 5
      ctx.tracks[1].params.note.loop_start = 1
      ctx.tracks[1].params.note.loop_end = 16
      grid_ui.draw_value_page(ctx, g, "note")
      -- Value 5 at row 3. Rows below (4,5,6,7) represent values 4,3,2,1 which are < 5
      -- They should be brightness 3 (in loop, below value)
      assert.are.equal(led_at(g, 1, 4), 3)
      assert.are.equal(led_at(g, 1, 5), 3)
      assert.are.equal(led_at(g, 1, 6), 3)
      assert.are.equal(led_at(g, 1, 7), 3)
    end)

    it("does not show bar above value", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 1
      ctx.tracks[1].params.note.steps[1] = 5
      ctx.tracks[1].params.note.loop_start = 1
      ctx.tracks[1].params.note.loop_end = 16
      grid_ui.draw_value_page(ctx, g, "note")
      -- Value 5 at row 3, rows above (1,2) represent values 7,6 which are > 5
      assert.are.equal(led_at(g, 1, 1), 0)
      assert.are.equal(led_at(g, 1, 2), 0)
    end)

    it("playhead column shows value at brightness 15", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = true
      ctx.active_track = 1
      ctx.tracks[1].params.note.steps[2] = 4
      ctx.tracks[1].params.note.pos = 2
      grid_ui.draw_value_page(ctx, g, "note")
      -- Value 4 at row 4, playhead at step 2
      assert.are.equal(led_at(g, 2, 4), 15)
    end)

    it("playhead column shows bar below value at brightness 6", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = true
      ctx.active_track = 1
      ctx.tracks[1].params.note.steps[2] = 4
      ctx.tracks[1].params.note.pos = 2
      grid_ui.draw_value_page(ctx, g, "note")
      -- Value 4 at row 4. Rows 5,6,7 (values 3,2,1) are below value at playhead
      assert.are.equal(led_at(g, 2, 5), 6)
      assert.are.equal(led_at(g, 2, 6), 6)
      assert.are.equal(led_at(g, 2, 7), 6)
    end)

    it("uses active_track data", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 3
      ctx.tracks[3].params.octave.steps[1] = 6
      ctx.tracks[3].params.octave.loop_start = 1
      ctx.tracks[3].params.octave.loop_end = 16
      grid_ui.draw_value_page(ctx, g, "octave")
      -- Value 6 at row 2 (8-6=2)
      assert.are.equal(led_at(g, 1, 2), 10)
    end)

    it("value 1 lights only row 7", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 1
      ctx.tracks[1].params.velocity.steps[1] = 1
      ctx.tracks[1].params.velocity.loop_start = 1
      ctx.tracks[1].params.velocity.loop_end = 16
      grid_ui.draw_value_page(ctx, g, "velocity")
      -- Value 1 at row 7 (8-1=7), no rows below
      assert.are.equal(led_at(g, 1, 7), 10)
      -- All rows above should be 0
      for y = 1, 6 do
        assert.are.equal(led_at(g, 1, y), 0, "row " .. y .. " should be off for value 1")
      end
    end)

    it("value 7 lights all rows", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 1
      ctx.tracks[1].params.duration.steps[1] = 7
      ctx.tracks[1].params.duration.loop_start = 1
      ctx.tracks[1].params.duration.loop_end = 16
      grid_ui.draw_value_page(ctx, g, "duration")
      -- Value 7 at row 1 (8-7=1), all rows below (2-7) are bar
      assert.are.equal(led_at(g, 1, 1), 10) -- active value
      for y = 2, 7 do
        assert.are.equal(led_at(g, 1, y), 3, "row " .. y .. " should be bar for value 7")
      end
    end)

  end)

  describe("draw_nav", function()

    it("highlights active track", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_track = 2
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 1, 8), 3)   -- not active
      assert.are.equal(led_at(g, 2, 8), 12)  -- active
      assert.are.equal(led_at(g, 3, 8), 3)
      assert.are.equal(led_at(g, 4, 8), 3)
    end)

    it("highlights active page", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.active_page = "octave"
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 6, 8), 3)   -- trigger (not active)
      assert.are.equal(led_at(g, 7, 8), 3)   -- note (not active)
      assert.are.equal(led_at(g, 8, 8), 12)  -- octave (active)
      assert.are.equal(led_at(g, 9, 8), 3)   -- duration (not active)
      assert.are.equal(led_at(g, 10, 8), 3)  -- velocity (not active)
    end)

    it("highlights loop key when held", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.loop_held = true
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 12, 8), 12)
    end)

    it("dims loop key when not held", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.loop_held = false
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 12, 8), 3)
    end)

    it("highlights play button when playing", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = true
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 16, 8), 12)
    end)

    it("dims play button when stopped", function()
      local ctx = make_ctx()
      local g = mock_grid()
      ctx.playing = false
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 16, 8), 3)
    end)

  end)

  describe("key", function()

    it("routes y=8 to nav_key", function()
      local ctx = make_ctx()
      -- Press track 2 on nav row
      grid_ui.key(ctx, 2, 8, 1)
      assert.are.equal(ctx.active_track, 2)
    end)

    it("routes y=1-7 to grid_key", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      -- Toggle trigger on track 1 (row 1), step 5
      local before = ctx.tracks[1].params.trigger.steps[5]
      grid_ui.key(ctx, 5, 1, 1)
      assert.are_not.equal(ctx.tracks[1].params.trigger.steps[5], before)
    end)

    it("ignores y values outside 1-8", function()
      local ctx = make_ctx()
      -- Should not error
      grid_ui.key(ctx, 1, 0, 1)
      grid_ui.key(ctx, 1, 9, 1)
    end)

  end)

  describe("nav_key", function()

    it("selects track 1-4 on press", function()
      local ctx = make_ctx()
      for t = 1, 4 do
        grid_ui.nav_key(ctx, t, 1)
        assert.are.equal(ctx.active_track, t)
      end
    end)

    it("ignores track select on release", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      grid_ui.nav_key(ctx, 3, 0)
      assert.are.equal(ctx.active_track, 1)
    end)

    it("selects trigger page (x=6)", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      grid_ui.nav_key(ctx, 6, 1)
      assert.are.equal(ctx.active_page, "trigger")
    end)

    it("selects note page (x=7)", function()
      local ctx = make_ctx()
      grid_ui.nav_key(ctx, 7, 1)
      assert.are.equal(ctx.active_page, "note")
    end)

    it("selects octave page (x=8)", function()
      local ctx = make_ctx()
      grid_ui.nav_key(ctx, 8, 1)
      assert.are.equal(ctx.active_page, "octave")
    end)

    it("selects duration page (x=9)", function()
      local ctx = make_ctx()
      grid_ui.nav_key(ctx, 9, 1)
      assert.are.equal(ctx.active_page, "duration")
    end)

    it("selects velocity page (x=10)", function()
      local ctx = make_ctx()
      grid_ui.nav_key(ctx, 10, 1)
      assert.are.equal(ctx.active_page, "velocity")
    end)

    it("sets loop_held on press of x=12", function()
      local ctx = make_ctx()
      grid_ui.nav_key(ctx, 12, 1)
      assert.is_true(ctx.loop_held)
    end)

    it("clears loop_held and loop_first_press on release of x=12", function()
      local ctx = make_ctx()
      ctx.loop_held = true
      ctx.loop_first_press = 5
      grid_ui.nav_key(ctx, 12, 0)
      assert.is_false(ctx.loop_held)
      assert.is_nil(ctx.loop_first_press)
    end)

    it("toggles play/stop on x=16 press", function()
      local ctx = make_ctx()
      ctx.playing = false
      grid_ui.nav_key(ctx, 16, 1)
      assert.is_true(ctx.playing)
      grid_ui.nav_key(ctx, 16, 1)
      assert.is_false(ctx.playing)
    end)

    it("ignores play/stop on release", function()
      local ctx = make_ctx()
      ctx.playing = false
      grid_ui.nav_key(ctx, 16, 0)
      assert.is_false(ctx.playing)
    end)

  end)

  describe("grid_key", function()

    it("ignores key up events (z=0)", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      local before = ctx.tracks[1].params.trigger.steps[1]
      grid_ui.grid_key(ctx, 1, 1, 0)
      assert.are.equal(ctx.tracks[1].params.trigger.steps[1], before)
    end)

    it("routes to loop_key when loop_held", function()
      local ctx = make_ctx()
      ctx.loop_held = true
      ctx.active_page = "trigger"
      ctx.active_track = 1
      -- First press sets loop_first_press
      grid_ui.grid_key(ctx, 3, 1, 1)
      assert.are.equal(ctx.loop_first_press, 3)
    end)

    it("routes to trigger_key on trigger page", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      local before = ctx.tracks[1].params.trigger.steps[5]
      grid_ui.grid_key(ctx, 5, 1, 1)
      assert.are_not.equal(ctx.tracks[1].params.trigger.steps[5], before)
    end)

    it("routes to value_key on value pages", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      ctx.active_track = 1
      -- Press step 3, row 2 (value = 8-2 = 6)
      grid_ui.grid_key(ctx, 3, 2, 1)
      assert.are.equal(ctx.tracks[1].params.note.steps[3], 6)
    end)

  end)

  describe("trigger_key", function()

    it("toggles trigger step for the track matching the row", function()
      local ctx = make_ctx()
      -- Row 1 = track 1
      ctx.tracks[1].params.trigger.steps[5] = 0
      grid_ui.trigger_key(ctx, 5, 1)
      assert.are.equal(ctx.tracks[1].params.trigger.steps[5], 1)
      grid_ui.trigger_key(ctx, 5, 1)
      assert.are.equal(ctx.tracks[1].params.trigger.steps[5], 0)
    end)

    it("maps row to correct track", function()
      local ctx = make_ctx()
      for t = 1, 4 do
        ctx.tracks[t].params.trigger.steps[1] = 0
        grid_ui.trigger_key(ctx, 1, t)
        assert.are.equal(ctx.tracks[t].params.trigger.steps[1], 1,
          "row " .. t .. " should toggle track " .. t)
      end
    end)

    it("ignores rows beyond NUM_TRACKS", function()
      local ctx = make_ctx()
      -- Row 5 is beyond NUM_TRACKS (4), should not error
      grid_ui.trigger_key(ctx, 1, 5)
    end)

  end)

  describe("value_key", function()

    it("sets step value based on row (row 1 = value 7)", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      grid_ui.value_key(ctx, 1, 1, "note")
      assert.are.equal(ctx.tracks[1].params.note.steps[1], 7)
    end)

    it("sets step value based on row (row 7 = value 1)", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      grid_ui.value_key(ctx, 1, 7, "note")
      assert.are.equal(ctx.tracks[1].params.note.steps[1], 1)
    end)

    it("sets value for the active track", function()
      local ctx = make_ctx()
      ctx.active_track = 3
      grid_ui.value_key(ctx, 5, 3, "octave")
      -- Row 3 = value 5
      assert.are.equal(ctx.tracks[3].params.octave.steps[5], 5)
    end)

    it("works across all value pages", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      for _, page in ipairs({"note", "octave", "duration", "velocity"}) do
        grid_ui.value_key(ctx, 1, 4, page)
        -- Row 4 = value 4
        assert.are.equal(ctx.tracks[1].params[page].steps[1], 4,
          page .. " should be set to 4")
      end
    end)

  end)

  describe("loop_key", function()

    it("first press sets loop_first_press", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      ctx.loop_first_press = nil
      grid_ui.loop_key(ctx, 5, "trigger")
      assert.are.equal(ctx.loop_first_press, 5)
    end)

    it("second press sets loop boundaries and clears loop_first_press", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      ctx.loop_first_press = 3
      grid_ui.loop_key(ctx, 8, "trigger")
      assert.are.equal(ctx.tracks[1].params.trigger.loop_start, 3)
      assert.are.equal(ctx.tracks[1].params.trigger.loop_end, 8)
      assert.is_nil(ctx.loop_first_press)
    end)

    it("orders boundaries correctly regardless of press order", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      ctx.loop_first_press = 10
      grid_ui.loop_key(ctx, 4, "trigger")
      assert.are.equal(ctx.tracks[1].params.trigger.loop_start, 4)
      assert.are.equal(ctx.tracks[1].params.trigger.loop_end, 10)
    end)

    it("uses trigger param on trigger page", function()
      local ctx = make_ctx()
      ctx.active_track = 2
      ctx.loop_first_press = 2
      grid_ui.loop_key(ctx, 6, "trigger")
      assert.are.equal(ctx.tracks[2].params.trigger.loop_start, 2)
      assert.are.equal(ctx.tracks[2].params.trigger.loop_end, 6)
    end)

    it("uses page-specific param on value pages", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      for _, page in ipairs({"note", "octave", "duration", "velocity"}) do
        ctx.loop_first_press = 3
        grid_ui.loop_key(ctx, 7, page)
        assert.are.equal(ctx.tracks[1].params[page].loop_start, 3,
          page .. " loop_start should be 3")
        assert.are.equal(ctx.tracks[1].params[page].loop_end, 7,
          page .. " loop_end should be 7")
      end
    end)

    it("sets single-step loop when both presses are same column", function()
      local ctx = make_ctx()
      ctx.active_track = 1
      ctx.loop_first_press = 5
      grid_ui.loop_key(ctx, 5, "trigger")
      assert.are.equal(ctx.tracks[1].params.trigger.loop_start, 5)
      assert.are.equal(ctx.tracks[1].params.trigger.loop_end, 5)
    end)

  end)

end)
