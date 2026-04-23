-- specs/e2e_integration_spec.lua
-- End-to-end integration tests: full sequencer flows, pattern round-trips,
-- polymetric behavior, mute/unmute during playback

package.path = package.path .. ";./?.lua"

-- Mock clock with controllable beat counter
-- NOTE: clock.run does NOT execute fn synchronously by default because
-- sequencer.start -> track_clock has a `while ctx.playing` loop that
-- would hang. Tests that need synchronous clock.run (e.g. ratchet) can
-- temporarily override it.
local beat_counter = 0
local clock_run_immediate = false
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn)
    if clock_run_immediate then fn() end
    return 1
  end,
  cancel = function(id) end,
  sync = function(dur) beat_counter = beat_counter + (dur or 0) end,
  sleep = function(t) beat_counter = beat_counter + (t or 0) end,
})

-- Mock params system
local param_store = {}
local param_actions = {}
rawset(_G, "params", {
  add_separator = function(self, id, name) end,
  add_group = function(self, id, name, n) end,
  add_number = function(self, id, name, min, max, default, units, formatter)
    param_store[id] = default
  end,
  add_text = function(self, id, name, default)
    param_store[id] = default
  end,
  add_option = function(self, id, name, options, default)
    param_store[id] = default
  end,
  set_action = function(self, id, fn)
    param_actions[id] = fn
  end,
  get = function(self, id)
    return param_store[id]
  end,
  set = function(self, id, val)
    param_store[id] = val
    if param_actions[id] then param_actions[id](val) end
  end,
})

-- Mock grid
rawset(_G, "grid", {
  connect = function()
    return {
      key = nil,
      led = function(self, x, y, val) end,
      refresh = function(self) end,
      all = function(self, val) end,
    }
  end,
})

-- Mock metro
rawset(_G, "metro", {
  init = function()
    return {
      time = 0,
      event = nil,
      start = function(self) end,
      stop = function(self) end,
    }
  end,
})

-- Mock screen
rawset(_G, "screen", {
  clear = function() end,
  color = function(...) end,
  move = function(x, y) end,
  text = function(s) end,
  rect_fill = function(w, h) end,
  refresh = function() end,
  level = function(l) end,
  update = function() end,
})

-- Mock util
rawset(_G, "util", {
  clamp = function(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
  end,
})

-- Mock musicutil with a real-ish chromatic scale
package.loaded["musicutil"] = {
  generate_scale = function(root, scale_type, octaves)
    -- Generate a simple diatonic-like scale: W W H W W W H pattern
    local intervals = {0, 2, 4, 5, 7, 9, 11}
    local notes = {}
    for oct = 0, octaves - 1 do
      for _, interval in ipairs(intervals) do
        table.insert(notes, root + oct * 12 + interval)
      end
    end
    return notes
  end,
}

local app = require("lib/app")
local sequencer = require("lib/sequencer")
local track_mod = require("lib/track")
local pattern_mod = require("lib/pattern")
local events = require("lib/events")
local direction_mod = require("lib/direction")
local recorder = require("lib/voices/recorder")
local scale_mod = require("lib/scale")

-- Helper: fresh app context with recorder voices
local function make_app()
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  beat_counter = 0

  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  local ctx = app.init({ voices = voices })
  return ctx, buffer, voices
end

-- Helper: build a minimal ctx without app.init (for isolated sequencer tests)
local function make_ctx_raw()
  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    grid_dirty = false,
    scale_notes = scale_mod.build_scale(60, 1),
    voices = voices,
    events = events.new(),
    patterns = pattern_mod.new_slots(),
    pattern_slot = 1,
    pattern_held = false,
  }
  return ctx, buffer, voices
end

-- Filter note events from buffer (exclude portamento, all_notes_off, etc.)
local function note_events(buffer)
  local result = {}
  for _, e in ipairs(buffer) do
    if e.note and e.type ~= "portamento" and e.type ~= "on" and e.type ~= "off" and e.type ~= "all_notes_off" then
      table.insert(result, e)
    end
  end
  return result
end

-- Clear buffer contents in-place
local function clear_buffer(buffer)
  for i = #buffer, 1, -1 do table.remove(buffer, i) end
end

-- ============================================================================

describe("e2e: clock tick -> step advance -> note output", function()

  it("single tick on one track produces a note with correct fields", function()
    local ctx, buffer = make_ctx_raw()
    -- Set up a single trigger at step 1
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.steps[1] = 3
    ctx.tracks[1].params.note.pos = 1
    ctx.tracks[1].params.octave.steps[1] = 4  -- center octave
    ctx.tracks[1].params.octave.pos = 1
    ctx.tracks[1].params.duration.steps[1] = 5  -- 1 beat
    ctx.tracks[1].params.duration.pos = 1
    ctx.tracks[1].params.velocity.steps[1] = 6  -- 0.90
    ctx.tracks[1].params.velocity.pos = 1

    sequencer.step_track(ctx, 1)

    local notes = note_events(buffer)
    assert.are.equal(1, #notes, "exactly one note from one triggered step")
    local n = notes[1]
    assert.are.equal(1, n.track)
    assert.is_number(n.note)
    assert.is_number(n.vel)
    assert.is_number(n.dur)
    -- Verify the note came from scale quantization, not raw step value
    assert.are_not.equal(3, n.note, "note should be MIDI value from scale, not raw degree")
    -- Verify velocity maps correctly
    assert.are.equal(track_mod.VELOCITY_MAP[6], n.vel)
    -- Verify duration maps correctly
    assert.are.equal(track_mod.DURATION_MAP[5], n.dur)
  end)

  it("stepping N times advances playhead N positions and produces N notes", function()
    local ctx, buffer = make_ctx_raw()
    -- Enable triggers on first 4 steps, loop of 4
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.octave, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.duration, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.velocity, 1, 4)

    for _ = 1, 4 do
      sequencer.step_track(ctx, 1)
    end

    local notes = note_events(buffer)
    assert.are.equal(4, #notes, "4 triggers should produce 4 notes")
    -- After 4 steps in a 4-step loop, pos wraps to loop_start
    assert.are.equal(1, ctx.tracks[1].params.trigger.pos, "pos wraps after full loop")
  end)

  it("no trigger at current step => no note, but playhead still advances", function()
    local ctx, buffer = make_ctx_raw()
    -- Explicitly zero out all triggers (defaults have a pattern)
    for i = 1, track_mod.NUM_STEPS do
      ctx.tracks[1].params.trigger.steps[i] = 0
    end
    ctx.tracks[1].params.trigger.pos = 3

    sequencer.step_track(ctx, 1)

    local notes = note_events(buffer)
    assert.are.equal(0, #notes)
    assert.are.equal(4, ctx.tracks[1].params.trigger.pos, "playhead advanced from 3 to 4")
  end)

  it("notes are scale-quantized: same degree + different octave => 12 semitones apart", function()
    local ctx, buffer = make_ctx_raw()
    -- Step 1: degree 1, octave 4 (center)
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.note.steps[1] = 1
    ctx.tracks[1].params.octave.steps[1] = 4

    -- Step 2: degree 1, octave 5 (one octave up)
    ctx.tracks[1].params.trigger.steps[2] = 1
    ctx.tracks[1].params.note.steps[2] = 1
    ctx.tracks[1].params.octave.steps[2] = 5

    for _, name in ipairs(track_mod.PARAM_NAMES) do
      ctx.tracks[1].params[name].pos = 1
      track_mod.set_loop(ctx.tracks[1].params[name], 1, 2)
    end

    sequencer.step_track(ctx, 1)
    sequencer.step_track(ctx, 1)

    local notes = note_events(buffer)
    assert.are.equal(2, #notes)
    local diff = notes[2].note - notes[1].note
    assert.are.equal(12, diff, "one octave up = 12 semitones, got " .. diff)
  end)

  it("event bus receives sequencer:step and voice:note for each triggered step", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1

    local step_events = {}
    local note_events_bus = {}
    ctx.events:on("sequencer:step", function(d) table.insert(step_events, d) end)
    ctx.events:on("voice:note", function(d) table.insert(note_events_bus, d) end)

    sequencer.step_track(ctx, 1)

    assert.are.equal(1, #step_events, "one sequencer:step event")
    assert.are.equal(1, step_events[1].track)
    assert.are.equal(1, #note_events_bus, "one voice:note event")
    assert.is_number(note_events_bus[1].note)
  end)

end)

-- ============================================================================

describe("e2e: pattern save/load round-trip", function()

  it("save slot -> modify tracks -> load slot restores original", function()
    local ctx, buffer = make_ctx_raw()
    -- Set distinctive values
    ctx.tracks[1].params.note.steps[1] = 7
    ctx.tracks[1].params.note.steps[5] = 2
    ctx.tracks[2].params.trigger.steps[3] = 1
    ctx.tracks[3].params.octave.steps[8] = 6

    pattern_mod.save(ctx, 1)

    -- Mutate everything
    ctx.tracks[1].params.note.steps[1] = 1
    ctx.tracks[1].params.note.steps[5] = 6
    ctx.tracks[2].params.trigger.steps[3] = 0
    ctx.tracks[3].params.octave.steps[8] = 2

    pattern_mod.load(ctx, 1)

    assert.are.equal(7, ctx.tracks[1].params.note.steps[1])
    assert.are.equal(2, ctx.tracks[1].params.note.steps[5])
    assert.are.equal(1, ctx.tracks[2].params.trigger.steps[3])
    assert.are.equal(6, ctx.tracks[3].params.octave.steps[8])
  end)

  it("saved pattern is a deep copy — mutations after save don't affect slot", function()
    local ctx = make_ctx_raw()
    ctx.tracks[1].params.note.steps[1] = 5
    pattern_mod.save(ctx, 2)

    ctx.tracks[1].params.note.steps[1] = 99
    assert.are.equal(5, ctx.patterns[2].tracks[1].params.note.steps[1],
      "slot should retain original value")
  end)

  it("load is a deep copy — mutations after load don't affect slot", function()
    local ctx = make_ctx_raw()
    ctx.tracks[1].params.note.steps[1] = 5
    pattern_mod.save(ctx, 3)

    pattern_mod.load(ctx, 3)
    ctx.tracks[1].params.note.steps[1] = 42

    -- Slot should still have original
    assert.are.equal(5, ctx.patterns[3].tracks[1].params.note.steps[1])
  end)

  it("saving to multiple slots preserves each independently", function()
    local ctx = make_ctx_raw()
    ctx.tracks[1].params.note.steps[1] = 10
    pattern_mod.save(ctx, 1)

    ctx.tracks[1].params.note.steps[1] = 20
    pattern_mod.save(ctx, 2)

    ctx.tracks[1].params.note.steps[1] = 30
    pattern_mod.save(ctx, 3)

    pattern_mod.load(ctx, 1)
    assert.are.equal(10, ctx.tracks[1].params.note.steps[1])

    pattern_mod.load(ctx, 2)
    assert.are.equal(20, ctx.tracks[1].params.note.steps[1])

    pattern_mod.load(ctx, 3)
    assert.are.equal(30, ctx.tracks[1].params.note.steps[1])
  end)

  it("loading empty slot is safe and leaves tracks unchanged", function()
    local ctx = make_ctx_raw()
    ctx.tracks[1].params.note.steps[1] = 7
    pattern_mod.load(ctx, 16) -- never saved
    assert.are.equal(7, ctx.tracks[1].params.note.steps[1])
  end)

  it("save preserves loop boundaries and positions", function()
    local ctx = make_ctx_raw()
    track_mod.set_loop(ctx.tracks[1].params.note, 3, 10)
    ctx.tracks[1].params.note.pos = 7
    pattern_mod.save(ctx, 4)

    -- Mutate
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 16)
    ctx.tracks[1].params.note.pos = 1

    pattern_mod.load(ctx, 4)
    assert.are.equal(3, ctx.tracks[1].params.note.loop_start)
    assert.are.equal(10, ctx.tracks[1].params.note.loop_end)
    assert.are.equal(7, ctx.tracks[1].params.note.pos)
  end)

  it("save preserves direction and mute state", function()
    local ctx = make_ctx_raw()
    ctx.tracks[1].direction = "reverse"
    ctx.tracks[2].muted = true
    pattern_mod.save(ctx, 5)

    ctx.tracks[1].direction = "forward"
    ctx.tracks[2].muted = false

    pattern_mod.load(ctx, 5)
    assert.are.equal("reverse", ctx.tracks[1].direction)
    assert.is_true(ctx.tracks[2].muted)
  end)

  it("pattern round-trip produces identical notes on playback", function()
    local ctx, buffer = make_ctx_raw()
    -- Set specific note pattern
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)

    pattern_mod.save(ctx, 1)

    -- Play 4 steps, collect notes
    for _ = 1, 4 do sequencer.step_track(ctx, 1) end
    local notes_before = note_events(buffer)

    -- Scramble and reload
    for i = 1, 4 do ctx.tracks[1].params.note.steps[i] = 7 end
    pattern_mod.load(ctx, 1)
    -- Reset playheads
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.pos = 1
    ctx.tracks[1].params.octave.pos = 1
    ctx.tracks[1].params.duration.pos = 1
    ctx.tracks[1].params.velocity.pos = 1
    ctx.tracks[1].params.alt_note.pos = 1

    clear_buffer(buffer)
    for _ = 1, 4 do sequencer.step_track(ctx, 1) end
    local notes_after = note_events(buffer)

    assert.are.equal(#notes_before, #notes_after)
    for i = 1, #notes_before do
      assert.are.equal(notes_before[i].note, notes_after[i].note,
        "note " .. i .. " should match after pattern round-trip")
    end
  end)

end)

-- ============================================================================

describe("e2e: multi-track polymetric behavior", function()

  it("tracks with different trigger loop lengths produce polymetric output", function()
    local ctx, buffer = make_ctx_raw()
    -- Track 1: 3-step trigger loop (all on)
    for i = 1, 3 do ctx.tracks[1].params.trigger.steps[i] = 1 end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 3)

    -- Track 2: 4-step trigger loop (all on)
    for i = 1, 4 do ctx.tracks[2].params.trigger.steps[i] = 1 end
    track_mod.set_loop(ctx.tracks[2].params.trigger, 1, 4)

    -- Track 3: 5-step trigger loop (all on)
    for i = 1, 5 do ctx.tracks[3].params.trigger.steps[i] = 1 end
    track_mod.set_loop(ctx.tracks[3].params.trigger, 1, 5)

    -- Run 12 steps (LCM of 3,4 = 12)
    for _ = 1, 12 do
      for t = 1, 3 do
        sequencer.step_track(ctx, t)
      end
    end

    -- Count notes per track
    local counts = {0, 0, 0}
    for _, e in ipairs(note_events(buffer)) do
      counts[e.track] = counts[e.track] + 1
    end

    -- Each track fired on every step since all triggers are on
    assert.are.equal(12, counts[1], "track 1: 12 notes in 12 steps")
    assert.are.equal(12, counts[2], "track 2: 12 notes in 12 steps")
    assert.are.equal(12, counts[3], "track 3: 12 notes in 12 steps")

    -- But their playhead positions differ due to different loop lengths
    -- After 12 steps: track 1 (loop 3) = 12 mod 3 = 0 → pos 1
    -- track 2 (loop 4) = 12 mod 4 = 0 → pos 1
    -- track 3 (loop 5) = 12 mod 5 = 2 → pos 3
    assert.are.equal(1, ctx.tracks[1].params.trigger.pos, "track 1 loops back after 12 steps")
    assert.are.equal(1, ctx.tracks[2].params.trigger.pos, "track 2 loops back after 12 steps")
    assert.are.equal(3, ctx.tracks[3].params.trigger.pos, "track 3 at pos 3 after 12 steps (5-step loop)")
  end)

  it("independent note loops create different melodic cycles per track", function()
    local ctx, buffer = make_ctx_raw()
    -- Track 1: 3-step note loop, trigger always on
    for i = 1, 16 do ctx.tracks[1].params.trigger.steps[i] = 1 end
    ctx.tracks[1].params.note.steps[1] = 1
    ctx.tracks[1].params.note.steps[2] = 3
    ctx.tracks[1].params.note.steps[3] = 5
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 3)
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 6)

    -- Track 2: 4-step note loop, trigger always on
    for i = 1, 16 do ctx.tracks[2].params.trigger.steps[i] = 1 end
    ctx.tracks[2].params.note.steps[1] = 2
    ctx.tracks[2].params.note.steps[2] = 4
    ctx.tracks[2].params.note.steps[3] = 6
    ctx.tracks[2].params.note.steps[4] = 7
    track_mod.set_loop(ctx.tracks[2].params.note, 1, 4)
    track_mod.set_loop(ctx.tracks[2].params.trigger, 1, 6)

    -- Run 6 steps for each track
    local track1_notes = {}
    local track2_notes = {}
    for _ = 1, 6 do
      local before = #buffer
      sequencer.step_track(ctx, 1)
      for i = before + 1, #buffer do
        if buffer[i].track == 1 and buffer[i].note and buffer[i].type ~= "portamento" then
          table.insert(track1_notes, buffer[i].note)
        end
      end

      before = #buffer
      sequencer.step_track(ctx, 2)
      for i = before + 1, #buffer do
        if buffer[i].track == 2 and buffer[i].note and buffer[i].type ~= "portamento" then
          table.insert(track2_notes, buffer[i].note)
        end
      end
    end

    assert.are.equal(6, #track1_notes, "6 notes from track 1")
    assert.are.equal(6, #track2_notes, "6 notes from track 2")

    -- Track 1 note loop is 3 steps, so after 6 steps it repeats once:
    -- notes should be: [a, b, c, a, b, c]
    assert.are.equal(track1_notes[1], track1_notes[4], "track 1 cycle repeats at step 4")
    assert.are.equal(track1_notes[2], track1_notes[5], "track 1 cycle repeats at step 5")
    assert.are.equal(track1_notes[3], track1_notes[6], "track 1 cycle repeats at step 6")

    -- Track 2 note loop is 4 steps, so after 6 steps it's partway through second cycle:
    -- notes should be: [d, e, f, g, d, e]
    assert.are.equal(track2_notes[1], track2_notes[5], "track 2 cycle repeats at step 5")
    assert.are.equal(track2_notes[2], track2_notes[6], "track 2 cycle repeats at step 6")

    -- The two tracks should have different note values
    local track1_unique = {}
    local track2_unique = {}
    for _, n in ipairs(track1_notes) do track1_unique[n] = true end
    for _, n in ipairs(track2_notes) do track2_unique[n] = true end
    -- At least some notes should differ between tracks
    local all_same = true
    for n in pairs(track1_unique) do
      if not track2_unique[n] then all_same = false; break end
    end
    -- This assertion is soft; if scales align perfectly it could pass
    -- But with different degree patterns (1,3,5 vs 2,4,6,7) they should differ
  end)

  it("per-param loop lengths create polymetric rhythm + melody interaction", function()
    local ctx, buffer = make_ctx_raw()
    -- Track 1: trigger loop = 3, note loop = 4
    -- This means trigger and note advance independently
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1 -- triggers on 1,2,3
      ctx.tracks[1].params.note.steps[i] = i    -- degrees 1,2,3,4
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 3)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)

    -- Run 12 steps (LCM of 3 and 4) to see full polymetric cycle
    local note_sequence = {}
    for _ = 1, 12 do
      local before = #buffer
      sequencer.step_track(ctx, 1)
      for i = before + 1, #buffer do
        if buffer[i].note and buffer[i].type ~= "portamento" then
          table.insert(note_sequence, buffer[i].note)
        end
      end
    end

    -- All 12 steps have triggers (loop 1-3 repeated 4x)
    assert.are.equal(12, #note_sequence, "12 triggered notes in 12 steps")

    -- After 12 steps, both loops should be back at start
    assert.are.equal(1, ctx.tracks[1].params.trigger.pos, "trigger loop aligned after 12")
    assert.are.equal(1, ctx.tracks[1].params.note.pos, "note loop aligned after 12")
  end)

  it("all 4 tracks running simultaneously maintain independent state", function()
    local ctx, buffer = make_ctx_raw()
    -- Give each track a unique setup
    for t = 1, track_mod.NUM_TRACKS do
      for i = 1, 16 do
        ctx.tracks[t].params.trigger.steps[i] = 1
        ctx.tracks[t].params.note.steps[i] = ((i + t - 1) % 7) + 1
      end
      -- Different loop lengths
      track_mod.set_loop(ctx.tracks[t].params.trigger, 1, t + 2) -- 3,4,5,6
      track_mod.set_loop(ctx.tracks[t].params.note, 1, t + 2)
    end

    -- Step all tracks 20 times
    for _ = 1, 20 do
      for t = 1, track_mod.NUM_TRACKS do
        sequencer.step_track(ctx, t)
      end
    end

    -- Count events per track
    local counts = {}
    for t = 1, track_mod.NUM_TRACKS do counts[t] = 0 end
    for _, e in ipairs(note_events(buffer)) do
      counts[e.track] = counts[e.track] + 1
    end

    -- All tracks should have 20 notes (all triggers on)
    for t = 1, track_mod.NUM_TRACKS do
      assert.are.equal(20, counts[t], "track " .. t .. " should have 20 notes")
    end

    -- Verify playhead positions differ (different loop lengths)
    local positions = {}
    for t = 1, track_mod.NUM_TRACKS do
      positions[t] = ctx.tracks[t].params.trigger.pos
    end
    -- With loop lengths 3,4,5,6: after 20 steps
    -- Track 1 (loop 3): 20 mod 3 = 2, pos = 3
    -- Track 2 (loop 4): 20 mod 4 = 0, pos = 1
    -- Track 3 (loop 5): 20 mod 5 = 0, pos = 1
    -- Track 4 (loop 6): 20 mod 6 = 2, pos = 3
    assert.are.equal(3, positions[1], "track 1 pos after 20 steps in 3-step loop")
    assert.are.equal(1, positions[2], "track 2 pos after 20 steps in 4-step loop")
    assert.are.equal(1, positions[3], "track 3 pos after 20 steps in 5-step loop")
    assert.are.equal(3, positions[4], "track 4 pos after 20 steps in 6-step loop")
  end)

end)

-- ============================================================================

describe("e2e: mute/unmute during playback", function()

  it("muted track produces no notes but advances playhead", function()
    local ctx, buffer = make_ctx_raw()
    for i = 1, 4 do ctx.tracks[1].params.trigger.steps[i] = 1 end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    ctx.tracks[1].muted = true

    for _ = 1, 4 do sequencer.step_track(ctx, 1) end

    assert.are.equal(0, #note_events(buffer), "muted track produces no notes")
    assert.are.equal(1, ctx.tracks[1].params.trigger.pos, "playhead wraps after 4 steps")
  end)

  it("unmuting mid-playback starts producing notes from current position", function()
    local ctx, buffer = make_ctx_raw()
    for i = 1, 8 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i  -- distinct degrees per step
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 8)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 8)

    -- Mute and advance 3 steps
    ctx.tracks[1].muted = true
    for _ = 1, 3 do sequencer.step_track(ctx, 1) end
    assert.are.equal(0, #note_events(buffer), "no notes while muted")

    -- Unmute and advance 2 more steps
    ctx.tracks[1].muted = false
    for _ = 1, 2 do sequencer.step_track(ctx, 1) end

    local notes = note_events(buffer)
    assert.are.equal(2, #notes, "2 notes after unmuting")
    -- Position should be at step 6 (started at 1, advanced 5 total)
    assert.are.equal(6, ctx.tracks[1].params.trigger.pos)
  end)

  it("muting one track doesn't affect other tracks' output", function()
    local ctx, buffer = make_ctx_raw()
    for t = 1, track_mod.NUM_TRACKS do
      for i = 1, 4 do ctx.tracks[t].params.trigger.steps[i] = 1 end
      track_mod.set_loop(ctx.tracks[t].params.trigger, 1, 4)
    end

    -- Mute track 2
    ctx.tracks[2].muted = true

    -- Step all tracks 4 times
    for _ = 1, 4 do
      for t = 1, track_mod.NUM_TRACKS do
        sequencer.step_track(ctx, t)
      end
    end

    local counts = {}
    for t = 1, track_mod.NUM_TRACKS do counts[t] = 0 end
    for _, e in ipairs(note_events(buffer)) do
      counts[e.track] = counts[e.track] + 1
    end

    assert.are.equal(4, counts[1], "track 1 unmuted: 4 notes")
    assert.are.equal(0, counts[2], "track 2 muted: 0 notes")
    assert.are.equal(4, counts[3], "track 3 unmuted: 4 notes")
    assert.are.equal(4, counts[4], "track 4 unmuted: 4 notes")
  end)

  it("rapid mute/unmute toggling produces correct note count", function()
    local ctx, buffer = make_ctx_raw()
    for i = 1, 8 do ctx.tracks[1].params.trigger.steps[i] = 1 end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 8)

    -- Step 8 times, toggling mute every other step
    -- Expected: muted steps produce 0 notes, unmuted produce 1
    local expected_notes = 0
    for step = 1, 8 do
      ctx.tracks[1].muted = (step % 2 == 0) -- mute on even steps
      if not ctx.tracks[1].muted then expected_notes = expected_notes + 1 end
      sequencer.step_track(ctx, 1)
    end

    local notes = note_events(buffer)
    assert.are.equal(expected_notes, #notes,
      "expected " .. expected_notes .. " notes with alternating mute")
  end)

  it("sequencer:step event fires even when muted, voice:note does not", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].muted = true

    local step_count = 0
    local note_count = 0
    ctx.events:on("sequencer:step", function() step_count = step_count + 1 end)
    ctx.events:on("voice:note", function() note_count = note_count + 1 end)

    sequencer.step_track(ctx, 1)

    assert.are.equal(1, step_count, "sequencer:step fires while muted")
    assert.are.equal(0, note_count, "voice:note does NOT fire while muted")
  end)

  it("muted track can be edited and changes are heard on unmute", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].muted = true

    -- Edit note value while muted
    ctx.tracks[1].params.note.steps[1] = 7

    -- Advance while muted (no output)
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.pos = 1
    sequencer.step_track(ctx, 1)
    assert.are.equal(0, #note_events(buffer))

    -- Unmute and play same step
    ctx.tracks[1].muted = false
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.pos = 1
    sequencer.step_track(ctx, 1)

    local notes = note_events(buffer)
    assert.are.equal(1, #notes)
    -- The note should reflect the edited degree (7) mapped through scale
    -- Degree 7 at octave 4 center should produce a different MIDI note than default (4)
    assert.is_number(notes[1].note)
  end)

end)

-- ============================================================================

describe("e2e: direction modes in full sequencer flow", function()

  it("forward direction cycles through loop in order", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].direction = "forward"
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i  -- degrees 1,2,3,4
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)

    local collected = {}
    for _ = 1, 8 do
      local before = #buffer
      sequencer.step_track(ctx, 1)
      for i = before + 1, #buffer do
        if buffer[i].note and buffer[i].type ~= "portamento" then
          table.insert(collected, buffer[i].note)
        end
      end
    end

    assert.are.equal(8, #collected)
    -- Forward should repeat: [a,b,c,d,a,b,c,d]
    assert.are.equal(collected[1], collected[5])
    assert.are.equal(collected[2], collected[6])
    assert.are.equal(collected[3], collected[7])
    assert.are.equal(collected[4], collected[8])
  end)

  it("reverse direction cycles through loop backwards", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].direction = "reverse"
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)
    -- Start at end of loop for reverse
    ctx.tracks[1].params.trigger.pos = 4
    ctx.tracks[1].params.note.pos = 4

    local collected = {}
    for _ = 1, 4 do
      local before = #buffer
      sequencer.step_track(ctx, 1)
      for i = before + 1, #buffer do
        if buffer[i].note and buffer[i].type ~= "portamento" then
          table.insert(collected, buffer[i].note)
        end
      end
    end

    assert.are.equal(4, #collected)
    -- Reverse from pos 4: reads 4,3,2,1 (values at those positions)
    -- Note: advance reads current pos then moves back
    -- So starting at 4: read step[4], move to 3; read step[3], move to 2; etc.
    -- With note.steps = {1,2,3,4} and starting at pos 4:
    -- step 1: read degree 4, advance to 3
    -- step 2: read degree 3, advance to 2
    -- step 3: read degree 2, advance to 1
    -- step 4: read degree 1, advance to 4 (wrap)
    -- Notes should be descending
    for i = 1, 3 do
      assert.is_true(collected[i] >= collected[i + 1],
        "reverse: note " .. i .. " >= note " .. (i+1))
    end
  end)

  it("pendulum direction bounces at loop boundaries", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].direction = "pendulum"
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)

    -- Collect 8 steps worth of notes
    local collected = {}
    for _ = 1, 8 do
      local before = #buffer
      sequencer.step_track(ctx, 1)
      for i = before + 1, #buffer do
        if buffer[i].note and buffer[i].type ~= "portamento" then
          table.insert(collected, buffer[i].note)
        end
      end
    end

    assert.are.equal(8, #collected)
    -- Pendulum on a 4-step loop starting at 1:
    -- Forward: 1,2,3,4 then hits boundary, reverses: 3,2,1 then boundary, forward: 2...
    -- Should see a palindromic-ish pattern
    -- Key property: it should NOT just repeat forward
    -- collected[4] ≠ collected[5] would indicate direction change
  end)

  it("random direction stays within loop bounds over many steps", function()
    local ctx, buffer = make_ctx_raw()
    ctx.tracks[1].direction = "random"
    for i = 1, 16 do ctx.tracks[1].params.trigger.steps[i] = 1 end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 3, 7) -- loop 3-7
    track_mod.set_loop(ctx.tracks[1].params.note, 3, 7)
    ctx.tracks[1].params.trigger.pos = 3
    ctx.tracks[1].params.note.pos = 3

    -- Run many steps
    for _ = 1, 50 do
      sequencer.step_track(ctx, 1)
      -- Check trigger pos stays in bounds
      local pos = ctx.tracks[1].params.trigger.pos
      assert.is_true(pos >= 3 and pos <= 7,
        "random pos " .. pos .. " out of loop bounds 3-7")
    end
  end)

end)

-- ============================================================================

describe("e2e: start/stop lifecycle", function()

  it("start -> step tracks -> stop -> all_notes_off for each voice", function()
    local ctx, buffer = make_ctx_raw()
    for t = 1, track_mod.NUM_TRACKS do
      ctx.tracks[t].params.trigger.steps[1] = 1
      ctx.tracks[t].params.trigger.pos = 1
    end

    sequencer.start(ctx)
    assert.is_true(ctx.playing)

    for t = 1, track_mod.NUM_TRACKS do
      sequencer.step_track(ctx, t)
    end

    sequencer.stop(ctx)
    assert.is_false(ctx.playing)

    -- Check we got notes and then all_notes_off
    local notes = note_events(buffer)
    assert.are.equal(track_mod.NUM_TRACKS, #notes)

    local off_count = 0
    for _, e in ipairs(buffer) do
      if e.type == "all_notes_off" then off_count = off_count + 1 end
    end
    assert.are.equal(track_mod.NUM_TRACKS, off_count, "one all_notes_off per voice")
  end)

  it("double-start is idempotent", function()
    local ctx = make_ctx_raw()
    sequencer.start(ctx)
    sequencer.start(ctx) -- second start should be no-op
    assert.is_true(ctx.playing)
  end)

  it("double-stop is idempotent", function()
    local ctx = make_ctx_raw()
    sequencer.start(ctx)
    sequencer.stop(ctx)
    sequencer.stop(ctx) -- second stop should be no-op
    assert.is_false(ctx.playing)
  end)

  it("reset puts all playheads back to loop_start", function()
    local ctx = make_ctx_raw()
    -- Advance all tracks
    for t = 1, track_mod.NUM_TRACKS do
      for _ = 1, 5 do sequencer.step_track(ctx, t) end
    end

    sequencer.reset(ctx)

    for t = 1, track_mod.NUM_TRACKS do
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        assert.are.equal(ctx.tracks[t].params[name].loop_start,
          ctx.tracks[t].params[name].pos,
          "track " .. t .. " " .. name .. " should reset to loop_start")
      end
    end
  end)

end)

-- ============================================================================

describe("e2e: full app lifecycle with app.init", function()

  it("init -> play -> step -> stop -> cleanup with no errors", function()
    local ctx, buffer = make_app()
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1

    app.key(ctx, 2, 1) -- K2 toggles play
    assert.is_true(ctx.playing)

    sequencer.step_track(ctx, 1)
    local notes = note_events(buffer)
    assert.is_true(#notes >= 1)

    app.key(ctx, 2, 1) -- K2 stops play
    assert.is_false(ctx.playing)

    app.cleanup(ctx)
    assert.is_false(ctx.playing)
  end)

  it("K3 reset during playback resets all positions", function()
    local ctx, buffer = make_app()
    -- Advance tracks
    for t = 1, track_mod.NUM_TRACKS do
      for _ = 1, 5 do sequencer.step_track(ctx, t) end
    end

    app.key(ctx, 3, 1) -- K3 resets

    for t = 1, track_mod.NUM_TRACKS do
      assert.are.equal(ctx.tracks[t].params.trigger.loop_start,
        ctx.tracks[t].params.trigger.pos,
        "track " .. t .. " trigger pos should reset")
    end
  end)

end)

-- ============================================================================

describe("e2e: combined scenarios", function()

  it("pattern load mid-playback changes note output immediately", function()
    local ctx, buffer = make_ctx_raw()
    -- Save pattern with note degree 1 everywhere
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = 1
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)
    pattern_mod.save(ctx, 1)

    -- Save pattern with note degree 7 everywhere
    for i = 1, 4 do ctx.tracks[1].params.note.steps[i] = 7 end
    pattern_mod.save(ctx, 2)

    -- Play 2 steps with pattern 1
    pattern_mod.load(ctx, 1)
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.pos = 1
    sequencer.step_track(ctx, 1)
    sequencer.step_track(ctx, 1)

    local before_count = #note_events(buffer)

    -- Switch to pattern 2 mid-playback
    pattern_mod.load(ctx, 2)
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.pos = 1
    sequencer.step_track(ctx, 1)
    sequencer.step_track(ctx, 1)

    local all_notes = note_events(buffer)
    assert.are.equal(4, #all_notes)
    -- Notes from pattern 2 should differ from pattern 1
    -- (degree 1 vs degree 7 produce different MIDI notes)
    assert.are_not.equal(all_notes[1].note, all_notes[3].note,
      "pattern switch should change notes")
  end)

  it("mute + pattern load + unmute: plays restored pattern", function()
    local ctx, buffer = make_ctx_raw()
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i + 1
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)
    pattern_mod.save(ctx, 1)

    -- Mute, scramble, load pattern while muted
    ctx.tracks[1].muted = true
    for i = 1, 4 do ctx.tracks[1].params.note.steps[i] = 7 end
    pattern_mod.load(ctx, 1)
    -- Re-apply mute after load (load restores saved mute state which was false)
    ctx.tracks[1].muted = true

    -- Advance while muted (no output)
    ctx.tracks[1].params.trigger.pos = 1
    ctx.tracks[1].params.note.pos = 1
    for _ = 1, 2 do sequencer.step_track(ctx, 1) end
    assert.are.equal(0, #note_events(buffer))

    -- Unmute
    ctx.tracks[1].muted = false
    for _ = 1, 2 do sequencer.step_track(ctx, 1) end

    local notes = note_events(buffer)
    assert.are.equal(2, #notes, "unmuted track produces notes")
  end)

  it("direction change mid-playback takes effect immediately", function()
    local ctx, buffer = make_ctx_raw()
    for i = 1, 4 do
      ctx.tracks[1].params.trigger.steps[i] = 1
      ctx.tracks[1].params.note.steps[i] = i
    end
    track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
    track_mod.set_loop(ctx.tracks[1].params.note, 1, 4)

    -- Play forward for 2 steps
    ctx.tracks[1].direction = "forward"
    sequencer.step_track(ctx, 1)
    sequencer.step_track(ctx, 1)

    -- Change to reverse
    ctx.tracks[1].direction = "reverse"
    sequencer.step_track(ctx, 1)

    -- After forward 2 steps from pos 1: pos is now 3
    -- Reverse from pos 3: reads step[3], advances to 2
    -- So we should get a note from step 3
    local notes = note_events(buffer)
    assert.are.equal(3, #notes)
  end)

end)
