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

-- Mock grid that records led() calls
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
  }
  return ctx, g
end

describe("grid_ui", function()

  -- ========================================================================
  -- Basic display tests for existing pages
  -- ========================================================================

  describe("redraw", function()

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

end)
