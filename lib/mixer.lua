-- lib/mixer.lua
-- Per-track mixer state: level (0.0-1.0), pan (-1.0 to 1.0), mute (bool).
-- Mute lives on ctx.tracks[t].muted (single source of truth with grid NAV_MUTE
-- and alt-track page); the mixer only exposes a view/setter that writes there.
--
-- Level and pan live on ctx.mixer and are propagated to voices via
-- voice:set_level / voice:set_pan (if the voice implements them).
--
-- Level is a velocity multiplier: sequencer.play_note scales the step velocity
-- by mixer.level[t] before dispatch. Pan is pushed to the voice backend once
-- per change (and re-applied when a voice is rebuilt via mixer.apply_to_voice).

local track_mod = require("lib/track")

local M = {}

local DEFAULT_LEVEL = 1.0
local DEFAULT_PAN = 0.0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- Create a fresh mixer state with defaults (level=1.0, pan=0.0 per track).
function M.new()
  local state = {level = {}, pan = {}}
  for t = 1, track_mod.NUM_TRACKS do
    state.level[t] = DEFAULT_LEVEL
    state.pan[t] = DEFAULT_PAN
  end
  return state
end

--- Apply level/pan to a single voice (call after voice:new or rebuild).
function M.apply_to_voice(ctx, t)
  local voice = ctx.voices and ctx.voices[t]
  if not voice then return end
  local mx = ctx.mixer
  if not mx then return end
  if voice.set_level and mx.level[t] ~= nil then
    voice:set_level(mx.level[t])
  end
  if voice.set_pan and mx.pan[t] ~= nil then
    voice:set_pan(mx.pan[t])
  end
end

--- Apply level/pan for every track. Useful after bulk rebuild or preset load.
function M.apply_all(ctx)
  for t = 1, track_mod.NUM_TRACKS do
    M.apply_to_voice(ctx, t)
  end
end

--- Set level for a track. Clamps to [0, 1]. Propagates to voice.
function M.set_level(ctx, t, val)
  if not ctx.mixer then ctx.mixer = M.new() end
  local v = clamp(val or 0, 0, 1)
  ctx.mixer.level[t] = v
  local voice = ctx.voices and ctx.voices[t]
  if voice and voice.set_level then
    voice:set_level(v)
  end
  if ctx.events then
    ctx.events:emit("mixer:level", {track = t, level = v})
  end
  return v
end

--- Set pan for a track. Clamps to [-1, 1]. Propagates to voice.
function M.set_pan(ctx, t, val)
  if not ctx.mixer then ctx.mixer = M.new() end
  local v = clamp(val or 0, -1, 1)
  ctx.mixer.pan[t] = v
  local voice = ctx.voices and ctx.voices[t]
  if voice and voice.set_pan then
    voice:set_pan(v)
  end
  if ctx.events then
    ctx.events:emit("mixer:pan", {track = t, pan = v})
  end
  return v
end

--- Set mute for a track. Writes ctx.tracks[t].muted (authoritative).
function M.set_mute(ctx, t, muted)
  local track = ctx.tracks and ctx.tracks[t]
  if not track then return end
  track.muted = muted and true or false
  if ctx.events then
    ctx.events:emit("mixer:mute", {track = t, muted = track.muted})
  end
  return track.muted
end

--- Toggle mute for a track.
function M.toggle_mute(ctx, t)
  local track = ctx.tracks and ctx.tracks[t]
  if not track then return end
  return M.set_mute(ctx, t, not track.muted)
end

--- Read current level (0-1) for a track.
function M.get_level(ctx, t)
  if not ctx.mixer then return DEFAULT_LEVEL end
  return ctx.mixer.level[t] or DEFAULT_LEVEL
end

--- Read current pan (-1..1) for a track.
function M.get_pan(ctx, t)
  if not ctx.mixer then return DEFAULT_PAN end
  return ctx.mixer.pan[t] or DEFAULT_PAN
end

--- Read current mute for a track.
function M.get_mute(ctx, t)
  local track = ctx.tracks and ctx.tracks[t]
  return track and track.muted == true
end

--- Snapshot current mixer state into a plain table (preset persistence, OSC).
function M.snapshot(ctx)
  local snap = {level = {}, pan = {}, mute = {}}
  for t = 1, track_mod.NUM_TRACKS do
    snap.level[t] = M.get_level(ctx, t)
    snap.pan[t] = M.get_pan(ctx, t)
    snap.mute[t] = M.get_mute(ctx, t)
  end
  return snap
end

--- Restore mixer state from a snapshot table (no-op on nil fields).
function M.restore(ctx, snap)
  if not snap then return end
  if snap.level then
    for t = 1, track_mod.NUM_TRACKS do
      if snap.level[t] ~= nil then
        M.set_level(ctx, t, snap.level[t])
      end
    end
  end
  if snap.pan then
    for t = 1, track_mod.NUM_TRACKS do
      if snap.pan[t] ~= nil then
        M.set_pan(ctx, t, snap.pan[t])
      end
    end
  end
  if snap.mute then
    for t = 1, track_mod.NUM_TRACKS do
      if snap.mute[t] ~= nil then
        M.set_mute(ctx, t, snap.mute[t])
      end
    end
  end
end

M.DEFAULT_LEVEL = DEFAULT_LEVEL
M.DEFAULT_PAN = DEFAULT_PAN

return M
