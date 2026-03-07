-- specs/track_spec.lua
-- Tests for lib/track.lua

package.path = package.path .. ";./?.lua"

local track = require("lib/track")
local direction = require("lib/direction")

describe("track", function()

  describe("new_param", function()
    it("creates a param with default values", function()
      local p = track.new_param(4)
      assert.are.equal(#p.steps, track.NUM_STEPS)
      assert.are.equal(p.steps[1], 4)
      assert.are.equal(p.loop_start, 1)
      assert.are.equal(p.loop_end, track.NUM_STEPS)
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

  describe("advance (via direction module)", function()
    it("advances position within loop", function()
      local p = track.new_param(0)
      p.steps = {1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0}
      assert.are.equal(p.pos, 1)
      local v1 = direction.advance(p, "forward")
      assert.are.equal(v1, 1)
      assert.are.equal(p.pos, 2)
      local v2 = direction.advance(p, "forward")
      assert.are.equal(v2, 2)
      assert.are.equal(p.pos, 3)
    end)

    it("wraps at loop boundary", function()
      local p = track.new_param(0)
      p.loop_start = 1
      p.loop_end = 4
      p.pos = 4
      p.steps = {10, 20, 30, 40, 50, 60, 70, 80, 0, 0, 0, 0, 0, 0, 0, 0}
      local v = direction.advance(p, "forward")
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
        table.insert(vals, direction.advance(p, "forward"))
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
      assert.are.equal(p.loop_end, 16)

      track.set_loop(p, 0, 5) -- start < 1
      assert.are.equal(p.loop_start, 1)

      track.set_loop(p, 5, 17) -- end > NUM_STEPS
      assert.are.equal(p.loop_end, 16)
    end)
  end)

  describe("peek (direct access)", function()
    it("returns value without advancing", function()
      local p = track.new_param(0)
      p.steps[1] = 5
      assert.are.equal(p.steps[p.pos], 5)
      assert.are.equal(p.pos, 1) -- unchanged
    end)
  end)

end)
