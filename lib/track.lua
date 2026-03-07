-- lib/track.lua
-- Track data model: steps, loop control, per-param state

local M = {}

M.NUM_TRACKS = 4
M.NUM_STEPS = 16
M.PARAM_NAMES = {"trigger", "note", "octave", "duration", "velocity", "ratchet", "alt_note", "glide"}
M.CORE_PARAMS = {"trigger", "note", "octave", "duration", "velocity"}
M.EXTENDED_PARAMS = {"ratchet", "alt_note", "glide"}

-- Step value ranges (1-indexed, matching grid rows 1-7)
-- trigger: 0 or 1
-- note: 1-7 (scale degree)
-- octave: 1-7 (4 = center/no offset)
-- duration: 1-7 (mapped to beat fractions)
-- velocity: 1-7 (mapped to 0.0-1.0)

-- Duration map: step value -> beats
M.DURATION_MAP = {
  [1] = 1/16,
  [2] = 1/8,
  [3] = 1/4,
  [4] = 1/2,
  [5] = 1,
  [6] = 2,
  [7] = 4,
}

-- Velocity map: step value -> 0.0-1.0
M.VELOCITY_MAP = {
  [1] = 0.15,
  [2] = 0.30,
  [3] = 0.45,
  [4] = 0.60,
  [5] = 0.75,
  [6] = 0.90,
  [7] = 1.0,
}

function M.new_param(default_val)
  local steps = {}
  for i = 1, M.NUM_STEPS do
    steps[i] = default_val
  end
  return {
    steps = steps,
    loop_start = 1,
    loop_end = M.NUM_STEPS,
    pos = 1,
  }
end

-- Musically useful defaults per track
local DEFAULT_PATTERNS = {
  -- Track 1: steady 16th triggers, ascending scale fragment
  [1] = {
    trigger  = {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0},
    note     = {1,2,3,4, 5,4,3,2, 1,3,5,3, 1,2,4,5},
    octave   = {4,4,4,4, 4,4,4,4, 4,4,4,4, 4,4,4,4},
    duration = {3,3,3,3, 3,3,3,3, 3,3,3,3, 3,3,3,3},
    velocity = {5,4,5,4, 5,4,5,4, 5,4,5,4, 5,4,5,4},
    note_loop_end = 8,
  },
  -- Track 2: sparser, bass-register
  [2] = {
    trigger  = {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,1},
    note     = {1,1,1,1, 5,5,5,5, 3,3,3,3, 1,1,1,4},
    octave   = {3,3,3,3, 3,3,3,3, 3,3,3,3, 3,3,3,3},
    duration = {5,5,5,5, 5,5,5,5, 5,5,5,5, 4,4,4,4},
    velocity = {6,5,6,5, 6,5,6,5, 6,5,6,5, 6,5,6,5},
  },
  -- Track 3: offset rhythm, middle register
  [3] = {
    trigger  = {0,0,1,0, 0,1,0,0, 1,0,0,1, 0,0,1,0},
    note     = {3,3,5,5, 4,4,2,2, 1,1,3,3, 5,5,7,7},
    octave   = {4,4,4,4, 4,4,4,4, 4,4,4,4, 4,4,4,4},
    duration = {3,3,4,4, 3,3,4,4, 3,3,4,4, 3,3,4,4},
    velocity = {4,4,5,5, 4,4,5,5, 4,4,5,5, 4,4,5,5},
    note_loop_end = 8,
  },
  -- Track 4: sparse high accents
  [4] = {
    trigger  = {0,0,0,0, 1,0,0,0, 0,0,0,0, 0,0,1,0},
    note     = {5,5,7,7, 6,6,5,5, 3,3,4,4, 5,5,6,6},
    octave   = {5,5,5,5, 5,5,5,5, 5,5,5,5, 5,5,5,5},
    duration = {2,2,2,2, 3,3,3,3, 2,2,2,2, 2,2,2,2},
    velocity = {5,6,5,6, 7,6,5,6, 5,6,5,6, 5,6,7,6},
  },
}

-- Default step values per param name
local PARAM_DEFAULTS = {
  trigger  = 0,
  note     = 4,
  octave   = 4,
  duration = 4,
  velocity = 4,
  ratchet  = 1,
  alt_note = 1,
  glide    = 1,
}

function M.new_track(track_num)
  local defaults = DEFAULT_PATTERNS[track_num] or DEFAULT_PATTERNS[1]
  local track = {
    params = {},
    division = 1,
    muted = false,
    direction = "forward",
  }
  for _, name in ipairs(M.PARAM_NAMES) do
    local default_val = PARAM_DEFAULTS[name] or 4
    local p = M.new_param(default_val)
    if defaults[name] then
      for i = 1, M.NUM_STEPS do
        p.steps[i] = defaults[name][i]
      end
    end
    if name == "note" and defaults.note_loop_end then
      p.loop_end = defaults.note_loop_end
    end
    track.params[name] = p
  end
  return track
end

function M.new_tracks()
  local tracks = {}
  for i = 1, M.NUM_TRACKS do
    tracks[i] = M.new_track(i)
  end
  return tracks
end

-- Advance a param's position within its loop, return the current step value
function M.advance(param)
  local pos = param.pos
  local val = param.steps[pos]
  -- advance
  if pos >= param.loop_end then
    param.pos = param.loop_start
  else
    param.pos = pos + 1
    -- handle case where pos went past loop_end (shouldn't happen but be safe)
    if param.pos > param.loop_end then
      param.pos = param.loop_start
    end
  end
  return val
end

-- Get current step value without advancing
function M.peek(param)
  return param.steps[param.pos]
end

-- Set a step value
function M.set_step(param, step, value)
  if step >= 1 and step <= M.NUM_STEPS then
    param.steps[step] = value
  end
end

-- Toggle a trigger step
function M.toggle_step(param, step)
  if step >= 1 and step <= M.NUM_STEPS then
    param.steps[step] = param.steps[step] == 0 and 1 or 0
  end
end

-- Set loop boundaries
function M.set_loop(param, loop_start, loop_end)
  if loop_start >= 1 and loop_start <= M.NUM_STEPS
    and loop_end >= 1 and loop_end <= M.NUM_STEPS
    and loop_start <= loop_end then
    param.loop_start = loop_start
    param.loop_end = loop_end
    -- clamp position into new loop
    if param.pos < loop_start or param.pos > loop_end then
      param.pos = loop_start
    end
  end
end

return M
