-- specs/events_integration_spec.lua
-- Integration tests for event bus wiring: sequencer, grid_ui, mute, pattern

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer, required indirectly by grid_ui)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local events = require("lib/events")
local sequencer = require("lib/sequencer")
local grid_ui = require("lib/grid_ui")
local pattern = require("lib/pattern")
local scale_mod = require("lib/scale")
local recorder = require("lib/voices/recorder")

-- Build a test scale_notes table (same as sequencer_spec)
local function build_test_scale()
  local notes = {}
  for i = 1, 56 do
    notes[i] = 24 + (i - 1) * 2
  end
  return notes
end

-- Mock grid
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

-- Helper: create a full ctx with events bus, voices, patterns
local function make_ctx(opts)
  opts = opts or {}
  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  local g = mock_grid()
  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = opts.active_track or 1,
    active_page = opts.active_page or "trigger",
    playing = opts.playing or false,
    loop_held = false,
    loop_first_press = nil,
    grid_dirty = true,
    scale_notes = build_test_scale(),
    voices = voices,
    g = g,
    clock_ids = nil,
    events = events.new(),
    patterns = pattern.new_slots(),
    pattern_held = false,
    pattern_slot = 1,
  }
  return ctx, g, buffer
end

describe("events integration", function()

  -- ========================================================================
  -- Part 1: Event bus on ctx
  -- ========================================================================

  describe("event bus on ctx", function()

    it("ctx has an event bus after creation", function()
      local ctx = make_ctx()
      assert.is_not_nil(ctx.events)
      assert.is_function(ctx.events.on)
      assert.is_function(ctx.events.emit)
    end)

    it("event bus works end-to-end via ctx", function()
      local ctx = make_ctx()
      local received = nil
      ctx.events:on("test:ping", function(data)
        received = data
      end)
      ctx.events:emit("test:ping", {msg="hello"})
      assert.is_not_nil(received)
      assert.are.equal(received.msg, "hello")
    end)

  end)

  -- ========================================================================
  -- Part 1: Sequencer emits events
  -- ========================================================================

  describe("sequencer events", function()

    it("emits sequencer:start on start", function()
      local ctx = make_ctx()
      local received = false
      ctx.events:on("sequencer:start", function()
        received = true
      end)
      sequencer.start(ctx)
      assert.is_true(received)
    end)

    it("emits sequencer:stop on stop", function()
      local ctx = make_ctx()
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}
      local received = false
      ctx.events:on("sequencer:stop", function()
        received = true
      end)
      sequencer.stop(ctx)
      assert.is_true(received)
    end)

    it("emits sequencer:step after stepping a track", function()
      local ctx = make_ctx()
      local received = nil
      ctx.events:on("sequencer:step", function(data)
        received = data
      end)
      sequencer.step_track(ctx, 1)
      assert.is_not_nil(received)
      assert.are.equal(received.track, 1)
      assert.is_not_nil(received.vals)
    end)

    it("emits voice:note when a trigger fires", function()
      local ctx = make_ctx()
      -- Set up trigger at pos 1
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1

      local received = nil
      ctx.events:on("voice:note", function(data)
        received = data
      end)
      sequencer.step_track(ctx, 1)
      assert.is_not_nil(received)
      assert.are.equal(received.track, 1)
      assert.is_number(received.note)
      assert.is_number(received.vel)
      assert.is_number(received.dur)
    end)

    it("does not emit voice:note when trigger is 0", function()
      local ctx = make_ctx()
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.tracks[1].params.trigger.pos = 1

      local received = nil
      ctx.events:on("voice:note", function(data)
        received = data
      end)
      sequencer.step_track(ctx, 1)
      assert.is_nil(received)
    end)

    it("still emits sequencer:step when muted (but not voice:note)", function()
      local ctx = make_ctx()
      ctx.tracks[1].muted = true
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1

      local step_received = false
      local note_received = false
      ctx.events:on("sequencer:step", function() step_received = true end)
      ctx.events:on("voice:note", function() note_received = true end)
      sequencer.step_track(ctx, 1)
      assert.is_true(step_received)
      assert.is_false(note_received)
    end)

    it("works without events on ctx (backward compat)", function()
      local ctx = make_ctx()
      ctx.events = nil
      -- Should not error
      sequencer.start(ctx)
      sequencer.step_track(ctx, 1)
      sequencer.stop(ctx)
    end)

  end)

  -- ========================================================================
  -- Part 1: Grid emits events
  -- ========================================================================

  describe("grid key events", function()

    it("emits grid:key on any key press", function()
      local ctx = make_ctx()
      local received = nil
      ctx.events:on("grid:key", function(data)
        received = data
      end)
      grid_ui.key(ctx, 3, 4, 1)
      assert.is_not_nil(received)
      assert.are.equal(received.x, 3)
      assert.are.equal(received.y, 4)
      assert.are.equal(received.z, 1)
    end)

    it("emits track:select when track changes", function()
      local ctx = make_ctx()
      local received = nil
      ctx.events:on("track:select", function(data)
        received = data
      end)
      -- Press track 3 button (x=3, y=8, z=1)
      grid_ui.key(ctx, 3, 8, 1)
      assert.is_not_nil(received)
      assert.are.equal(received.track, 3)
      assert.are.equal(ctx.active_track, 3)
    end)

    it("emits page:select when page changes", function()
      local ctx = make_ctx({active_page = "trigger"})
      local received = nil
      ctx.events:on("page:select", function(data)
        received = data
      end)
      -- Press note page button (x=7, y=8, z=1)
      grid_ui.key(ctx, 7, 8, 1)
      assert.is_not_nil(received)
      assert.are.equal(received.page, "note")
      assert.are.equal(received.prev, "trigger")
    end)

    it("does not emit page:select when page stays the same", function()
      local ctx = make_ctx({active_page = "duration"})
      local received = nil
      ctx.events:on("page:select", function(data)
        received = data
      end)
      -- Press duration page button (x=9) when already on duration
      grid_ui.key(ctx, 9, 8, 1)
      -- duration has no extended page, so it stays the same
      assert.is_nil(received)
    end)

    it("works without events on ctx", function()
      local ctx = make_ctx()
      ctx.events = nil
      -- Should not error
      grid_ui.key(ctx, 3, 8, 1)
      grid_ui.key(ctx, 7, 8, 1)
    end)

  end)

  -- ========================================================================
  -- Part 2: Mute toggle
  -- ========================================================================

  describe("mute toggle", function()

    it("toggles mute on active track via x=5 row 8", function()
      local ctx = make_ctx()
      assert.is_false(ctx.tracks[1].muted)
      -- Press mute button
      grid_ui.key(ctx, 5, 8, 1)
      assert.is_true(ctx.tracks[1].muted)
      -- Press again to unmute
      grid_ui.key(ctx, 5, 8, 1)
      assert.is_false(ctx.tracks[1].muted)
    end)

    it("mutes the active track, not always track 1", function()
      local ctx = make_ctx({active_track = 3})
      assert.is_false(ctx.tracks[3].muted)
      grid_ui.key(ctx, 5, 8, 1)
      assert.is_true(ctx.tracks[3].muted)
      -- Track 1 should be unaffected
      assert.is_false(ctx.tracks[1].muted)
    end)

    it("emits track:mute event", function()
      local ctx = make_ctx()
      local received = nil
      ctx.events:on("track:mute", function(data)
        received = data
      end)
      grid_ui.key(ctx, 5, 8, 1)
      assert.is_not_nil(received)
      assert.are.equal(received.track, 1)
      assert.is_true(received.muted)
    end)

    it("emits track:mute with muted=false on unmute", function()
      local ctx = make_ctx()
      ctx.tracks[1].muted = true
      local received = nil
      ctx.events:on("track:mute", function(data)
        received = data
      end)
      grid_ui.key(ctx, 5, 8, 1)
      assert.is_not_nil(received)
      assert.is_false(received.muted)
    end)

    it("draws mute indicator bright when muted", function()
      local ctx, g = make_ctx()
      ctx.tracks[1].muted = true
      grid_ui.redraw(ctx)
      assert.are.equal(g:get_led(5, 8), 12)
    end)

    it("draws mute indicator dim when not muted", function()
      local ctx, g = make_ctx()
      ctx.tracks[1].muted = false
      grid_ui.redraw(ctx)
      assert.are.equal(g:get_led(5, 8), 3)
    end)

  end)

  -- ========================================================================
  -- Part 3: Pattern load via grid
  -- ========================================================================

  describe("pattern grid controls", function()

    it("x=14 row 8 sets pattern_held on press", function()
      local ctx = make_ctx()
      assert.is_false(ctx.pattern_held)
      grid_ui.key(ctx, 14, 8, 1)
      assert.is_true(ctx.pattern_held)
    end)

    it("x=14 row 8 clears pattern_held on release", function()
      local ctx = make_ctx()
      ctx.pattern_held = true
      grid_ui.key(ctx, 14, 8, 0)
      assert.is_false(ctx.pattern_held)
    end)

    it("pressing slot in pattern mode loads pattern and emits event", function()
      local ctx = make_ctx()
      -- Save a pattern to slot 3 first
      ctx.tracks[1].params.trigger.steps[1] = 1
      pattern.save(ctx, 3)

      -- Modify tracks so we can verify load restores
      ctx.tracks[1].params.trigger.steps[1] = 0

      local received = nil
      ctx.events:on("pattern:load", function(data)
        received = data
      end)

      -- Enter pattern mode
      ctx.pattern_held = true
      -- Press slot 3 (row 1, col 3)
      grid_ui.key(ctx, 3, 1, 1)

      assert.are.equal(ctx.pattern_slot, 3)
      assert.is_not_nil(received)
      assert.are.equal(received.slot, 3)
      -- Verify pattern was loaded (trigger step restored)
      assert.are.equal(ctx.tracks[1].params.trigger.steps[1], 1)
    end)

    it("pattern slot mapping: row 1 cols 1-8 = slots 1-8", function()
      local ctx = make_ctx()
      ctx.pattern_held = true
      for x = 1, 8 do
        pattern.save(ctx, x) -- populate so load doesn't skip
        grid_ui.key(ctx, x, 1, 1)
        assert.are.equal(ctx.pattern_slot, x)
      end
    end)

    it("pattern slot mapping: row 2 cols 1-8 = slots 9-16", function()
      local ctx = make_ctx()
      ctx.pattern_held = true
      for x = 1, 8 do
        local slot = 8 + x
        pattern.save(ctx, slot)
        grid_ui.key(ctx, x, 2, 1)
        assert.are.equal(ctx.pattern_slot, slot)
      end
    end)

    it("ignores presses outside rows 1-2 or cols 1-8 in pattern mode", function()
      local ctx = make_ctx()
      ctx.pattern_held = true
      local initial_slot = ctx.pattern_slot
      -- Row 3 should be ignored
      grid_ui.key(ctx, 1, 3, 1)
      assert.are.equal(ctx.pattern_slot, initial_slot)
      -- Col 9 should be ignored
      grid_ui.key(ctx, 9, 1, 1)
      assert.are.equal(ctx.pattern_slot, initial_slot)
    end)

    it("draws pattern indicator bright when held", function()
      local ctx, g = make_ctx()
      ctx.pattern_held = true
      grid_ui.redraw(ctx)
      assert.are.equal(g:get_led(14, 8), 12)
    end)

    it("draws pattern indicator dim when not held", function()
      local ctx, g = make_ctx()
      ctx.pattern_held = false
      grid_ui.redraw(ctx)
      assert.are.equal(g:get_led(14, 8), 3)
    end)

    it("draws pattern slots when pattern_held", function()
      local ctx, g = make_ctx()
      ctx.pattern_held = true
      pattern.save(ctx, 1)
      pattern.save(ctx, 5)
      ctx.pattern_slot = 1

      grid_ui.redraw(ctx)

      -- Slot 1 (row 1, col 1): populated + current = 15
      assert.are.equal(g:get_led(1, 1), 15)
      -- Slot 5 (row 1, col 5): populated, not current = 10
      assert.are.equal(g:get_led(5, 1), 10)
      -- Slot 2 (row 1, col 2): empty, not current = 2
      assert.are.equal(g:get_led(2, 1), 2)
    end)

  end)

end)
