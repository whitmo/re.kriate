-- lib/meta_pattern.lua
-- Meta-pattern sequencing: ordered sequence of patterns with loop counts
-- Each meta-step specifies a pattern slot and how many trigger loops to play

local pattern = require("lib/pattern")
local track_mod = require("lib/track")

local M = {}

M.MAX_STEPS = 16

-- Create a new meta-pattern state
function M.new()
  local steps = {}
  for i = 1, M.MAX_STEPS do
    steps[i] = { slot = 0, loops = 1 }
  end
  return {
    steps = steps,
    length = 0,
    pos = 1,
    loop_counter = 0,
    active = false,
    selected_step = 1,
    cued_slot = nil,
  }
end

-- Set a meta-step's pattern slot and loop count
function M.set_step(meta, step_num, slot, loops)
  if step_num < 1 or step_num > M.MAX_STEPS then return end
  meta.steps[step_num].slot = slot or 0
  meta.steps[step_num].loops = math.max(1, math.min(7, loops or 1))
  if slot and slot > 0 and step_num > meta.length then
    meta.length = step_num
  end
end

-- Clear a meta-step
function M.clear_step(meta, step_num)
  if step_num < 1 or step_num > M.MAX_STEPS then return end
  meta.steps[step_num].slot = 0
  meta.steps[step_num].loops = 1
  if step_num == meta.length then
    while meta.length > 0 and meta.steps[meta.length].slot == 0 do
      meta.length = meta.length - 1
    end
  end
end

-- Check if a step has a pattern assigned
function M.is_active(meta, step_num)
  return step_num >= 1 and step_num <= M.MAX_STEPS and meta.steps[step_num].slot > 0
end

-- Find the next active step starting from pos (wrapping)
local function find_next_active(meta, start_pos)
  for i = start_pos, meta.length do
    if meta.steps[i].slot > 0 then return i end
  end
  for i = 1, math.min(start_pos - 1, meta.length) do
    if meta.steps[i].slot > 0 then return i end
  end
  return nil
end

-- Reset all playheads to loop_start for clean pattern transitions
local function reset_playheads(ctx)
  for _, track in ipairs(ctx.tracks) do
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      local p = track.params[name]
      p.pos = p.loop_start
      p.tick = 0
    end
  end
end

-- Start meta-sequencing from beginning
function M.start(meta, ctx)
  if meta.length == 0 then return end
  meta.active = true
  local first = find_next_active(meta, 1)
  if not first then
    meta.active = false
    return
  end
  meta.pos = first
  local step = meta.steps[meta.pos]
  meta.loop_counter = step.loops
  pattern.load(ctx, step.slot)
  ctx.pattern_slot = step.slot
  reset_playheads(ctx)
  if ctx.events then
    ctx.events:emit("meta:start", { pos = meta.pos, slot = step.slot })
    ctx.events:emit("pattern:load", { slot = step.slot })
  end
end

-- Stop meta-sequencing
function M.stop(meta)
  meta.active = false
  meta.cued_slot = nil
end

-- Reset to beginning (without starting)
function M.reset(meta)
  meta.pos = 1
  meta.loop_counter = 0
  meta.cued_slot = nil
end

-- Toggle meta-sequencing on/off
function M.toggle(meta, ctx)
  if meta.active then
    M.stop(meta)
  else
    M.start(meta, ctx)
  end
end

-- Cue a pattern slot to load at next loop boundary
function M.cue(meta, slot)
  if slot and slot >= 1 and slot <= 16 then
    meta.cued_slot = slot
  end
end

-- Cancel pending cue
function M.cancel_cue(meta)
  meta.cued_slot = nil
end

-- Called when track 1's trigger param wraps (one pattern loop complete).
-- Returns true if a pattern switch occurred.
function M.on_loop_complete(meta, ctx)
  if not meta.active or meta.length == 0 then return false end

  -- Handle cued pattern override
  if meta.cued_slot then
    local cued = meta.cued_slot
    meta.cued_slot = nil
    pattern.load(ctx, cued)
    ctx.pattern_slot = cued
    reset_playheads(ctx)
    if ctx.events then
      ctx.events:emit("pattern:load", { slot = cued })
      ctx.events:emit("meta:cue_applied", { slot = cued })
    end
    return true
  end

  meta.loop_counter = meta.loop_counter - 1
  if meta.loop_counter > 0 then return false end

  -- Advance to next active step (wrap around)
  local next_pos = find_next_active(meta, meta.pos + 1)
  if not next_pos then
    meta.active = false
    return false
  end

  meta.pos = next_pos
  local step = meta.steps[meta.pos]
  meta.loop_counter = step.loops

  pattern.load(ctx, step.slot)
  ctx.pattern_slot = step.slot
  reset_playheads(ctx)
  if ctx.events then
    ctx.events:emit("pattern:load", { slot = step.slot })
    ctx.events:emit("meta:step", { pos = meta.pos, slot = step.slot, loops = step.loops })
  end

  return true
end

return M
