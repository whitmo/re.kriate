-- specs/sequencer_spec.lua
-- Tests for lib/sequencer.lua

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by recorder voice and sequencer)
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
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

  describe("muted track advancement (US9)", function()

    it("advances all param playheads when muted", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      track.muted = true

      -- Record starting positions
      local start_positions = {}
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        track.params[name].pos = 1
        start_positions[name] = 1
      end

      sequencer.step_track(ctx, 1)

      -- All params should have advanced even though muted
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        assert.are_not.equal(track.params[name].pos, start_positions[name],
          name .. " should have advanced on muted track")
      end
    end)

    it("fires no notes when muted", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      track.muted = true
      track.params.trigger.steps[1] = 1
      track.params.trigger.pos = 1

      sequencer.step_track(ctx, 1)

      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 0, "muted track should fire no notes")
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

  describe("direction integration (US8)", function()

    it("uses track.direction to advance params in reverse", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "reverse"

      -- Set up a short loop 1-4 with known values, start at pos 4
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        track.params[name].loop_start = 1
        track.params[name].loop_end = 4
        track.params[name].pos = 4
      end

      -- Step once - reverse should move pos from 4 to 3
      sequencer.step_track(ctx, 1)

      for _, name in ipairs(track_mod.PARAM_NAMES) do
        assert.are.equal(3, track.params[name].pos,
          name .. " should be at pos 3 after reverse step from 4")
      end
    end)

    it("reverse direction produces descending step values", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "reverse"

      -- Set trigger=1 everywhere, note steps = 1,2,3,4,5,6,7, loop 1-7
      track.params.trigger.loop_start = 1
      track.params.trigger.loop_end = 7
      track.params.trigger.pos = 7
      for i = 1, 7 do track.params.trigger.steps[i] = 1 end

      track.params.note.loop_start = 1
      track.params.note.loop_end = 7
      track.params.note.pos = 7
      for i = 1, 7 do track.params.note.steps[i] = i end

      -- Also set octave/duration/velocity to fixed values so notes fire
      for _, name in ipairs({"octave", "duration", "velocity"}) do
        track.params[name].loop_start = 1
        track.params[name].loop_end = 7
        track.params[name].pos = 1
      end

      -- Collect note values from 7 steps
      local note_vals = {}
      for _ = 1, 7 do
        local notes_before = #note_events_for(ctx.voices[1])
        sequencer.step_track(ctx, 1)
        local notes_after = note_events_for(ctx.voices[1])
        if #notes_after > notes_before then
          table.insert(note_vals, notes_after[#notes_after].note)
        end
      end

      -- Note degree at pos 7=7, 6=6, ..., 1=1 (reverse order)
      -- Verify descending: each note should be >= the next
      assert.is_true(#note_vals > 0, "should have fired some notes")
      for i = 1, #note_vals - 1 do
        assert.is_true(note_vals[i] >= note_vals[i+1],
          "note " .. i .. " (" .. note_vals[i] .. ") should be >= note " ..
          (i+1) .. " (" .. note_vals[i+1] .. ") in reverse")
      end
    end)

    it("pendulum direction bounces at loop boundaries", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "pendulum"

      -- Short loop 1-4, start at pos 1
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        track.params[name].loop_start = 1
        track.params[name].loop_end = 4
        track.params[name].pos = 1
        track.params[name].advancing_forward = true
      end

      -- Collect positions of trigger param over 8 steps
      local positions = {}
      for _ = 1, 8 do
        table.insert(positions, track.params.trigger.pos)
        sequencer.step_track(ctx, 1)
      end

      -- Pendulum: 1,2,3,4,3,2,1,2
      assert.are.same({1, 2, 3, 4, 3, 2, 1, 2}, positions)
    end)

    it("forward direction behaves the same as before", function()
      local ctx = make_ctx()
      local track = ctx.tracks[1]
      track.direction = "forward"

      for _, name in ipairs(track_mod.PARAM_NAMES) do
        track.params[name].loop_start = 1
        track.params[name].loop_end = 4
        track.params[name].pos = 1
      end

      local positions = {}
      for _ = 1, 5 do
        table.insert(positions, track.params.trigger.pos)
        sequencer.step_track(ctx, 1)
      end

      -- Forward: 1,2,3,4,1
      assert.are.same({1, 2, 3, 4, 1}, positions)
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

      -- Filter to just note events (exclude portamento)
      local events = ctx.voices[1]:get_events()
      local note_events = {}
      for _, e in ipairs(events) do
        if e.note and e.type ~= "portamento" then
          table.insert(note_events, e)
        end
      end

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

      local events = ctx.voices[1]:get_events()
      local note_events = {}
      for _, e in ipairs(events) do
        if e.note and e.type ~= "portamento" then
          table.insert(note_events, e)
        end
      end

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

      local events = ctx.voices[1]:get_events()
      local note_events = {}
      for _, e in ipairs(events) do
        if e.note and e.type ~= "portamento" then
          table.insert(note_events, e)
        end
      end

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
      local events = ctx.voices[1]:get_events()
      local note_events = {}
      for _, e in ipairs(events) do
        if e.note and e.type ~= "portamento" then
          table.insert(note_events, e)
        end
      end

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
      local events = ctx.voices[1]:get_events()
      local note_events = {}
      for _, e in ipairs(events) do
        if e.note and e.type ~= "portamento" then
          table.insert(note_events, e)
        end
      end

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
      local events = ctx.voices[1]:get_events()
      local note_events = {}
      for _, e in ipairs(events) do
        if e.note and e.type ~= "portamento" then
          table.insert(note_events, e)
        end
      end

      assert.are.equal(expected_note, note_events[1].note,
        "note=6 + alt_note=5 should wrap to degree 3")
    end)

  end)

end)
