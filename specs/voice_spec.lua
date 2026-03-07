-- specs/voice_spec.lua
-- Tests for voice backends

package.path = package.path .. ";./?.lua"

-- Mock clock for all voice backends
local beat_counter = 0
local next_coro_id = 1
local cancelled_coros = {}
local clock_run_fns = {}

rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn)
    local id = next_coro_id
    next_coro_id = next_coro_id + 1
    clock_run_fns[id] = fn
    return id
  end,
  cancel = function(id)
    cancelled_coros[id] = true
    clock_run_fns[id] = nil
  end,
  sync = function() end,
})

local recorder = require("lib/voices/recorder")
local midi_voice = require("lib/voices/midi")

-- Mock MIDI device that records all calls
local function mock_midi_dev()
  local calls = {}
  return {
    calls = calls,
    note_on = function(self, note, vel, ch)
      table.insert(calls, { type = "note_on", note = note, vel = vel, ch = ch })
    end,
    note_off = function(self, note, vel, ch)
      table.insert(calls, { type = "note_off", note = note, vel = vel, ch = ch })
    end,
    cc = function(self, num, val, ch)
      table.insert(calls, { type = "cc", num = num, val = val, ch = ch })
    end,
  }
end

describe("recorder voice", function()

  before_each(function()
    beat_counter = 0
    next_coro_id = 1
    cancelled_coros = {}
    clock_run_fns = {}
  end)

  describe("play_note", function()
    it("captures events into the buffer", function()
      local voice = recorder.new(1)
      voice:play_note(60, 0.8, 0.25)
      assert.are.equal(#voice.events, 1)
      assert.are.equal(voice.events[1].note, 60)
      assert.are.equal(voice.events[1].vel, 0.8)
      assert.are.equal(voice.events[1].dur, 0.25)
      assert.are.equal(voice.events[1].track, 1)
      assert.are.equal(voice.events[1].beat, 0)
    end)

    it("records beat timestamp", function()
      local voice = recorder.new(1)
      beat_counter = 4.5
      voice:play_note(64, 0.5, 1)
      assert.are.equal(voice.events[1].beat, 4.5)
    end)
  end)

  describe("note_on", function()
    it("captures on events", function()
      local voice = recorder.new(1)
      voice:note_on(60, 0.7)
      assert.are.equal(#voice.events, 1)
      assert.are.equal(voice.events[1].type, "on")
      assert.are.equal(voice.events[1].note, 60)
      assert.are.equal(voice.events[1].vel, 0.7)
    end)
  end)

  describe("note_off", function()
    it("captures off events", function()
      local voice = recorder.new(1)
      voice:note_off(60)
      assert.are.equal(#voice.events, 1)
      assert.are.equal(voice.events[1].type, "off")
      assert.are.equal(voice.events[1].note, 60)
    end)
  end)

  describe("get_events", function()
    it("filters by track number", function()
      local buffer = {}
      local v1 = recorder.new(1, buffer)
      local v2 = recorder.new(2, buffer)
      v1:play_note(60, 0.5, 0.25)
      v2:play_note(72, 0.8, 0.5)
      v1:play_note(64, 0.6, 0.25)

      local events1 = v1:get_events()
      assert.are.equal(#events1, 2)
      assert.are.equal(events1[1].note, 60)
      assert.are.equal(events1[2].note, 64)

      local events2 = v2:get_events()
      assert.are.equal(#events2, 1)
      assert.are.equal(events2[1].note, 72)
    end)
  end)

  describe("get_notes", function()
    it("returns note numbers from play_note events", function()
      local voice = recorder.new(1)
      voice:play_note(60, 0.5, 0.25)
      voice:play_note(64, 0.5, 0.25)
      voice:play_note(67, 0.5, 0.25)
      assert.are.same(voice:get_notes(), {60, 64, 67})
    end)

    it("includes note_on but excludes note_off", function()
      local voice = recorder.new(1)
      voice:note_on(60, 0.5)
      voice:note_off(60)
      voice:note_on(64, 0.5)
      assert.are.same(voice:get_notes(), {60, 64})
    end)
  end)

  describe("clear", function()
    it("removes only this track's events from shared buffer", function()
      local buffer = {}
      local v1 = recorder.new(1, buffer)
      local v2 = recorder.new(2, buffer)
      v1:play_note(60, 0.5, 0.25)
      v2:play_note(72, 0.8, 0.5)
      v1:play_note(64, 0.6, 0.25)

      assert.are.equal(#buffer, 3)
      v1:clear()
      assert.are.equal(#buffer, 1)
      assert.are.equal(buffer[1].track, 2)
      assert.are.equal(buffer[1].note, 72)
    end)
  end)

  describe("clear_all", function()
    it("empties the entire buffer", function()
      local buffer = {}
      local v1 = recorder.new(1, buffer)
      local v2 = recorder.new(2, buffer)
      v1:play_note(60, 0.5, 0.25)
      v2:play_note(72, 0.8, 0.5)
      assert.are.equal(#buffer, 2)
      recorder.clear_all(buffer)
      assert.are.equal(#buffer, 0)
    end)
  end)

  describe("shared buffer", function()
    it("multiple voices write to the same buffer", function()
      local buffer = {}
      local voices = {}
      for t = 1, 4 do
        voices[t] = recorder.new(t, buffer)
      end
      voices[1]:play_note(60, 0.5, 0.25)
      voices[3]:play_note(67, 0.7, 0.5)
      voices[2]:play_note(64, 0.6, 0.25)
      voices[4]:play_note(72, 0.9, 1)

      assert.are.equal(#buffer, 4)
      -- Events are in insertion order
      assert.are.equal(buffer[1].track, 1)
      assert.are.equal(buffer[2].track, 3)
      assert.are.equal(buffer[3].track, 2)
      assert.are.equal(buffer[4].track, 4)
    end)
  end)

  describe("all_notes_off", function()
    it("is a no-op (does not error)", function()
      local voice = recorder.new(1)
      voice:all_notes_off()
      assert.are.equal(#voice.events, 0)
    end)
  end)

end)

describe("midi voice", function()

  local dev, voice

  before_each(function()
    beat_counter = 0
    next_coro_id = 1
    cancelled_coros = {}
    clock_run_fns = {}
    dev = mock_midi_dev()
    voice = midi_voice.new(dev, 1)
  end)

  describe("construction", function()
    it("stores midi device and channel", function()
      assert.are.equal(voice.midi_dev, dev)
      assert.are.equal(voice.channel, 1)
    end)

    it("starts with empty active_notes", function()
      assert.are.same(voice.active_notes, {})
    end)
  end)

  describe("play_note", function()
    it("sends note_on immediately", function()
      voice:play_note(60, 0.8, 0.25)
      assert.are.equal(dev.calls[1].type, "note_on")
      assert.are.equal(dev.calls[1].note, 60)
      assert.are.equal(dev.calls[1].ch, 1)
    end)

    it("maps velocity from 0.0-1.0 to 0-127", function()
      voice:play_note(60, 1.0, 0.25)
      assert.are.equal(dev.calls[1].vel, 127)
    end)

    it("floors velocity to integer", function()
      voice:play_note(60, 0.5, 0.25)
      assert.are.equal(dev.calls[1].vel, 63)
    end)

    it("maps zero velocity", function()
      voice:play_note(60, 0.0, 0.25)
      assert.are.equal(dev.calls[1].vel, 0)
    end)

    it("schedules a clock coroutine for note-off", function()
      voice:play_note(60, 0.8, 0.25)
      local key = 1 * 128 + 60
      assert.is_not_nil(voice.active_notes[key])
      assert.is_not_nil(clock_run_fns[voice.active_notes[key]])
    end)

    it("tracks active note by channel*128+note key", function()
      voice:play_note(60, 0.8, 0.25)
      local key = 1 * 128 + 60
      assert.are.equal(voice.active_notes[key], 1) -- first coroutine id
    end)
  end)

  describe("retrigger", function()
    it("cancels pending note-off and sends note-off before new note-on", function()
      voice:play_note(60, 0.8, 0.25)
      local first_coro = voice.active_notes[1 * 128 + 60]
      voice:play_note(60, 0.6, 0.5)

      -- First coro was cancelled
      assert.is_true(cancelled_coros[first_coro])
      -- Calls: note_on(60), note_off(60), note_on(60)
      assert.are.equal(#dev.calls, 3)
      assert.are.equal(dev.calls[1].type, "note_on")
      assert.are.equal(dev.calls[2].type, "note_off")
      assert.are.equal(dev.calls[3].type, "note_on")
      assert.are.equal(dev.calls[3].vel, 76) -- floor(0.6 * 127)
    end)
  end)

  describe("note_on", function()
    it("sends note_on with mapped velocity", function()
      voice:note_on(64, 0.7)
      assert.are.equal(#dev.calls, 1)
      assert.are.equal(dev.calls[1].type, "note_on")
      assert.are.equal(dev.calls[1].note, 64)
      assert.are.equal(dev.calls[1].vel, 88) -- floor(0.7 * 127)
      assert.are.equal(dev.calls[1].ch, 1)
    end)
  end)

  describe("note_off", function()
    it("sends note_off with velocity 0", function()
      voice:note_off(64)
      assert.are.equal(#dev.calls, 1)
      assert.are.equal(dev.calls[1].type, "note_off")
      assert.are.equal(dev.calls[1].note, 64)
      assert.are.equal(dev.calls[1].vel, 0)
      assert.are.equal(dev.calls[1].ch, 1)
    end)
  end)

  describe("all_notes_off", function()
    it("cancels coroutines and sends note_off for active notes", function()
      voice:play_note(60, 0.8, 0.25)
      voice:play_note(64, 0.6, 0.5)
      local coro1 = 1
      local coro2 = 2

      -- Clear call history to focus on all_notes_off
      for i = #dev.calls, 1, -1 do table.remove(dev.calls, i) end

      voice:all_notes_off()

      -- Both coroutines cancelled
      assert.is_true(cancelled_coros[coro1])
      assert.is_true(cancelled_coros[coro2])

      -- note_off sent for both notes, plus CC 123
      -- Note: pairs iteration order is not guaranteed, so check by content
      local note_offs = {}
      local cc_sent = false
      for _, call in ipairs(dev.calls) do
        if call.type == "note_off" then
          note_offs[call.note] = true
        elseif call.type == "cc" then
          cc_sent = true
          assert.are.equal(call.num, 123)
          assert.are.equal(call.val, 0)
          assert.are.equal(call.ch, 1)
        end
      end
      assert.is_true(note_offs[60])
      assert.is_true(note_offs[64])
      assert.is_true(cc_sent)
    end)

    it("clears active_notes table", function()
      voice:play_note(60, 0.8, 0.25)
      voice:all_notes_off()
      assert.are.same(voice.active_notes, {})
    end)

    it("sends CC 123 even with no active notes", function()
      voice:all_notes_off()
      assert.are.equal(#dev.calls, 1)
      assert.are.equal(dev.calls[1].type, "cc")
      assert.are.equal(dev.calls[1].num, 123)
    end)
  end)

  describe("multi-channel", function()
    it("uses the configured channel for all messages", function()
      local voice_ch3 = midi_voice.new(dev, 3)
      voice_ch3:play_note(60, 0.8, 0.25)
      assert.are.equal(dev.calls[1].ch, 3)
    end)

    it("tracks notes per channel", function()
      local voice_ch1 = midi_voice.new(dev, 1)
      local voice_ch2 = midi_voice.new(dev, 2)
      voice_ch1:play_note(60, 0.8, 0.25)
      voice_ch2:play_note(60, 0.6, 0.25)
      -- Different keys: 1*128+60 vs 2*128+60
      assert.is_not_nil(voice_ch1.active_notes[1 * 128 + 60])
      assert.is_not_nil(voice_ch2.active_notes[2 * 128 + 60])
    end)
  end)

  describe("note-off coroutine behavior", function()
    it("coroutine function sends note_off and clears active_notes", function()
      voice:play_note(60, 0.8, 0.25)
      local coro_id = voice.active_notes[1 * 128 + 60]
      local fn = clock_run_fns[coro_id]

      -- Clear calls to isolate coroutine behavior
      for i = #dev.calls, 1, -1 do table.remove(dev.calls, i) end

      -- Simulate what happens when clock.sync returns
      fn()

      assert.are.equal(#dev.calls, 1)
      assert.are.equal(dev.calls[1].type, "note_off")
      assert.are.equal(dev.calls[1].note, 60)
      assert.is_nil(voice.active_notes[1 * 128 + 60])
    end)
  end)

end)
