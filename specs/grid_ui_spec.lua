-- specs/grid_ui_spec.lua
-- Tests for lib/grid_ui.lua, focusing on extended page toggle

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer -> recorder)
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local grid_ui = require("lib/grid_ui")

-- Helper: create a minimal ctx for grid_ui testing
local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    loop_first_press = nil,
    grid_dirty = false,
    voices = {},
    clock_ids = nil,
  }
end

describe("grid_ui", function()

  describe("extended page toggle", function()

    it("double-press trigger page key switches to ratchet", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      -- Press trigger page key (x=6) while already on trigger -> should switch to ratchet
      grid_ui.nav_key(ctx, 6, 1)
      assert.are.equal("ratchet", ctx.active_page)
    end)

    it("pressing ratchet page key again returns to trigger", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      -- Press trigger page key (x=6) while on ratchet -> should switch back to trigger
      grid_ui.nav_key(ctx, 6, 1)
      assert.are.equal("trigger", ctx.active_page)
    end)

    it("switching to a different page clears extended state", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      -- Press note page key (x=7) -> should switch to note, not alt_note
      grid_ui.nav_key(ctx, 7, 1)
      assert.are.equal("note", ctx.active_page)
    end)

    it("double-press note page key switches to alt_note", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      grid_ui.nav_key(ctx, 7, 1)
      assert.are.equal("alt_note", ctx.active_page)
    end)

    it("double-press octave page key switches to glide", function()
      local ctx = make_ctx()
      ctx.active_page = "octave"
      grid_ui.nav_key(ctx, 8, 1)
      assert.are.equal("glide", ctx.active_page)
    end)

    it("alt_note key press returns to note", function()
      local ctx = make_ctx()
      ctx.active_page = "alt_note"
      grid_ui.nav_key(ctx, 7, 1)
      assert.are.equal("note", ctx.active_page)
    end)

    it("glide key press returns to octave", function()
      local ctx = make_ctx()
      ctx.active_page = "glide"
      grid_ui.nav_key(ctx, 8, 1)
      assert.are.equal("octave", ctx.active_page)
    end)

    it("duration double-press stays on duration (no extended page)", function()
      local ctx = make_ctx()
      ctx.active_page = "duration"
      grid_ui.nav_key(ctx, 9, 1)
      assert.are.equal("duration", ctx.active_page)
    end)

    it("velocity double-press stays on velocity (no extended page)", function()
      local ctx = make_ctx()
      ctx.active_page = "velocity"
      grid_ui.nav_key(ctx, 10, 1)
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

  describe("nav_key draw_nav highlights", function()

    it("draw_nav highlights trigger button when on ratchet page", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      -- Create a mock grid that records LED calls
      local leds = {}
      local mock_g = {
        led = function(self, x, y, val) leds[x .. "," .. y] = val end,
        all = function(self, val) end,
        refresh = function(self) end,
      }
      grid_ui.draw_nav(ctx, mock_g)
      -- x=6 (trigger button) should be highlighted (12) even when on ratchet
      assert.are.equal(12, leds["6,8"])
    end)

    it("draw_nav highlights note button when on alt_note page", function()
      local ctx = make_ctx()
      ctx.active_page = "alt_note"
      local leds = {}
      local mock_g = {
        led = function(self, x, y, val) leds[x .. "," .. y] = val end,
        all = function(self, val) end,
        refresh = function(self) end,
      }
      grid_ui.draw_nav(ctx, mock_g)
      -- x=7 (note button) should be highlighted
      assert.are.equal(12, leds["7,8"])
    end)

    it("draw_nav highlights octave button when on glide page", function()
      local ctx = make_ctx()
      ctx.active_page = "glide"
      local leds = {}
      local mock_g = {
        led = function(self, x, y, val) leds[x .. "," .. y] = val end,
        all = function(self, val) end,
        refresh = function(self) end,
      }
      grid_ui.draw_nav(ctx, mock_g)
      -- x=8 (octave button) should be highlighted
      assert.are.equal(12, leds["8,8"])
    end)

  end)

  describe("redraw dispatches extended pages", function()

    it("redraw does not error on ratchet page", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      local mock_g = {
        led = function(self, x, y, val) end,
        all = function(self, val) end,
        refresh = function(self) end,
      }
      ctx.g = mock_g
      -- Should not error
      grid_ui.redraw(ctx)
    end)

    it("redraw does not error on alt_note page", function()
      local ctx = make_ctx()
      ctx.active_page = "alt_note"
      local mock_g = {
        led = function(self, x, y, val) end,
        all = function(self, val) end,
        refresh = function(self) end,
      }
      ctx.g = mock_g
      grid_ui.redraw(ctx)
    end)

    it("redraw does not error on glide page", function()
      local ctx = make_ctx()
      ctx.active_page = "glide"
      local mock_g = {
        led = function(self, x, y, val) end,
        all = function(self, val) end,
        refresh = function(self) end,
      }
      ctx.g = mock_g
      grid_ui.redraw(ctx)
    end)

  end)

end)
