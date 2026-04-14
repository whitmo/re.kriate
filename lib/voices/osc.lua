-- lib/voices/osc.lua
-- OSC voice backend: sends note events over OSC
-- Path format: /rekriate/track/{n}/note {midi_note} {velocity} {duration}

local M = {}

function M.new(track_num, host, port)
  local target = {host, port}
  return {
    track_num = track_num,
    target = target,
    active_notes = {},

    play_note = function(self, note, vel, dur)
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/note",
        {note, vel, dur})
      -- Schedule note-off after duration
      local coro_id = clock.run(function()
        clock.sync(dur)
        osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/note_off",
          {note})
        self.active_notes[note] = nil
      end)
      self.active_notes[note] = coro_id
    end,

    all_notes_off = function(self)
      for note, coro_id in pairs(self.active_notes) do
        clock.cancel(coro_id)
        osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/note_off",
          {note})
      end
      self.active_notes = {}
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/all_notes_off", {})
    end,

    set_portamento = function(self, time)
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/portamento",
        {time or 0})
    end,

    set_target = function(self, new_host, new_port)
      self.target = {new_host, new_port}
    end,

    set_level = function(self, val)
      local v = val or 0
      if v < 0 then v = 0 end
      if v > 1 then v = 1 end
      osc.send(self.target,
        "/rekriate/track/" .. self.track_num .. "/level", {v})
    end,

    set_pan = function(self, val)
      local v = val or 0
      if v < -1 then v = -1 end
      if v > 1 then v = 1 end
      osc.send(self.target,
        "/rekriate/track/" .. self.track_num .. "/pan", {v})
    end,
  }
end

return M
