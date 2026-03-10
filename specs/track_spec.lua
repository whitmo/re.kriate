-- specs/track_spec.lua
-- Tests for lib/track.lua

package.path = package.path .. ";./?.lua"

local track = require("lib/track")

describe("track", function()

  describe("new_param", function()
    it("creates a param with default values", function()
      local p = track.new_param(4)
      assert.are.equal(#p.steps, track.NUM_STEPS)
      assert.are.equal(p.steps[1], 4)
      assert.are.equal(p.loop_start, 1)
      assert.are.equal(p.loop_end, track.DEFAULT_LOOP_LEN)
      assert.are.equal(p.pos, 1)
    end)
  end)

  describe("new_track", function()
    it("creates a track with all params", function()
      local t = track.new_track(1)
      for _, name in ipairs(track.PARAM_NAMES) do
        assert.is_not_nil(t.params[name])
        assert.are.equal(#t.params[name].steps, track.NUM_STEPS)
      end
    end)

    it("has musically useful defaults", function()
      local t = track.new_track(1)
      -- track 1 should have triggers on some steps
      local has_triggers = false
      for _, v in ipairs(t.params.trigger.steps) do
        if v == 1 then has_triggers = true; break end
      end
      assert.is_true(has_triggers)
    end)
  end)

  describe("new_tracks", function()
    it("creates NUM_TRACKS tracks", function()
      local tracks = track.new_tracks()
      assert.are.equal(#tracks, track.NUM_TRACKS)
    end)
  end)

  describe("advance", function()
    it("advances position within loop", function()
      local p = track.new_param(0)
      p.steps = {1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0}
      assert.are.equal(p.pos, 1)
      local v1 = track.advance(p)
      assert.are.equal(v1, 1)
      assert.are.equal(p.pos, 2)
      local v2 = track.advance(p)
      assert.are.equal(v2, 2)
      assert.are.equal(p.pos, 3)
    end)

    it("wraps at loop boundary", function()
      local p = track.new_param(0)
      p.loop_start = 1
      p.loop_end = 4
      p.pos = 4
      p.steps = {10, 20, 30, 40, 50, 60, 70, 80, 0, 0, 0, 0, 0, 0, 0, 0}
      local v = track.advance(p)
      assert.are.equal(v, 40) -- value at pos 4
      assert.are.equal(p.pos, 1) -- wrapped back to loop_start
    end)

    it("respects non-default loop boundaries", function()
      local p = track.new_param(0)
      p.loop_start = 5
      p.loop_end = 8
      p.pos = 5
      p.steps = {0, 0, 0, 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0}
      local vals = {}
      for _ = 1, 8 do
        table.insert(vals, track.advance(p))
      end
      -- should cycle through 1,2,3,4,1,2,3,4
      assert.are.same(vals, {1, 2, 3, 4, 1, 2, 3, 4})
    end)
  end)

  describe("toggle_step", function()
    it("toggles trigger steps", function()
      local p = track.new_param(0)
      assert.are.equal(p.steps[1], 0)
      track.toggle_step(p, 1)
      assert.are.equal(p.steps[1], 1)
      track.toggle_step(p, 1)
      assert.are.equal(p.steps[1], 0)
    end)
  end)

  describe("set_step", function()
    it("sets step value", function()
      local p = track.new_param(4)
      track.set_step(p, 3, 7)
      assert.are.equal(p.steps[3], 7)
    end)

    it("ignores out of range steps", function()
      local p = track.new_param(4)
      track.set_step(p, 0, 7)
      track.set_step(p, 17, 7)
      -- should not error or change anything
      assert.are.equal(p.steps[1], 4)
    end)
  end)

  describe("set_loop", function()
    it("sets loop boundaries", function()
      local p = track.new_param(0)
      track.set_loop(p, 3, 8)
      assert.are.equal(p.loop_start, 3)
      assert.are.equal(p.loop_end, 8)
    end)

    it("clamps position into new loop", function()
      local p = track.new_param(0)
      p.pos = 12
      track.set_loop(p, 3, 8)
      assert.are.equal(p.pos, 3) -- clamped to loop_start
    end)

    it("rejects invalid boundaries", function()
      local p = track.new_param(0)
      track.set_loop(p, 8, 3) -- start > end
      assert.are.equal(p.loop_start, 1)  -- unchanged
      assert.are.equal(p.loop_end, track.DEFAULT_LOOP_LEN)

      track.set_loop(p, 0, 5) -- start < 1
      assert.are.equal(p.loop_start, 1)

      track.set_loop(p, 5, 17) -- end > NUM_STEPS
      assert.are.equal(p.loop_end, track.DEFAULT_LOOP_LEN)
    end)
  end)

  describe("peek", function()
    it("returns value without advancing", function()
      local p = track.new_param(0)
      p.steps[1] = 5
      assert.are.equal(track.peek(p), 5)
      assert.are.equal(p.pos, 1) -- unchanged
    end)
  end)

  describe("extended params", function()
    it("PARAM_NAMES includes ratchet, alt_note, glide", function()
      local names = {}
      for _, name in ipairs(track.PARAM_NAMES) do
        names[name] = true
      end
      assert.is_true(names["trigger"])
      assert.is_true(names["note"])
      assert.is_true(names["octave"])
      assert.is_true(names["duration"])
      assert.is_true(names["velocity"])
      assert.is_true(names["ratchet"])
      assert.is_true(names["alt_note"])
      assert.is_true(names["glide"])
      assert.equals(8, #track.PARAM_NAMES)
    end)

    it("CORE_PARAMS has 5 core params", function()
      assert.equals(5, #track.CORE_PARAMS)
      assert.are.same(
        {"trigger", "note", "octave", "duration", "velocity"},
        track.CORE_PARAMS
      )
    end)

    it("EXTENDED_PARAMS has 3 extended params", function()
      assert.equals(3, #track.EXTENDED_PARAMS)
      assert.are.same(
        {"ratchet", "alt_note", "glide"},
        track.EXTENDED_PARAMS
      )
    end)

    it("new_track creates ratchet param with default 1", function()
      local t = track.new_track(1)
      assert.is_not_nil(t.params.ratchet)
      assert.equals(1, t.params.ratchet.steps[1])
      -- all steps should be 1
      for i = 1, track.NUM_STEPS do
        assert.equals(1, t.params.ratchet.steps[i])
      end
    end)

    it("new_track creates alt_note param with default 1", function()
      local t = track.new_track(1)
      assert.is_not_nil(t.params.alt_note)
      assert.equals(1, t.params.alt_note.steps[1])
      for i = 1, track.NUM_STEPS do
        assert.equals(1, t.params.alt_note.steps[i])
      end
    end)

    it("new_track creates glide param with default 1", function()
      local t = track.new_track(1)
      assert.is_not_nil(t.params.glide)
      assert.equals(1, t.params.glide.steps[1])
      for i = 1, track.NUM_STEPS do
        assert.equals(1, t.params.glide.steps[i])
      end
    end)

    it("extended params have standard loop defaults", function()
      local t = track.new_track(1)
      for _, name in ipairs(track.EXTENDED_PARAMS) do
        assert.equals(1, t.params[name].loop_start)
        assert.equals(track.DEFAULT_LOOP_LEN, t.params[name].loop_end)
        assert.equals(1, t.params[name].pos)
      end
    end)
  end)

  describe("direction field", function()
    it("new_track has direction defaulting to forward", function()
      local t = track.new_track(1)
      assert.equals("forward", t.direction)
    end)

    it("new_tracks creates 4 tracks all with forward direction", function()
      local tracks = track.new_tracks()
      for i = 1, 4 do
        assert.equals("forward", tracks[i].direction)
      end
    end)
  end)

end)
