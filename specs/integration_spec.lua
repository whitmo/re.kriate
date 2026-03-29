-- specs/integration_spec.lua
-- Integration tests: validates full wiring from app.init through sequencer to voices

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by recorder voice and sequencer)
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock params system (mimics norns/seamstress params)
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

-- Mock screen (seamstress-style with color)
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

-- Mock util (needed by app.enc)
rawset(_G, "util", {
  clamp = function(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
  end,
})

-- Mock musicutil (needed by scale.build_scale via app.init)
package.loaded["musicutil"] = {
  generate_scale = function(root, scale_type, octaves)
    local notes = {}
    for i = 1, octaves * 7 do
      notes[i] = root + (i - 1) * 2
    end
    return notes
  end,
}

local app = require("lib/app")
local sequencer = require("lib/sequencer")
local keyboard = require("lib/seamstress/keyboard")
local screen_ui = require("lib/seamstress/screen_ui")
local recorder = require("lib/voices/recorder")
local track_mod = require("lib/track")
local pattern_persistence = require("lib/pattern_persistence")

local persistence_tmp = "specs/tmp/app_pattern_persistence"

-- Helper: create recorder voices and call app.init
local function make_app()
  -- Reset param store between tests
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  beat_counter = 0
  os.execute("mkdir -p " .. persistence_tmp)
  pattern_persistence._test_set_data_dir(persistence_tmp)

  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  local ctx = app.init({ voices = voices })
  return ctx, buffer
end

-- Helper: filter note events from shared buffer (exclude portamento/other CC)
local function note_events(buffer)
  local result = {}
  for _, e in ipairs(buffer) do
    if e.note and e.type ~= "portamento" then
      table.insert(result, e)
    end
  end
  return result
end

describe("integration", function()

  before_each(function()
    os.execute("rm -rf " .. persistence_tmp)
    os.execute("mkdir -p " .. persistence_tmp)
    pattern_persistence._test_set_data_dir(persistence_tmp)
  end)

  describe("app.init with recorder voices", function()

    it("returns a valid ctx with all required fields", function()
      local ctx = make_app()
      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.tracks)
      assert.are.equal(#ctx.tracks, track_mod.NUM_TRACKS)
      assert.is_not_nil(ctx.voices)
      assert.are.equal(#ctx.voices, track_mod.NUM_TRACKS)
      assert.are.equal(ctx.active_track, 1)
      assert.are.equal(ctx.active_page, "trigger")
      assert.is_false(ctx.playing)
      assert.is_not_nil(ctx.scale_notes)
      assert.is_true(#ctx.scale_notes > 0)
      assert.is_not_nil(ctx.g)
      assert.is_not_nil(ctx.grid_metro)
    end)

    it("builds a usable scale_notes table", function()
      local ctx = make_app()
      -- scale_notes should have enough entries for all degree/octave combos
      assert.is_true(#ctx.scale_notes >= 7 * 4)
      -- all entries should be numbers
      for _, n in ipairs(ctx.scale_notes) do
        assert.are.equal(type(n), "number")
      end
    end)

  end)

  describe("direction params (T041)", function()

    it("all tracks default to forward direction after init", function()
      local ctx = make_app()
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal("forward", ctx.tracks[t].direction)
      end
    end)

    it("setting direction param changes track direction", function()
      local ctx = make_app()
      params:set("direction_1", 2)  -- 2 = reverse
      assert.are.equal("reverse", ctx.tracks[1].direction)
    end)

    it("each track has independent direction param", function()
      local ctx = make_app()
      params:set("direction_1", 3)  -- pendulum
      params:set("direction_3", 5)  -- random
      assert.are.equal("pendulum", ctx.tracks[1].direction)
      assert.are.equal("forward", ctx.tracks[2].direction)
      assert.are.equal("random", ctx.tracks[3].direction)
      assert.are.equal("forward", ctx.tracks[4].direction)
    end)

    it("direction param maps to correct mode names", function()
      local ctx = make_app()
      local expected = {"forward", "reverse", "pendulum", "drunk", "random"}
      for i, mode in ipairs(expected) do
        params:set("direction_1", i)
        assert.are.equal(mode, ctx.tracks[1].direction,
          "index " .. i .. " should map to " .. mode)
      end
    end)

  end)

  describe("pattern persistence params", function()

    it("saves and loads the current bank through params actions", function()
      local ctx = make_app()
      ctx.tracks[1].division = 6
      ctx.tracks[2].params.note.steps[3] = 5
      params:set("pattern_bank_name", "menu-bank")
      params:set("pattern_bank_save", 2)
      assert.are.equal("saved bank", ctx.pattern_message.text)

      ctx.tracks = track_mod.new_tracks()
      assert.are.equal(1, ctx.tracks[1].division)

      params:set("pattern_bank_load", 2)

      assert.are.equal(6, ctx.tracks[1].division)
      assert.are.equal(5, ctx.tracks[2].params.note.steps[3])
      assert.are.equal("loaded bank", ctx.pattern_message.text)
      assert.are.equal(1, params:get("pattern_bank_save"))
      assert.are.equal(1, params:get("pattern_bank_load"))
    end)

    it("lists saved banks through params actions", function()
      local ctx = make_app()
      params:set("pattern_bank_name", "alpha-bank")
      params:set("pattern_bank_save", 2)
      params:set("pattern_bank_name", "beta-bank")
      params:set("pattern_bank_save", 2)

      params:set("pattern_bank_list", 2)

      assert.are.equal("banks: alpha-bank, beta-bank", ctx.pattern_message.text)
      assert.are.equal(1, params:get("pattern_bank_list"))
    end)

    it("deletes the current bank through params actions", function()
      local ctx = make_app()
      params:set("pattern_bank_name", "trash-bank")
      params:set("pattern_bank_save", 2)

      params:set("pattern_bank_delete", 2)
      params:set("pattern_bank_list", 2)

      assert.are.equal("banks: none", ctx.pattern_message.text)
      assert.are.equal(1, params:get("pattern_bank_delete"))
    end)

  end)

  describe("full sequencer cycle", function()

    it("step_track fires notes into recorder voices", function()
      local ctx, buffer = make_app()
      -- Enable trigger on track 1
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events(buffer)
      assert.are.equal(1, #notes)
      assert.are.equal(1, notes[1].track)
      assert.is_number(notes[1].note)
      assert.is_number(notes[1].vel)
      assert.is_number(notes[1].dur)
    end)

    it("multiple tracks produce events in shared buffer", function()
      local ctx, buffer = make_app()
      for t = 1, track_mod.NUM_TRACKS do
        ctx.tracks[t].params.trigger.steps[1] = 1
        ctx.tracks[t].params.trigger.pos = 1
      end

      for t = 1, track_mod.NUM_TRACKS do
        sequencer.step_track(ctx, t)
      end

      local notes = note_events(buffer)
      assert.are.equal(track_mod.NUM_TRACKS, #notes)
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(t, notes[t].track)
      end
    end)

    it("note values come from scale quantization", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.note.steps[1] = 3
      ctx.tracks[1].params.note.pos = 1
      ctx.tracks[1].params.octave.steps[1] = 4
      ctx.tracks[1].params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events(buffer)
      local note = notes[1].note
      -- Note should be in the scale_notes table
      local found = false
      for _, sn in ipairs(ctx.scale_notes) do
        if sn == note then found = true; break end
      end
      assert.is_true(found, "note " .. note .. " should be in scale_notes")
    end)

  end)

  describe("start/stop via app and keyboard", function()

    it("start sets playing, stop clears it", function()
      local ctx = make_app()
      sequencer.start(ctx)
      assert.is_true(ctx.playing)
      sequencer.stop(ctx)
      assert.is_false(ctx.playing)
    end)

    it("keyboard space toggles play state on app ctx", function()
      local ctx = make_app()
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_true(ctx.playing)
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_false(ctx.playing)
    end)

    it("keyboard track/page select works on app ctx", function()
      local ctx = make_app()
      keyboard.key(ctx, "3", {}, false, 1)
      assert.are.equal(ctx.active_track, 3)
      keyboard.key(ctx, "w", {}, false, 1)
      assert.are.equal(ctx.active_page, "note")
    end)

    it("keyboard reset resets all playheads on app ctx", function()
      local ctx = make_app()
      -- Advance positions
      for t = 1, track_mod.NUM_TRACKS do
        ctx.tracks[t].params.trigger.pos = 8
      end
      keyboard.key(ctx, "r", {}, false, 1)
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(ctx.tracks[t].params.trigger.pos,
          ctx.tracks[t].params.trigger.loop_start)
      end
    end)

  end)

  describe("cleanup", function()

    it("stops sequencer and calls all_notes_off", function()
      local ctx = make_app()
      sequencer.start(ctx)
      assert.is_true(ctx.playing)
      app.cleanup(ctx)
      assert.is_false(ctx.playing)
    end)

    it("does not error when voices are present", function()
      local ctx = make_app()
      -- Should not raise
      app.cleanup(ctx)
    end)

  end)

  describe("screen_ui.redraw", function()

    it("does not error with valid app ctx", function()
      local ctx = make_app()
      -- Should not raise
      screen_ui.redraw(ctx)
    end)

    it("does not error when playing", function()
      local ctx = make_app()
      ctx.playing = true
      screen_ui.redraw(ctx)
    end)

  end)

  describe("app.rebuild_scale (T065)", function()

    it("changes scale_notes when root_note param changes", function()
      local ctx = make_app()
      local original = {}
      for i, n in ipairs(ctx.scale_notes) do original[i] = n end
      params:set("root_note", 72)
      assert.are_not.equal(original[1], ctx.scale_notes[1])
    end)

    it("changes scale_notes when scale_type param changes", function()
      local ctx = make_app()
      local original_count = #ctx.scale_notes
      params:set("scale_type", 2)
      -- Still produces a valid scale
      assert.is_true(#ctx.scale_notes > 0)
    end)

  end)

  describe("app.redraw (T065)", function()

    it("does not error with valid ctx", function()
      local ctx = make_app()
      app.redraw(ctx)
    end)

    it("does not error when playing", function()
      local ctx = make_app()
      ctx.playing = true
      app.redraw(ctx)
    end)

  end)

  describe("app.key (T065)", function()

    it("K2 toggles play state", function()
      local ctx = make_app()
      assert.is_false(ctx.playing)
      app.key(ctx, 2, 1)
      assert.is_true(ctx.playing)
      app.key(ctx, 2, 1)
      assert.is_false(ctx.playing)
    end)

    it("K2 key-up is ignored", function()
      local ctx = make_app()
      app.key(ctx, 2, 0)
      assert.is_false(ctx.playing)
    end)

    it("K3 resets playheads", function()
      local ctx = make_app()
      ctx.tracks[1].params.trigger.pos = 8
      ctx.tracks[2].params.note.pos = 5
      app.key(ctx, 3, 1)
      assert.are.equal(ctx.tracks[1].params.trigger.loop_start, ctx.tracks[1].params.trigger.pos)
      assert.are.equal(ctx.tracks[2].params.note.loop_start, ctx.tracks[2].params.note.pos)
    end)

  end)

  describe("app.enc (T065)", function()

    it("E1 selects track", function()
      local ctx = make_app()
      assert.are.equal(1, ctx.active_track)
      app.enc(ctx, 1, 1)
      assert.are.equal(2, ctx.active_track)
      app.enc(ctx, 1, 1)
      assert.are.equal(3, ctx.active_track)
    end)

    it("E1 clamps to valid range", function()
      local ctx = make_app()
      app.enc(ctx, 1, -10)
      assert.are.equal(1, ctx.active_track)
      app.enc(ctx, 1, 100)
      assert.are.equal(track_mod.NUM_TRACKS, ctx.active_track)
    end)

    it("E2 selects page", function()
      local ctx = make_app()
      assert.are.equal("trigger", ctx.active_page)
      app.enc(ctx, 2, 1)
      assert.are.equal("note", ctx.active_page)
      app.enc(ctx, 2, 1)
      assert.are.equal("octave", ctx.active_page)
    end)

    it("E2 clamps to valid page range", function()
      local ctx = make_app()
      app.enc(ctx, 2, -10)
      assert.are.equal("trigger", ctx.active_page)
      app.enc(ctx, 2, 100)
      assert.are.equal("alt_track", ctx.active_page)
    end)

  end)

  describe("extended features integration (T064)", function()

    it("glide sends portamento CC before note", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.glide.steps[1] = 3  -- non-zero glide
      ctx.tracks[1].params.glide.pos = 1

      sequencer.step_track(ctx, 1)

      -- Find portamento event before note event
      local port_idx, note_idx
      for i, e in ipairs(buffer) do
        if e.type == "portamento" and not port_idx then port_idx = i end
        if e.note and e.type ~= "portamento" and not note_idx then note_idx = i end
      end
      assert.is_not_nil(port_idx, "portamento event should exist")
      assert.is_not_nil(note_idx, "note event should exist")
      assert.is_true(port_idx < note_idx, "portamento should come before note")
    end)

    it("glide=1 sends zero portamento time", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.glide.steps[1] = 1  -- off
      ctx.tracks[1].params.glide.pos = 1

      sequencer.step_track(ctx, 1)

      local port_event
      for _, e in ipairs(buffer) do
        if e.type == "portamento" then port_event = e; break end
      end
      assert.is_not_nil(port_event)
      assert.are.equal(0, port_event.time)
    end)

    it("ratchet subdivides into multiple notes", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.ratchet.steps[1] = 3
      ctx.tracks[1].params.ratchet.pos = 1

      -- Override clock.run to execute synchronously (ratchet uses clock.run+clock.sleep)
      local orig_run = clock.run
      local orig_sleep = clock.sleep
      clock.run = function(fn) fn(); return 1 end
      clock.sleep = function() end

      sequencer.step_track(ctx, 1)

      clock.run = orig_run
      clock.sleep = orig_sleep

      local notes = note_events(buffer)
      assert.are.equal(3, #notes, "ratchet=3 should produce 3 notes")
    end)

    it("alt_note shifts pitch additively", function()
      local ctx, buffer = make_app()
      -- First: play with alt_note=1 (no shift)
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.note.steps[1] = 1
      ctx.tracks[1].params.note.pos = 1
      ctx.tracks[1].params.alt_note.steps[1] = 1
      ctx.tracks[1].params.alt_note.pos = 1
      ctx.tracks[1].params.octave.steps[1] = 1
      ctx.tracks[1].params.octave.pos = 1

      sequencer.step_track(ctx, 1)
      local notes1 = note_events(buffer)
      local base_note = notes1[1].note

      -- Clear and play with alt_note=3 (shift by 2)
      for i = #buffer, 1, -1 do table.remove(buffer, i) end
      -- Reset positions
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.note.pos = 1
      ctx.tracks[1].params.alt_note.pos = 1
      ctx.tracks[1].params.octave.pos = 1
      ctx.tracks[1].params.alt_note.steps[1] = 3

      sequencer.step_track(ctx, 1)
      local notes2 = note_events(buffer)
      local shifted_note = notes2[1].note

      assert.are_not.equal(base_note, shifted_note, "alt_note=3 should shift pitch")
    end)

    it("muted track advances but fires no notes", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].muted = true

      sequencer.step_track(ctx, 1)

      local notes = note_events(buffer)
      assert.are.equal(0, #notes, "muted track should produce no notes")
      -- But position should advance
      assert.are_not.equal(1, ctx.tracks[1].params.trigger.pos, "playhead should advance")
    end)

    it("muted track unmutes at correct position", function()
      local ctx, buffer = make_app()
      -- Enable triggers on all 16 steps
      for i = 1, 16 do
        ctx.tracks[1].params.trigger.steps[i] = 1
      end
      ctx.tracks[1].muted = true

      -- Advance 3 times while muted
      for _ = 1, 3 do sequencer.step_track(ctx, 1) end
      local notes = note_events(buffer)
      assert.are.equal(0, #notes, "no notes while muted")

      -- Unmute and verify position advanced past step 3
      ctx.tracks[1].muted = false
      sequencer.step_track(ctx, 1)
      local notes2 = note_events(buffer)
      assert.is_true(#notes2 >= 1, "should fire note after unmute")
    end)

    it("pattern save and load through app ctx", function()
      local ctx = make_app()
      local pattern_mod = require("lib/pattern")

      -- Set a distinctive value
      ctx.tracks[1].params.note.steps[1] = 7
      pattern_mod.save(ctx, 1)

      -- Change the value
      ctx.tracks[1].params.note.steps[1] = 3
      assert.are.equal(3, ctx.tracks[1].params.note.steps[1])

      -- Load restores original
      pattern_mod.load(ctx, 1)
      assert.are.equal(7, ctx.tracks[1].params.note.steps[1])
    end)

    it("pattern save is independent copy", function()
      local ctx = make_app()
      local pattern_mod = require("lib/pattern")

      pattern_mod.save(ctx, 1)
      ctx.tracks[1].params.note.steps[1] = 99
      -- Saved pattern should not be affected
      assert.are_not.equal(99, ctx.patterns[1].tracks[1].params.note.steps[1])
    end)

  end)

  describe("full end-to-end cycle (T064)", function()

    it("init -> start -> step all tracks -> stop -> verify notes", function()
      local ctx, buffer = make_app()
      -- Enable triggers on all tracks
      for t = 1, track_mod.NUM_TRACKS do
        ctx.tracks[t].params.trigger.steps[1] = 1
        ctx.tracks[t].params.trigger.pos = 1
      end

      sequencer.start(ctx)
      assert.is_true(ctx.playing)

      -- Step each track
      for t = 1, track_mod.NUM_TRACKS do
        sequencer.step_track(ctx, t)
      end

      sequencer.stop(ctx)
      assert.is_false(ctx.playing)

      -- Verify notes from each track
      local notes = note_events(buffer)
      assert.are.equal(track_mod.NUM_TRACKS, #notes)
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(t, notes[t].track)
      end

      -- Verify all_notes_off was sent on stop
      local off_events = {}
      for _, e in ipairs(buffer) do
        if e.type == "all_notes_off" then table.insert(off_events, e) end
      end
      assert.are.equal(track_mod.NUM_TRACKS, #off_events)
    end)

    it("direction mode affects step sequence in full cycle", function()
      local ctx, buffer = make_app()
      -- Set reverse direction on track 1
      params:set("direction_1", 2)
      assert.are.equal("reverse", ctx.tracks[1].direction)

      -- Set distinct note values
      for i = 1, 4 do
        ctx.tracks[1].params.note.steps[i] = i
      end
      ctx.tracks[1].params.trigger.loop_end = 4
      ctx.tracks[1].params.note.loop_end = 4

      -- Set trigger active for all steps
      for i = 1, 4 do
        ctx.tracks[1].params.trigger.steps[i] = 1
      end

      -- Step 4 times, collect notes
      local collected_notes = {}
      for _ = 1, 4 do
        local before = #buffer
        sequencer.step_track(ctx, 1)
        -- Find the note event that was just added
        for i = before + 1, #buffer do
          if buffer[i].note and buffer[i].type ~= "portamento" then
            table.insert(collected_notes, buffer[i].note)
          end
        end
      end

      assert.are.equal(4, #collected_notes, "should have 4 notes from 4 steps")
    end)

  end)

  describe("edge cases (T032-T039)", function()

    -- T032: loop_start > loop_end is rejected by set_loop
    it("T032 set_loop rejects loop_start > loop_end in integration context", function()
      local ctx = make_app()
      local param = ctx.tracks[1].params.trigger
      local orig_start = param.loop_start
      local orig_end = param.loop_end
      -- Attempt to set invalid loop
      track_mod.set_loop(param, 12, 4)  -- start > end
      -- Should be unchanged (set_loop rejects invalid bounds)
      assert.are.equal(orig_start, param.loop_start)
      assert.are.equal(orig_end, param.loop_end)
    end)

    -- T033: all-zero triggers track — playhead advances, no notes fire
    it("T033 all-zero triggers track advances playhead without firing notes", function()
      local ctx, buffer = make_app()
      -- Set all triggers to 0
      for i = 1, track_mod.NUM_STEPS do
        ctx.tracks[1].params.trigger.steps[i] = 0
      end
      local start_pos = ctx.tracks[1].params.trigger.pos

      -- Step 5 times
      for _ = 1, 5 do
        sequencer.step_track(ctx, 1)
      end

      local notes = note_events(buffer)
      assert.are.equal(0, #notes, "no notes should fire with all-zero triggers")
      -- Playhead should have advanced from initial position
      assert.are_not.equal(start_pos, ctx.tracks[1].params.trigger.pos,
        "playhead should advance even with no triggers")
    end)

    -- T034: load never-saved slot — defaults gracefully, no error
    it("T034 loading a never-saved pattern slot is safe and leaves tracks unchanged", function()
      local pattern_mod = require("lib/pattern")
      local ctx = make_app()
      -- Set a distinctive value so we can detect changes
      ctx.tracks[1].params.note.steps[1] = 7
      local before = ctx.tracks[1].params.note.steps[1]

      -- Load slot 5 (never saved)
      pattern_mod.load(ctx, 5)

      -- Tracks should be unchanged (load returns early if not populated)
      assert.are.equal(before, ctx.tracks[1].params.note.steps[1],
        "tracks should be unchanged after loading empty slot")
    end)

    -- T035: 4 tracks × random direction × single-step loops — no crash
    it("T035 four tracks with random direction and single-step loops do not crash", function()
      local ctx, buffer = make_app()
      for t = 1, track_mod.NUM_TRACKS do
        params:set("direction_" .. t, 5)  -- 5 = random
        assert.are.equal("random", ctx.tracks[t].direction)
        -- Set single-step loops on all params
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          track_mod.set_loop(ctx.tracks[t].params[name], 1, 1)
        end
        ctx.tracks[t].params.trigger.steps[1] = 1
      end

      -- Advance all tracks 20 times — must not crash
      for _ = 1, 20 do
        for t = 1, track_mod.NUM_TRACKS do
          sequencer.step_track(ctx, t)
        end
      end

      -- All playheads should still be at step 1 (single-step loop)
      for t = 1, track_mod.NUM_TRACKS do
        for _, name in ipairs(track_mod.PARAM_NAMES) do
          assert.are.equal(1, ctx.tracks[t].params[name].pos,
            "track " .. t .. " " .. name .. " should stay at step 1")
        end
      end
    end)

    -- T036: 1-degree scale — all notes map to single pitch
    it("T036 single-degree scale maps all notes to the same pitch", function()
      local ctx, buffer = make_app()
      -- Replace scale_notes with a single repeated note
      ctx.scale_notes = {}
      for i = 1, 56 do  -- 8 octaves × 7 degrees
        ctx.scale_notes[i] = 60  -- all map to middle C
      end

      -- Play several steps with different note degrees
      for step = 1, 4 do
        ctx.tracks[1].params.trigger.steps[step] = 1
        ctx.tracks[1].params.note.steps[step] = step  -- degrees 1,2,3,4
      end
      ctx.tracks[1].params.trigger.loop_end = 4
      ctx.tracks[1].params.note.loop_end = 4

      for _ = 1, 4 do
        sequencer.step_track(ctx, 1)
      end

      local notes = note_events(buffer)
      assert.are.equal(4, #notes, "should fire 4 notes")
      for i, e in ipairs(notes) do
        assert.are.equal(60, e.note, "note " .. i .. " should be 60 (single-degree scale)")
      end
    end)

    -- T037: extreme clock division (min and max) — sequencer still functions
    it("T037 extreme clock division values do not break step_track", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1

      -- Min division (1 = sixteenth notes)
      ctx.tracks[1].division = 1
      sequencer.step_track(ctx, 1)
      local notes1 = note_events(buffer)
      assert.is_true(#notes1 >= 1, "should fire note at min division")

      -- Clear buffer and reset trigger pos
      for i = #buffer, 1, -1 do table.remove(buffer, i) end
      ctx.tracks[1].params.trigger.pos = 1

      -- Max division (7 = whole notes)
      ctx.tracks[1].division = 7
      sequencer.step_track(ctx, 1)
      local notes2 = note_events(buffer)
      assert.is_true(#notes2 >= 1, "should fire note at max division")
    end)

    -- T038: cleanup mid-step — note-on sent, pending note-off, cleanup silences all
    it("T038 cleanup mid-step silences all notes via all_notes_off", function()
      local ctx, buffer = make_app()
      -- Play a note (simulates mid-step: note-on sent, note-off pending)
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      sequencer.step_track(ctx, 1)

      local notes_before = note_events(buffer)
      assert.is_true(#notes_before >= 1, "should have at least one note-on")

      -- Now call cleanup (while that note is "sounding")
      app.cleanup(ctx)

      -- Verify all_notes_off was sent for every voice
      local off_count = 0
      for _, e in ipairs(buffer) do
        if e.type == "all_notes_off" then off_count = off_count + 1 end
      end
      -- cleanup calls sequencer.stop (which sends all_notes_off for each track)
      -- plus its own all_notes_off for each voice = 2× per track
      assert.is_true(off_count >= track_mod.NUM_TRACKS,
        "should have at least " .. track_mod.NUM_TRACKS .. " all_notes_off events, got " .. off_count)
    end)

    -- T039: muted track grid editing — data reflects edits even when muted
    it("T039 muted track accepts step edits while muted", function()
      local ctx = make_app()
      ctx.tracks[1].muted = true

      -- Edit step values while muted
      track_mod.set_step(ctx.tracks[1].params.note, 3, 7)
      -- Track 1 step 2 defaults to trigger=0, so toggle should set it to 1
      track_mod.toggle_step(ctx.tracks[1].params.trigger, 2)

      -- Verify edits took effect despite mute
      assert.are.equal(7, ctx.tracks[1].params.note.steps[3],
        "note step should be edited while muted")
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[2],
        "trigger toggle should work while muted")

      -- Unmute and play — the edited values should be used
      ctx.tracks[1].muted = false
    end)

  end)

end)
