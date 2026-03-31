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

-- X position map: effective degree (1-7) -> horizontal position (screen width 256)
-- Effective degree combines note + alt_note, mirroring the audio path
M.X_MAP = {
  [1] = 32,
  [2] = 64,
  [3] = 96,
  [4] = 128,
  [5] = 160,
  [6] = 192,
  [7] = 224,
}

-- Movement constants
M.DRIFT_SPEED = 20   -- pixels per second horizontal drift
M.FLOAT_SPEED = 15   -- pixels per second upward float

-- Echo sprite multipliers
M.ECHO_SIZE_MULT = 1.5
M.ECHO_ALPHA_MULT = 0.3
M.ECHO_DURATION_MULT = 1.5

function M.new(track_num)
  local base_color = M.TRACK_COLORS[track_num] or M.TRACK_COLORS[1]
  return {
    track_num = track_num,
    active_events = {},
    base_color = base_color,
    last_event = nil,  -- for glide line rendering

    play = function(self, vals, duration, opts)
      opts = opts or {}
      local note_val = vals.note or 1
      local oct_val = vals.octave or 4
      local alt_val = vals.alt_note or 4
      local vel_val = vals.velocity or 4
      local ratchet_val = vals.ratchet or 1
      local glide_val = vals.glide or 1
      local is_muted = opts.muted or false

      -- Combine note + alt_note into effective degree (mirrors audio path)
      local effective_degree = ((note_val - 1) + (alt_val - 1)) % 7 + 1
      local x = M.X_MAP[effective_degree] or 128
      local y = M.Y_MAP[oct_val] or 64
      local size = M.SIZE_MAP[vel_val] or 10
      local alpha = base_color[4]

      -- Ratcheted notes are brighter/whiter
      local r, g, b = base_color[1], base_color[2], base_color[3]
      if ratchet_val > 1 then
        -- Blend toward white proportionally to ratchet intensity
        local blend = (ratchet_val - 1) / 6  -- 0 at ratchet=1, ~1 at ratchet=7
        r = math.floor(r + (255 - r) * blend)
        g = math.floor(g + (255 - g) * blend)
        b = math.floor(b + (255 - b) * blend)
      end

      -- Muted tracks produce ghost sprites at 10% alpha
      if is_muted then
        alpha = math.floor(alpha * 0.1)
      end

      -- Store previous event position for glide lines
      local prev_event = self.last_event

      -- Main sprite
      local event = {
        shape = note_val,
        x = x,
        y = y,
        size = size,
        color = {r, g, b, alpha},
        spawn_beat = clock.get_beats(),
        duration = duration,
        track_num = self.track_num,
        is_echo = false,
        is_ghost = is_muted,
        ratchet = ratchet_val,
        glide = glide_val,
        -- Glide line: connect to previous note position
        glide_from = (glide_val > 1 and prev_event) and {
          x = prev_event.x,
          y = prev_event.y,
        } or nil,
      }
      table.insert(self.active_events, event)
      self.last_event = event

      -- Echo sprite (larger, fainter, longer duration)
      -- Skip echo for muted/ghost notes
      if not is_muted then
        table.insert(self.active_events, {
          shape = note_val,
          x = x,
          y = y,
          size = size * M.ECHO_SIZE_MULT,
          color = {r, g, b, math.floor(alpha * M.ECHO_ALPHA_MULT)},
          spawn_beat = clock.get_beats(),
          duration = duration * M.ECHO_DURATION_MULT,
          track_num = self.track_num,
          is_echo = true,
          is_ghost = false,
          ratchet = ratchet_val,
          glide = glide_val,
          glide_from = nil,
        })
      end
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
      self.last_event = nil
    end,
  }
end

return M
