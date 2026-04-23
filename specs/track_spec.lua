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
    it("PARAM_NAMES includes probability and extended params", function()
      local names = {}
      for _, name in ipairs(track.PARAM_NAMES) do
        names[name] = true
      end
      assert.is_true(names["trigger"])
      assert.is_true(names["note"])
      assert.is_true(names["octave"])
      assert.is_true(names["duration"])
      assert.is_true(names["velocity"])
      assert.is_true(names["probability"])
      assert.is_true(names["ratchet"])
      assert.is_true(names["alt_note"])
      assert.is_true(names["glide"])
      assert.is_true(names["probability"])
      assert.equals(9, #track.PARAM_NAMES)
    end)

    it("CORE_PARAMS has 6 core params", function()
      assert.equals(6, #track.CORE_PARAMS)
      assert.are.same(
        {"trigger", "note", "octave", "duration", "velocity", "probability"},
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

  describe("loop boundary edge cases", function()
    it("T002: single-step loop stays on same step", function()
      local p = track.new_param(0)
      p.steps = {10, 20, 30, 40, 50, 60, 70, 80, 0, 0, 0, 0, 0, 0, 0, 0}
      track.set_loop(p, 5, 5)
      -- advance N times, should always return same value and stay on step 5
      for _ = 1, 10 do
        local v = track.advance(p)
        assert.are.equal(50, v)
        assert.are.equal(5, p.pos)
      end
    end)

    it("T003: full-range loop cycles through all 16 steps twice", function()
      local p = track.new_param(0)
      for i = 1, 16 do p.steps[i] = i end
      p.loop_start = 1
      p.loop_end = 16
      p.pos = 1
      local vals = {}
      for _ = 1, 32 do
        table.insert(vals, track.advance(p))
      end
      -- should be 1..16, 1..16
      for i = 1, 32 do
        assert.are.equal((i - 1) % 16 + 1, vals[i])
      end
    end)

    it("T004: loop boundary change mid-playback clamps position", function()
      local p = track.new_param(0)
      for i = 1, 16 do p.steps[i] = i * 10 end
      track.set_loop(p, 1, 8)
      p.pos = 3
      -- change loop to 5-12 while at step 3 (outside new loop)
      track.set_loop(p, 5, 12)
      -- pos should clamp to loop_start (5)
      assert.are.equal(5, p.pos)
      -- advance should return value at step 5
      local v = track.advance(p)
      assert.are.equal(50, v)
    end)

    it("T005: last-two-steps wrapping returns to step 15 not step 1", function()
      local p = track.new_param(0)
      for i = 1, 16 do p.steps[i] = i end
      track.set_loop(p, 15, 16)
      local vals = {}
      for _ = 1, 6 do
        table.insert(vals, track.advance(p))
      end
      -- should cycle 15,16,15,16,15,16
      assert.are.same({15, 16, 15, 16, 15, 16}, vals)
    end)

    it("T006: polymetric independence — 9 params with different loop lengths", function()
      local t = track.new_track(1)
      -- set each param to a different loop length
      local lengths = {2, 3, 4, 5, 6, 7, 8, 16, 9}
      local param_names = track.PARAM_NAMES
      for i, name in ipairs(param_names) do
        local p = t.params[name]
        for s = 1, 16 do p.steps[s] = s end
        track.set_loop(p, 1, lengths[i])
        p.pos = 1
      end
      -- advance all params 100 times and verify each wraps independently
      for step = 1, 100 do
        for i, name in ipairs(param_names) do
          local p = t.params[name]
          local val = track.advance(p)
          -- expected position before advance was: ((step-1) % lengths[i]) + 1
          local expected_val = ((step - 1) % lengths[i]) + 1
          assert.are.equal(expected_val, val,
            string.format("param %s step %d: expected %d got %d", name, step, expected_val, val))
        end
      end
    end)

    it("T007: set_loop rejects loop_start > loop_end", function()
      local p = track.new_param(0)
      -- original boundaries
      assert.are.equal(1, p.loop_start)
      assert.are.equal(track.DEFAULT_LOOP_LEN, p.loop_end)
      -- attempt invalid: start > end
      track.set_loop(p, 8, 3)
      -- should be unchanged
      assert.are.equal(1, p.loop_start)
      assert.are.equal(track.DEFAULT_LOOP_LEN, p.loop_end)
    end)
  end)

  describe("per-param clock division", function()
    it("new_param has clock_div=1 and tick=0 by default", function()
      local p = track.new_param(4)
      assert.are.equal(1, p.clock_div)
      assert.are.equal(0, p.tick)
    end)

    it("should_advance returns true every tick when clock_div=1", function()
      local p = track.new_param(0)
      for _ = 1, 5 do
        assert.is_true(track.should_advance(p))
      end
    end)

    it("should_advance returns true every Nth tick when clock_div=N", function()
      local p = track.new_param(0)
      p.clock_div = 3
      -- tick 1: false, tick 2: false, tick 3: true
      assert.is_false(track.should_advance(p))
      assert.is_false(track.should_advance(p))
      assert.is_true(track.should_advance(p))
      -- again
      assert.is_false(track.should_advance(p))
      assert.is_false(track.should_advance(p))
      assert.is_true(track.should_advance(p))
    end)

    it("should_advance with clock_div=2 alternates false/true", function()
      local p = track.new_param(0)
      p.clock_div = 2
      local results = {}
      for _ = 1, 6 do
        table.insert(results, track.should_advance(p))
      end
      assert.are.same({false, true, false, true, false, true}, results)
    end)

    it("polymetric clock division: two params with different dividers", function()
      local p1 = track.new_param(0)
      p1.clock_div = 2
      for i = 1, 16 do p1.steps[i] = i end
      track.set_loop(p1, 1, 4)

      local p2 = track.new_param(0)
      p2.clock_div = 3
      for i = 1, 16 do p2.steps[i] = i * 10 end
      track.set_loop(p2, 1, 4)

      local v1, v2 = {}, {}
      for _ = 1, 12 do
        if track.should_advance(p1) then
          table.insert(v1, track.advance(p1))
        end
        if track.should_advance(p2) then
          table.insert(v2, track.advance(p2))
        end
      end
      -- p1 (div=2): advances on ticks 2,4,6,8,10,12 => 6 advances through loop 1-4
      assert.are.equal(6, #v1)
      assert.are.same({1, 2, 3, 4, 1, 2}, v1)
      -- p2 (div=3): advances on ticks 3,6,9,12 => 4 advances through loop 1-4
      assert.are.equal(4, #v2)
      assert.are.same({10, 20, 30, 40}, v2)
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
