-- lib/scale.lua
-- Scale quantization using musicutil

local M = {}

-- Scale degree (1-7) + octave offset -> MIDI note number
-- Uses musicutil.generate_scale to build the note lookup
function M.build_scale(root, scale_type)
  local mu = require("musicutil")
  -- Generate 7 octaves of scale centered around root
  -- root is MIDI note (e.g. 60 = middle C)
  local notes = mu.generate_scale(root - 36, scale_type, 8)
  return notes
end

-- Convert track step values to a MIDI note
-- degree: 1-7 (scale degree)
-- octave: 1-7 (4 = center, maps to octave offset 0)
-- scale_notes: table from build_scale
function M.to_midi(degree, octave, scale_notes)
  -- octave offset: 4 = center (0), so offset = octave - 4
  local oct_offset = octave - 4
  -- degree is 1-7, each octave has 7 degrees in most common scales
  -- index into scale_notes: (oct_offset * 7) + degree
  -- scale_notes is 0-based octaves starting from root-36
  -- center the lookup around the 4th octave of the generated scale
  local idx = (3 + oct_offset) * 7 + degree
  -- clamp to scale bounds
  if idx < 1 then idx = 1 end
  if idx > #scale_notes then idx = #scale_notes end
  return scale_notes[idx]
end

return M
