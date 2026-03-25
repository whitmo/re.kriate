-- specs/sequencer_spec.lua
-- Tests for lib/sequencer.lua

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by recorder voice and sequencer)
local beat_counter = 0
local clock_run_immediate = false  -- when true, clock.run executes fn immediately
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn)
    if clock_run_immediate then
      fn()
    end
    return 1
  end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")
local sequencer = require("lib/sequencer")
local recorder = require("lib/voices/recorder")

-- Build a test scale_notes table (chromatic-ish, 8 octaves * 7 degrees = 56 notes)
-- This mimics what scale.build_scale returns without requiring musicutil
local function build_test_scale()
  local notes = {}
  for i = 1, 56 do
    -- Start at MIDI 24 (C1), each degree = 2 semitones (whole tone scale-like)
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
  }, buffer
end

-- Helper: filter note events (exclude portamento/all_notes_off) from voice events
local function note_events_for(voice)
  local result = {}
  for _, e in ipairs(voice:get_events()) do
    if e.note and e.type ~= "portamento" then
      table.insert(result, e)
    end
  end
  return result
end

describe("sequencer", function()

  before_each(function()
    beat_counter = 0
  end)

  describe("step_track", function()

    it("fires a note when trigger is 1", function()
      local ctx, buffer = make_ctx()
      -- Set up track 1: trigger=1 at pos 1
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
      assert.are.equal(events[1].track, 1)
    end)

    it("does not fire when trigger is 0", function()
      local ctx, buffer = make_ctx()
      -- Set up track 1: trigger=0 at pos 1
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.tracks[1].params.trigger.pos = 1

      sequencer.step_track(ctx, 1)

      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 0)
    end)

    it("advances all params independently", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      -- Record starting positions
      local start_positions = {}
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        start_positions[name] = track.params[name].pos
      end

      sequencer.step_track(ctx, 1)

      -- All params should have advanced
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        assert.are_not.equal(track.params[name].pos, start_positions[name],
          name .. " should have advanced")
      end
    end)

    it("sets grid_dirty flag", function()
      local ctx = make_ctx()
      ctx.grid_dirty = false
      sequencer.step_track(ctx, 1)
      assert.is_true(ctx.grid_dirty)
    end)

    it("sends correct MIDI note via scale lookup", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      -- Force specific values: trigger=1, note_deg=3, octave=4 (center)
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 3
      track.params.note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
      -- scale_mod.to_midi(3, 4, scale_notes) -> scale_notes[(3+0)*7 + 3] = scale_notes[24]
      local expected_note = scale_mod.to_midi(3, 4, ctx.scale_notes)
      assert.are.equal(events[1].note, expected_note)
    end)

    it("maps duration from step value via DURATION_MAP", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.duration.steps[1] = 5  -- 1 beat
      track.params.duration.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(events[1].dur, track_mod.DURATION_MAP[5])
    end)

    it("maps velocity from step value via VELOCITY_MAP", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.velocity.steps[1] = 6  -- 0.90
      track.params.velocity.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(events[1].vel, track_mod.VELOCITY_MAP[6])
    end)

    it("routes notes to the correct track voice", function()
      local ctx, buffer = make_ctx()
      -- Enable trigger on tracks 1 and 3
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[3].params.trigger.steps[1] = 1
      ctx.tracks[3].params.trigger.pos = 1

      sequencer.step_track(ctx, 1)
      sequencer.step_track(ctx, 3)

      local events1 = note_events_for(ctx.voices[1])
      local events3 = note_events_for(ctx.voices[3])
      assert.are.equal(#events1, 1)
      assert.are.equal(events1[1].track, 1)
      assert.are.equal(#events3, 1)
      assert.are.equal(events3[1].track, 3)
    end)

    it("handles missing voice gracefully", function()
      local ctx = make_ctx()
      ctx.voices[2] = nil
      ctx.tracks[2].params.trigger.steps[1] = 1
      ctx.tracks[2].params.trigger.pos = 1
      -- Should not error
      sequencer.step_track(ctx, 2)
    end)

    it("handles nil voices table gracefully", function()
      local ctx = make_ctx()
      ctx.voices = nil
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      -- Should not error
      sequencer.step_track(ctx, 1)
    end)

  end)

  describe("play_note", function()

    it("delegates to ctx.voices[track_num]", function()
      local ctx = make_ctx()
      sequencer.play_note(ctx, 2, 60, 0.8, 0.25)
      local events = ctx.voices[2]:get_events()
      assert.are.equal(#events, 1)
      assert.are.equal(events[1].note, 60)
      assert.are.equal(events[1].vel, 0.8)
      assert.are.equal(events[1].dur, 0.25)
    end)

  end)

  describe("reset", function()

    it("resets all playheads to loop_start", function()
      local ctx = make_ctx()
      -- Advance some params
      for t = 1, track_mod.NUM_TRACKS do
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          ctx.tracks[t].params[name].pos = 8
        end
      end

      sequencer.reset(ctx)

      for t = 1, track_mod.NUM_TRACKS do
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          assert.are.equal(ctx.tracks[t].params[name].pos,
            ctx.tracks[t].params[name].loop_start,
            "track " .. t .. " " .. name .. " should be at loop_start")
        end
      end
    end)

  end)

  describe("start/stop", function()

    it("start sets playing to true", function()
      local ctx = make_ctx()
      ctx.playing = false
      sequencer.start(ctx)
      assert.is_true(ctx.playing)
    end)

    it("start is idempotent", function()
      local ctx = make_ctx()
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}
      sequencer.start(ctx)
      -- Should not overwrite existing clock_ids
      assert.are.same(ctx.clock_ids, {1, 2, 3, 4})
    end)

    it("stop sets playing to false", function()
      local ctx = make_ctx()
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}
      sequencer.stop(ctx)
      assert.is_false(ctx.playing)
      assert.is_nil(ctx.clock_ids)
    end)

    it("stop is idempotent", function()
      local ctx = make_ctx()
      ctx.playing = false
      sequencer.stop(ctx)
      assert.is_false(ctx.playing)
    end)

  end)

  describe("direction integration", function()

    it("uses direction.advance for stepping", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "reverse"
      -- Set up a 4-step loop with known values
      track.params.trigger.steps = {1,1,1,1, 0,0,0,0, 0,0,0,0, 0,0,0,0}
      track.params.trigger.loop_start = 1
      track.params.trigger.loop_end = 4
      track.params.trigger.pos = 4

      track.params.note.steps = {1,2,3,4, 0,0,0,0, 0,0,0,0, 0,0,0,0}
      track.params.note.loop_start = 1
      track.params.note.loop_end = 4
      track.params.note.pos = 4

      -- Step once - reverse should read pos 4, then move to pos 3
      sequencer.step_track(ctx, 1)
      assert.are.equal(track.params.note.pos, 3)

      -- Step again - should read pos 3, then move to pos 2
      sequencer.step_track(ctx, 1)
      assert.are.equal(track.params.note.pos, 2)
    end)

    it("reverse direction produces descending step sequence", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "reverse"

      -- Set up with all triggers on, distinct note values
      for i = 1, 4 do
        track.params.trigger.steps[i] = 1
        track.params.note.steps[i] = i
      end
      track.params.trigger.loop_end = 4
      track.params.note.loop_end = 4
      track.params.trigger.pos = 4
      track.params.note.pos = 4

      local notes_played = {}
      for _ = 1, 4 do
        sequencer.step_track(ctx, 1)
        local events = ctx.voices[1]:get_events()
        table.insert(notes_played, events[#events].note)
      end

      -- In reverse, note degrees should be 4, 3, 2, 1
      -- The MIDI notes should be in descending order
      for i = 2, #notes_played do
        assert.is_true(notes_played[i] <= notes_played[i-1],
          "note " .. i .. " should be <= note " .. (i-1))
      end
    end)

    it("pendulum bounces at boundaries", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "pendulum"

      for i = 1, 4 do
        track.params.trigger.steps[i] = 1
        track.params.note.steps[i] = i
      end
      track.params.trigger.loop_end = 4
      track.params.note.loop_end = 4
      track.params.trigger.pos = 1
      track.params.note.pos = 1

      local note_degrees = {}
      for _ = 1, 7 do
        local prev_note_pos = track.params.note.pos
        sequencer.step_track(ctx, 1)
        table.insert(note_degrees, prev_note_pos)
      end

      -- pendulum: 1, 2, 3, 4, 3, 2, 1
      assert.are.same(note_degrees, {1, 2, 3, 4, 3, 2, 1})
    end)

    it("defaults to forward when direction is nil", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.direction = nil  -- explicitly nil

      track.params.note.pos = 1
      track.params.note.loop_end = 4

      sequencer.step_track(ctx, 1)
      assert.are.equal(track.params.note.pos, 2) -- forward
    end)

  end)

  describe("mute fix", function()

    it("muted track advances playheads but fires no notes", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.muted = true
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.pos = 1

      -- Step the muted track
      sequencer.step_track(ctx, 1)

      -- No notes should have been fired
      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 0)

      -- But playheads should have advanced
      assert.are.equal(track.params.trigger.pos, 2)
      assert.are.equal(track.params.note.pos, 2)
    end)

    it("muted track advances N steps correctly", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.muted = true
      for i = 1, 16 do
        track.params.trigger.steps[i] = 1
      end
      track.params.trigger.pos = 1
      track.params.note.pos = 1

      -- Step 5 times
      for _ = 1, 5 do
        sequencer.step_track(ctx, 1)
      end

      -- No notes fired
      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 0)

      -- Playheads advanced 5 positions
      assert.are.equal(track.params.trigger.pos, 6)
      assert.are.equal(track.params.note.pos, 6)
    end)

    it("unmuted track still fires notes normally", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.muted = false
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
    end)

    it("sets grid_dirty even when muted", function()
      local ctx = make_ctx()
      ctx.tracks[1].muted = true
      ctx.grid_dirty = false
      sequencer.step_track(ctx, 1)
      assert.is_true(ctx.grid_dirty)
    end)

  end)

  describe("alt-note", function()

    it("alt_note value 1 does not alter the note degree", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 3
      track.params.note.pos = 1
      track.params.alt_note.steps[1] = 1  -- no offset
      track.params.alt_note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
      local expected = scale_mod.to_midi(3, 4, ctx.scale_notes)
      assert.are.equal(events[1].note, expected)
    end)

    it("alt_note offsets note degree additively", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 2     -- degree 2
      track.params.note.pos = 1
      track.params.alt_note.steps[1] = 3  -- offset +2 degrees
      track.params.alt_note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
      -- effective = ((2-1) + (3-1)) % 7 + 1 = (1 + 2) % 7 + 1 = 4
      local expected = scale_mod.to_midi(4, 4, ctx.scale_notes)
      assert.are.equal(events[1].note, expected)
    end)

    it("alt_note wraps around scale degrees", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 6     -- degree 6
      track.params.note.pos = 1
      track.params.alt_note.steps[1] = 5  -- offset +4
      track.params.alt_note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
      -- effective = ((6-1) + (5-1)) % 7 + 1 = (5 + 4) % 7 + 1 = 2 + 1 = 3
      local expected = scale_mod.to_midi(3, 4, ctx.scale_notes)
      assert.are.equal(events[1].note, expected)
    end)

  end)

  describe("glide", function()

    it("calls set_portamento when glide > 1", function()
      local ctx, buffer = make_ctx()
      -- Add set_portamento spy to voice
      local portamento_calls = {}
      ctx.voices[1].set_portamento = function(self, time)
        table.insert(portamento_calls, time)
      end
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.glide.steps[1] = 3
      track.params.glide.pos = 1

      sequencer.step_track(ctx, 1)

      assert.are.equal(#portamento_calls, 1)
      assert.are.equal(portamento_calls[1], 3)
    end)

    it("disables portamento when glide is 1", function()
      local ctx, buffer = make_ctx()
      local portamento_calls = {}
      ctx.voices[1].set_portamento = function(self, time)
        table.insert(portamento_calls, time)
      end
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.glide.steps[1] = 1
      track.params.glide.pos = 1

      sequencer.step_track(ctx, 1)

      assert.are.equal(#portamento_calls, 1)
      assert.are.equal(portamento_calls[1], 0)
    end)

    it("does not error when voice has no set_portamento", function()
      local ctx, buffer = make_ctx()
      -- Default recorder voice does not have set_portamento
      -- Remove it explicitly to be sure
      ctx.voices[1].set_portamento = nil
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.glide.steps[1] = 5
      track.params.glide.pos = 1

      -- Should not error
      sequencer.step_track(ctx, 1)
      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 1)
    end)

  end)

  describe("ratchet", function()

    before_each(function()
      clock_run_immediate = true
    end)

    after_each(function()
      clock_run_immediate = false
    end)

    it("ratchet value 1 plays a single note normally", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.ratchet.steps[1] = 1
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 1)
    end)

    it("ratchet value 3 produces 3 notes", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.ratchet.steps[1] = 3
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 3)
    end)

    it("ratchet subdivides duration evenly", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.duration.steps[1] = 5  -- 1 beat
      track.params.duration.pos = 1
      track.params.ratchet.steps[1] = 4
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 4)
      -- Each sub-note should have duration = 1/4 beat
      for _, ev in ipairs(events) do
        assert.are.equal(ev.dur, 1 / 4)
      end
    end)

    it("ratchet preserves note and velocity", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 3
      track.params.note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1
      track.params.velocity.steps[1] = 6
      track.params.velocity.pos = 1
      track.params.ratchet.steps[1] = 2
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local events = note_events_for(ctx.voices[1])
      assert.are.equal(#events, 2)
      local expected_note = scale_mod.to_midi(3, 4, ctx.scale_notes)
      local expected_vel = track_mod.VELOCITY_MAP[6]
      for _, ev in ipairs(events) do
        assert.are.equal(ev.note, expected_note)
        assert.are.equal(ev.vel, expected_vel)
      end
    end)

    it("no ratchet when trigger is 0", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 0
      track.params.trigger.pos = 1
      track.params.ratchet.steps[1] = 4
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 0)
    end)

  end)

  describe("clock stop/start idempotency", function()

    local clock_run_count
    local clock_cancel_count
    local original_clock_run
    local original_clock_cancel

    before_each(function()
      clock_run_count = 0
      clock_cancel_count = 0
      original_clock_run = clock.run
      original_clock_cancel = clock.cancel
      clock.run = function(fn)
        clock_run_count = clock_run_count + 1
        if clock_run_immediate then fn() end
        return clock_run_count
      end
      clock.cancel = function(id)
        clock_cancel_count = clock_cancel_count + 1
      end
    end)

    after_each(function()
      clock.run = original_clock_run
      clock.cancel = original_clock_cancel
    end)

    it("double-start creates no duplicate coroutines (T012)", function()
      local ctx = make_ctx()
      sequencer.start(ctx)
      local first_count = clock_run_count
      assert.are.equal(track_mod.NUM_TRACKS, first_count)

      sequencer.start(ctx)
      -- No additional coroutines created
      assert.are.equal(first_count, clock_run_count)
      assert.is_true(ctx.playing)
    end)

    it("double-stop causes no error and state remains stopped (T013)", function()
      local ctx = make_ctx()
      ctx.playing = false

      sequencer.stop(ctx)
      assert.is_false(ctx.playing)

      sequencer.stop(ctx)
      assert.is_false(ctx.playing)

      -- Nothing to cancel when already stopped
      assert.are.equal(0, clock_cancel_count)
    end)

    it("rapid start/stop 50x toggle produces consistent end state (T014)", function()
      local ctx = make_ctx()

      for i = 1, 50 do
        if i % 2 == 1 then
          sequencer.start(ctx)
        else
          sequencer.stop(ctx)
        end
      end

      -- 50 iterations: odd=start, even=stop -> ends stopped
      assert.is_false(ctx.playing)
      assert.is_nil(ctx.clock_ids)

      -- 25 starts × NUM_TRACKS coroutines each, 25 stops × NUM_TRACKS cancels each
      assert.are.equal(25 * track_mod.NUM_TRACKS, clock_run_count)
      assert.are.equal(25 * track_mod.NUM_TRACKS, clock_cancel_count)
    end)

    it("stop then start resumes from current playhead, not reset (T015)", function()
      local ctx = make_ctx()

      -- Advance all tracks to step 5
      for t = 1, track_mod.NUM_TRACKS do
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          ctx.tracks[t].params[name].pos = 5
        end
      end

      sequencer.start(ctx)
      sequencer.stop(ctx)

      -- Playheads NOT reset
      for t = 1, track_mod.NUM_TRACKS do
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          assert.are.equal(5, ctx.tracks[t].params[name].pos,
            "track " .. t .. " " .. name .. " should remain at step 5")
        end
      end

      -- Restart — still at 5
      sequencer.start(ctx)
      assert.is_true(ctx.playing)
      for t = 1, track_mod.NUM_TRACKS do
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          assert.are.equal(5, ctx.tracks[t].params[name].pos,
            "track " .. t .. " " .. name .. " should still be at step 5 after restart")
        end
      end
    end)

  end)

  describe("track model additions", function()

    it("tracks have direction field defaulting to forward", function()
      local ctx = make_ctx()
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(ctx.tracks[t].direction, "forward")
      end
    end)

    it("tracks have ratchet param", function()
      local ctx = make_ctx()
      assert.is_not_nil(ctx.tracks[1].params.ratchet)
      assert.are.equal(#ctx.tracks[1].params.ratchet.steps, track_mod.NUM_STEPS)
    end)

    it("tracks have alt_note param", function()
      local ctx = make_ctx()
      assert.is_not_nil(ctx.tracks[1].params.alt_note)
      assert.are.equal(#ctx.tracks[1].params.alt_note.steps, track_mod.NUM_STEPS)
    end)

    it("tracks have glide param", function()
      local ctx = make_ctx()
      assert.is_not_nil(ctx.tracks[1].params.glide)
      assert.are.equal(#ctx.tracks[1].params.glide.steps, track_mod.NUM_STEPS)
    end)

    it("ratchet defaults to 1 (no ratchet)", function()
      local ctx = make_ctx()
      assert.are.equal(ctx.tracks[1].params.ratchet.steps[1], 1)
    end)

    it("alt_note defaults to 1 (no offset)", function()
      local ctx = make_ctx()
      assert.are.equal(ctx.tracks[1].params.alt_note.steps[1], 1)
    end)

    it("glide defaults to 1 (no glide)", function()
      local ctx = make_ctx()
      assert.are.equal(ctx.tracks[1].params.glide.steps[1], 1)
    end)

  end)

end)
