-- lib/track.lua
-- Track data model: steps, loop control, per-param state

local M = {}

M.NUM_TRACKS = 4
M.NUM_STEPS = 16
M.PARAM_NAMES = {"trigger", "note", "octave", "duration", "velocity", "ratchet", "alt_note", "glide", "probability"}
M.CORE_PARAMS = {"trigger", "note", "octave", "duration", "velocity", "probability"}
M.EXTENDED_PARAMS = {"ratchet", "alt_note", "glide"}
M.DEFAULT_LOOP_LEN = 6
M.MAX_RATCHET = 5  -- max subdivisions per step (matches kria ansible/n.kria)

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

-- Probability map: step value -> percentage (0-100)
M.PROBABILITY_MAP = {
  [1] = 0,
  [2] = 17,
  [3] = 33,
  [4] = 50,
  [5] = 67,
  [6] = 83,
  [7] = 100,
}

function M.new_param(default_val)
  local steps = {}
  for i = 1, M.NUM_STEPS do
    steps[i] = default_val
  end
  return {
    steps = steps,
    loop_start = 1,
    loop_end = M.DEFAULT_LOOP_LEN,
    pos = 1,
    clock_div = 1,  -- per-param clock divider: 1 = every tick, 2 = every other, etc.
    tick = 0,       -- internal tick counter for clock division
  }
end

-- Extended param value ranges
-- ratchet: 1-5 (subdivision count per step; 1 = normal, 2-5 = ratchet)
--   Each step also has a ratchet_bits bitmask controlling which sub-gates fire
-- alt_note: 1-7 (secondary note offset, combined with note for variation)
-- glide: 1-7 (portamento amount; 1 = none, 7 = max)
-- probability: 1-7 (trigger probability; 7 = 100% always fire, 1 = 0% never fire)

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
  ratchet  = 1,  -- 1 = no ratchet
  alt_note = 1,  -- 1 = no offset
  glide    = 1,  -- 1 = no glide
  probability = 7,  -- 7 = 100% (always fire)
}

function M.new_track(track_num)
  local defaults = DEFAULT_PATTERNS[track_num] or DEFAULT_PATTERNS[1]
  local track = {
    params = {},
    division = 1,
    muted = false,
    direction = "forward",
    swing = 0,
    trig_clock = false,  -- trigger clocking: non-trigger params advance only when trigger fires
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
    if name == "ratchet" then
      p.bits = {}
      for i = 1, M.NUM_STEPS do
        p.bits[i] = 1  -- default: single subdivision active (bit 0 set)
      end
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

-- Check if a param should advance on this tick (based on clock_div).
-- Increments the internal tick counter; returns true when the param should step.
function M.should_advance(param)
  param.tick = param.tick + 1
  if param.tick >= param.clock_div then
    param.tick = 0
    return true
  end
  return false
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

-- Ratchet sub-gate helpers (operate on ratchet param's bits array)

-- Check if a specific sub-gate bit is active
function M.get_ratchet_bit(param, step, bit_idx)
  local bits = param.bits and param.bits[step] or 0
  return (bits >> bit_idx) & 1 == 1
end

-- Toggle a specific sub-gate bit; auto-extend count if toggling ON above current count,
-- auto-shrink count if toggling OFF leaves highest bits clear
function M.toggle_ratchet_bit(param, step, bit_idx)
  if not param.bits then return end
  local bits = param.bits[step] or 0
  local count = param.steps[step] or 1

  -- Toggle the bit
  bits = bits ~ (1 << bit_idx)
  local new_bit_on = (bits >> bit_idx) & 1 == 1

  if new_bit_on and bit_idx >= count then
    -- Extending: set count to include this bit position
    count = bit_idx + 1
  elseif not new_bit_on then
    -- Shrinking: find highest set bit to determine new count
    local highest = 0
    for i = M.MAX_RATCHET - 1, 0, -1 do
      if (bits >> i) & 1 == 1 then
        highest = i + 1
        break
      end
    end
    count = math.max(1, highest)
  end

  -- Ensure at least one bit is set
  local mask = (1 << count) - 1
  bits = bits & mask
  if bits == 0 then bits = 1; count = math.max(count, 1) end

  param.steps[step] = count
  param.bits[step] = bits
end

-- Increment/decrement ratchet subdivision count
-- delta > 0: new subdivision bit is set by default
-- delta < 0: bits above new count are cleared
function M.delta_ratchet_count(param, step, delta)
  if not param.bits then return end
  local old_count = param.steps[step] or 1
  local new_count = math.max(1, math.min(M.MAX_RATCHET, old_count + delta))
  if new_count == old_count then return end

  local bits = param.bits[step] or ((1 << old_count) - 1)
  if delta > 0 then
    -- Set new subdivision bits
    for i = old_count, new_count - 1 do
      bits = bits | (1 << i)
    end
  else
    -- Clear bits above new count
    local mask = (1 << new_count) - 1
    bits = bits & mask
  end

  -- Ensure at least one bit set
  if bits == 0 then bits = 1 end
  param.steps[step] = new_count
  param.bits[step] = bits
end

-- Fill all subdivisions in current count range
function M.fill_ratchet_bits(param, step)
  if not param.bits then return end
  local count = param.steps[step] or 1
  param.bits[step] = (1 << count) - 1
end

-- Clear ratchet: reset to single subdivision
function M.clear_ratchet(param, step)
  param.steps[step] = 1
  if param.bits then param.bits[step] = 1 end
end

-- Ensure ratchet param has bits array (migration helper for loaded patterns)
function M.ensure_ratchet_bits(param)
  if param.bits then return end
  param.bits = {}
  for i = 1, M.NUM_STEPS do
    local count = param.steps[i] or 1
    count = math.max(1, math.min(M.MAX_RATCHET, count))
    param.steps[i] = count
    param.bits[i] = (1 << count) - 1  -- all subdivisions active
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
