-- lib/voices/midi.lua
-- MIDI voice backend: sends note_on/note_off with clock-based note-off timing

local log = require("lib/log")

local M = {}

function M.new(midi_dev, channel)
  return {
    midi_dev = midi_dev,
    channel = channel,
    active_notes = {},

    play_note = function(self, note, vel, dur)
      -- monophonic: cancel all active notes before new note-on
      for existing_key, coro_id in pairs(self.active_notes) do
        clock.cancel(coro_id)
        local existing_note = existing_key % 128
        self.midi_dev:note_off(existing_note, 0, self.channel)
      end
      self.active_notes = {}
      local key = self.channel * 128 + note
      self.midi_dev:note_on(note, math.floor(vel * 127), self.channel)
      local coro_id = clock.run(log.wrap(function()
        clock.sync(dur)
        self.midi_dev:note_off(note, 0, self.channel)
        self.active_notes[key] = nil
      end, "note_off:ch" .. self.channel))
      self.active_notes[key] = coro_id
    end,

    note_on = function(self, note, vel)
      self.midi_dev:note_on(note, math.floor(vel * 127), self.channel)
    end,

    note_off = function(self, note)
      self.midi_dev:note_off(note, 0, self.channel)
    end,

    all_notes_off = function(self)
      for key, coro_id in pairs(self.active_notes) do
        clock.cancel(coro_id)
        local note = key % 128
        self.midi_dev:note_off(note, 0, self.channel)
      end
      self.active_notes = {}
      self.midi_dev:cc(123, 0, self.channel)
    end,

    set_portamento = function(self, time)
      if time and time > 0 then
        -- Enable portamento: CC 65 (Portamento On/Off) = 127
        self.midi_dev:cc(65, 127, self.channel)
        -- Set portamento time: CC 5 = mapped value (time 1-7 -> 0-127 range)
        local cc_val = math.floor((time - 1) * 127 / 6)
        self.midi_dev:cc(5, cc_val, self.channel)
      else
        -- Disable portamento: CC 65 = 0
        self.midi_dev:cc(65, 0, self.channel)
      end
    end,

    -- Channel Volume (CC 7): level in [0, 1] -> CC value [0, 127]
    set_level = function(self, val)
      local v = val or 0
      if v < 0 then v = 0 end
      if v > 1 then v = 1 end
      self.midi_dev:cc(7, math.floor(v * 127 + 0.5), self.channel)
    end,

    -- Pan (CC 10): pan in [-1, 1] -> CC value [0, 127] (64 = center)
    set_pan = function(self, val)
      local v = val or 0
      if v < -1 then v = -1 end
      if v > 1 then v = 1 end
      self.midi_dev:cc(10, math.floor((v + 1) * 63.5 + 0.5), self.channel)
    end,
  }
end

return M
