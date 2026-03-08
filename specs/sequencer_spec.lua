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

-- Helper: filter note events (exclude portamento) from voice events
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

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(1, #notes)
      assert.are.equal(1, notes[1].track)
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

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(1, #notes)
      -- scale_mod.to_midi(3, 4, scale_notes) -> scale_notes[(3+0)*7 + 3] = scale_notes[24]
      local expected_note = scale_mod.to_midi(3, 4, ctx.scale_notes)
      assert.are.equal(expected_note, notes[1].note)
    end)

    it("maps duration from step value via DURATION_MAP", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.duration.steps[1] = 5  -- 1 beat
      track.params.duration.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(track_mod.DURATION_MAP[5], notes[1].dur)
    end)

    it("maps velocity from step value via VELOCITY_MAP", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.velocity.steps[1] = 6  -- 0.90
      track.params.velocity.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(track_mod.VELOCITY_MAP[6], notes[1].vel)
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

      local notes1 = note_events_for(ctx.voices[1])
      local notes3 = note_events_for(ctx.voices[3])
      assert.are.equal(1, #notes1)
      assert.are.equal(1, notes1[1].track)
      assert.are.equal(1, #notes3)
      assert.are.equal(3, notes3[1].track)
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

  describe("stop silences voices (US1)", function()

    it("calls all_notes_off on each voice when stopping", function()
      local ctx = make_ctx()
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}

      sequencer.stop(ctx)

      for t = 1, track_mod.NUM_TRACKS do
        local events = ctx.voices[t]:get_events()
        local found = false
        for _, e in ipairs(events) do
          if e.type == "all_notes_off" then found = true; break end
        end
        assert.is_true(found, "voice " .. t .. " should receive all_notes_off on stop")
      end
    end)

    it("handles nil voices gracefully on stop", function()
      local ctx = make_ctx()
      ctx.voices = nil
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}
      -- Should not error
      sequencer.stop(ctx)
      assert.is_false(ctx.playing)
    end)

    it("handles missing individual voice gracefully on stop", function()
      local ctx = make_ctx()
      ctx.voices[2] = nil
      ctx.playing = true
      ctx.clock_ids = {1, 2, 3, 4}
      -- Should not error
      sequencer.stop(ctx)
      assert.is_false(ctx.playing)
    end)

  end)

  describe("polymetric sequencing (US3)", function()

    it("independent loop lengths produce different cycle counts", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      -- Trigger loop: 1-4 (4 steps), all triggers active
      track.params.trigger.loop_start = 1
      track.params.trigger.loop_end = 4
      track.params.trigger.pos = 1
      for i = 1, 4 do track.params.trigger.steps[i] = 1 end

      -- Note loop: 1-2 (2 steps), alternating notes
      track.params.note.loop_start = 1
      track.params.note.loop_end = 2
      track.params.note.pos = 1
      track.params.note.steps[1] = 3
      track.params.note.steps[2] = 5

      -- Fix octave and other params
      for _, name in ipairs({"octave", "duration", "velocity", "ratchet", "alt_note", "glide"}) do
        track.params[name].loop_start = 1
        track.params[name].loop_end = 1
        track.params[name].pos = 1
      end

      -- Step 4 times (full trigger cycle)
      local notes = {}
      for _ = 1, 4 do
        sequencer.step_track(ctx, 1)
        local all = note_events_for(ctx.voices[1])
        table.insert(notes, all[#all].note)
      end

      -- Note should cycle twice (2-step loop within 4 trigger steps)
      -- note degrees: 3, 5, 3, 5
      assert.are.equal(notes[1], notes[3], "note should repeat at step 3")
      assert.are.equal(notes[2], notes[4], "note should repeat at step 4")
      assert.are_not.equal(notes[1], notes[2], "alternating notes should differ")
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

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(#notes, 1)
    end)

    it("sets grid_dirty even when muted", function()
      local ctx = make_ctx()
      ctx.tracks[1].muted = true
      ctx.grid_dirty = false
      sequencer.step_track(ctx, 1)
      assert.is_true(ctx.grid_dirty)
    end)

    it("resumes at correct position after unmute", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]

      -- Step while muted 4 times
      track.muted = true
      for _ = 1, 4 do
        sequencer.step_track(ctx, 1)
      end

      -- Record positions after muted advancement
      local muted_positions = {}
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        muted_positions[name] = track.params[name].pos
      end

      -- Unmute and step - should fire from current position
      track.muted = false
      track.params.trigger.steps[muted_positions.trigger] = 1
      sequencer.step_track(ctx, 1)

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(1, #notes, "unmuted track should fire notes")
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

  describe("glide/portamento (US12)", function()

    it("sends portamento CC before note when glide > 1", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.glide.steps[1] = 3
      track.params.glide.pos = 1

      sequencer.step_track(ctx, 1)

      local events = ctx.voices[1]:get_events()
      -- Should have portamento event then note event
      assert.is_true(#events >= 2, "expected portamento + note events, got " .. #events)
      assert.are.equal("portamento", events[1].type)
      assert.is_true(events[1].time > 0, "glide > 1 should produce non-zero portamento time")
      assert.are.equal(events[2].note ~= nil, true, "second event should be a note")
    end)

    it("sends portamento off (time=0) when glide == 1", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.glide.steps[1] = 1
      track.params.glide.pos = 1

      sequencer.step_track(ctx, 1)

      local events = ctx.voices[1]:get_events()
      assert.is_true(#events >= 2, "expected portamento-off + note events")
      assert.are.equal("portamento", events[1].type)
      assert.are.equal(0, events[1].time)
    end)

  end)

  describe("ratchet subdivision (US13)", function()

    it("fires N notes when ratchet > 1", function()
      -- Override clock mock to execute ratchet callbacks synchronously
      local orig_run = clock.run
      local orig_sleep = clock.sleep
      clock.run = function(fn) fn(); return 1 end
      clock.sleep = function() end

      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.ratchet.steps[1] = 3
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local note_events = note_events_for(ctx.voices[1])
      assert.are.equal(3, #note_events, "ratchet=3 should fire 3 notes")

      -- Restore clock mock
      clock.run = orig_run
      clock.sleep = orig_sleep
    end)

    it("fires 1 note when ratchet == 1 (default)", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.ratchet.steps[1] = 1
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local note_events = note_events_for(ctx.voices[1])
      assert.are.equal(1, #note_events, "ratchet=1 should fire 1 note")
    end)

    it("subdivides duration equally among ratchet notes", function()
      local orig_run = clock.run
      local orig_sleep = clock.sleep
      clock.run = function(fn) fn(); return 1 end
      clock.sleep = function() end

      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.duration.steps[1] = 5  -- 1 beat
      track.params.duration.pos = 1
      track.params.ratchet.steps[1] = 4
      track.params.ratchet.pos = 1

      sequencer.step_track(ctx, 1)

      local note_events = note_events_for(ctx.voices[1])
      local expected_dur = track_mod.DURATION_MAP[5] / 4
      for i, e in ipairs(note_events) do
        assert.are.equal(expected_dur, e.dur,
          "ratchet note " .. i .. " duration should be total/ratchet_count")
      end

      clock.run = orig_run
      clock.sleep = orig_sleep
    end)

  end)

  describe("alt_note additive pitch (US14)", function()

    it("combines note + alt_note additively for effective degree", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 3
      track.params.note.pos = 1
      track.params.alt_note.steps[1] = 2
      track.params.alt_note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      -- effective_degree = ((3-1) + (2-1)) % 7 + 1 = 4
      local expected_note = scale_mod.to_midi(4, 4, ctx.scale_notes)
      local note_events = note_events_for(ctx.voices[1])

      assert.is_true(#note_events >= 1, "should have at least one note event")
      assert.are.equal(expected_note, note_events[1].note,
        "note=3 + alt_note=2 should produce degree 4")
    end)

    it("alt_note=1 (default) does not alter the note", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 5
      track.params.note.pos = 1
      track.params.alt_note.steps[1] = 1
      track.params.alt_note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      -- effective_degree = ((5-1) + (1-1)) % 7 + 1 = 4 % 7 + 1 = 5
      local expected_note = scale_mod.to_midi(5, 4, ctx.scale_notes)
      local note_events = note_events_for(ctx.voices[1])

      assert.are.equal(expected_note, note_events[1].note,
        "alt_note=1 should not change the note")
    end)

    it("wraps around scale length when combined degree exceeds 7", function()
      local ctx, buffer = make_ctx()
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 6
      track.params.note.pos = 1
      track.params.alt_note.steps[1] = 5
      track.params.alt_note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      -- effective_degree = ((6-1) + (5-1)) % 7 + 1 = 9 % 7 + 1 = 2 + 1 = 3
      local expected_note = scale_mod.to_midi(3, 4, ctx.scale_notes)
      local note_events = note_events_for(ctx.voices[1])

      assert.are.equal(expected_note, note_events[1].note,
        "note=6 + alt_note=5 should wrap to degree 3")
    end)

  end)

  describe("clock division per track (US6)", function()

    it("DIVISION_MAP covers all 7 division values", function()
      for i = 1, 7 do
        assert.is_not_nil(sequencer.DIVISION_MAP[i],
          "DIVISION_MAP[" .. i .. "] should be defined")
        assert.are.equal("number", type(sequencer.DIVISION_MAP[i]),
          "DIVISION_MAP[" .. i .. "] should be a number")
      end
    end)

    it("DIVISION_MAP values increase (slower divisions)", function()
      for i = 2, 7 do
        assert.is_true(sequencer.DIVISION_MAP[i] > sequencer.DIVISION_MAP[i - 1],
          "DIVISION_MAP[" .. i .. "] should be > DIVISION_MAP[" .. (i - 1) .. "]")
      end
    end)

    it("DIVISION_MAP[1] is 1/16 note (1/4 beat)", function()
      assert.are.equal(1/4, sequencer.DIVISION_MAP[1])
    end)

    it("DIVISION_MAP[5] is 1/4 note (1 beat)", function()
      assert.are.equal(1, sequencer.DIVISION_MAP[5])
    end)

    it("DIVISION_MAP[7] is whole note (4 beats)", function()
      assert.are.equal(4, sequencer.DIVISION_MAP[7])
    end)

    it("track_clock passes correct division to clock.sync", function()
      local ctx = make_ctx()
      ctx.playing = true
      local track = ctx.tracks[1]
      track.division = 3  -- eighth note

      -- Capture clock.sync calls
      local sync_args = {}
      local orig_sync = clock.sync
      local step_count = 0
      clock.sync = function(div)
        table.insert(sync_args, div)
        step_count = step_count + 1
        if step_count >= 2 then ctx.playing = false end
      end

      sequencer.track_clock(ctx, 1)

      clock.sync = orig_sync

      assert.is_true(#sync_args >= 1, "clock.sync should have been called")
      assert.are.equal(sequencer.DIVISION_MAP[3], sync_args[1],
        "track_clock should sync with DIVISION_MAP[track.division]")
    end)

    it("default division=1 uses fastest rate (1/16)", function()
      local ctx = make_ctx()
      ctx.playing = true
      local track = ctx.tracks[1]
      assert.are.equal(1, track.division, "default division should be 1")

      local sync_args = {}
      local orig_sync = clock.sync
      local step_count = 0
      clock.sync = function(div)
        table.insert(sync_args, div)
        step_count = step_count + 1
        if step_count >= 1 then ctx.playing = false end
      end

      sequencer.track_clock(ctx, 1)
      clock.sync = orig_sync

      assert.are.equal(1/4, sync_args[1], "default division should be 1/16 (0.25 beats)")
    end)

    it("different tracks can have different divisions", function()
      local ctx = make_ctx()
      ctx.tracks[1].division = 1  -- 1/16
      ctx.tracks[2].division = 5  -- 1/4

      -- Capture sync calls per track
      local sync_args_1, sync_args_2 = {}, {}
      local orig_sync = clock.sync

      -- Run track 1
      ctx.playing = true
      local count = 0
      clock.sync = function(div)
        table.insert(sync_args_1, div)
        count = count + 1
        if count >= 1 then ctx.playing = false end
      end
      sequencer.track_clock(ctx, 1)

      -- Run track 2
      ctx.playing = true
      count = 0
      clock.sync = function(div)
        table.insert(sync_args_2, div)
        count = count + 1
        if count >= 1 then ctx.playing = false end
      end
      sequencer.track_clock(ctx, 2)

      clock.sync = orig_sync

      assert.are.equal(sequencer.DIVISION_MAP[1], sync_args_1[1])
      assert.are.equal(sequencer.DIVISION_MAP[5], sync_args_2[1])
      -- Division 5 (1/4 note) should be 4x slower than division 1 (1/16)
      assert.are.equal(4, sync_args_2[1] / sync_args_1[1],
        "1/4 note should be 4x the duration of 1/16 note")
    end)

  end)

  describe("scale quantization (US7)", function()

    it("C4 Major degree=1 octave=4 produces MIDI 60 (C4)", function()
      local ctx = make_ctx()
      -- The mock scale: generate_scale(24, "Major", 8)
      -- 4th octave (idx base = 3*7 = 21): 24+21*2=66... no wait, the mock uses diatonic intervals
      -- Actually let's check: build_test_scale() uses 24 + (i-1)*2
      -- So idx 22 = 24 + 21*2 = 66. That's the whole-tone mock, not a real major scale.
      -- The scale_spec.lua mock uses musicutil which produces proper diatonic intervals.
      -- For this test, we should build the scale from the mock musicutil used in scale_spec.
      -- BUT sequencer_spec uses build_test_scale() which is whole-tone.
      --
      -- Let's just verify using the actual scale module with the mock:
      -- The sequencer calls scale_mod.to_midi(degree, octave, ctx.scale_notes)
      -- So if we build a proper scale, we get the right answer.

      -- Use scale_mod.build_scale which requires musicutil mock
      -- But sequencer_spec doesn't mock musicutil. Let's use scale_mod.to_midi directly
      -- with a manually-constructed correct C Major scale.

      -- C Major from C1 (root=60, build_scale(60) => generate_scale(24, Major, 8)):
      -- Oct 0: C1=24, D1=26, E1=28, F1=29, G1=31, A1=33, B1=35
      -- Oct 1: C2=36, D2=38, E2=40, F2=41, G2=43, A2=45, B2=47
      -- Oct 2: C3=48, D3=50, E3=52, F3=53, G3=55, A3=57, B3=59
      -- Oct 3: C4=60, D4=62, E4=64, F4=65, G4=67, A4=69, B4=71  (center octave, octave=4)
      local c_major = {}
      local intervals = {0, 2, 4, 5, 7, 9, 11}
      for oct = 0, 7 do
        for _, iv in ipairs(intervals) do
          table.insert(c_major, 24 + oct * 12 + iv)
        end
      end
      table.insert(c_major, 24 + 8 * 12) -- final root

      ctx.scale_notes = c_major

      -- Set trigger=1, note=1, octave=4
      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 1
      track.params.note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(1, #notes)
      assert.are.equal(60, notes[1].note,
        "degree=1, octave=4, C Major should produce MIDI 60 (C4)")
    end)

    it("C4 Major degree=3 octave=4 produces MIDI 64 (E4)", function()
      local ctx = make_ctx()

      local c_major = {}
      local intervals = {0, 2, 4, 5, 7, 9, 11}
      for oct = 0, 7 do
        for _, iv in ipairs(intervals) do
          table.insert(c_major, 24 + oct * 12 + iv)
        end
      end
      table.insert(c_major, 24 + 8 * 12)

      ctx.scale_notes = c_major

      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 3
      track.params.note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events_for(ctx.voices[1])
      assert.are.equal(1, #notes)
      assert.are.equal(64, notes[1].note,
        "degree=3, octave=4, C Major should produce MIDI 64 (E4)")
    end)

    it("different root produces different MIDI notes for same degree", function()
      local ctx = make_ctx()

      -- C Major scale
      local c_major = {}
      local intervals = {0, 2, 4, 5, 7, 9, 11}
      for oct = 0, 7 do
        for _, iv in ipairs(intervals) do
          table.insert(c_major, 24 + oct * 12 + iv)
        end
      end

      -- D Major scale (root=62, generate from D1=26)
      local d_major = {}
      for oct = 0, 7 do
        for _, iv in ipairs(intervals) do
          table.insert(d_major, 26 + oct * 12 + iv)
        end
      end

      local track = ctx.tracks[1]
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1
      track.params.note.steps[1] = 1
      track.params.note.pos = 1
      track.params.octave.steps[1] = 4
      track.params.octave.pos = 1

      -- Play with C Major
      ctx.scale_notes = c_major
      sequencer.step_track(ctx, 1)
      local c_notes = note_events_for(ctx.voices[1])

      -- Reset and play with D Major
      track.params.trigger.pos = 1
      track.params.note.pos = 1
      track.params.octave.pos = 1
      ctx.voices[1]:clear()
      ctx.scale_notes = d_major
      sequencer.step_track(ctx, 1)
      local d_notes = note_events_for(ctx.voices[1])

      assert.are_not.equal(c_notes[1].note, d_notes[1].note,
        "different root should produce different MIDI notes")
    end)

    it("all output notes are members of the selected scale", function()
      local ctx = make_ctx()

      -- Build C Major scale
      local c_major = {}
      local scale_set = {}
      local intervals = {0, 2, 4, 5, 7, 9, 11}
      for oct = 0, 7 do
        for _, iv in ipairs(intervals) do
          local n = 24 + oct * 12 + iv
          table.insert(c_major, n)
          scale_set[n] = true
        end
      end
      local final = 24 + 8 * 12
      table.insert(c_major, final)
      scale_set[final] = true

      ctx.scale_notes = c_major

      -- Step through all 7 degrees at center octave
      for deg = 1, 7 do
        local track = ctx.tracks[1]
        track.params.trigger.steps[1] = 1
        track.params.trigger.pos = 1
        track.params.note.steps[1] = deg
        track.params.note.pos = 1
        track.params.octave.steps[1] = 4
        track.params.octave.pos = 1
        ctx.voices[1]:clear()

        sequencer.step_track(ctx, 1)

        local notes = note_events_for(ctx.voices[1])
        assert.are.equal(1, #notes, "degree " .. deg .. " should produce a note")
        assert.is_true(scale_set[notes[1].note],
          "degree " .. deg .. " note " .. notes[1].note .. " should be in C Major scale")
      end
    end)

  end)

end)
