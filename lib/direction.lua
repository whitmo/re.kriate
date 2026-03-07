-- lib/direction.lua
-- Direction modes for parameter step advancement

local M = {}

M.MODES = {"forward", "reverse", "pendulum", "drunk", "random"}

-- Direction advance functions (all operate on param table in-place)
-- Each reads the value at param.pos, then advances param.pos, then returns the value.

local function advance_forward(param)
  if param.pos >= param.loop_end then
    param.pos = param.loop_start
  else
    param.pos = param.pos + 1
  end
end

local function advance_reverse(param)
  if param.pos <= param.loop_start then
    param.pos = param.loop_end
  else
    param.pos = param.pos - 1
  end
end

local function advance_pendulum(param)
  -- Single-step loop: nowhere to go
  if param.loop_start == param.loop_end then
    return
  end

  -- Default advancing_forward to true if not set
  if param.advancing_forward == nil then
    param.advancing_forward = true
  end

  if param.advancing_forward then
    if param.pos >= param.loop_end then
      -- Hit the top boundary, reverse direction
      param.advancing_forward = false
      param.pos = param.pos - 1
    else
      param.pos = param.pos + 1
    end
  else
    if param.pos <= param.loop_start then
      -- Hit the bottom boundary, reverse direction
      param.advancing_forward = true
      param.pos = param.pos + 1
    else
      param.pos = param.pos - 1
    end
  end
end

local function advance_drunk(param)
  local delta = math.random(-1, 1)
  local new_pos = param.pos + delta
  -- Clamp to loop bounds
  if new_pos < param.loop_start then
    new_pos = param.loop_start
  elseif new_pos > param.loop_end then
    new_pos = param.loop_end
  end
  param.pos = new_pos
end

local function advance_random(param)
  param.pos = math.random(param.loop_start, param.loop_end)
end

local advance_fns = {
  forward  = advance_forward,
  reverse  = advance_reverse,
  pendulum = advance_pendulum,
  drunk    = advance_drunk,
  random   = advance_random,
}

--- Advance param.pos according to direction mode, return the current step value.
--- Works exactly like track.advance() but supports all 5 directions.
--- @param param table  The param table with steps, loop_start, loop_end, pos, advancing_forward
--- @param direction string|nil  One of M.MODES; nil defaults to "forward"
--- @return any  The step value at the position BEFORE advancing
function M.advance(param, direction)
  local val = param.steps[param.pos]
  local fn = advance_fns[direction] or advance_forward
  fn(param)
  return val
end

return M
