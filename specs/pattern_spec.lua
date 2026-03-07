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

end)
