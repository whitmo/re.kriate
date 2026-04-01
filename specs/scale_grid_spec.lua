-- specs/scale_grid_spec.lua
-- Tests for scale selection grid page (lib/grid_ui.lua draw_scale_page + scale_key)

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
local events = require("lib/events")

-- Spy grid: captures all led() calls
local function spy_grid()
  local leds = {}
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
      for k in pairs(leds) do leds[k] = nil end
    end,
    refresh = function(self)
      self.refreshed = true
    end,
  }
  return g
end

local function led_at(g, x, y)
  return (g.leds[x] and g.leds[x][y]) or 0
end

-- Helper: create a minimal ctx for scale page testing
local function make_ctx(opts)
  opts = opts or {}
  return {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "scale",
    playing = false,
    loop_held = false,
    loop_first_press = nil,
    grid_dirty = true,
    g = spy_grid(),
    voices = {},
    root_note = opts.root_note or 60,  -- C5 (middle C)
    scale_type = opts.scale_type or 1,  -- Major
    scale_notes = opts.scale_notes or {},
    events = events.new(),
    pattern_held = false,
    pattern_slot = 1,
  }
end

describe("scale grid page", function()

  -- ==========================================================================
  -- draw_scale_page
  -- ==========================================================================
  describe("draw_scale_page", function()

    it("highlights correct pitch class on row 1", function()
      local ctx = make_ctx({root_note = 60}) -- C (pitch class 0 → x=1)
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 1, 1))  -- C highlighted
      assert.are.equal(3, led_at(g, 2, 1))   -- C# dim
      assert.are.equal(3, led_at(g, 12, 1))  -- B dim
    end)

    it("highlights D# (pitch class 3) on row 1", function()
      local ctx = make_ctx({root_note = 63}) -- D# (63 % 12 = 3 → x=4)
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 4, 1))  -- D# highlighted
      assert.are.equal(3, led_at(g, 3, 1))   -- D dim
    end)

    it("highlights correct octave on row 2", function()
      local ctx = make_ctx({root_note = 60}) -- octave 5 → x=6
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 6, 2))  -- octave 5 highlighted
      assert.are.equal(3, led_at(g, 5, 2))   -- octave 4 dim
    end)

    it("highlights octave 0 for low MIDI notes", function()
      local ctx = make_ctx({root_note = 3}) -- octave 0 → x=1
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 1, 2))
      assert.are.equal(3, led_at(g, 2, 2))
    end)

    it("highlights scale type 1 (Major) on row 3", function()
      local ctx = make_ctx({scale_type = 1})
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 1, 3))  -- Major highlighted
      assert.are.equal(3, led_at(g, 2, 3))   -- Natural Minor dim
    end)

    it("highlights scale type 5 (Lydian) on row 3", function()
      local ctx = make_ctx({scale_type = 5})
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 5, 3))
      assert.are.equal(3, led_at(g, 1, 3))
    end)

    it("highlights scale type 8 (Harmonic Minor) on row 4 x=1", function()
      local ctx = make_ctx({scale_type = 8})
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 1, 4))
      -- Row 3 should have no highlight
      for x = 1, 7 do
        assert.are.equal(3, led_at(g, x, 3))
      end
    end)

    it("highlights scale type 14 (Chromatic) on row 4 x=7", function()
      local ctx = make_ctx({scale_type = 14})
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      assert.are.equal(15, led_at(g, 7, 4))
    end)

    it("shows scale visualization on row 5", function()
      -- C major scale notes: C D E F G A B (pitch classes 0,2,4,5,7,9,11)
      local ctx = make_ctx({
        root_note = 60,
        scale_notes = {24, 26, 28, 29, 31, 33, 35, 36, 38, 40, 41, 43, 45, 47},
      })
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      -- In scale: C(x=1), D(x=3), E(x=5), F(x=6), G(x=8), A(x=10), B(x=12)
      assert.are.equal(8, led_at(g, 1, 5))   -- C in scale
      assert.are.equal(1, led_at(g, 2, 5))   -- C# not in scale
      assert.are.equal(8, led_at(g, 3, 5))   -- D in scale
      assert.are.equal(1, led_at(g, 4, 5))   -- D# not in scale
      assert.are.equal(8, led_at(g, 5, 5))   -- E in scale
      assert.are.equal(8, led_at(g, 6, 5))   -- F in scale
      assert.are.equal(1, led_at(g, 7, 5))   -- F# not in scale
      assert.are.equal(8, led_at(g, 8, 5))   -- G in scale
      assert.are.equal(1, led_at(g, 9, 5))   -- G# not in scale
      assert.are.equal(8, led_at(g, 10, 5))  -- A in scale
      assert.are.equal(1, led_at(g, 11, 5))  -- A# not in scale
      assert.are.equal(8, led_at(g, 12, 5))  -- B in scale
    end)

    it("skips visualization when scale_notes is empty", function()
      local ctx = make_ctx({scale_notes = {}})
      local g = spy_grid()
      grid_ui.draw_scale_page(ctx, g)
      -- Row 5 should be all 0 (unset)
      for x = 1, 12 do
        assert.are.equal(0, led_at(g, x, 5))
      end
    end)
  end)

  -- ==========================================================================
  -- scale_key
  -- ==========================================================================
  describe("scale_key", function()

    it("sets pitch class from row 1 press", function()
      local ctx = make_ctx({root_note = 60}) -- C5
      grid_ui.scale_key(ctx, 4, 1) -- D# (pitch class 3)
      -- octave stays 5 (60/12=5), pitch class = 3 → 5*12+3 = 63
      assert.are.equal(63, ctx.root_note)
    end)

    it("sets pitch class B from row 1 x=12", function()
      local ctx = make_ctx({root_note = 60}) -- C5
      grid_ui.scale_key(ctx, 12, 1) -- B (pitch class 11)
      -- octave 5, pitch class 11 → 5*12+11 = 71
      assert.are.equal(71, ctx.root_note)
    end)

    it("sets octave from row 2 press", function()
      local ctx = make_ctx({root_note = 60}) -- C5
      grid_ui.scale_key(ctx, 4, 2) -- octave 3
      -- pitch class stays C (0), octave = 3 → 3*12+0 = 36
      assert.are.equal(36, ctx.root_note)
    end)

    it("clamps root_note to 127 max", function()
      local ctx = make_ctx({root_note = 120}) -- high note
      grid_ui.scale_key(ctx, 10, 2) -- octave 9
      -- pitch class = 120%12 = 0 (C), 9*12+0 = 108
      assert.are.equal(108, ctx.root_note)
      -- Now set high octave + high pitch class
      ctx.root_note = 127
      grid_ui.scale_key(ctx, 10, 2) -- octave 9, pitch class 7 (G) → 9*12+7 = 115
      assert.are.equal(115, ctx.root_note)
    end)

    it("sets scale type 1-7 from row 3", function()
      local ctx = make_ctx({scale_type = 1})
      grid_ui.scale_key(ctx, 3, 3) -- scale type 3 (Dorian)
      assert.are.equal(3, ctx.scale_type)
    end)

    it("sets scale type 8-14 from row 4", function()
      local ctx = make_ctx({scale_type = 1})
      grid_ui.scale_key(ctx, 5, 4) -- scale type 12 (Blues Scale)
      assert.are.equal(12, ctx.scale_type)
    end)

    it("sets scale type 14 from row 4 x=7", function()
      local ctx = make_ctx({scale_type = 1})
      grid_ui.scale_key(ctx, 7, 4) -- scale type 14 (Chromatic)
      assert.are.equal(14, ctx.scale_type)
    end)

    it("emits scale:root event on pitch class change", function()
      local ctx = make_ctx({root_note = 60})
      local received = nil
      ctx.events:on("scale:root", function(data) received = data end)
      grid_ui.scale_key(ctx, 5, 1) -- E
      assert.is_not_nil(received)
      assert.are.equal(ctx.root_note, received.root_note)
    end)

    it("emits scale:root event on octave change", function()
      local ctx = make_ctx({root_note = 60})
      local received = nil
      ctx.events:on("scale:root", function(data) received = data end)
      grid_ui.scale_key(ctx, 3, 2) -- octave 2
      assert.is_not_nil(received)
      assert.are.equal(24, received.root_note) -- C2 = 24
    end)

    it("emits scale:type event on scale change", function()
      local ctx = make_ctx({scale_type = 1})
      local received = nil
      ctx.events:on("scale:type", function(data) received = data end)
      grid_ui.scale_key(ctx, 2, 3) -- Natural Minor
      assert.is_not_nil(received)
      assert.are.equal(2, received.scale_type)
    end)

    it("ignores presses outside active regions", function()
      local ctx = make_ctx({root_note = 60, scale_type = 1})
      -- Row 1 x=13-16: no effect
      grid_ui.scale_key(ctx, 13, 1)
      assert.are.equal(60, ctx.root_note)
      -- Row 2 x=11-16: no effect
      grid_ui.scale_key(ctx, 11, 2)
      assert.are.equal(60, ctx.root_note)
      -- Row 3 x=8+: no effect
      grid_ui.scale_key(ctx, 8, 3)
      assert.are.equal(1, ctx.scale_type)
      -- Row 6-7: no effect
      grid_ui.scale_key(ctx, 1, 6)
      assert.are.equal(60, ctx.root_note)
      assert.are.equal(1, ctx.scale_type)
    end)

    it("works without events bus", function()
      local ctx = make_ctx({root_note = 60})
      ctx.events = nil
      -- Should not error
      grid_ui.scale_key(ctx, 5, 1)
      assert.are.equal(64, ctx.root_note) -- E5
    end)
  end)

  -- ==========================================================================
  -- Integration: key routing and full redraw
  -- ==========================================================================
  describe("integration", function()

    it("routes grid key presses to scale_key when on scale page", function()
      local ctx = make_ctx({root_note = 60, scale_type = 1})
      ctx.g = spy_grid()
      -- Simulate grid press on row 3 x=4 (Mixolydian)
      grid_ui.key(ctx, 4, 3, 1)
      assert.are.equal(4, ctx.scale_type)
    end)

    it("does not route scale keys when on other pages", function()
      local ctx = make_ctx({root_note = 60, scale_type = 1})
      ctx.active_page = "trigger"
      -- This should go to trigger_key, not scale_key
      grid_ui.key(ctx, 4, 3, 1)
      assert.are.equal(1, ctx.scale_type) -- unchanged
    end)

    it("full redraw on scale page draws all regions", function()
      local ctx = make_ctx({
        root_note = 62,  -- D5 (pitch class 2 → x=3, octave 5 → x=6)
        scale_type = 10, -- Major Pentatonic (row 4, x=3)
        scale_notes = {24, 26, 28, 31, 33, 36}, -- C D E G A scale
      })
      ctx.g = spy_grid()
      grid_ui.redraw(ctx)
      local g = ctx.g

      -- Row 1: D highlighted at x=3
      assert.are.equal(15, led_at(g, 3, 1))
      assert.are.equal(3, led_at(g, 1, 1))

      -- Row 2: octave 5 at x=6
      assert.are.equal(15, led_at(g, 6, 2))

      -- Row 3: no highlight (type 10 is on row 4)
      for x = 1, 7 do
        assert.are.equal(3, led_at(g, x, 3))
      end

      -- Row 4: x=3 highlighted (type 10 = 10-7 = x=3)
      assert.are.equal(15, led_at(g, 3, 4))
      assert.are.equal(3, led_at(g, 1, 4))

      -- Row 8 nav: scale button (x=14) highlighted
      assert.are.equal(12, led_at(g, 14, 8))
    end)

    it("nav key x=14 switches to scale page", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      grid_ui.key(ctx, 14, 8, 1) -- nav row press on scale button
      assert.are.equal("scale", ctx.active_page)
    end)
  end)
end)
