-- lib/pattern.lua
-- Pattern storage: save/load track state to 16 slots
--
-- Pattern cueing (quantized transitions):
--   ctx.cued_pattern_slot holds a slot number pending a load at the next
--   track-1 trigger loop boundary. This matches hardware kria behavior:
--   pattern changes during playback quantize to loop boundaries instead of
--   jumping mid-loop. See sequencer.step_track for the loop-wrap hook.

local track_mod = require("lib/track")

local M = {}

local function deep_copy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Create 16 empty pattern slots
function M.new_slots()
  local slots = {}
  for i = 1, 16 do
    slots[i] = { populated = false, tracks = nil }
  end
  return slots
end

-- Deep-copy current ctx.tracks into pattern slot
function M.save(ctx, slot_num)
  if slot_num < 1 or slot_num > 16 then return end
  ctx.patterns[slot_num].tracks = deep_copy(ctx.tracks)
  ctx.patterns[slot_num].populated = true
end

-- Restore tracks from pattern slot into ctx
function M.load(ctx, slot_num)
  if slot_num < 1 or slot_num > 16 then return end
  if not ctx.patterns[slot_num] or not ctx.patterns[slot_num].populated then return end
  ctx.tracks = deep_copy(ctx.patterns[slot_num].tracks)
end

-- Check if a slot has data
function M.is_populated(patterns, slot_num)
  return patterns[slot_num] and patterns[slot_num].populated
end

-- Reset all param playheads to loop_start (clean quantized transition).
local function reset_playheads(ctx)
  for _, track in ipairs(ctx.tracks) do
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      local p = track.params[name]
      if p then
        p.pos = p.loop_start
        p.tick = 0
      end
    end
  end
end

-- Queue a pattern slot to load at the next loop boundary.
-- Silently ignores out-of-range slots.
function M.cue(ctx, slot)
  if not slot or slot < 1 or slot > 16 then return end
  ctx.cued_pattern_slot = slot
  if ctx.events then
    ctx.events:emit("pattern:cue", {slot=slot})
  end
end

-- Cancel any pending cue.
function M.cancel_cue(ctx)
  if not ctx.cued_pattern_slot then return end
  local slot = ctx.cued_pattern_slot
  ctx.cued_pattern_slot = nil
  if ctx.events then
    ctx.events:emit("pattern:cue_cancel", {slot=slot})
  end
end

-- Consume the pending cue: load the cued pattern and reset playheads to
-- loop_start so the new pattern starts cleanly. Returns true if a pattern
-- was loaded. Empty-slot cues are cancelled silently without loading.
function M.apply_cue(ctx)
  local slot = ctx.cued_pattern_slot
  if not slot then return false end
  ctx.cued_pattern_slot = nil
  if not M.is_populated(ctx.patterns, slot) then
    return false
  end
  M.load(ctx, slot)
  ctx.pattern_slot = slot
  reset_playheads(ctx)
  if ctx.events then
    ctx.events:emit("pattern:load", {slot=slot})
    ctx.events:emit("pattern:cue_applied", {slot=slot})
  end
  return true
end

return M
