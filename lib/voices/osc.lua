-- lib/voices/osc.lua
-- OSC voice backend: sends note events via OSC
-- Path format: /rekriate/track/{n}/note {midi_note} {velocity} {duration}

local M = {}

function M.new(track_num, host, port)
  host = host or "127.0.0.1"
  port = port or 57120
  local target = {host, port}
  local prefix = "/rekriate/track/" .. track_num

  return {
    track_num = track_num,
    target = target,

    play_note = function(self, note, vel, dur)
      osc.send(self.target, prefix .. "/note", {note, vel, dur})
    end,

    all_notes_off = function(self)
      osc.send(self.target, prefix .. "/all_notes_off", {})
    end,

    set_portamento = function(self, time)
      osc.send(self.target, prefix .. "/portamento", {time or 0})
    end,

    set_target = function(self, new_host, new_port)
      self.target = {new_host, new_port}
    end,
  }
end

return M
