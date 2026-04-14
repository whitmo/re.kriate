-- lib/voices/sc_drums.lua
-- SuperCollider drum voice backend: sends drum events over OSC
-- Path format: /rekriate/track/{n}/drum {midi_note} {velocity} {duration}
-- SC side maps MIDI note to drum type (kick/snare/hat/perc)

local M = {}

function M.new(track_num, host, port)
  local target = {host, port}
  return {
    track_num = track_num,
    target = target,
    active_notes = {},

    play_note = function(self, note, vel, dur)
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/drum",
        {note, vel, dur})
      -- Schedule note-off after duration (drums are typically one-shots,
      -- but we track for all_notes_off cleanup)
      local coro_id = clock.run(function()
        clock.sync(dur)
        osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/drum_off",
          {note})
        self.active_notes[note] = nil
      end)
      self.active_notes[note] = coro_id
    end,

    note_on = function(self, note, vel)
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/drum",
        {note, vel, 0})
    end,

    note_off = function(self, note)
      if self.active_notes[note] then
        clock.cancel(self.active_notes[note])
        self.active_notes[note] = nil
      end
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/drum_off",
        {note})
    end,

    all_notes_off = function(self)
      for note, coro_id in pairs(self.active_notes) do
        clock.cancel(coro_id)
        osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/drum_off",
          {note})
      end
      self.active_notes = {}
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/all_drums_off", {})
    end,

    set_portamento = function(self, time)
      -- Portamento is not typical for drums, but we support the interface.
      -- SC side can use this for pitch slide effects on tuned percussion.
      osc.send(self.target, "/rekriate/track/" .. self.track_num .. "/drum_portamento",
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
        "/rekriate/track/" .. self.track_num .. "/drum_level", {v})
    end,

    set_pan = function(self, val)
      local v = val or 0
      if v < -1 then v = -1 end
      if v > 1 then v = 1 end
      osc.send(self.target,
        "/rekriate/track/" .. self.track_num .. "/drum_pan", {v})
    end,
  }
end

return M
