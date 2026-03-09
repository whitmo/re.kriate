-- lib/pattern.lua
-- Pattern storage: save/load track state to 16 slots

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

return M
