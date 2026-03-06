-- specs/voice_spec.lua
-- Tests for voice backends

package.path = package.path .. ";./?.lua"

-- Mock clock for recorder voice
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
})

local recorder = require("lib/voices/recorder")

describe("recorder voice", function()

  before_each(function()
    beat_counter = 0
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
