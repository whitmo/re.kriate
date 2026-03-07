-- lib/voices/sprite.lua
-- Sprite voice backend: spawns visual events (sprites) from sequencer steps
-- Additive: fires alongside audio voices, never replaces them

local M = {}

-- Track color palettes (RGBA)
M.TRACK_COLORS = {
  [1] = {255, 120, 50, 255},   -- warm: orange
  [2] = {50, 180, 255, 255},   -- cool: cyan
  [3] = {80, 230, 120, 255},   -- organic: green
  [4] = {200, 80, 255, 255},   -- electric: purple
}

-- Shape names (mapped from note values 1-7)
M.SHAPES = {"circle", "rect", "triangle", "diamond", "star", "line", "dot"}

-- Size map: velocity value (1-7) -> pixel radius/half-size
M.SIZE_MAP = {
  [1] = 3,
  [2] = 5,
  [3] = 7,
  [4] = 10,
  [5] = 13,
  [6] = 17,
  [7] = 22,
}

-- Y position map: octave (1-7) -> vertical position (screen height 128)
-- Lower octave = lower on screen (higher Y)
M.Y_MAP = {
  [1] = 112,
  [2] = 96,
  [3] = 80,
  [4] = 64,
  [5] = 48,
  [6] = 32,
  [7] = 16,
}

-- X position map: alt_note (1-7) -> horizontal position (screen width 256)
M.X_MAP = {
  [1] = 32,
  [2] = 64,
  [3] = 96,
  [4] = 128,
  [5] = 160,
  [6] = 192,
  [7] = 224,
}

function M.new(track_num)
  local base_color = M.TRACK_COLORS[track_num] or M.TRACK_COLORS[1]
  return {
    track_num = track_num,
    active_events = {},
    base_color = base_color,

    play = function(self, vals, duration)
      local note_val = vals.note or 1
      local oct_val = vals.octave or 4
      local alt_val = vals.alt_note or 4
      local vel_val = vals.velocity or 4
      table.insert(self.active_events, {
        shape = note_val,
        x = M.X_MAP[alt_val] or 128,
        y = M.Y_MAP[oct_val] or 64,
        size = M.SIZE_MAP[vel_val] or 10,
        color = {base_color[1], base_color[2], base_color[3], base_color[4]},
        spawn_beat = clock.get_beats(),
        duration = duration,
      })
    end,

    get_active_events = function(self)
      local current_beat = clock.get_beats()
      local i = 1
      while i <= #self.active_events do
        local e = self.active_events[i]
        if (current_beat - e.spawn_beat) > e.duration then
          table.remove(self.active_events, i)
        else
          i = i + 1
        end
      end
      return self.active_events
    end,

    all_notes_off = function(self)
      self.active_events = {}
    end,
  }
end

return M
