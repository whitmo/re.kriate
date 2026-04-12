-- lib/voices/sc_synth.lua
-- SuperCollider melodic synth voice backend.
--
-- Sends OSC messages to a companion sclang script that hosts multiple
-- SynthDefs (subtractive, FM, wavetable). Supports the full voice
-- interface and native portamento/glide on the SC side.
--
-- OSC paths:
--   /rekriate/synth/{n}/play      midi_note velocity duration
--   /rekriate/synth/{n}/note_on   midi_note velocity
--   /rekriate/synth/{n}/note_off  midi_note
--   /rekriate/synth/{n}/all_notes_off
--   /rekriate/synth/{n}/portamento  time
--   /rekriate/synth/{n}/synthdef    name    -- "sub" | "fm" | "wavetable"

local M = {}

local VALID_SYNTHDEFS = {
  sub = true,
  fm = true,
  wavetable = true,
}

function M.new(track_num, host, port, synthdef)
  local target = {host, port}
  local voice_synthdef = VALID_SYNTHDEFS[synthdef] and synthdef or "sub"

  return {
    track_num = track_num,
    target = target,
    synthdef = voice_synthdef,
    active_notes = {},

    play_note = function(self, note, vel, dur)
      osc.send(self.target,
        "/rekriate/synth/" .. self.track_num .. "/play",
        {note, vel, dur})
      -- Schedule note-off after duration so all_notes_off can find it.
      local coro_id = clock.run(function()
        clock.sync(dur)
        osc.send(self.target,
          "/rekriate/synth/" .. self.track_num .. "/note_off",
          {note})
        self.active_notes[note] = nil
      end)
      self.active_notes[note] = coro_id
    end,

    note_on = function(self, note, vel)
      osc.send(self.target,
        "/rekriate/synth/" .. self.track_num .. "/note_on",
        {note, vel})
    end,

    note_off = function(self, note)
      if self.active_notes[note] then
        clock.cancel(self.active_notes[note])
        self.active_notes[note] = nil
      end
      osc.send(self.target,
        "/rekriate/synth/" .. self.track_num .. "/note_off",
        {note})
    end,

    all_notes_off = function(self)
      for note, coro_id in pairs(self.active_notes) do
        clock.cancel(coro_id)
        osc.send(self.target,
          "/rekriate/synth/" .. self.track_num .. "/note_off",
          {note})
      end
      self.active_notes = {}
      osc.send(self.target,
        "/rekriate/synth/" .. self.track_num .. "/all_notes_off", {})
    end,

    set_portamento = function(self, time)
      osc.send(self.target,
        "/rekriate/synth/" .. self.track_num .. "/portamento",
        {time or 0})
    end,

    set_synthdef = function(self, name)
      if not VALID_SYNTHDEFS[name] then
        return
      end
      self.synthdef = name
      osc.send(self.target,
        "/rekriate/synth/" .. self.track_num .. "/synthdef",
        {name})
    end,

    set_target = function(self, new_host, new_port)
      self.target = {new_host, new_port}
    end,
  }
end

M.VALID_SYNTHDEFS = VALID_SYNTHDEFS

return M
