-- specs/grid_ui_spec.lua
-- Tests for lib/grid_ui.lua: grid display, input, and extended page toggle

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer, required indirectly by grid_ui)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local grid_ui = require("lib/grid_ui")

-- Mock grid that records led() calls (used by make_ctx and extended page tests)
local function mock_grid()
  local leds = {}
  return {
    all = function(self, val)
      leds = {}
      if val and val > 0 then
        for y = 1, 8 do
          for x = 1, 16 do
            leds[y * 16 + x] = val
          end
        end
      end
    end,
    led = function(self, x, y, brightness)
      leds[y * 16 + x] = brightness
    end,
    refresh = function(self) end,
    get_led = function(self, x, y)
      return leds[y * 16 + x] or 0
    end,
  }
end

-- Spy grid: captures all led() calls with introspectable state
-- (used by granular draw_* tests that pass a grid object directly)
local function spy_grid()
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

-- Helper to read an LED value from either grid type
local function led_at(g, x, y)
  if g.leds then
    return (g.leds[x] and g.leds[x][y]) or 0
  elseif g.get_led then
    return g:get_led(x, y)
  end
  return 0
end

-- Helper: create a minimal ctx for grid_ui testing
local function make_ctx(opts)
  opts = opts or {}
  local g = mock_grid()
  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = opts.active_track or 1,
    active_page = opts.active_page or "trigger",
    playing = opts.playing or false,
    loop_held = opts.loop_held or false,
    loop_first_press = nil,
    grid_dirty = true,
    g = g,
    voices = {},
    clock_ids = nil,
  }
  return ctx, g
end

describe("grid_ui", function()

  -- ========================================================================
  -- Basic display tests for existing pages
  -- ========================================================================

  describe("redraw", function()

    it("returns early if ctx.g is nil", function()
      local ctx = make_ctx()
      ctx.g = nil
      -- Should not error
      grid_ui.redraw(ctx)
    end)

    it("calls g:all(0) to clear grid", function()
      local ctx = make_ctx()
      ctx.g = spy_grid()
      grid_ui.redraw(ctx)
      assert.are.equal(ctx.g.all_val, 0)
    end)

    it("calls g:refresh() at the end", function()
      local ctx = make_ctx()
      ctx.g = spy_grid()
      grid_ui.redraw(ctx)
      assert.is_true(ctx.g.refreshed)
    end)

    it("draws trigger page when active_page is trigger", function()
      local ctx, g = make_ctx({ active_page = "trigger" })
      -- Set a trigger on track 1, step 3
      ctx.tracks[1].params.trigger.steps[3] = 1
      grid_ui.redraw(ctx)
      -- Trigger page: row = track number, lit steps have brightness 8
      assert.are.equal(8, g:get_led(3, 1))
    end)

    it("draws note page as bar graph", function()
      local ctx, g = make_ctx({ active_page = "note" })
      -- Set note value 5 on step 1
      ctx.tracks[1].params.note.steps[1] = 5
      grid_ui.redraw(ctx)
      -- Value 5 => row_val==5 at y = 8-5 = 3, brightness 10 (in loop)
      assert.are.equal(10, g:get_led(1, 3))
    end)

    it("draws velocity page as bar graph", function()
      local ctx, g = make_ctx({ active_page = "velocity" })
      ctx.tracks[1].params.velocity.steps[2] = 6
      grid_ui.redraw(ctx)
      -- Value 6 => row_val==6 at y = 8-6 = 2, brightness 10 (in loop)
      assert.are.equal(10, g:get_led(2, 2))
    end)

    it("delegates to draw_value_page for all non-trigger pages", function()
      for _, page in ipairs({"note", "octave", "duration", "velocity"}) do
        local ctx = make_ctx()
        ctx.active_page = page
        ctx.g = spy_grid()
        -- Should not error
        grid_ui.redraw(ctx)
        -- Nav row should be drawn
        assert.is_true(led_at(ctx.g, 1, 8) > 0, page .. " page should draw nav row")
      end
    end)

  end)

  -- ========================================================================
  -- Granular draw_trigger_page tests
  -- ========================================================================

  describe("draw_trigger_page", function()

    it("shows brightness 0 for steps outside loop", function()
      local ctx = make_ctx()
      local g = spy_grid()
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
      local g = spy_grid()
      ctx.tracks[1].params.trigger.loop_start = 1
      ctx.tracks[1].params.trigger.loop_end = 8
      for i = 1, 16 do ctx.tracks[1].params.trigger.steps[i] = 0 end
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 3 is in loop, no trigger -> brightness 2
      assert.are.equal(led_at(g, 3, 1), 2)
    end)

    it("shows brightness 8 for active trigger steps", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.tracks[1].params.trigger.steps[5] = 1
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 5 has trigger=1, should be 8
      assert.are.equal(led_at(g, 5, 1), 8)
    end)

    it("shows brightness 15 for playhead when playing", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.playing = true
      ctx.tracks[1].params.trigger.pos = 3
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 3 is playhead -> brightness 15
      assert.are.equal(led_at(g, 3, 1), 15)
    end)

    it("does not show playhead brightness when not playing", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.playing = false
      ctx.tracks[1].params.trigger.pos = 3
      ctx.tracks[1].params.trigger.steps[3] = 1
      grid_ui.draw_trigger_page(ctx, g)
      -- Step 3 is playhead but not playing, should be 8 (trigger active), not 15
      assert.are.equal(led_at(g, 3, 1), 8)
    end)

    it("draws all 4 tracks on rows 1-4", function()
      local ctx = make_ctx()
      local g = spy_grid()
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
      local g = spy_grid()
      ctx.playing = true
      ctx.tracks[2].params.trigger.pos = 7
      ctx.tracks[2].params.trigger.steps[7] = 1
      grid_ui.draw_trigger_page(ctx, g)
      -- Even though trigger is active (8), playhead (15) wins
      assert.are.equal(led_at(g, 7, 2), 15)
    end)

  end)

  -- ========================================================================
  -- Granular draw_value_page tests
  -- ========================================================================

  describe("draw_value_page", function()

    it("shows active value row at brightness 10 when in loop", function()
      local ctx = make_ctx()
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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
      local g = spy_grid()
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

    it("renders probability bars by percentage", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.active_page = "probability"
      ctx.tracks[1].params.probability.steps[1] = 50
      grid_ui.draw_value_page(ctx, g, "probability")
      assert.is_true(led_at(g, 1, 5) > 0)   -- lower rows lit
      assert.are.equal(0, led_at(g, 1, 2))  -- upper row off
    end)

    it("lights all probability rows at 100%", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.active_page = "probability"
      ctx.tracks[1].params.probability.steps[1] = 100
      grid_ui.draw_value_page(ctx, g, "probability")
      for y = 1, 7 do
        assert.is_true(led_at(g, 1, y) > 0)
      end
    end)

  end)

  -- ========================================================================
  -- Alt-track page
  -- ========================================================================

  describe("alt_track page", function()

    it("draws direction, division, swing, and mute per track row", function()
      local ctx = make_ctx({active_page = "alt_track"})
      local g = spy_grid()
      ctx.tracks[1].direction = "pendulum"
      ctx.tracks[1].division = 4
      ctx.tracks[1].swing = 75
      ctx.tracks[1].muted = true

      grid_ui.draw_alt_track_page(ctx, g)

      assert.are.equal(12, led_at(g, 3, 1))   -- direction pendulum (col 3)
      assert.are.equal(12, led_at(g, 9, 1))   -- division 4 -> col 9 (6..12 mapping)
      assert.are.equal(12, led_at(g, 14, 1))  -- swing 75 -> col 14 (11..15 mapping)
      assert.are.equal(15, led_at(g, 16, 1))  -- mute toggle bright
    end)

    it("accentuates active track row on unselected cells", function()
      local ctx = make_ctx({active_page = "alt_track", active_track = 2})
      local g = spy_grid()
      grid_ui.draw_alt_track_page(ctx, g)
      assert.is_true(led_at(g, 2, 2) > led_at(g, 2, 1))
    end)

    it("dims non-mute cells when track is muted", function()
      local ctx = make_ctx({active_page = "alt_track"})
      local g = spy_grid()
      ctx.tracks[3].muted = true
      grid_ui.draw_alt_track_page(ctx, g)
      assert.is_true(led_at(g, 1, 3) < led_at(g, 1, 1))
      assert.are.equal(15, led_at(g, 16, 3))
    end)

    it("grid presses set meta values per track row", function()
      local ctx = make_ctx({active_page = "alt_track"})
      grid_ui.alt_track_key(ctx, 5, 2)  -- direction random
      assert.are.equal("random", ctx.tracks[2].direction)

      grid_ui.alt_track_key(ctx, 10, 2)  -- division col 10 => 5
      assert.are.equal(5, ctx.tracks[2].division)

      grid_ui.alt_track_key(ctx, 13, 2) -- swing 50 (cols 11-15 map to 0/25/50/75/100)
      assert.are.equal(50, ctx.tracks[2].swing)
      grid_ui.alt_track_key(ctx, 14, 2) -- swing 75
      assert.are.equal(75, ctx.tracks[2].swing)
      grid_ui.alt_track_key(ctx, 15, 2) -- swing 100
      assert.are.equal(100, ctx.tracks[2].swing)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)
      grid_ui.alt_track_key(ctx, 15, 2)

      grid_ui.alt_track_key(ctx, 16, 3) -- mute toggle on track row 3
      assert.is_true(ctx.tracks[3].muted)
    end)

  end)

  -- ========================================================================
  -- Granular draw_nav tests
  -- ========================================================================

  describe("draw_nav", function()

    it("highlights active track", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.active_track = 2
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 1, 8), 3)   -- not active
      assert.are.equal(led_at(g, 2, 8), 12)  -- active
      assert.are.equal(led_at(g, 3, 8), 3)
      assert.are.equal(led_at(g, 4, 8), 3)
    end)

    it("highlights active page", function()
      local ctx = make_ctx()
      local g = spy_grid()
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
      local g = spy_grid()
      ctx.loop_held = true
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 12, 8), 12)
    end)

    it("dims loop key when not held", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.loop_held = false
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 12, 8), 3)
    end)

    it("highlights play button when playing", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.playing = true
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 16, 8), 12)
    end)

    it("dims play button when stopped", function()
      local ctx = make_ctx()
      local g = spy_grid()
      ctx.playing = false
      grid_ui.draw_nav(ctx, g)
      assert.are.equal(led_at(g, 16, 8), 3)
    end)

  end)

  -- ========================================================================
  -- Key routing tests
  -- ========================================================================

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

  -- ========================================================================
  -- Nav key tests
  -- ========================================================================

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

    it("selects probability page (x=11)", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      grid_ui.nav_key(ctx, 11, 1)
      assert.are.equal("probability", ctx.active_page)
    end)

    it("selects alt_track page (x=15)", function()
      local ctx = make_ctx()
      grid_ui.nav_key(ctx, 15, 1)
      assert.are.equal("alt_track", ctx.active_page)
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

  -- ========================================================================
  -- Grid key tests
  -- ========================================================================

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

  -- ========================================================================
  -- Trigger key tests
  -- ========================================================================

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

  -- ========================================================================
  -- Value key tests
  -- ========================================================================

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

    it("maps probability rows to percentages", function()
      local ctx = make_ctx({active_track = 1})
      grid_ui.value_key(ctx, 2, 7, "probability")
      assert.are.equal(0, ctx.tracks[1].params.probability.steps[2])
      grid_ui.value_key(ctx, 2, 1, "probability")
      assert.are.equal(100, ctx.tracks[1].params.probability.steps[2])
    end)

  end)

  -- ========================================================================
  -- Loop key tests
  -- ========================================================================

  describe("extended page grid display (T048/T050/T052)", function()

    describe("glide page (T048)", function()

      it("displays bar graph for glide param via draw_value_page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.active_track = 1
        ctx.tracks[1].params.glide.steps[1] = 5
        ctx.tracks[1].params.glide.loop_start = 1
        ctx.tracks[1].params.glide.loop_end = 16
        grid_ui.draw_value_page(ctx, g, "glide")
        -- Value 5 at row 3 (8-5=3), brightness 10 in loop
        assert.are.equal(led_at(g, 1, 3), 10)
        -- Bar below: rows 4-7 at brightness 3
        for y = 4, 7 do
          assert.are.equal(led_at(g, 1, y), 3, "row " .. y .. " should be bar")
        end
        -- Above value: rows 1-2 should be off
        assert.are.equal(led_at(g, 1, 1), 0)
        assert.are.equal(led_at(g, 1, 2), 0)
      end)

      it("shows playhead brightness on glide page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.playing = true
        ctx.active_track = 1
        ctx.tracks[1].params.glide.steps[4] = 3
        ctx.tracks[1].params.glide.pos = 4
        grid_ui.draw_value_page(ctx, g, "glide")
        -- Value 3 at row 5 (8-3=5), playhead -> brightness 15
        assert.are.equal(led_at(g, 4, 5), 15)
        -- Bar below playhead: rows 6-7 at brightness 6
        assert.are.equal(led_at(g, 4, 6), 6)
        assert.are.equal(led_at(g, 4, 7), 6)
      end)

      it("shows dim value outside loop on glide page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.active_track = 1
        ctx.tracks[1].params.glide.steps[10] = 4
        ctx.tracks[1].params.glide.loop_start = 1
        ctx.tracks[1].params.glide.loop_end = 8
        grid_ui.draw_value_page(ctx, g, "glide")
        -- Step 10 outside loop, value 4 at row 4 -> brightness 4
        assert.are.equal(led_at(g, 10, 4), 4)
      end)

      it("redraw dispatches glide page correctly", function()
        local ctx = make_ctx()
        ctx.active_page = "glide"
        ctx.active_track = 1
        ctx.tracks[1].params.glide.steps[1] = 6
        ctx.tracks[1].params.glide.loop_start = 1
        ctx.tracks[1].params.glide.loop_end = 16
        grid_ui.redraw(ctx)
        -- Value 6 at row 2 (8-6=2) should be lit
        assert.are.equal(led_at(ctx.g, 1, 2), 10)
      end)

    end)

    describe("ratchet page (T050)", function()

      it("displays bar graph for ratchet param via draw_value_page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.active_track = 1
        ctx.tracks[1].params.ratchet.steps[1] = 3
        ctx.tracks[1].params.ratchet.loop_start = 1
        ctx.tracks[1].params.ratchet.loop_end = 16
        grid_ui.draw_value_page(ctx, g, "ratchet")
        -- Value 3 at row 5 (8-3=5), brightness 10 in loop
        assert.are.equal(led_at(g, 1, 5), 10)
        -- Bar below: rows 6-7 at brightness 3
        assert.are.equal(led_at(g, 1, 6), 3)
        assert.are.equal(led_at(g, 1, 7), 3)
        -- Above value: rows 1-4 should be off
        for y = 1, 4 do
          assert.are.equal(led_at(g, 1, y), 0, "row " .. y .. " should be off")
        end
      end)

      it("shows playhead brightness on ratchet page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.playing = true
        ctx.active_track = 2
        ctx.tracks[2].params.ratchet.steps[7] = 5
        ctx.tracks[2].params.ratchet.pos = 7
        grid_ui.draw_value_page(ctx, g, "ratchet")
        -- Value 5 at row 3 (8-5=3), playhead -> brightness 15
        assert.are.equal(led_at(g, 7, 3), 15)
        -- Bar below playhead: rows 4-7 at brightness 6
        for y = 4, 7 do
          assert.are.equal(led_at(g, 7, y), 6, "row " .. y .. " should be playhead bar")
        end
      end)

      it("ratchet default value 1 lights only row 7", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.active_track = 1
        -- Default ratchet is 1
        ctx.tracks[1].params.ratchet.loop_start = 1
        ctx.tracks[1].params.ratchet.loop_end = 16
        grid_ui.draw_value_page(ctx, g, "ratchet")
        -- Value 1 at row 7, brightness 10
        assert.are.equal(led_at(g, 1, 7), 10)
        -- All rows above off
        for y = 1, 6 do
          assert.are.equal(led_at(g, 1, y), 0, "row " .. y .. " should be off for ratchet=1")
        end
      end)

      it("redraw dispatches ratchet page correctly", function()
        local ctx = make_ctx()
        ctx.active_page = "ratchet"
        ctx.active_track = 1
        ctx.tracks[1].params.ratchet.steps[2] = 4
        ctx.tracks[1].params.ratchet.loop_start = 1
        ctx.tracks[1].params.ratchet.loop_end = 16
        grid_ui.redraw(ctx)
        -- Value 4 at row 4 (8-4=4) should be lit
        assert.are.equal(led_at(ctx.g, 2, 4), 10)
      end)

    end)

    describe("alt_note page (T052)", function()

      it("displays bar graph for alt_note param via draw_value_page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.active_track = 1
        ctx.tracks[1].params.alt_note.steps[1] = 6
        ctx.tracks[1].params.alt_note.loop_start = 1
        ctx.tracks[1].params.alt_note.loop_end = 16
        grid_ui.draw_value_page(ctx, g, "alt_note")
        -- Value 6 at row 2 (8-6=2), brightness 10 in loop
        assert.are.equal(led_at(g, 1, 2), 10)
        -- Bar below: rows 3-7 at brightness 3
        for y = 3, 7 do
          assert.are.equal(led_at(g, 1, y), 3, "row " .. y .. " should be bar")
        end
        -- Above value: row 1 should be off
        assert.are.equal(led_at(g, 1, 1), 0)
      end)

      it("shows playhead brightness on alt_note page", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.playing = true
        ctx.active_track = 1
        ctx.tracks[1].params.alt_note.steps[3] = 2
        ctx.tracks[1].params.alt_note.pos = 3
        grid_ui.draw_value_page(ctx, g, "alt_note")
        -- Value 2 at row 6 (8-2=6), playhead -> brightness 15
        assert.are.equal(led_at(g, 3, 6), 15)
        -- Bar below playhead: row 7 at brightness 6
        assert.are.equal(led_at(g, 3, 7), 6)
      end)

      it("alt_note default value 1 lights only row 7", function()
        local ctx = make_ctx()
        local g = mock_grid()
        ctx.active_track = 1
        -- Default alt_note is 1
        ctx.tracks[1].params.alt_note.loop_start = 1
        ctx.tracks[1].params.alt_note.loop_end = 16
        grid_ui.draw_value_page(ctx, g, "alt_note")
        -- Value 1 at row 7, brightness 10
        assert.are.equal(led_at(g, 1, 7), 10)
        -- All rows above off
        for y = 1, 6 do
          assert.are.equal(led_at(g, 1, y), 0, "row " .. y .. " should be off for alt_note=1")
        end
      end)

      it("redraw dispatches alt_note page correctly", function()
        local ctx = make_ctx()
        ctx.active_page = "alt_note"
        ctx.active_track = 1
        ctx.tracks[1].params.alt_note.steps[5] = 7
        ctx.tracks[1].params.alt_note.loop_start = 1
        ctx.tracks[1].params.alt_note.loop_end = 16
        grid_ui.redraw(ctx)
        -- Value 7 at row 1 (8-7=1) should be lit
        assert.are.equal(led_at(ctx.g, 5, 1), 10)
      end)

      it("value editing works on alt_note page", function()
        local ctx = make_ctx()
        ctx.active_page = "alt_note"
        ctx.active_track = 1
        grid_ui.grid_key(ctx, 5, 3, 1) -- step 5, row 3 = value 5
        assert.are.equal(ctx.tracks[1].params.alt_note.steps[5], 5)
      end)

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

  -- ========================================================================
  -- T048: Ratchet page display
  -- ========================================================================

  describe("ratchet page display (T048)", function()

    it("displays ratchet values as bar graph when active_page is ratchet", function()
      local ctx, g = make_ctx({ active_page = "ratchet" })
      -- Set ratchet values: step 1 = 3, step 5 = 7
      ctx.tracks[1].params.ratchet.steps[1] = 3
      ctx.tracks[1].params.ratchet.steps[5] = 7

      grid_ui.redraw(ctx)

      -- Value 3 at step 1: row_val==3 at y = 8-3 = 5, brightness 10 (in loop)
      assert.are.equal(10, g:get_led(1, 5))
      -- Value 7 at step 5: row_val==7 at y = 8-7 = 1, brightness 10
      assert.are.equal(10, g:get_led(5, 1))
      -- Below the value (bar fill): step 1, row_val 2 at y=6, brightness 3
      assert.are.equal(3, g:get_led(1, 6))
      -- Above the value should be 0: step 1, row_val 4 at y=4
      assert.are.equal(0, g:get_led(1, 4))
    end)

    it("shows playhead highlight on ratchet page", function()
      local ctx, g = make_ctx({ active_page = "ratchet", playing = true })
      ctx.tracks[1].params.ratchet.steps[1] = 4
      ctx.tracks[1].params.ratchet.pos = 1

      grid_ui.redraw(ctx)

      -- Playhead at step 1: value 4, row_val==4 at y=4, brightness 15
      assert.are.equal(15, g:get_led(1, 4))
      -- Below value on playhead: row_val 3 at y=5, brightness 6
      assert.are.equal(6, g:get_led(1, 5))
    end)

    it("shows default ratchet values (1) for a fresh track", function()
      local ctx, g = make_ctx({ active_page = "ratchet" })
      -- Default ratchet value should be 1

      grid_ui.redraw(ctx)

      -- Value 1 at step 1: row_val==1 at y=7, brightness 10
      assert.are.equal(10, g:get_led(1, 7))
      -- All rows above should be 0 for step 1
      for y = 1, 6 do
        assert.are.equal(0, g:get_led(1, y))
      end
    end)

    it("highlights primary nav button (trigger x=6) when on ratchet page", function()
      local ctx, g = make_ctx({ active_page = "ratchet" })

      grid_ui.redraw(ctx)

      -- Nav row is y=8. The trigger nav button at x=6 should be highlighted
      -- because ratchet is trigger's extended page
      assert.are.equal(12, g:get_led(6, 8))
      -- Other page buttons should be dim
      assert.are.equal(3, g:get_led(7, 8))  -- note
    end)

  end)

  -- ========================================================================
  -- T050: Alt_note page display
  -- ========================================================================

  describe("alt_note page display (T050)", function()

    it("displays alt_note values as bar graph", function()
      local ctx, g = make_ctx({ active_page = "alt_note" })
      ctx.tracks[1].params.alt_note.loop_end = 16
      ctx.tracks[1].params.alt_note.steps[3] = 5
      ctx.tracks[1].params.alt_note.steps[8] = 2

      grid_ui.redraw(ctx)

      -- Value 5 at step 3: row_val==5 at y=3, brightness 10
      assert.are.equal(10, g:get_led(3, 3))
      -- Value 2 at step 8: row_val==2 at y=6, brightness 10
      assert.are.equal(10, g:get_led(8, 6))
    end)

    it("shows playhead on alt_note page", function()
      local ctx, g = make_ctx({ active_page = "alt_note", playing = true })
      ctx.tracks[1].params.alt_note.steps[4] = 6
      ctx.tracks[1].params.alt_note.pos = 4

      grid_ui.redraw(ctx)

      -- Playhead at step 4: value 6, row_val==6 at y=2, brightness 15
      assert.are.equal(15, g:get_led(4, 2))
    end)

    it("highlights primary nav button (note x=7) when on alt_note page", function()
      local ctx, g = make_ctx({ active_page = "alt_note" })

      grid_ui.redraw(ctx)

      -- Note nav button at x=7 should be highlighted for alt_note
      assert.are.equal(12, g:get_led(7, 8))
      -- Trigger button should be dim
      assert.are.equal(3, g:get_led(6, 8))
    end)

  end)

  -- ========================================================================
  -- T052: Glide page display
  -- ========================================================================

  describe("glide page display (T052)", function()

    it("displays glide values as bar graph", function()
      local ctx, g = make_ctx({ active_page = "glide" })
      ctx.tracks[1].params.glide.loop_end = 16
      ctx.tracks[1].params.glide.steps[2] = 4
      ctx.tracks[1].params.glide.steps[10] = 7

      grid_ui.redraw(ctx)

      -- Value 4 at step 2: row_val==4 at y=4, brightness 10
      assert.are.equal(10, g:get_led(2, 4))
      -- Value 7 at step 10: row_val==7 at y=1, brightness 10
      assert.are.equal(10, g:get_led(10, 1))
    end)

    it("shows playhead on glide page", function()
      local ctx, g = make_ctx({ active_page = "glide", playing = true })
      ctx.tracks[1].params.glide.steps[7] = 3
      ctx.tracks[1].params.glide.pos = 7

      grid_ui.redraw(ctx)

      -- Playhead at step 7: value 3, row_val==3 at y=5, brightness 15
      assert.are.equal(15, g:get_led(7, 5))
    end)

    it("highlights primary nav button (octave x=8) when on glide page", function()
      local ctx, g = make_ctx({ active_page = "glide" })

      grid_ui.redraw(ctx)

      -- Octave nav button at x=8 should be highlighted for glide
      assert.are.equal(12, g:get_led(8, 8))
      -- Other page buttons dim
      assert.are.equal(3, g:get_led(6, 8))  -- trigger
    end)

  end)

  -- ========================================================================
  -- T060: Grid key editing on extended pages
  -- ========================================================================

  describe("value editing on extended pages (T060)", function()

    it("edits ratchet values via grid press", function()
      local ctx, g = make_ctx({ active_page = "ratchet" })

      -- Press at (x=3, y=5) -> value = 8-5 = 3
      grid_ui.key(ctx, 3, 5, 1)

      assert.are.equal(3, ctx.tracks[1].params.ratchet.steps[3])
    end)

    it("edits alt_note values via grid press", function()
      local ctx, g = make_ctx({ active_page = "alt_note" })

      -- Press at (x=7, y=2) -> value = 8-2 = 6
      grid_ui.key(ctx, 7, 2, 1)

      assert.are.equal(6, ctx.tracks[1].params.alt_note.steps[7])
    end)

    it("edits glide values via grid press", function()
      local ctx, g = make_ctx({ active_page = "glide" })

      -- Press at (x=10, y=1) -> value = 8-1 = 7
      grid_ui.key(ctx, 10, 1, 1)

      assert.are.equal(7, ctx.tracks[1].params.glide.steps[10])
    end)

    it("edits ratchet on correct track", function()
      local ctx, g = make_ctx({ active_page = "ratchet", active_track = 3 })

      grid_ui.key(ctx, 5, 3, 1)

      -- Should edit track 3, not track 1
      assert.are.equal(5, ctx.tracks[3].params.ratchet.steps[5])
      -- Track 1 should be unchanged (default = 1)
      assert.are.equal(1, ctx.tracks[1].params.ratchet.steps[5])
    end)

    it("loop editing works on ratchet page", function()
      local ctx, g = make_ctx({ active_page = "ratchet", loop_held = true })

      -- First press sets start
      grid_ui.key(ctx, 3, 3, 1)
      -- Second press sets end
      grid_ui.key(ctx, 8, 3, 1)

      assert.are.equal(3, ctx.tracks[1].params.ratchet.loop_start)
      assert.are.equal(8, ctx.tracks[1].params.ratchet.loop_end)
    end)

    it("loop editing works on alt_note page", function()
      local ctx, g = make_ctx({ active_page = "alt_note", loop_held = true })

      grid_ui.key(ctx, 2, 4, 1)
      grid_ui.key(ctx, 10, 4, 1)

      assert.are.equal(2, ctx.tracks[1].params.alt_note.loop_start)
      assert.are.equal(10, ctx.tracks[1].params.alt_note.loop_end)
    end)

    it("loop editing works on glide page", function()
      local ctx, g = make_ctx({ active_page = "glide", loop_held = true })

      grid_ui.key(ctx, 4, 2, 1)
      grid_ui.key(ctx, 12, 2, 1)

      assert.are.equal(4, ctx.tracks[1].params.glide.loop_start)
      assert.are.equal(12, ctx.tracks[1].params.glide.loop_end)
    end)

    it("ignores key release events on extended pages", function()
      local ctx, g = make_ctx({ active_page = "ratchet" })
      local original = ctx.tracks[1].params.ratchet.steps[3]

      -- z=0 is key release, should be ignored
      grid_ui.key(ctx, 3, 5, 0)

      assert.are.equal(original, ctx.tracks[1].params.ratchet.steps[3])
    end)

  end)

  -- ========================================================================
  -- Nav key tests for extended page navigation
  -- ========================================================================

  describe("nav key extended page toggle", function()

    it("pressing trigger nav (x=6) when already on trigger toggles to ratchet", function()
      local ctx, g = make_ctx({ active_page = "trigger" })

      -- Press trigger nav while already on trigger -> toggles to ratchet
      grid_ui.key(ctx, 6, 8, 1)
      assert.are.equal("ratchet", ctx.active_page)
    end)

    it("pressing trigger nav from different page goes to trigger first", function()
      local ctx, g = make_ctx({ active_page = "note" })

      -- Press trigger nav while on note -> goes to trigger (not ratchet)
      grid_ui.key(ctx, 6, 8, 1)
      assert.are.equal("trigger", ctx.active_page)

      -- Press again while on trigger -> toggles to ratchet
      grid_ui.key(ctx, 6, 8, 1)
      assert.are.equal("ratchet", ctx.active_page)
    end)

    it("pressing note nav (x=7) when already on note toggles to alt_note", function()
      local ctx, g = make_ctx({ active_page = "note" })

      grid_ui.key(ctx, 7, 8, 1)
      assert.are.equal("alt_note", ctx.active_page)
    end)

    it("pressing octave nav (x=8) when already on octave toggles to glide", function()
      local ctx, g = make_ctx({ active_page = "octave" })

      grid_ui.key(ctx, 8, 8, 1)
      assert.are.equal("glide", ctx.active_page)
    end)

    it("pressing trigger nav while on ratchet returns to trigger", function()
      local ctx, g = make_ctx({ active_page = "ratchet" })

      grid_ui.key(ctx, 6, 8, 1)
      assert.are.equal("trigger", ctx.active_page)
    end)

    it("pressing note nav while on alt_note returns to note", function()
      local ctx, g = make_ctx({ active_page = "alt_note" })

      grid_ui.key(ctx, 7, 8, 1)
      assert.are.equal("note", ctx.active_page)
    end)

    it("pressing octave nav while on glide returns to octave", function()
      local ctx, g = make_ctx({ active_page = "glide" })

      grid_ui.key(ctx, 8, 8, 1)
      assert.are.equal("octave", ctx.active_page)
    end)

    it("pressing duration nav (x=9) does not toggle to extended page", function()
      local ctx, g = make_ctx({ active_page = "duration" })

      -- Duration has no extended page, pressing again stays on duration
      grid_ui.key(ctx, 9, 8, 1)
      assert.are.equal("duration", ctx.active_page)
    end)

    it("pressing velocity nav (x=10) does not toggle to extended page", function()
      local ctx, g = make_ctx({ active_page = "velocity" })

      grid_ui.key(ctx, 10, 8, 1)
      assert.are.equal("velocity", ctx.active_page)
    end)

    it("extended pages are included in PAGES list", function()
      local found_ratchet = false
      local found_alt_note = false
      local found_glide = false
      for _, p in ipairs(grid_ui.PAGES) do
        if p == "ratchet" then found_ratchet = true end
        if p == "alt_note" then found_alt_note = true end
        if p == "glide" then found_glide = true end
      end
      assert.is_true(found_ratchet, "PAGES should include ratchet")
      assert.is_true(found_alt_note, "PAGES should include alt_note")
      assert.is_true(found_glide, "PAGES should include glide")
    end)

  end)

  -- ========================================================================
  -- Respects active track for extended page display
  -- ========================================================================

  describe("extended pages respect active track", function()

    it("ratchet page shows active track's ratchet param", function()
      local ctx, g = make_ctx({ active_page = "ratchet", active_track = 2 })
      ctx.tracks[2].params.ratchet.steps[4] = 6

      grid_ui.redraw(ctx)

      -- Value 6 at step 4: row_val==6 at y=2, brightness 10
      assert.are.equal(10, g:get_led(4, 2))
    end)

    it("switching tracks changes displayed ratchet data", function()
      local ctx, g = make_ctx({ active_page = "ratchet", active_track = 1 })
      ctx.tracks[1].params.ratchet.steps[1] = 5
      ctx.tracks[2].params.ratchet.steps[1] = 2

      -- Track 1 display
      grid_ui.redraw(ctx)
      assert.are.equal(10, g:get_led(1, 3))  -- value 5, y = 8-5 = 3

      -- Switch to track 2
      ctx.active_track = 2
      grid_ui.redraw(ctx)
      assert.are.equal(10, g:get_led(1, 6))  -- value 2, y = 8-2 = 6
      assert.are.equal(0, g:get_led(1, 3))   -- previous value row cleared
    end)

  end)

  -- ========================================================================
  -- Direction cycling via grid nav
  -- ========================================================================

  describe("direction cycling (nav x=11)", function()

    it("pressing x=11 cycles direction from forward to reverse", function()
      local ctx = make_ctx()
      assert.are.equal("forward", ctx.tracks[1].direction)
      grid_ui.key(ctx, 11, 8, 1)
      assert.are.equal("reverse", ctx.tracks[1].direction)
    end)

    it("cycles through all modes in order", function()
      local ctx = make_ctx()
      local expected = {"reverse", "pendulum", "drunk", "random", "forward"}
      for _, mode in ipairs(expected) do
        grid_ui.key(ctx, 11, 8, 1)
        assert.are.equal(mode, ctx.tracks[ctx.active_track].direction)
      end
    end)

    it("affects only the active track", function()
      local ctx = make_ctx()
      ctx.active_track = 2
      grid_ui.key(ctx, 11, 8, 1)
      assert.are.equal("forward", ctx.tracks[1].direction)
      assert.are.equal("reverse", ctx.tracks[2].direction)
    end)

    it("nav LED is dim for forward, bright for other modes", function()
      local ctx, g = make_ctx()
      grid_ui.redraw(ctx)
      assert.are.equal(3, g:get_led(11, 8))  -- forward = dim

      ctx.tracks[1].direction = "reverse"
      grid_ui.redraw(ctx)
      assert.are.equal(10, g:get_led(11, 8))  -- non-forward = bright
    end)

    it("ignores key release (z=0)", function()
      local ctx = make_ctx()
      grid_ui.key(ctx, 11, 8, 0)
      assert.are.equal("forward", ctx.tracks[1].direction)
    end)

  end)

end)
