-- specs/meta_pattern_spec.lua
-- Tests for lib/meta_pattern.lua (meta-pattern sequencing engine)

package.path = package.path .. ";./?.lua"

rawset(_G, "clock", {
  run = function(f) return 1 end,
  sync = function() end,
  cancel = function() end,
  get_beats = function() return 0 end,
})

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local meta_pattern = require("lib/meta_pattern")
local events = require("lib/events")

local function make_ctx()
  local ctx = {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
    pattern_slot = 1,
    events = events.new(),
    meta = meta_pattern.new(),
  }
  -- Populate a few pattern slots with distinct data
  ctx.tracks[1].params.trigger.steps[1] = 1
  ctx.tracks[1].division = 1
  pattern.save(ctx, 1)

  ctx.tracks[1].params.trigger.steps[1] = 0
  ctx.tracks[1].params.trigger.steps[2] = 1
  ctx.tracks[1].division = 2
  pattern.save(ctx, 2)

  ctx.tracks[1].params.trigger.steps[1] = 1
  ctx.tracks[1].params.trigger.steps[3] = 1
  ctx.tracks[1].division = 3
  pattern.save(ctx, 3)

  -- Reset to slot 1
  pattern.load(ctx, 1)
  ctx.pattern_slot = 1

  return ctx
end

describe("meta_pattern", function()

  describe("new", function()
    it("creates empty meta-pattern state", function()
      local meta = meta_pattern.new()
      assert.are.equal(0, meta.length)
      assert.are.equal(1, meta.pos)
      assert.are.equal(0, meta.loop_counter)
      assert.is_false(meta.active)
      assert.are.equal(1, meta.selected_step)
      assert.is_nil(meta.cued_slot)
      assert.are.equal(16, #meta.steps)
      for i = 1, 16 do
        assert.are.equal(0, meta.steps[i].slot)
        assert.are.equal(1, meta.steps[i].loops)
      end
    end)
  end)

  describe("set_step / clear_step", function()
    it("sets a step's slot and loops", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 3, 4)
      assert.are.equal(3, meta.steps[1].slot)
      assert.are.equal(4, meta.steps[1].loops)
      assert.are.equal(1, meta.length)
    end)

    it("auto-extends length when setting later steps", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 1, 1)
      meta_pattern.set_step(meta, 5, 2, 2)
      assert.are.equal(5, meta.length)
    end)

    it("clamps loops to 1-7", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 1, 0)
      assert.are.equal(1, meta.steps[1].loops)
      meta_pattern.set_step(meta, 1, 1, 10)
      assert.are.equal(7, meta.steps[1].loops)
    end)

    it("clear_step removes assignment and shrinks length", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 1, 1)
      meta_pattern.set_step(meta, 3, 2, 2)
      assert.are.equal(3, meta.length)

      meta_pattern.clear_step(meta, 3)
      assert.are.equal(0, meta.steps[3].slot)
      assert.are.equal(1, meta.length)
    end)

    it("clear_step on middle step does not shrink length", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 1, 1)
      meta_pattern.set_step(meta, 2, 2, 1)
      meta_pattern.set_step(meta, 3, 3, 1)
      meta_pattern.clear_step(meta, 2)
      assert.are.equal(3, meta.length)
    end)

    it("ignores out-of-range steps", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 0, 1, 1)
      meta_pattern.set_step(meta, 17, 1, 1)
      assert.are.equal(0, meta.length)
    end)
  end)

  describe("is_active", function()
    it("returns false for empty step", function()
      local meta = meta_pattern.new()
      assert.is_false(meta_pattern.is_active(meta, 1))
    end)

    it("returns true for step with pattern", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 5, 1)
      assert.is_true(meta_pattern.is_active(meta, 1))
    end)
  end)

  describe("start", function()
    it("activates and loads first pattern", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 2, 3)
      meta_pattern.set_step(ctx.meta, 2, 3, 1)

      meta_pattern.start(ctx.meta, ctx)

      assert.is_true(ctx.meta.active)
      assert.are.equal(1, ctx.meta.pos)
      assert.are.equal(3, ctx.meta.loop_counter)
      assert.are.equal(2, ctx.pattern_slot)
      -- Pattern 2 has division=2
      assert.are.equal(2, ctx.tracks[1].division)
    end)

    it("skips empty first steps", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 3, 1, 2)

      meta_pattern.start(ctx.meta, ctx)

      assert.is_true(ctx.meta.active)
      assert.are.equal(3, ctx.meta.pos)
    end)

    it("does nothing when no steps defined", function()
      local ctx = make_ctx()
      meta_pattern.start(ctx.meta, ctx)
      assert.is_false(ctx.meta.active)
    end)

    it("resets playheads to loop_start", function()
      local ctx = make_ctx()
      -- Move playheads away from start
      ctx.tracks[1].params.trigger.pos = 5
      ctx.tracks[1].params.note.pos = 8
      pattern.save(ctx, 1)

      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.start(ctx.meta, ctx)

      -- After start, playheads should be at loop_start
      assert.are.equal(ctx.tracks[1].params.trigger.loop_start, ctx.tracks[1].params.trigger.pos)
      assert.are.equal(ctx.tracks[1].params.note.loop_start, ctx.tracks[1].params.note.pos)
    end)
  end)

  describe("stop", function()
    it("deactivates meta-sequencing", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.start(ctx.meta, ctx)
      assert.is_true(ctx.meta.active)

      meta_pattern.stop(ctx.meta)
      assert.is_false(ctx.meta.active)
    end)

    it("clears cued slot", function()
      local meta = meta_pattern.new()
      meta_pattern.cue(meta, 5)
      meta_pattern.stop(meta)
      assert.is_nil(meta.cued_slot)
    end)
  end)

  describe("toggle", function()
    it("toggles active state", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 1)

      meta_pattern.toggle(ctx.meta, ctx)
      assert.is_true(ctx.meta.active)

      meta_pattern.toggle(ctx.meta, ctx)
      assert.is_false(ctx.meta.active)
    end)
  end)

  describe("on_loop_complete", function()
    it("decrements loop counter without switching when loops remain", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 3)
      meta_pattern.set_step(ctx.meta, 2, 2, 1)
      meta_pattern.start(ctx.meta, ctx)

      assert.are.equal(3, ctx.meta.loop_counter)
      local switched = meta_pattern.on_loop_complete(ctx.meta, ctx)
      assert.is_false(switched)
      assert.are.equal(2, ctx.meta.loop_counter)
      assert.are.equal(1, ctx.meta.pos)
    end)

    it("advances to next step when loop counter reaches zero", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.set_step(ctx.meta, 2, 2, 1)
      meta_pattern.start(ctx.meta, ctx)
      assert.are.equal(1, ctx.pattern_slot)

      local switched = meta_pattern.on_loop_complete(ctx.meta, ctx)
      assert.is_true(switched)
      assert.are.equal(2, ctx.meta.pos)
      assert.are.equal(2, ctx.pattern_slot)
      assert.are.equal(2, ctx.tracks[1].division)
    end)

    it("wraps around from last step to first", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.set_step(ctx.meta, 2, 2, 1)
      meta_pattern.start(ctx.meta, ctx)

      meta_pattern.on_loop_complete(ctx.meta, ctx) -- 1 -> 2
      meta_pattern.on_loop_complete(ctx.meta, ctx) -- 2 -> 1 (wrap)

      assert.are.equal(1, ctx.meta.pos)
      assert.are.equal(1, ctx.pattern_slot)
    end)

    it("skips empty steps during advancement", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      -- step 2 is empty
      meta_pattern.set_step(ctx.meta, 3, 3, 1)
      meta_pattern.start(ctx.meta, ctx)

      local switched = meta_pattern.on_loop_complete(ctx.meta, ctx)
      assert.is_true(switched)
      assert.are.equal(3, ctx.meta.pos)
      assert.are.equal(3, ctx.pattern_slot)
    end)

    it("does nothing when not active", function()
      local ctx = make_ctx()
      ctx.meta.active = false
      local switched = meta_pattern.on_loop_complete(ctx.meta, ctx)
      assert.is_false(switched)
    end)

    it("multi-loop step counts down correctly", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 3)
      meta_pattern.set_step(ctx.meta, 2, 2, 2)
      meta_pattern.start(ctx.meta, ctx)

      -- 3 loops on step 1
      assert.is_false(meta_pattern.on_loop_complete(ctx.meta, ctx))  -- 3->2
      assert.is_false(meta_pattern.on_loop_complete(ctx.meta, ctx))  -- 2->1
      assert.is_true(meta_pattern.on_loop_complete(ctx.meta, ctx))   -- 1->0, advance to step 2

      assert.are.equal(2, ctx.meta.pos)
      assert.are.equal(2, ctx.meta.loop_counter)

      -- 2 loops on step 2
      assert.is_false(meta_pattern.on_loop_complete(ctx.meta, ctx))  -- 2->1
      assert.is_true(meta_pattern.on_loop_complete(ctx.meta, ctx))   -- 1->0, wrap to step 1

      assert.are.equal(1, ctx.meta.pos)
    end)

    it("emits pattern:load and meta:step events", function()
      local ctx = make_ctx()
      local emitted = {}
      ctx.events:on("meta:step", function(data)
        table.insert(emitted, { type = "meta:step", data = data })
      end)
      ctx.events:on("pattern:load", function(data)
        table.insert(emitted, { type = "pattern:load", data = data })
      end)

      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.set_step(ctx.meta, 2, 2, 1)
      meta_pattern.start(ctx.meta, ctx)
      emitted = {}  -- clear start events

      meta_pattern.on_loop_complete(ctx.meta, ctx)

      local found_pattern_load = false
      local found_meta_step = false
      for _, e in ipairs(emitted) do
        if e.type == "pattern:load" and e.data.slot == 2 then found_pattern_load = true end
        if e.type == "meta:step" and e.data.pos == 2 then found_meta_step = true end
      end
      assert.is_true(found_pattern_load)
      assert.is_true(found_meta_step)
    end)
  end)

  describe("cueing", function()
    it("cue sets pending slot", function()
      local meta = meta_pattern.new()
      meta_pattern.cue(meta, 5)
      assert.are.equal(5, meta.cued_slot)
    end)

    it("cancel_cue clears pending slot", function()
      local meta = meta_pattern.new()
      meta_pattern.cue(meta, 5)
      meta_pattern.cancel_cue(meta)
      assert.is_nil(meta.cued_slot)
    end)

    it("cued pattern overrides normal advancement", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.set_step(ctx.meta, 2, 2, 1)
      meta_pattern.start(ctx.meta, ctx)

      -- Cue pattern 3 instead of normal advance to step 2
      meta_pattern.cue(ctx.meta, 3)
      local switched = meta_pattern.on_loop_complete(ctx.meta, ctx)

      assert.is_true(switched)
      assert.are.equal(3, ctx.pattern_slot)
      assert.is_nil(ctx.meta.cued_slot) -- consumed
    end)

    it("cued pattern loads even when loops remain", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 1, 5)
      meta_pattern.start(ctx.meta, ctx)

      meta_pattern.cue(ctx.meta, 3)
      local switched = meta_pattern.on_loop_complete(ctx.meta, ctx)

      assert.is_true(switched)
      assert.are.equal(3, ctx.pattern_slot)
    end)

    it("emits meta:cue_applied event", function()
      local ctx = make_ctx()
      local cue_events = {}
      ctx.events:on("meta:cue_applied", function(data)
        table.insert(cue_events, data)
      end)

      meta_pattern.set_step(ctx.meta, 1, 1, 1)
      meta_pattern.start(ctx.meta, ctx)
      meta_pattern.cue(ctx.meta, 2)
      meta_pattern.on_loop_complete(ctx.meta, ctx)

      assert.are.equal(1, #cue_events)
      assert.are.equal(2, cue_events[1].slot)
    end)

    it("rejects invalid cue slots", function()
      local meta = meta_pattern.new()
      meta_pattern.cue(meta, 0)
      assert.is_nil(meta.cued_slot)
      meta_pattern.cue(meta, 17)
      assert.is_nil(meta.cued_slot)
    end)
  end)

  describe("reset", function()
    it("resets position and loop counter", function()
      local meta = meta_pattern.new()
      meta_pattern.set_step(meta, 1, 1, 3)
      meta.pos = 5
      meta.loop_counter = 2
      meta.cued_slot = 3

      meta_pattern.reset(meta)

      assert.are.equal(1, meta.pos)
      assert.are.equal(0, meta.loop_counter)
      assert.is_nil(meta.cued_slot)
    end)
  end)

  describe("single-step sequence", function()
    it("loops the same pattern indefinitely", function()
      local ctx = make_ctx()
      meta_pattern.set_step(ctx.meta, 1, 2, 1)
      meta_pattern.start(ctx.meta, ctx)

      -- Each on_loop_complete should wrap back to step 1
      for _ = 1, 5 do
        meta_pattern.on_loop_complete(ctx.meta, ctx)
        assert.are.equal(1, ctx.meta.pos)
        assert.are.equal(2, ctx.pattern_slot)
      end
    end)
  end)
end)
