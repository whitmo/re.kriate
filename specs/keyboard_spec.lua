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

local param_store = { pattern_bank_name = "default" }
rawset(_G, "params", {
  get = function(self, id)
    return param_store[id]
  end,
  set = function(self, id, val)
    param_store[id] = val
  end,
})

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local app = require("lib/app")
local keyboard = require("lib/seamstress/keyboard")
local pattern_persistence = require("lib/pattern_persistence")

local persistence_tmp = "specs/tmp/keyboard_pattern_persistence"

-- Helper: create a minimal ctx
local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    grid_dirty = false,
    voices = {},
    clock_ids = nil,
  }
end

describe("keyboard", function()

  before_each(function()
    os.execute("rm -rf " .. persistence_tmp)
    os.execute("mkdir -p " .. persistence_tmp)
    pattern_persistence._test_set_data_dir(persistence_tmp)
    param_store.pattern_bank_name = "default"
  end)

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

    it("ctrl+p toggles probability modifier", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "p", {ctrl = true}, false, 1)
      assert.is_true(ctx.prob_held)
      keyboard.key(ctx, "p", {ctrl = true}, false, 1)
      assert.is_false(ctx.prob_held)
    end)

  end)

  describe("pattern save (ctrl+number)", function()

    it("ctrl+1 saves current tracks to pattern slot 1", function()
      local ctx = make_ctx()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[2].division = 5

      keyboard.key(ctx, "1", {ctrl = true}, false, 1)

      assert.is_true(pattern.is_populated(ctx.patterns, 1))
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[1])
      assert.are.equal(5, ctx.patterns[1].tracks[2].division)
    end)

    it("ctrl+3 saves to slot 3 without changing active_track", function()
      local ctx = make_ctx()
      ctx.active_track = 2

      keyboard.key(ctx, "3", {ctrl = true}, false, 1)

      assert.is_true(pattern.is_populated(ctx.patterns, 3))
      assert.are.equal(2, ctx.active_track) -- unchanged
    end)

    it("ctrl+9 saves to slot 9", function()
      local ctx = make_ctx()
      ctx.tracks[1].division = 7

      keyboard.key(ctx, "9", {ctrl = true}, false, 1)

      assert.is_true(pattern.is_populated(ctx.patterns, 9))
      assert.are.equal(7, ctx.patterns[9].tracks[1].division)
    end)

  end)

  describe("pattern persistence shortcuts", function()

    it("ctrl+s saves the current bank using the configured name", function()
      local ctx = make_ctx()
      ctx.tracks[1].division = 7
      params:set("pattern_bank_name", "shortcut-bank")

      keyboard.key(ctx, "s", {ctrl = true}, false, 1)

      local fh = io.open(persistence_tmp .. "/shortcut-bank.krp", "r")
      assert.is_not_nil(fh)
      fh:close()
      assert.are.equal("saved bank", ctx.pattern_message.text)
    end)

    it("ctrl+l reloads the configured bank into ctx", function()
      local ctx = make_ctx()
      params:set("pattern_bank_name", "reload-bank")
      ctx.tracks[1].division = 8
      keyboard.key(ctx, "s", {ctrl = true}, false, 1)

      ctx.tracks[1].division = 1
      keyboard.key(ctx, "l", {ctrl = true}, false, 1)

      assert.are.equal(8, ctx.tracks[1].division)
      assert.are.equal("loaded bank", ctx.pattern_message.text)
    end)

    it("ctrl+b lists saved banks", function()
      local ctx = make_ctx()
      params:set("pattern_bank_name", "alpha-bank")
      keyboard.key(ctx, "s", {ctrl = true}, false, 1)
      params:set("pattern_bank_name", "beta-bank")
      keyboard.key(ctx, "s", {ctrl = true}, false, 1)

      keyboard.key(ctx, "b", {ctrl = true}, false, 1)

      assert.are.equal("banks: alpha-bank, beta-bank", ctx.pattern_message.text)
    end)


    it("ctrl+shift+d deletes the configured bank and removes it from the list", function()
      local ctx = make_ctx()
      params:set("pattern_bank_name", "delete-bank")
      keyboard.key(ctx, "s", {ctrl = true}, false, 1)

      keyboard.key(ctx, "d", {ctrl = true, shift = true}, false, 1)

      assert.are.equal("deleted bank", ctx.pattern_message.text)
      assert.are.same({}, app.list_pattern_banks())
    end)

    it("ctrl+shift+d reports delete failures", function()
      local ctx = make_ctx()
      params:set("pattern_bank_name", "missing-bank")

      keyboard.key(ctx, "d", {ctrl = true, shift = true}, false, 1)

      assert.are.equal("delete failed: not_found", ctx.pattern_message.text)
    end)

  end)

  describe("pattern load (shift+number)", function()

    it("shift+1 loads tracks from pattern slot 1", function()
      local ctx = make_ctx()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[2].division = 5
      pattern.save(ctx, 1)

      -- modify current tracks
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.tracks[2].division = 1

      keyboard.key(ctx, "1", {shift = true}, false, 1)

      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[1])
      assert.are.equal(5, ctx.tracks[2].division)
    end)

    it("shift+5 loads from slot 5 without changing active_track", function()
      local ctx = make_ctx()
      ctx.active_track = 3
      ctx.tracks[1].division = 4
      pattern.save(ctx, 5)
      ctx.tracks[1].division = 1

      keyboard.key(ctx, "5", {shift = true}, false, 1)

      assert.are.equal(4, ctx.tracks[1].division)
      assert.are.equal(3, ctx.active_track) -- unchanged
    end)

    it("shift+2 does nothing when slot is empty", function()
      local ctx = make_ctx()
      ctx.tracks[1].division = 99

      keyboard.key(ctx, "2", {shift = true}, false, 1)

      assert.are.equal(99, ctx.tracks[1].division) -- unchanged
    end)

  end)

  describe("modifier priority", function()

    it("plain number still selects track (no modifier)", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "3", {}, false, 1)
      assert.are.equal(3, ctx.active_track)
      assert.is_false(pattern.is_populated(ctx.patterns, 3))
    end)

  end)

  describe("extended page toggle", function()

    it("q on trigger toggles to ratchet", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      keyboard.key(ctx, "q", {}, false, 1)
      assert.are.equal("ratchet", ctx.active_page)
    end)

    it("q on ratchet toggles back to trigger", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      keyboard.key(ctx, "q", {}, false, 1)
      assert.are.equal("trigger", ctx.active_page)
    end)

    it("w on note toggles to alt_note", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      keyboard.key(ctx, "w", {}, false, 1)
      assert.are.equal("alt_note", ctx.active_page)
    end)

    it("e on octave toggles to glide", function()
      local ctx = make_ctx()
      ctx.active_page = "octave"
      keyboard.key(ctx, "e", {}, false, 1)
      assert.are.equal("glide", ctx.active_page)
    end)

    it("pressing different page key clears extended state", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      keyboard.key(ctx, "w", {}, false, 1)
      assert.are.equal("note", ctx.active_page)
    end)

    it("q from note goes to trigger (primary, not extended)", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      keyboard.key(ctx, "q", {}, false, 1)
      assert.are.equal("trigger", ctx.active_page)
    end)

    it("duration has no extended page (stays on duration)", function()
      local ctx = make_ctx()
      ctx.active_page = "duration"
      keyboard.key(ctx, "t", {}, false, 1)
      assert.are.equal("duration", ctx.active_page)
    end)

    it("velocity has no extended page (stays on velocity)", function()
      local ctx = make_ctx()
      ctx.active_page = "velocity"
      keyboard.key(ctx, "y", {}, false, 1)
      assert.are.equal("velocity", ctx.active_page)
    end)

  end)

  describe("ansible key emulation", function()
    -- seamstress delivers F-keys as tables ({name = "F1"}), not strings.
    -- The keyboard handler must accept the table form; string "f1" never
    -- arrives from the real runtime.
    local F1 = {name = "F1"}
    local F2 = {name = "F2"}

    it("F1 toggles time_held on", function()
      local ctx = make_ctx()
      ctx.time_held = false
      keyboard.key(ctx, F1, {}, false, 1)
      assert.is_true(ctx.time_held)
    end)

    it("F1 toggles time_held off", function()
      local ctx = make_ctx()
      ctx.time_held = true
      keyboard.key(ctx, F1, {}, false, 1)
      assert.is_false(ctx.time_held)
    end)

    it("F1 marks grid dirty so the time page redraws", function()
      local ctx = make_ctx()
      ctx.grid_dirty = false
      keyboard.key(ctx, F1, {}, false, 1)
      assert.is_true(ctx.grid_dirty)
    end)

    it("F2 switches to alt_track page", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      keyboard.key(ctx, F2, {}, false, 1)
      assert.are.equal("alt_track", ctx.active_page)
    end)

    it("F2 from any page switches to alt_track", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      keyboard.key(ctx, F2, {}, false, 1)
      assert.are.equal("alt_track", ctx.active_page)
    end)

    it("unknown table-form keycodes are ignored", function()
      local ctx = make_ctx()
      ctx.time_held = false
      ctx.active_page = "trigger"
      keyboard.key(ctx, {name = "F5"}, {}, false, 1)
      assert.is_false(ctx.time_held)
      assert.are.equal("trigger", ctx.active_page)
    end)

  end)

  describe("direction cycling", function()

    it("d cycles direction from forward to reverse", function()
      local ctx = make_ctx()
      assert.are.equal("forward", ctx.tracks[1].direction)
      keyboard.key(ctx, "d", {}, false, 1)
      assert.are.equal("reverse", ctx.tracks[1].direction)
    end)

    it("d cycles through all modes in order", function()
      local ctx = make_ctx()
      local expected = {"reverse", "pendulum", "drunk", "random", "forward"}
      for _, mode in ipairs(expected) do
        keyboard.key(ctx, "d", {}, false, 1)
        assert.are.equal(mode, ctx.tracks[ctx.active_track].direction)
      end
    end)

    it("d affects only the active track", function()
      local ctx = make_ctx()
      ctx.active_track = 2
      keyboard.key(ctx, "d", {}, false, 1)
      assert.are.equal("forward", ctx.tracks[1].direction)
      assert.are.equal("reverse", ctx.tracks[2].direction)
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

    it("ignores nil char (unmapped keycodes like page up/down)", function()
      local ctx = make_ctx()
      keyboard.key(ctx, nil, {}, false, 1)
      assert.are.equal(1, ctx.active_track)
      assert.are.equal("trigger", ctx.active_page)
      assert.is_false(ctx.playing)
      assert.is_false(ctx.grid_dirty)
    end)

    it("ignores table char (named keys not handled by keyboard)", function()
      local ctx = make_ctx()
      keyboard.key(ctx, {name = "up"}, {}, false, 1)
      assert.are.equal(1, ctx.active_track)
      assert.are.equal("trigger", ctx.active_page)
      assert.is_false(ctx.playing)
      assert.is_false(ctx.grid_dirty)
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
