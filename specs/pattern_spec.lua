-- specs/pattern_spec.lua
-- Tests for lib/pattern.lua (pattern storage: save/load to 16 slots)

package.path = package.path .. ";./?.lua"

-- Mock platform globals needed by track module
rawset(_G, "clock", {
  run = function(f) f() end,
  sync = function() end,
  cancel = function() end,
  get_beats = function() return 0 end,
})

local track_mod = require("lib/track")
local pattern = require("lib/pattern")

local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
  }
end

describe("pattern", function()

  describe("new_slots", function()
    it("returns 16 slots all with populated = false", function()
      local slots = pattern.new_slots()
      assert.are.equal(16, #slots)
      for i = 1, 16 do
        assert.are.equal(false, slots[i].populated)
        assert.is_nil(slots[i].tracks)
      end
    end)
  end)

  describe("is_populated", function()
    it("returns false for empty slot", function()
      local slots = pattern.new_slots()
      for i = 1, 16 do
        assert.is_false(pattern.is_populated(slots, i))
      end
    end)

    it("returns true after save", function()
      local ctx = make_ctx()
      pattern.save(ctx, 1)
      assert.is_true(pattern.is_populated(ctx.patterns, 1))
    end)
  end)

  describe("save", function()
    it("stores track data and sets populated = true", function()
      local ctx = make_ctx()
      -- Modify a step so we can verify it was saved
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[2].division = 3

      pattern.save(ctx, 1)

      assert.is_true(ctx.patterns[1].populated)
      assert.is_not_nil(ctx.patterns[1].tracks)
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[1])
      assert.are.equal(3, ctx.patterns[1].tracks[2].division)
    end)

    it("does nothing with invalid slot 0", function()
      local ctx = make_ctx()
      pattern.save(ctx, 0)
      -- All slots should remain unpopulated
      for i = 1, 16 do
        assert.is_false(pattern.is_populated(ctx.patterns, i))
      end
    end)

    it("does nothing with invalid slot 17", function()
      local ctx = make_ctx()
      pattern.save(ctx, 17)
      for i = 1, 16 do
        assert.is_false(pattern.is_populated(ctx.patterns, i))
      end
    end)
  end)

  describe("load", function()
    it("restores track state: trigger steps, note steps, loop boundaries, division, muted, pos", function()
      local ctx = make_ctx()

      -- Set up distinctive state
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.steps[5] = 1
      ctx.tracks[1].params.note.steps[3] = 7
      ctx.tracks[1].params.note.loop_start = 2
      ctx.tracks[1].params.note.loop_end = 10
      ctx.tracks[1].params.note.pos = 5
      ctx.tracks[1].division = 4
      ctx.tracks[1].muted = true

      ctx.tracks[3].params.velocity.steps[8] = 7
      ctx.tracks[3].division = 2

      -- Save
      pattern.save(ctx, 5)

      -- Now overwrite ctx.tracks with fresh defaults
      ctx.tracks = track_mod.new_tracks()

      -- Load
      pattern.load(ctx, 5)

      -- Verify restored state
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[1])
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[5])
      assert.are.equal(7, ctx.tracks[1].params.note.steps[3])
      assert.are.equal(2, ctx.tracks[1].params.note.loop_start)
      assert.are.equal(10, ctx.tracks[1].params.note.loop_end)
      assert.are.equal(5, ctx.tracks[1].params.note.pos)
      assert.are.equal(4, ctx.tracks[1].division)
      assert.are.equal(true, ctx.tracks[1].muted)

      assert.are.equal(7, ctx.tracks[3].params.velocity.steps[8])
      assert.are.equal(2, ctx.tracks[3].division)
    end)

    it("does nothing when loading from unpopulated slot", function()
      local ctx = make_ctx()
      -- Modify tracks
      ctx.tracks[1].division = 99

      -- Try to load from empty slot
      pattern.load(ctx, 3)

      -- Tracks should be unchanged
      assert.are.equal(99, ctx.tracks[1].division)
    end)

    it("does nothing with invalid slot for load", function()
      local ctx = make_ctx()
      ctx.tracks[1].division = 99

      pattern.load(ctx, 0)
      assert.are.equal(99, ctx.tracks[1].division)

      pattern.load(ctx, 17)
      assert.are.equal(99, ctx.tracks[1].division)
    end)
  end)

  describe("deep copy independence", function()
    it("modifying ctx.tracks after save does not affect saved pattern", function()
      local ctx = make_ctx()

      -- Set a known value
      ctx.tracks[1].params.trigger.steps[1] = 1

      -- Save to slot 1
      pattern.save(ctx, 1)

      -- Modify ctx.tracks AFTER save
      ctx.tracks[1].params.trigger.steps[1] = 0

      -- The saved pattern should still have the original value
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[1])
    end)

    it("modifying loaded tracks does not affect saved pattern", function()
      local ctx = make_ctx()

      -- Set a known value and save
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[2].params.note.steps[4] = 6
      pattern.save(ctx, 1)

      -- Load from slot 1
      pattern.load(ctx, 1)

      -- Modify the loaded tracks
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.tracks[2].params.note.steps[4] = 1

      -- The saved pattern should still have the original values
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[1])
      assert.are.equal(6, ctx.patterns[1].tracks[2].params.note.steps[4])
    end)
  end)

  describe("multiple slots", function()
    it("can save to different slots independently", function()
      local ctx = make_ctx()

      -- Save state A to slot 1
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].division = 2
      pattern.save(ctx, 1)

      -- Modify and save state B to slot 2
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.tracks[1].division = 4
      pattern.save(ctx, 2)

      -- Verify slot 1 still has state A
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[1])
      assert.are.equal(2, ctx.patterns[1].tracks[1].division)

      -- Verify slot 2 has state B
      assert.are.equal(0, ctx.patterns[2].tracks[1].params.trigger.steps[1])
      assert.are.equal(4, ctx.patterns[2].tracks[1].division)

      -- Both should be populated
      assert.is_true(pattern.is_populated(ctx.patterns, 1))
      assert.is_true(pattern.is_populated(ctx.patterns, 2))

      -- Slot 3 should still be empty
      assert.is_false(pattern.is_populated(ctx.patterns, 3))
    end)
  end)

  -- T016-T020: Quality hardening — pattern save/load roundtrip fidelity
  describe("roundtrip fidelity", function()

    -- T016: extended params roundtrip
    it("preserves non-default ratchet, alt_note, glide values through save/load", function()
      local ctx = make_ctx()

      -- Set non-default extended param values across tracks
      for t = 1, 4 do
        for step = 1, 16 do
          ctx.tracks[t].params.ratchet.steps[step] = ((t + step) % 7) + 1
          ctx.tracks[t].params.alt_note.steps[step] = ((t * step) % 7) + 1
          ctx.tracks[t].params.glide.steps[step] = ((t + step * 2) % 7) + 1
        end
        -- Also set non-default loop boundaries on extended params
        ctx.tracks[t].params.ratchet.loop_start = 2
        ctx.tracks[t].params.ratchet.loop_end = 12
        ctx.tracks[t].params.alt_note.loop_start = 3
        ctx.tracks[t].params.alt_note.loop_end = 10
        ctx.tracks[t].params.glide.loop_start = 1
        ctx.tracks[t].params.glide.loop_end = 8
      end

      pattern.save(ctx, 1)
      local saved_tracks = ctx.tracks
      ctx.tracks = track_mod.new_tracks()
      pattern.load(ctx, 1)

      for t = 1, 4 do
        for step = 1, 16 do
          assert.are.equal(((t + step) % 7) + 1, ctx.tracks[t].params.ratchet.steps[step],
            "track " .. t .. " ratchet step " .. step)
          assert.are.equal(((t * step) % 7) + 1, ctx.tracks[t].params.alt_note.steps[step],
            "track " .. t .. " alt_note step " .. step)
          assert.are.equal(((t + step * 2) % 7) + 1, ctx.tracks[t].params.glide.steps[step],
            "track " .. t .. " glide step " .. step)
        end
        assert.are.equal(2, ctx.tracks[t].params.ratchet.loop_start)
        assert.are.equal(12, ctx.tracks[t].params.ratchet.loop_end)
        assert.are.equal(3, ctx.tracks[t].params.alt_note.loop_start)
        assert.are.equal(10, ctx.tracks[t].params.alt_note.loop_end)
        assert.are.equal(1, ctx.tracks[t].params.glide.loop_start)
        assert.are.equal(8, ctx.tracks[t].params.glide.loop_end)
      end
    end)

    -- T017: direction mode roundtrip
    it("preserves different direction modes on each track through save/load", function()
      local ctx = make_ctx()
      local modes = {"reverse", "pendulum", "drunk", "random"}

      for t = 1, 4 do
        ctx.tracks[t].direction = modes[t]
      end

      pattern.save(ctx, 3)
      ctx.tracks = track_mod.new_tracks()

      -- Verify defaults are "forward" before load
      for t = 1, 4 do
        assert.are.equal("forward", ctx.tracks[t].direction)
      end

      pattern.load(ctx, 3)

      for t = 1, 4 do
        assert.are.equal(modes[t], ctx.tracks[t].direction,
          "track " .. t .. " direction should be " .. modes[t])
      end
    end)

    -- T018: all-params-all-tracks comprehensive roundtrip
    it("preserves all 8 params x 4 tracks including loop boundaries and positions", function()
      local ctx = make_ctx()
      local param_names = {"trigger", "note", "octave", "duration", "velocity", "ratchet", "alt_note", "glide"}

      -- Set unique values for every param on every track
      for t = 1, 4 do
        ctx.tracks[t].division = t + 1
        ctx.tracks[t].muted = (t % 2 == 0)
        ctx.tracks[t].direction = ({"forward", "reverse", "pendulum", "drunk"})[t]

        for _, pname in ipairs(param_names) do
          local p = ctx.tracks[t].params[pname]
          for step = 1, 16 do
            p.steps[step] = (t * 10 + step) % 8
          end
          p.loop_start = math.min(t, 16)
          p.loop_end = math.min(t + 8, 16)
          p.pos = math.min(t + 2, p.loop_end)
        end
      end

      pattern.save(ctx, 7)
      ctx.tracks = track_mod.new_tracks()
      pattern.load(ctx, 7)

      for t = 1, 4 do
        assert.are.equal(t + 1, ctx.tracks[t].division, "track " .. t .. " division")
        assert.are.equal(t % 2 == 0, ctx.tracks[t].muted, "track " .. t .. " muted")
        assert.are.equal(({"forward", "reverse", "pendulum", "drunk"})[t],
          ctx.tracks[t].direction, "track " .. t .. " direction")

        for _, pname in ipairs(param_names) do
          local p = ctx.tracks[t].params[pname]
          for step = 1, 16 do
            assert.are.equal((t * 10 + step) % 8, p.steps[step],
              "track " .. t .. " " .. pname .. " step " .. step)
          end
          assert.are.equal(math.min(t, 16), p.loop_start,
            "track " .. t .. " " .. pname .. " loop_start")
          assert.are.equal(math.min(t + 8, 16), p.loop_end,
            "track " .. t .. " " .. pname .. " loop_end")
          assert.are.equal(math.min(t + 2, p.loop_end), p.pos,
            "track " .. t .. " " .. pname .. " pos")
        end
      end
    end)

    -- T019: slot overwrite — save A, modify, save B, load A restores original
    it("loading slot A after saving slot B restores slot A's original state", function()
      local ctx = make_ctx()

      -- State A: specific trigger pattern
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.steps[2] = 1
      ctx.tracks[1].params.note.steps[1] = 7
      ctx.tracks[1].division = 3
      ctx.tracks[1].direction = "reverse"
      pattern.save(ctx, 1)

      -- Modify to state B
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.tracks[1].params.trigger.steps[2] = 0
      ctx.tracks[1].params.note.steps[1] = 1
      ctx.tracks[1].division = 6
      ctx.tracks[1].direction = "pendulum"
      pattern.save(ctx, 2)

      -- Load slot A — modifications should be discarded, original restored
      pattern.load(ctx, 1)

      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[1])
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[2])
      assert.are.equal(7, ctx.tracks[1].params.note.steps[1])
      assert.are.equal(3, ctx.tracks[1].division)
      assert.are.equal("reverse", ctx.tracks[1].direction)
    end)

    -- T020: empty/default slot load — no error, no corruption
    it("loading an empty slot does not error and leaves tracks unchanged", function()
      local ctx = make_ctx()

      -- Set distinctive values
      ctx.tracks[1].division = 42
      ctx.tracks[2].params.note.steps[5] = 7

      -- Load from never-saved slot — should be a no-op
      pattern.load(ctx, 10)

      -- Tracks should be unchanged
      assert.are.equal(42, ctx.tracks[1].division)
      assert.are.equal(7, ctx.tracks[2].params.note.steps[5])
    end)

  end)

end)
