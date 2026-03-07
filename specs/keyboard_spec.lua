-- specs/keyboard_spec.lua
-- Tests for lib/seamstress/keyboard.lua

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
local keyboard = require("lib/seamstress/keyboard")

-- Helper: create a minimal ctx
local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    grid_dirty = false,
    voices = {},
    clock_ids = nil,
  }
end

describe("keyboard", function()

  describe("play/stop", function()

    it("space starts playback when stopped", function()
      local ctx = make_ctx()
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_true(ctx.playing)
    end)

    it("space stops playback when playing", function()
      local ctx = make_ctx()
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_false(ctx.playing)
    end)

    it("space toggles play state", function()
      local ctx = make_ctx()
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_true(ctx.playing)
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_false(ctx.playing)
    end)

  end)

  describe("reset", function()

    it("r resets all playheads", function()
      local ctx = make_ctx()
      -- Advance some positions
      for t = 1, track_mod.NUM_TRACKS do
        ctx.tracks[t].params.trigger.pos = 8
      end
      keyboard.key(ctx, "r", {}, false, 1)
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(ctx.tracks[t].params.trigger.pos,
          ctx.tracks[t].params.trigger.loop_start)
      end
    end)

  end)

  describe("track select", function()

    it("1-4 selects track", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "2", {}, false, 1)
      assert.are.equal(ctx.active_track, 2)
      keyboard.key(ctx, "4", {}, false, 1)
      assert.are.equal(ctx.active_track, 4)
      keyboard.key(ctx, "1", {}, false, 1)
      assert.are.equal(ctx.active_track, 1)
      keyboard.key(ctx, "3", {}, false, 1)
      assert.are.equal(ctx.active_track, 3)
    end)

  end)

  describe("page select", function()

    it("q selects trigger page", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      keyboard.key(ctx, "q", {}, false, 1)
      assert.are.equal(ctx.active_page, "trigger")
    end)

    it("w selects note page", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "w", {}, false, 1)
      assert.are.equal(ctx.active_page, "note")
    end)

    it("e selects octave page", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "e", {}, false, 1)
      assert.are.equal(ctx.active_page, "octave")
    end)

    it("t selects duration page", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "t", {}, false, 1)
      assert.are.equal(ctx.active_page, "duration")
    end)

    it("y selects velocity page", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "y", {}, false, 1)
      assert.are.equal(ctx.active_page, "velocity")
    end)

  end)

  describe("input filtering", function()

    it("ignores key up events (state ~= 1)", function()
      local ctx = make_ctx()
      keyboard.key(ctx, " ", {}, false, 0)
      assert.is_false(ctx.playing)
    end)

    it("ignores key repeats", function()
      local ctx = make_ctx()
      keyboard.key(ctx, " ", {}, true, 1)
      assert.is_false(ctx.playing)
    end)

    it("ignores unmapped keys", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "z", {}, false, 1)
      assert.are.equal(ctx.active_track, 1)
      assert.are.equal(ctx.active_page, "trigger")
      assert.is_false(ctx.playing)
    end)

  end)

  describe("grid_dirty", function()

    it("sets grid_dirty on any key down", function()
      local ctx = make_ctx()
      ctx.grid_dirty = false
      keyboard.key(ctx, "2", {}, false, 1)
      assert.is_true(ctx.grid_dirty)
    end)

    it("sets grid_dirty even for unmapped keys", function()
      local ctx = make_ctx()
      ctx.grid_dirty = false
      keyboard.key(ctx, "z", {}, false, 1)
      assert.is_true(ctx.grid_dirty)
    end)

    it("does not set grid_dirty on key up", function()
      local ctx = make_ctx()
      ctx.grid_dirty = false
      keyboard.key(ctx, " ", {}, false, 0)
      assert.is_false(ctx.grid_dirty)
    end)

  end)

end)
