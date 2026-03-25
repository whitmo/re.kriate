-- lib/norns/nb_voice.lua
-- Wraps an nb player into the voice interface for the norns entrypoint

local M = {}

function M.new(param_id)
  return {
    param_id = param_id,

    play_note = function(self, note, vel, dur)
      local player = params:lookup_param(self.param_id):get_player()
      if player then player:play_note(note, vel, dur) end
    end,

    note_on = function(self, note, vel)
      local player = params:lookup_param(self.param_id):get_player()
      if player then player:note_on(note, vel) end
    end,

    note_off = function(self, note)
      local player = params:lookup_param(self.param_id):get_player()
      if player then player:note_off(note) end
    end,

    all_notes_off = function(self)
      -- nb handles cleanup through its own mechanisms
    end,

    set_portamento = function(self, time)
      local player = params:lookup_param(self.param_id):get_player()
      if player and player.set_slew then player:set_slew(time) end
    end,
  }
end

return M
