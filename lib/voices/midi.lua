-- lib/voices/midi.lua
-- MIDI voice backend: sends note_on/note_off with clock-based note-off timing

local M = {}

function M.new(midi_dev, channel)
  return {
    midi_dev = midi_dev,
    channel = channel,
    active_notes = {},

    play_note = function(self, note, vel, dur)
      local key = self.channel * 128 + note
      -- retrigger: cancel pending note-off, send note-off before new note-on
      if self.active_notes[key] then
        clock.cancel(self.active_notes[key])
        self.midi_dev:note_off(note, 0, self.channel)
      end
      self.midi_dev:note_on(note, math.floor(vel * 127), self.channel)
      local coro_id = clock.run(function()
        clock.sync(dur)
        self.midi_dev:note_off(note, 0, self.channel)
        self.active_notes[key] = nil
      end)
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
  }
end

return M
