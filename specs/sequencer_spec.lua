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

      local events = ctx.voices[1]:get_events()
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

      local events = ctx.voices[1]:get_events()
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

      local events = ctx.voices[1]:get_events()
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

      local events = ctx.voices[1]:get_events()
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

      local events1 = ctx.voices[1]:get_events()
      local events3 = ctx.voices[3]:get_events()
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

      local events = ctx.voices[1]:get_events()
      assert.are.equal(#events, 1, "unmuted track should fire notes")
    end)

  end)

end)
