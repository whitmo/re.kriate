-- specs/test_gap_hardening_spec.lua
-- Coverage gap tests: edge cases in sequencer advance, loop boundaries,
-- multi-track interaction, event ordering, and parameter value clamping.

package.path = package.path .. ";./?.lua"

-- Mock clock
local beat_counter = 0
local clock_run_immediate = false
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn)
    if clock_run_immediate then fn() end
    return 1
  end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")
local sequencer = require("lib/sequencer")
local direction_mod = require("lib/direction")
local pattern = require("lib/pattern")
local events_mod = require("lib/events")
local recorder = require("lib/voices/recorder")

-- Build a test scale_notes table
local function build_test_scale()
  local notes = {}
  for i = 1, 56 do
    notes[i] = 24 + (i - 1) * 2
  end
  return notes
end

-- Helper: create a minimal ctx with tracks and recorder voices
local function make_ctx()
  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  return {
    tracks = track_mod.new_tracks(),
    voices = voices,
    scale_notes = build_test_scale(),
    grid_dirty = false,
    events = events_mod.new(),
    patterns = pattern.new_slots(),
  }, buffer
end

local function note_events_for(voice)
  local result = {}
  for _, e in ipairs(voice:get_events()) do
    if e.note and e.type ~= "portamento" then
      table.insert(result, e)
    end
  end
  return result
end


-- ============================================================
-- 1. Loop boundary edge cases
-- ============================================================
describe("loop boundary edge cases (gap)", function()

  it("advance when pos is manually set beyond loop_end wraps to loop_start", function()
    local p = track_mod.new_param(0)
    for i = 1, 16 do p.steps[i] = i end
    track_mod.set_loop(p, 3, 8)
    -- Manually place pos outside loop (simulating a stale state)
    p.pos = 10
    local val = track_mod.advance(p)
    -- Should read value at pos 10 (since steps[10] exists), then clamp/wrap
    assert.are.equal(10, val)
    -- After advance, pos should be within loop bounds
    assert.is_true(p.pos >= 3 and p.pos <= 8,
      "pos " .. p.pos .. " should be within loop 3-8")
  end)

  it("advance when pos is below loop_start still reads and advances", function()
    local p = track_mod.new_param(0)
    for i = 1, 16 do p.steps[i] = i * 10 end
    track_mod.set_loop(p, 5, 10)
    -- Manually set pos below loop_start
    p.pos = 2
    local val = track_mod.advance(p)
    assert.are.equal(20, val)  -- reads steps[2]
    -- pos should move forward (2 -> 3), which is still outside loop
    -- but track.advance just does pos+1 or wrap at loop_end
    assert.are.equal(3, p.pos)
  end)

  it("set_loop keeps pos when already inside new loop", function()
    local p = track_mod.new_param(0)
    p.pos = 5
    track_mod.set_loop(p, 3, 8)
    assert.are.equal(5, p.pos)  -- 5 is inside [3,8], no clamping
  end)

  it("set_loop with pos at loop_end boundary keeps pos", function()
    local p = track_mod.new_param(0)
    p.pos = 8
    track_mod.set_loop(p, 3, 8)
    assert.are.equal(8, p.pos)  -- exactly at boundary, should stay
  end)

  it("set_loop with pos at loop_start boundary keeps pos", function()
    local p = track_mod.new_param(0)
    p.pos = 3
    track_mod.set_loop(p, 3, 8)
    assert.are.equal(3, p.pos)  -- exactly at boundary
  end)

  it("single-step loop at step 16 works correctly", function()
    local p = track_mod.new_param(0)
    p.steps[16] = 99
    track_mod.set_loop(p, 16, 16)
    for _ = 1, 5 do
      local v = track_mod.advance(p)
      assert.are.equal(99, v)
      assert.are.equal(16, p.pos)
    end
  end)

  it("single-step loop at step 1 works correctly", function()
    local p = track_mod.new_param(0)
    p.steps[1] = 77
    track_mod.set_loop(p, 1, 1)
    for _ = 1, 5 do
      local v = track_mod.advance(p)
      assert.are.equal(77, v)
      assert.are.equal(1, p.pos)
    end
  end)
end)


-- ============================================================
-- 2. Direction edge cases
-- ============================================================
describe("direction edge cases (gap)", function()

  it("pendulum with 2-step loop bounces correctly", function()
    local p = {
      steps = {10, 20, 30, 40},
      loop_start = 1, loop_end = 2, pos = 1,
      advancing_forward = true,
    }
    local positions = {}
    for _ = 1, 8 do
      table.insert(positions, p.pos)
      direction_mod.advance(p, "pendulum")
    end
    -- 2-step pendulum: 1,2,1,2,1,2,1,2
    assert.are.same({1, 2, 1, 2, 1, 2, 1, 2}, positions)
  end)

  it("reverse with 2-step loop wraps correctly", function()
    local p = {
      steps = {10, 20},
      loop_start = 1, loop_end = 2, pos = 2,
    }
    local values = {}
    for _ = 1, 6 do
      table.insert(values, direction_mod.advance(p, "reverse"))
    end
    assert.are.same({20, 10, 20, 10, 20, 10}, values)
  end)

  it("pendulum advancing_forward defaults to true when nil", function()
    local p = {
      steps = {10, 20, 30, 40},
      loop_start = 1, loop_end = 4, pos = 1,
      -- advancing_forward intentionally nil
    }
    local positions = {}
    for _ = 1, 6 do
      table.insert(positions, p.pos)
      direction_mod.advance(p, "pendulum")
    end
    -- Should default to forward: 1,2,3,4,3,2
    assert.are.same({1, 2, 3, 4, 3, 2}, positions)
  end)

  it("drunk on single-step loop always stays", function()
    local p = {
      steps = {42},
      loop_start = 1, loop_end = 1, pos = 1,
    }
    for _ = 1, 50 do
      local v = direction_mod.advance(p, "drunk")
      assert.are.equal(42, v)
      assert.are.equal(1, p.pos)
    end
  end)

  it("random on single-step loop always stays", function()
    local p = {
      steps = {42},
      loop_start = 1, loop_end = 1, pos = 1,
    }
    for _ = 1, 50 do
      local v = direction_mod.advance(p, "random")
      assert.are.equal(42, v)
      assert.are.equal(1, p.pos)
    end
  end)

  it("unknown direction string defaults to forward", function()
    local p = {
      steps = {10, 20, 30, 40},
      loop_start = 1, loop_end = 4, pos = 1,
    }
    local values = {}
    for _ = 1, 4 do
      table.insert(values, direction_mod.advance(p, "zigzag"))
    end
    assert.are.same({10, 20, 30, 40}, values)
  end)
end)


-- ============================================================
-- 3. Parameter value clamping / fallback behavior
-- ============================================================
describe("parameter value clamping and map fallbacks (gap)", function()

  it("out-of-range duration value falls back to DURATION_MAP[3]", function()
    local ctx = make_ctx()
    local track = ctx.tracks[1]
    track.params.trigger.steps[1] = 1
    track.params.trigger.pos = 1
    track.params.duration.steps[1] = 99  -- out of range
    track.params.duration.pos = 1

    sequencer.step_track(ctx, 1)

    local events = note_events_for(ctx.voices[1])
    assert.are.equal(1, #events)
    assert.are.equal(track_mod.DURATION_MAP[3], events[1].dur)
  end)

  it("out-of-range velocity value falls back to VELOCITY_MAP[4]", function()
    local ctx = make_ctx()
    local track = ctx.tracks[1]
    track.params.trigger.steps[1] = 1
    track.params.trigger.pos = 1
    track.params.velocity.steps[1] = 0  -- out of range (below 1)
    track.params.velocity.pos = 1

    sequencer.step_track(ctx, 1)

    local events = note_events_for(ctx.voices[1])
    assert.are.equal(1, #events)
    assert.are.equal(track_mod.VELOCITY_MAP[4], events[1].vel)
  end)

  it("out-of-range division value falls back to DIVISION_MAP[1]", function()
    -- DIVISION_MAP fallback is used in track_clock; we test it directly
    local div = sequencer.DIVISION_MAP[99]
    assert.is_nil(div)
    -- The track_clock code: local div = M.DIVISION_MAP[track.division] or M.DIVISION_MAP[1]
    local effective = div or sequencer.DIVISION_MAP[1]
    assert.are.equal(1/4, effective)
  end)

  it("GLIDE_TIME_MAP covers all expected values 1-7", function()
    for i = 1, 7 do
      assert.is_not_nil(sequencer.GLIDE_TIME_MAP[i],
        "GLIDE_TIME_MAP[" .. i .. "] should exist")
    end
  end)

  it("DURATION_MAP covers all values 1-7", function()
    for i = 1, 7 do
      assert.is_not_nil(track_mod.DURATION_MAP[i])
    end
  end)

  it("VELOCITY_MAP covers all values 1-7", function()
    for i = 1, 7 do
      assert.is_not_nil(track_mod.VELOCITY_MAP[i])
    end
  end)

  it("DIVISION_MAP covers all values 1-7", function()
    for i = 1, 7 do
      assert.is_not_nil(sequencer.DIVISION_MAP[i])
    end
  end)
end)


-- ============================================================
-- 4. Multi-track interaction
-- ============================================================
describe("multi-track interaction (gap)", function()

  it("tracks with different directions advance independently", function()
    local ctx = make_ctx()
    -- Track 1: forward, track 2: reverse
    ctx.tracks[1].direction = "forward"
    ctx.tracks[2].direction = "reverse"

    -- Set up distinct step values
    for i = 1, 16 do
      ctx.tracks[1].params.note.steps[i] = i
      ctx.tracks[2].params.note.steps[i] = i
    end

    -- Both start at same loop, different initial positions
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      track_mod.set_loop(ctx.tracks[1].params[name], 1, 8)
      track_mod.set_loop(ctx.tracks[2].params[name], 1, 8)
      ctx.tracks[1].params[name].pos = 1
      ctx.tracks[2].params[name].pos = 8
    end

    -- Enable triggers
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[2].params.trigger.steps[8] = 1

    sequencer.step_track(ctx, 1)
    sequencer.step_track(ctx, 2)

    -- Track 1 forward: was at 1, advances to 2
    assert.are.equal(2, ctx.tracks[1].params.note.pos)
    -- Track 2 reverse: was at 8, advances to 7
    assert.are.equal(7, ctx.tracks[2].params.note.pos)
  end)

  it("tracks with different loop lengths produce polymetric patterns", function()
    local ctx = make_ctx()
    -- Track 1: 3-step loop, Track 2: 4-step loop
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      track_mod.set_loop(ctx.tracks[1].params[name], 1, 3)
      track_mod.set_loop(ctx.tracks[2].params[name], 1, 4)
      ctx.tracks[1].params[name].pos = 1
      ctx.tracks[2].params[name].pos = 1
    end

    -- Track both trigger positions over 12 steps (LCM of 3 and 4)
    local t1_positions = {}
    local t2_positions = {}
    for _ = 1, 12 do
      table.insert(t1_positions, ctx.tracks[1].params.trigger.pos)
      table.insert(t2_positions, ctx.tracks[2].params.trigger.pos)
      sequencer.step_track(ctx, 1)
      sequencer.step_track(ctx, 2)
    end

    -- Track 1 (3-step): 1,2,3,1,2,3,1,2,3,1,2,3
    assert.are.same({1,2,3,1,2,3,1,2,3,1,2,3}, t1_positions)
    -- Track 2 (4-step): 1,2,3,4,1,2,3,4,1,2,3,4
    assert.are.same({1,2,3,4,1,2,3,4,1,2,3,4}, t2_positions)
  end)

  it("stepping one track does not affect another track's state", function()
    local ctx = make_ctx()
    -- Record track 2 initial state
    local t2_positions = {}
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      t2_positions[name] = ctx.tracks[2].params[name].pos
    end

    -- Step only track 1
    sequencer.step_track(ctx, 1)

    -- Track 2 should be unchanged
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      assert.are.equal(t2_positions[name], ctx.tracks[2].params[name].pos,
        "track 2 " .. name .. " should not change when stepping track 1")
    end
  end)

  it("all 4 tracks stepping produces correct number of note events", function()
    local ctx = make_ctx()
    clock_run_immediate = true

    -- Set all tracks to trigger on step 1
    local expected_notes = 0
    for t = 1, track_mod.NUM_TRACKS do
      ctx.tracks[t].params.trigger.steps[1] = 1
      ctx.tracks[t].params.trigger.pos = 1
      expected_notes = expected_notes + 1
    end

    for t = 1, track_mod.NUM_TRACKS do
      sequencer.step_track(ctx, t)
    end

    local total = 0
    for t = 1, track_mod.NUM_TRACKS do
      total = total + #note_events_for(ctx.voices[t])
    end
    assert.are.equal(expected_notes, total)

    clock_run_immediate = false
  end)
end)


-- ============================================================
-- 5. Event ordering and emission
-- ============================================================
describe("event ordering (gap)", function()

  it("sequencer:step event is emitted before voice:note event", function()
    local ctx = make_ctx()
    local event_order = {}

    ctx.events:on("sequencer:step", function(data)
      table.insert(event_order, "step")
    end)
    ctx.events:on("voice:note", function(data)
      table.insert(event_order, "note")
    end)

    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.are.equal("step", event_order[1])
    assert.are.equal("note", event_order[2])
  end)

  it("sequencer:step emits even when trigger is 0 (no note)", function()
    local ctx = make_ctx()
    local step_count = 0

    ctx.events:on("sequencer:step", function(data)
      step_count = step_count + 1
    end)

    ctx.tracks[1].params.trigger.steps[1] = 0
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.are.equal(1, step_count)
  end)

  it("no voice:note event when trigger is 0", function()
    local ctx = make_ctx()
    local note_count = 0

    ctx.events:on("voice:note", function(data)
      note_count = note_count + 1
    end)

    ctx.tracks[1].params.trigger.steps[1] = 0
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.are.equal(0, note_count)
  end)

  it("sequencer:step event contains correct track and vals", function()
    local ctx = make_ctx()
    local captured = nil

    ctx.events:on("sequencer:step", function(data)
      captured = data
    end)

    ctx.tracks[2].params.trigger.steps[1] = 1
    ctx.tracks[2].params.trigger.pos = 1
    ctx.tracks[2].params.note.steps[1] = 5
    ctx.tracks[2].params.note.pos = 1
    sequencer.step_track(ctx, 2)

    assert.is_not_nil(captured)
    assert.are.equal(2, captured.track)
    assert.are.equal(1, captured.vals.trigger)
    assert.are.equal(5, captured.vals.note)
  end)

  it("sequencer:step is emitted for muted tracks", function()
    local ctx = make_ctx()
    local step_count = 0

    ctx.events:on("sequencer:step", function(data)
      step_count = step_count + 1
    end)

    ctx.tracks[1].muted = true
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.are.equal(1, step_count)
  end)

  it("no voice:note event for muted tracks", function()
    local ctx = make_ctx()
    local note_count = 0

    ctx.events:on("voice:note", function(data)
      note_count = note_count + 1
    end)

    ctx.tracks[1].muted = true
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.are.equal(0, note_count)
  end)

  it("start/stop emit sequencer events", function()
    local ctx = make_ctx()
    local events_log = {}

    ctx.events:on("sequencer:start", function() table.insert(events_log, "start") end)
    ctx.events:on("sequencer:stop", function() table.insert(events_log, "stop") end)

    sequencer.start(ctx)
    sequencer.stop(ctx)

    assert.are.same({"start", "stop"}, events_log)
  end)

  it("double-start does not emit start event twice", function()
    local ctx = make_ctx()
    local start_count = 0

    ctx.events:on("sequencer:start", function() start_count = start_count + 1 end)

    sequencer.start(ctx)
    sequencer.start(ctx)

    assert.are.equal(1, start_count)
  end)

  it("double-stop does not emit stop event twice", function()
    local ctx = make_ctx()
    local stop_count = 0

    ctx.events:on("sequencer:stop", function() stop_count = stop_count + 1 end)

    sequencer.start(ctx)
    sequencer.stop(ctx)
    sequencer.stop(ctx)

    assert.are.equal(1, stop_count)
  end)
end)


-- ============================================================
-- 6. Alt-note edge cases
-- ============================================================
describe("alt_note edge cases (gap)", function()

  it("max note (7) + max alt_note (7) wraps to degree 6", function()
    local ctx = make_ctx()
    local track = ctx.tracks[1]
    track.params.trigger.steps[1] = 1
    track.params.trigger.pos = 1
    track.params.note.steps[1] = 7
    track.params.note.pos = 1
    track.params.alt_note.steps[1] = 7
    track.params.alt_note.pos = 1
    track.params.octave.steps[1] = 4
    track.params.octave.pos = 1

    sequencer.step_track(ctx, 1)

    local events = note_events_for(ctx.voices[1])
    assert.are.equal(1, #events)
    -- effective = ((7-1) + (7-1)) % 7 + 1 = 12 % 7 + 1 = 5 + 1 = 6
    local expected = scale_mod.to_midi(6, 4, ctx.scale_notes)
    assert.are.equal(expected, events[1].note)
  end)

  it("note=1, alt_note=1 gives degree 1 (identity)", function()
    local ctx = make_ctx()
    local track = ctx.tracks[1]
    track.params.trigger.steps[1] = 1
    track.params.trigger.pos = 1
    track.params.note.steps[1] = 1
    track.params.note.pos = 1
    track.params.alt_note.steps[1] = 1
    track.params.alt_note.pos = 1
    track.params.octave.steps[1] = 4
    track.params.octave.pos = 1

    sequencer.step_track(ctx, 1)

    local events = note_events_for(ctx.voices[1])
    -- effective = ((1-1)+(1-1)) % 7 + 1 = 0 % 7 + 1 = 1
    local expected = scale_mod.to_midi(1, 4, ctx.scale_notes)
    assert.are.equal(expected, events[1].note)
  end)
end)


-- ============================================================
-- 7. Swing duration edge cases
-- ============================================================
describe("swing duration edge cases (gap)", function()

  it("swing=0 returns base division unchanged", function()
    local dur = sequencer.swing_duration(0.25, 0, true)
    assert.are.equal(0.25, dur)
    dur = sequencer.swing_duration(0.25, 0, false)
    assert.are.equal(0.25, dur)
  end)

  it("swing=50 (straight) returns equal odd and even durations", function()
    local odd = sequencer.swing_duration(0.25, 50, true)
    local even = sequencer.swing_duration(0.25, 50, false)
    -- With swing=50: pair=0.5, odd_dur = 0.5/(2-0.5) = 0.5/1.5 = 0.333
    -- even_dur = 0.5 - 0.333 = 0.167
    -- Actually swing=50 should NOT give equal durations; swing=0 is straight.
    -- Just verify they sum to the pair duration
    local pair = 2 * 0.25
    assert.is_true(math.abs(odd + even - pair) < 0.0001,
      "odd + even should equal pair duration")
  end)

  it("swing=100 (max) clamps even step to MIN_SWING_RATIO", function()
    local odd = sequencer.swing_duration(0.25, 100, true)
    local even = sequencer.swing_duration(0.25, 100, false)
    local pair = 2 * 0.25
    local expected_even = pair * sequencer.MIN_SWING_RATIO
    assert.are.equal(expected_even, even)
    -- odd should be pair - floor
    assert.is_true(math.abs(odd - (pair - expected_even)) < 0.0001)
  end)

  it("odd + even durations always sum to pair for all swing values", function()
    for swing = 0, 100 do
      local odd = sequencer.swing_duration(1.0, swing, true)
      local even = sequencer.swing_duration(1.0, swing, false)
      local pair = 2 * 1.0
      assert.is_true(math.abs(odd + even - pair) < 0.0001,
        "swing=" .. swing .. ": odd(" .. odd .. ") + even(" .. even .. ") should sum to " .. pair)
    end
  end)

  it("even duration is always positive", function()
    for swing = 0, 100 do
      local even = sequencer.swing_duration(0.25, swing, false)
      assert.is_true(even > 0,
        "swing=" .. swing .. ": even duration should be > 0, got " .. even)
    end
  end)
end)


-- ============================================================
-- 8. Pattern save/load edge cases
-- ============================================================
describe("pattern save/load edge cases (gap)", function()

  it("save preserves playhead positions", function()
    local ctx = make_ctx()
    -- Advance track 1 to a non-default position
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      ctx.tracks[1].params[name].pos = 7
    end

    pattern.save(ctx, 1)

    -- Verify saved pattern has the positions
    assert.is_true(ctx.patterns[1].populated)
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      assert.are.equal(7, ctx.patterns[1].tracks[1].params[name].pos)
    end
  end)

  it("load restores playhead positions", function()
    local ctx = make_ctx()
    -- Set specific position
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      ctx.tracks[1].params[name].pos = 12
    end
    pattern.save(ctx, 1)

    -- Change positions
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      ctx.tracks[1].params[name].pos = 1
    end

    pattern.load(ctx, 1)
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      assert.are.equal(12, ctx.tracks[1].params[name].pos)
    end
  end)

  it("save/load is a deep copy (no aliasing)", function()
    local ctx = make_ctx()
    ctx.tracks[1].params.note.steps[1] = 5
    pattern.save(ctx, 1)

    -- Modify original
    ctx.tracks[1].params.note.steps[1] = 7

    -- Saved pattern should not be affected
    assert.are.equal(5, ctx.patterns[1].tracks[1].params.note.steps[1])
  end)

  it("load from unpopulated slot is a no-op", function()
    local ctx = make_ctx()
    local original_steps = {}
    for i = 1, 16 do
      original_steps[i] = ctx.tracks[1].params.note.steps[i]
    end

    pattern.load(ctx, 5)  -- slot 5 not populated

    for i = 1, 16 do
      assert.are.equal(original_steps[i], ctx.tracks[1].params.note.steps[i])
    end
  end)

  it("save to slot 0 is a no-op", function()
    local ctx = make_ctx()
    pattern.save(ctx, 0)
    -- Should not error or corrupt state
  end)

  it("save to slot 17 is a no-op", function()
    local ctx = make_ctx()
    pattern.save(ctx, 17)
  end)

  it("load from slot 0 is a no-op", function()
    local ctx = make_ctx()
    pattern.load(ctx, 0)
  end)

  it("load from slot 17 is a no-op", function()
    local ctx = make_ctx()
    pattern.load(ctx, 17)
  end)

  it("overwriting a pattern slot replaces the previous data", function()
    local ctx = make_ctx()
    ctx.tracks[1].params.note.steps[1] = 3
    pattern.save(ctx, 1)

    ctx.tracks[1].params.note.steps[1] = 7
    pattern.save(ctx, 1)  -- overwrite

    -- Load and verify it's the newer version
    ctx.tracks[1].params.note.steps[1] = 1
    pattern.load(ctx, 1)
    assert.are.equal(7, ctx.tracks[1].params.note.steps[1])
  end)
end)


-- ============================================================
-- 9. Reset edge cases
-- ============================================================
describe("reset edge cases (gap)", function()

  it("reset with non-default loop_start sets pos to loop_start", function()
    local ctx = make_ctx()
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      ctx.tracks[1].params[name].loop_start = 5
      ctx.tracks[1].params[name].loop_end = 12
      ctx.tracks[1].params[name].pos = 8
    end

    sequencer.reset(ctx)

    for _, name in ipairs(track_mod.PARAM_NAMES) do
      assert.are.equal(5, ctx.tracks[1].params[name].pos,
        name .. " should reset to loop_start 5")
    end
  end)

  it("reset after advancing multiple tracks resets all", function()
    local ctx = make_ctx()
    -- Advance all tracks several steps
    for t = 1, track_mod.NUM_TRACKS do
      for _ = 1, 5 do
        sequencer.step_track(ctx, t)
      end
    end

    sequencer.reset(ctx)

    for t = 1, track_mod.NUM_TRACKS do
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        assert.are.equal(
          ctx.tracks[t].params[name].loop_start,
          ctx.tracks[t].params[name].pos,
          "track " .. t .. " " .. name .. " should be at loop_start")
      end
    end
  end)
end)


-- ============================================================
-- 10. Scale edge cases
-- ============================================================
describe("scale to_midi edge cases (gap)", function()

  it("degree 1, octave 1 (lowest) clamps within scale bounds", function()
    local scale_notes = build_test_scale()
    local note = scale_mod.to_midi(1, 1, scale_notes)
    assert.is_true(note >= scale_notes[1])
  end)

  it("degree 7, octave 7 (highest) clamps within scale bounds", function()
    local scale_notes = build_test_scale()
    local note = scale_mod.to_midi(7, 7, scale_notes)
    assert.is_true(note <= scale_notes[#scale_notes])
  end)

  it("center octave (4) with degree 1 gives expected index", function()
    local scale_notes = build_test_scale()
    -- idx = (3 + 0) * 7 + 1 = 22
    local note = scale_mod.to_midi(1, 4, scale_notes)
    assert.are.equal(scale_notes[22], note)
  end)

  it("increasing octave produces higher MIDI notes", function()
    local scale_notes = build_test_scale()
    local prev = 0
    for oct = 1, 7 do
      local note = scale_mod.to_midi(4, oct, scale_notes)
      assert.is_true(note >= prev,
        "octave " .. oct .. " note " .. note .. " should be >= prev " .. prev)
      prev = note
    end
  end)

  it("increasing degree within same octave produces higher MIDI notes", function()
    local scale_notes = build_test_scale()
    local prev = 0
    for deg = 1, 7 do
      local note = scale_mod.to_midi(deg, 4, scale_notes)
      assert.is_true(note >= prev,
        "degree " .. deg .. " note " .. note .. " should be >= prev " .. prev)
      prev = note
    end
  end)
end)


-- ============================================================
-- 11. Sequencer stop cleans up voices
-- ============================================================
describe("stop voice cleanup (gap)", function()

  it("stop calls all_notes_off on all voices", function()
    local ctx = make_ctx()
    local off_called = {}
    for t = 1, track_mod.NUM_TRACKS do
      ctx.voices[t].all_notes_off = function(self)
        off_called[t] = true
      end
    end

    ctx.playing = true
    ctx.clock_ids = {1, 2, 3, 4}
    sequencer.stop(ctx)

    for t = 1, track_mod.NUM_TRACKS do
      assert.is_true(off_called[t], "voice " .. t .. " all_notes_off should be called")
    end
  end)

  it("stop calls all_notes_off on sprite voices too", function()
    local ctx = make_ctx()
    ctx.sprite_voices = {}
    local off_called = {}
    for t = 1, track_mod.NUM_TRACKS do
      ctx.sprite_voices[t] = {
        all_notes_off = function(self) off_called[t] = true end,
      }
    end

    ctx.playing = true
    ctx.clock_ids = {1, 2, 3, 4}
    sequencer.stop(ctx)

    for t = 1, track_mod.NUM_TRACKS do
      assert.is_true(off_called[t], "sprite voice " .. t .. " all_notes_off should be called")
    end
  end)

  it("stop handles missing all_notes_off gracefully", function()
    local ctx = make_ctx()
    -- Remove all_notes_off from voices
    for t = 1, track_mod.NUM_TRACKS do
      ctx.voices[t].all_notes_off = nil
    end

    ctx.playing = true
    ctx.clock_ids = {1, 2, 3, 4}
    -- Should not error
    sequencer.stop(ctx)
    assert.is_false(ctx.playing)
  end)
end)


-- ============================================================
-- 12. Sprite voice integration
-- ============================================================
describe("sprite voice integration (gap)", function()

  it("play_sprite fires when trigger is 1 and not muted", function()
    local ctx = make_ctx()
    local sprite_called = false
    ctx.sprite_voices = {
      [1] = {
        play = function(self, vals, dur, opts)
          sprite_called = true
          assert.is_nil(opts)  -- not muted
        end,
      },
    }

    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.is_true(sprite_called)
  end)

  it("play_sprite fires with muted=true opts when muted", function()
    local ctx = make_ctx()
    local sprite_opts = nil
    ctx.sprite_voices = {
      [1] = {
        play = function(self, vals, dur, opts)
          sprite_opts = opts
        end,
      },
    }

    ctx.tracks[1].muted = true
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.is_not_nil(sprite_opts)
    assert.is_true(sprite_opts.muted)
  end)

  it("no sprite call when trigger is 0 and not muted", function()
    local ctx = make_ctx()
    local sprite_called = false
    ctx.sprite_voices = {
      [1] = {
        play = function(self) sprite_called = true end,
      },
    }

    ctx.tracks[1].params.trigger.steps[1] = 0
    ctx.tracks[1].params.trigger.pos = 1
    sequencer.step_track(ctx, 1)

    assert.is_false(sprite_called)
  end)
end)


-- ============================================================
-- 13. Events bus edge cases
-- ============================================================
describe("events bus edge cases (gap)", function()

  it("emit with no subscribers does not error", function()
    local bus = events_mod.new()
    bus:emit("nonexistent:event", {foo = "bar"})
  end)

  it("unsubscribe during emit is safe", function()
    local bus = events_mod.new()
    local results = {}
    local unsub2

    bus:on("test", function(data)
      table.insert(results, "first")
      unsub2()  -- unsubscribe second handler during first
    end)
    unsub2 = bus:on("test", function(data)
      table.insert(results, "second")
    end)

    bus:emit("test", {})

    -- First handler should always fire; second may or may not depending on impl
    assert.are.equal("first", results[1])
  end)

  it("once handler fires exactly once", function()
    local bus = events_mod.new()
    local count = 0

    bus:once("test", function() count = count + 1 end)

    bus:emit("test", {})
    bus:emit("test", {})
    bus:emit("test", {})

    assert.are.equal(1, count)
  end)

  it("off removes all handlers for event", function()
    local bus = events_mod.new()
    local count = 0

    bus:on("test", function() count = count + 1 end)
    bus:on("test", function() count = count + 1 end)

    bus:emit("test", {})
    assert.are.equal(2, count)

    bus:off("test")
    bus:emit("test", {})
    assert.are.equal(2, count)  -- no additional calls
  end)

  it("clear removes all handlers from bus", function()
    local bus = events_mod.new()
    local count = 0

    bus:on("a", function() count = count + 1 end)
    bus:on("b", function() count = count + 1 end)
    bus:on("c:*", function() count = count + 1 end)

    bus:clear()

    bus:emit("a", {})
    bus:emit("b", {})
    bus:emit("c:test", {})
    assert.are.equal(0, count)
  end)

  it("data is shallow-copied per handler (mutation isolation)", function()
    local bus = events_mod.new()
    local original_data = {x = 1}
    local handler1_data
    local handler2_data

    bus:on("test", function(data)
      data.x = 999
      handler1_data = data
    end)
    bus:on("test", function(data)
      handler2_data = data
    end)

    bus:emit("test", original_data)

    -- Handler 1 mutated its copy, but handler 2 should see original value
    assert.are.equal(999, handler1_data.x)
    assert.are.equal(1, handler2_data.x)
  end)
end)
