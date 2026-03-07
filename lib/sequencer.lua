-- lib/sequencer.lua
-- Clock-driven sequencer with per-param step advancement and voice output

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")

local M = {}

-- Division map: division value -> clock.sync argument
-- 1 = sixteenth notes (1/4 beat), higher = slower
M.DIVISION_MAP = {
  [1] = 1/4,   -- sixteenth
  [2] = 1/3,   -- triplet sixteenth
  [3] = 1/2,   -- eighth
  [4] = 2/3,   -- triplet eighth
  [5] = 1,     -- quarter
  [6] = 2,     -- half
  [7] = 4,     -- whole
}

function M.start(ctx)
  if ctx.playing then return end
  ctx.playing = true
  -- one clock coroutine per track
  ctx.clock_ids = {}
  for t = 1, track_mod.NUM_TRACKS do
    ctx.clock_ids[t] = clock.run(function()
      M.track_clock(ctx, t)
    end)
  end
end

function M.stop(ctx)
  if not ctx.playing then return end
  ctx.playing = false
  if ctx.clock_ids then
    for _, id in ipairs(ctx.clock_ids) do
      clock.cancel(id)
    end
    ctx.clock_ids = nil
  end
end

function M.track_clock(ctx, track_num)
  local track = ctx.tracks[track_num]
  while ctx.playing do
    local div = M.DIVISION_MAP[track.division] or M.DIVISION_MAP[1]
    clock.sync(div)
    if ctx.playing and not track.muted then
      M.step_track(ctx, track_num)
    end
  end
end

function M.step_track(ctx, track_num)
  local track = ctx.tracks[track_num]
  -- advance all params independently
  local vals = {}
  for _, name in ipairs(track_mod.PARAM_NAMES) do
    vals[name] = track_mod.advance(track.params[name])
  end

  -- fire note on trigger
  if vals.trigger == 1 then
    local midi_note = scale_mod.to_midi(vals.note, vals.octave, ctx.scale_notes)
    local duration = track_mod.DURATION_MAP[vals.duration] or track_mod.DURATION_MAP[3]
    local velocity = track_mod.VELOCITY_MAP[vals.velocity] or track_mod.VELOCITY_MAP[4]
    M.play_note(ctx, track_num, midi_note, velocity, duration)
  end

  -- request grid redraw
  ctx.grid_dirty = true
end

function M.play_note(ctx, track_num, note, velocity, duration)
  local voice = ctx.voices and ctx.voices[track_num]
  if voice then
    voice:play_note(note, velocity, duration)
  end
end

-- Reset all playheads to loop start
function M.reset(ctx)
  for _, track in ipairs(ctx.tracks) do
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      track.params[name].pos = track.params[name].loop_start
    end
  end
end

return M
