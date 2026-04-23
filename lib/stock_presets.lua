-- lib/stock_presets.lua
-- Ship-with factory presets so a fresh install has something to load/test
-- against. Seeded on first run when the user preset dir is empty; never
-- overwrites existing user presets.

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local meta_pattern = require("lib/meta_pattern")

local M = {}

local NUM_STEPS = track_mod.NUM_STEPS
local NUM_TRACKS = track_mod.NUM_TRACKS

local function deep_copy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do copy[k] = deep_copy(v) end
  return copy
end

-- Uniform row value across all 16 steps (respects NUM_STEPS).
local function fill(val)
  local t = {}
  for i = 1, NUM_STEPS do t[i] = val end
  return t
end

-- Overlay {[step]=val, ...} onto a baseline fill value, producing a fresh row.
local function row(baseline, overrides)
  local t = fill(baseline)
  for k, v in pairs(overrides or {}) do t[k] = v end
  return t
end

-- Apply a steps array onto the track's named param, leaving loop bounds
-- and clock_div at their defaults from new_track. Useful for layering
-- stock patterns on top of musical track defaults without rebuilding the
-- whole param.
local function set_steps(track, pname, steps)
  local p = track.params[pname]
  if not p then return end
  for i = 1, NUM_STEPS do
    p.steps[i] = steps[i] or p.steps[i]
  end
end

local function set_loop(track, pname, loop_start, loop_end)
  local p = track.params[pname]
  if not p then return end
  p.loop_start = loop_start
  p.loop_end = loop_end
  p.pos = loop_start
end

-- Snapshot current tracks into `slot_num` of the slots table.
local function snapshot_slot(slots, slot_num, tracks)
  slots[slot_num] = { populated = true, tracks = deep_copy(tracks) }
end

-- Build "stock-defaults": the musical starting point shipped by track.new_track,
-- with slot 1 pre-populated so users can recall a "home" pattern.
local function build_defaults()
  local tracks = track_mod.new_tracks()
  local slots = pattern.new_slots()
  snapshot_slot(slots, 1, tracks)
  return {
    tracks = tracks,
    patterns = slots,
    meta = meta_pattern.new(),
    pattern_slot = 1,
    active_track = 1,
    active_page = "trigger",
  }
end

-- Build "stock-four-on-floor": a classic drum groove across tracks 1-3,
-- track 4 silent. Designed for `sc_drums` routing where rows map to
-- kick/snare/hat. Even without drums, the trigger pattern is a useful
-- timing reference.
local function build_four_on_floor()
  local tracks = track_mod.new_tracks()

  -- Track 1: kick on every quarter (steps 1, 5, 9, 13)
  set_steps(tracks[1], "trigger", row(0, {[1]=1, [5]=1, [9]=1, [13]=1}))
  set_steps(tracks[1], "note",     fill(1))
  set_steps(tracks[1], "octave",   fill(3))
  set_steps(tracks[1], "velocity", fill(7))
  set_loop(tracks[1], "trigger", 1, 16)

  -- Track 2: snare on backbeat (steps 5, 13)
  set_steps(tracks[2], "trigger", row(0, {[5]=1, [13]=1}))
  set_steps(tracks[2], "note",     fill(3))
  set_steps(tracks[2], "octave",   fill(4))
  set_steps(tracks[2], "velocity", fill(6))
  set_loop(tracks[2], "trigger", 1, 16)

  -- Track 3: closed hat on every 8th (odd steps)
  set_steps(tracks[3], "trigger", row(0,
    {[1]=1, [3]=1, [5]=1, [7]=1, [9]=1, [11]=1, [13]=1, [15]=1}))
  set_steps(tracks[3], "note",     fill(5))
  set_steps(tracks[3], "octave",   fill(5))
  set_steps(tracks[3], "velocity", fill(4))
  set_loop(tracks[3], "trigger", 1, 16)

  -- Track 4: muted — leave at defaults but mute flag on
  tracks[4].muted = true

  local slots = pattern.new_slots()
  snapshot_slot(slots, 1, tracks)

  return {
    tracks = tracks,
    patterns = slots,
    meta = meta_pattern.new(),
    pattern_slot = 1,
    active_track = 1,
    active_page = "trigger",
  }
end

-- Build "stock-arp-up": track 1 plays an 8-step ascending scale run
-- (notes 1..8, triggers every step). Tracks 2-4 muted so the arp is
-- clearly audible on its own for voice/routing sanity checks.
local function build_arp_up()
  local tracks = track_mod.new_tracks()

  set_steps(tracks[1], "trigger", fill(1))
  set_steps(tracks[1], "note",    { 1, 2, 3, 4, 5, 6, 7, 1,
                                    1, 2, 3, 4, 5, 6, 7, 1 })
  set_steps(tracks[1], "octave",  row(4, {[8]=5, [16]=5}))
  set_steps(tracks[1], "duration", fill(2))
  set_steps(tracks[1], "velocity", row(5, {[1]=7, [9]=7}))
  set_loop(tracks[1], "trigger", 1, 8)
  set_loop(tracks[1], "note",    1, 8)

  for t = 2, NUM_TRACKS do
    tracks[t].muted = true
  end

  local slots = pattern.new_slots()
  snapshot_slot(slots, 1, tracks)

  return {
    tracks = tracks,
    patterns = slots,
    meta = meta_pattern.new(),
    pattern_slot = 1,
    active_track = 1,
    active_page = "note",
  }
end

-- Ordered list of stock presets. Order is stable so tests and docs can
-- reference by index.
M.presets = {
  { name = "stock-defaults",      build = build_defaults },
  { name = "stock-four-on-floor", build = build_four_on_floor },
  { name = "stock-arp-up",        build = build_arp_up },
}

-- Seed stock presets onto disk via the provided preset module. Only
-- writes when the user preset dir has no visible presets (autosave is
-- hidden from preset.list so it does not inhibit seeding on next boot).
-- Returns (count_written, err). err is a map from preset name to error
-- string for any writes that failed; absent on full success.
function M.seed_if_empty(preset_mod)
  if not preset_mod or not preset_mod.list or not preset_mod.save_payload then
    return 0, { _missing = "preset_mod" }
  end
  local existing = preset_mod.list()
  if existing and #existing > 0 then return 0 end

  local count = 0
  local errs
  for _, stock in ipairs(M.presets) do
    local payload = stock.build()
    local ok, err = preset_mod.save_payload(payload, stock.name)
    if ok then
      count = count + 1
    else
      errs = errs or {}
      errs[stock.name] = err or "unknown"
    end
  end
  return count, errs
end

-- Return the list of stock preset names in definition order. Useful for
-- UI/tests that need to distinguish stock vs user presets.
function M.names()
  local out = {}
  for i, s in ipairs(M.presets) do out[i] = s.name end
  return out
end

return M
