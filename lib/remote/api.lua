-- lib/remote/api.lua
-- Transport-agnostic remote control API for the sequencer
--
-- Commands mutate state; queries read it. Both operate on the ctx object.
-- Transport backends (OSC, MIDI, websocket) parse their protocol and call
-- api.dispatch(ctx, path, args) — they never touch ctx directly.

local track_mod = require("lib/track")
local sequencer = require("lib/sequencer")
local direction_mod = require("lib/direction")

local M = {}

-- Registry of handlers keyed by path string.
-- Each handler receives (ctx, args) and returns (value, err).
-- Commands return true on success; queries return the requested data.
local handlers = {}

-- Helper: validate track number
local function check_track(args)
  local t = tonumber(args and args[1])
  if not t or t < 1 or t > track_mod.NUM_TRACKS then
    return nil, "invalid track (1-" .. track_mod.NUM_TRACKS .. ")"
  end
  return math.floor(t)
end

-- Helper: validate param name
local function check_param(name)
  for _, p in ipairs(track_mod.PARAM_NAMES) do
    if p == name then return name end
  end
  return nil, "invalid param name"
end

-- Helper: validate step number
local function check_step(s)
  local n = tonumber(s)
  if not n or n < 1 or n > track_mod.NUM_STEPS then
    return nil, "invalid step (1-" .. track_mod.NUM_STEPS .. ")"
  end
  return math.floor(n)
end

-- Value ranges per param (min, max). Trigger is 0/1; others are 1-7.
local PARAM_RANGES = {
  trigger     = {0, 1},
  note        = {1, 7},
  octave      = {1, 7},
  duration    = {1, 7},
  velocity    = {1, 7},
  ratchet     = {1, 5},
  alt_note    = {1, 7},
  glide       = {1, 7},
  probability = {1, 7},
}

-- Helper: validate step value against param-specific range
local function check_value(pname, v)
  local val = tonumber(v)
  if not val then return nil, "missing value" end
  val = math.floor(val)
  local range = PARAM_RANGES[pname]
  if range and (val < range[1] or val > range[2]) then
    return nil, "value out of range (" .. range[1] .. "-" .. range[2] .. ")"
  end
  return val
end

------------------------------------------------------------------------
-- Transport control
------------------------------------------------------------------------

handlers["/transport/play"] = function(ctx)
  sequencer.start(ctx)
  ctx.grid_dirty = true
  return true
end

handlers["/transport/stop"] = function(ctx)
  sequencer.stop(ctx)
  ctx.grid_dirty = true
  return true
end

handlers["/transport/toggle"] = function(ctx)
  if ctx.playing then
    sequencer.stop(ctx)
  else
    sequencer.start(ctx)
  end
  ctx.grid_dirty = true
  return true
end

handlers["/transport/reset"] = function(ctx)
  sequencer.reset(ctx)
  ctx.grid_dirty = true
  return true
end

------------------------------------------------------------------------
-- Transport queries
------------------------------------------------------------------------

handlers["/transport/state"] = function(ctx)
  return ctx.playing and "playing" or "stopped"
end

------------------------------------------------------------------------
-- Track selection and mute
------------------------------------------------------------------------

handlers["/track/select"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  ctx.active_track = t
  ctx.grid_dirty = true
  return true
end

handlers["/track/mute"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local val = args[2]
  if val == nil then
    -- toggle
    ctx.tracks[t].muted = not ctx.tracks[t].muted
  else
    ctx.tracks[t].muted = (tonumber(val) == 1)
  end
  ctx.grid_dirty = true
  return true
end

handlers["/track/direction"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local dir = args[2]
  if dir then
    -- validate direction
    local valid = false
    for _, m in ipairs(direction_mod.MODES) do
      if m == dir then valid = true; break end
    end
    if not valid then return nil, "invalid direction" end
    ctx.tracks[t].direction = dir
    ctx.grid_dirty = true
    return true
  else
    return ctx.tracks[t].direction
  end
end

handlers["/track/division"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local val = tonumber(args[2])
  if val then
    if val < 1 or val > 7 then return nil, "division must be 1-7" end
    ctx.tracks[t].division = math.floor(val)
    ctx.grid_dirty = true
    return true
  else
    return ctx.tracks[t].division
  end
end

------------------------------------------------------------------------
-- Track queries
------------------------------------------------------------------------

handlers["/track/get"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local track = ctx.tracks[t]
  return {
    division = track.division,
    muted = track.muted,
    direction = track.direction,
  }
end

handlers["/track/active"] = function(ctx)
  return ctx.active_track
end

------------------------------------------------------------------------
-- Step data: read and write
------------------------------------------------------------------------

-- /step/set <track> <param> <step> <value>
handlers["/step/set"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local pname, perr = check_param(args[2])
  if not pname then return nil, perr end
  local s, serr = check_step(args[3])
  if not s then return nil, serr end
  local val, verr = check_value(pname, args[4])
  if not val then return nil, verr end
  track_mod.set_step(ctx.tracks[t].params[pname], s, val)
  ctx.grid_dirty = true
  return true
end

-- /step/get <track> <param> <step>
handlers["/step/get"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local pname, perr = check_param(args[2])
  if not pname then return nil, perr end
  local s, serr = check_step(args[3])
  if not s then return nil, serr end
  return ctx.tracks[t].params[pname].steps[s]
end

-- /step/toggle <track> <step>  (trigger param only)
handlers["/step/toggle"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local s, serr = check_step(args[2])
  if not s then return nil, serr end
  track_mod.toggle_step(ctx.tracks[t].params.trigger, s)
  ctx.grid_dirty = true
  return true
end

------------------------------------------------------------------------
-- Pattern data: bulk read
------------------------------------------------------------------------

-- /pattern/get <track> <param> -> all 16 steps
handlers["/pattern/get"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local pname, perr = check_param(args[2])
  if not pname then return nil, perr end
  -- return a copy of the steps array
  local steps = {}
  for i = 1, track_mod.NUM_STEPS do
    steps[i] = ctx.tracks[t].params[pname].steps[i]
  end
  return steps
end

-- /pattern/set <track> <param> <v1> <v2> ... <v16>
handlers["/pattern/set"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local pname, perr = check_param(args[2])
  if not pname then return nil, perr end
  if #args < 2 + track_mod.NUM_STEPS then
    return nil, "need " .. track_mod.NUM_STEPS .. " values"
  end
  local param = ctx.tracks[t].params[pname]
  local range = PARAM_RANGES[pname]
  for i = 1, track_mod.NUM_STEPS do
    local v = tonumber(args[2 + i])
    if v then
      v = math.floor(v)
      if range and (v < range[1] or v > range[2]) then
        return nil, "value out of range (" .. range[1] .. "-" .. range[2] .. ") at step " .. i
      end
      param.steps[i] = v
    end
  end
  ctx.grid_dirty = true
  return true
end

------------------------------------------------------------------------
-- Loop control
------------------------------------------------------------------------

-- /loop/set <track> <param> <start> <end>
handlers["/loop/set"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local pname, perr = check_param(args[2])
  if not pname then return nil, perr end
  local ls = tonumber(args[3])
  local le = tonumber(args[4])
  if not ls or not le then return nil, "missing start/end" end
  ls, le = math.floor(ls), math.floor(le)
  if ls < 1 or ls > track_mod.NUM_STEPS or le < 1 or le > track_mod.NUM_STEPS then
    return nil, "loop bounds must be 1-" .. track_mod.NUM_STEPS
  end
  if ls > le then return nil, "loop start must be <= end" end
  track_mod.set_loop(ctx.tracks[t].params[pname], ls, le)
  ctx.grid_dirty = true
  return true
end

-- /loop/get <track> <param>
handlers["/loop/get"] = function(ctx, args)
  local t, err = check_track(args)
  if not t then return nil, err end
  local pname, perr = check_param(args[2])
  if not pname then return nil, perr end
  local param = ctx.tracks[t].params[pname]
  return {
    loop_start = param.loop_start,
    loop_end = param.loop_end,
    pos = param.pos,
  }
end

------------------------------------------------------------------------
-- Page selection
------------------------------------------------------------------------

handlers["/page/select"] = function(ctx, args)
  local page = args and args[1]
  local _, perr = check_param(page)
  if perr then return nil, perr end
  ctx.active_page = page
  ctx.grid_dirty = true
  return true
end

handlers["/page/active"] = function(ctx)
  return ctx.active_page
end

------------------------------------------------------------------------
-- Scale queries
------------------------------------------------------------------------

handlers["/scale/notes"] = function(ctx)
  -- return a copy
  local notes = {}
  for i, n in ipairs(ctx.scale_notes) do
    notes[i] = n
  end
  return notes
end

------------------------------------------------------------------------
-- Full state snapshot (for remote UIs)
------------------------------------------------------------------------

handlers["/state/snapshot"] = function(ctx)
  local tracks = {}
  for t = 1, track_mod.NUM_TRACKS do
    local track = ctx.tracks[t]
    local params = {}
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      local p = track.params[name]
      local steps = {}
      for i = 1, track_mod.NUM_STEPS do steps[i] = p.steps[i] end
      params[name] = {
        steps = steps,
        loop_start = p.loop_start,
        loop_end = p.loop_end,
        pos = p.pos,
      }
    end
    tracks[t] = {
      division = track.division,
      muted = track.muted,
      direction = track.direction,
      params = params,
    }
  end
  return {
    playing = ctx.playing,
    active_track = ctx.active_track,
    active_page = ctx.active_page,
    tracks = tracks,
  }
end

------------------------------------------------------------------------
-- Dispatch: the single entry point for all transports
------------------------------------------------------------------------

--- Dispatch a remote command/query.
--- @param ctx table  The application context
--- @param path string  The command path (e.g. "/transport/play")
--- @param args table|nil  Positional arguments
--- @return any value  The result (true for commands, data for queries)
--- @return string|nil err  Error message if dispatch failed
function M.dispatch(ctx, path, args)
  local handler = handlers[path]
  if not handler then
    return nil, "unknown path: " .. tostring(path)
  end
  return handler(ctx, args or {})
end

--- List all registered paths (for introspection/help).
--- @return table  Array of path strings
function M.list_paths()
  local paths = {}
  for path in pairs(handlers) do
    paths[#paths + 1] = path
  end
  table.sort(paths)
  return paths
end

return M
