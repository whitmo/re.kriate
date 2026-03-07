-- lib/voices/recorder.lua
-- Recorder voice: captures play_note calls into a buffer for testing and visualization

local M = {}

function M.new(track_num, shared_buffer)
  local buffer = shared_buffer or {}
  return {
    track_num = track_num,
    events = buffer,

    play_note = function(self, note, vel, dur)
      table.insert(self.events, {
        track = self.track_num,
        note = note,
        vel = vel,
        dur = dur,
        beat = clock.get_beats(),
      })
    end,

    note_on = function(self, note, vel)
      table.insert(self.events, {
        track = self.track_num,
        note = note,
        vel = vel,
        type = "on",
        beat = clock.get_beats(),
      })
    end,

    note_off = function(self, note)
      table.insert(self.events, {
        track = self.track_num,
        note = note,
        type = "off",
        beat = clock.get_beats(),
      })
    end,

    all_notes_off = function(self) end,

    set_portamento = function(self, time)
      table.insert(self.events, {
        track = self.track_num,
        type = "portamento",
        time = time,
      })
    end,

    get_events = function(self)
      local result = {}
      for _, e in ipairs(self.events) do
        if e.track == self.track_num then table.insert(result, e) end
      end
      return result
    end,

    get_notes = function(self)
      local notes = {}
      for _, e in ipairs(self:get_events()) do
        if not e.type or e.type ~= "off" then table.insert(notes, e.note) end
      end
      return notes
    end,

    clear = function(self)
      local i = 1
      while i <= #self.events do
        if self.events[i].track == self.track_num then
          table.remove(self.events, i)
        else
          i = i + 1
        end
      end
    end,
  }
end

function M.clear_all(buffer)
  for i = #buffer, 1, -1 do table.remove(buffer, i) end
end

return M
