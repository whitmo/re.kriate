-- lib/app.lua
-- Top-level app logic: init, cleanup, grid connection, params setup

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")
local sequencer = require("lib/sequencer")
local grid_ui = require("lib/grid_ui")
local grid_provider = require("lib/grid_provider")

local M = {}

local SCALE_NAMES = {
  "Major", "Natural Minor", "Dorian", "Mixolydian",
  "Lydian", "Phrygian", "Locrian", "Harmonic Minor",
  "Melodic Minor", "Pentatonic Major", "Pentatonic Minor",
  "Blues Scale", "Whole Tone", "Chromatic",
}

function M.init(config)
  config = config or {}

  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    loop_first_press = nil,
    grid_dirty = true,
    scale_notes = {},
    voices = config.voices or {},
  }

  -- params: scale
  params:add_separator("re_kriate", "re.kriate")

  params:add_number("root_note", "root note", 0, 127, 60)
  params:set_action("root_note", function() M.rebuild_scale(ctx) end)

  params:add_option("scale_type", "scale", SCALE_NAMES, 1)
  params:set_action("scale_type", function() M.rebuild_scale(ctx) end)

  -- params: per-track division
  local div_names = {"1/16", "1/12", "1/8", "1/6", "1/4", "1/2", "1/1"}
  for t = 1, track_mod.NUM_TRACKS do
    params:add_option("division_" .. t, "track " .. t .. " division", div_names, 1)
    params:set_action("division_" .. t, function(val)
      ctx.tracks[t].division = val
    end)
  end

  -- voice params are set up by the entrypoint
  -- (nb params for norns, MIDI channel params for seamstress)

  -- build initial scale
  M.rebuild_scale(ctx)

  -- grid (pluggable: config.grid_provider selects backend)
  ctx.g = grid_provider.connect(config.grid_provider, config.grid_opts)
  ctx.g.key = function(x, y, z)
    grid_ui.key(ctx, x, y, z)
    ctx.grid_dirty = true
  end

  -- grid redraw metro
  ctx.grid_metro = metro.init()
  ctx.grid_metro.time = 1 / 30
  ctx.grid_metro.event = function()
    if ctx.grid_dirty then
      grid_ui.redraw(ctx)
      ctx.grid_dirty = false
    end
  end
  ctx.grid_metro:start()

  return ctx
end

function M.rebuild_scale(ctx)
  local root = params:get("root_note")
  local scale_type = SCALE_NAMES[params:get("scale_type")]
  ctx.scale_notes = scale_mod.build_scale(root, scale_type)
end

function M.redraw(ctx)
   -- screen UI: minimal info display
  screen.clear()
  screen.level(15)
  screen.move(5, 10)
  screen.text("re.kriate")
  screen.level(8)
  screen.move(5, 25)
  screen.text("track " .. ctx.active_track .. " | " .. ctx.active_page)
  screen.move(5, 40)
  screen.text(ctx.playing and "playing" or "stopped")
  screen.update()
end

function M.key(ctx, n, z)
  if n == 2 and z == 1 then
    -- K2: play/stop
    if ctx.playing then
      sequencer.stop(ctx)
    else
      sequencer.start(ctx)
    end
  elseif n == 3 and z == 1 then
    -- K3: reset playheads
    sequencer.reset(ctx)
  end
  ctx.grid_dirty = true
end

function M.enc(ctx, n, d)
  if n == 1 then
    -- E1: select track
    ctx.active_track = util.clamp(ctx.active_track + d, 1, track_mod.NUM_TRACKS)
  elseif n == 2 then
    -- E2: select page
    local pages = grid_ui.PAGES
    local idx = 1
    for i, p in ipairs(pages) do
      if p == ctx.active_page then idx = i; break end
    end
    idx = util.clamp(idx + d, 1, #pages)
    ctx.active_page = pages[idx]
  end
  ctx.grid_dirty = true
end

function M.cleanup(ctx)
  sequencer.stop(ctx)
  if ctx.voices then
    for _, voice in ipairs(ctx.voices) do
      voice:all_notes_off()
    end
  end
  if ctx.grid_metro then
    ctx.grid_metro:stop()
  end
  if ctx.g and ctx.g.cleanup then
    ctx.g:cleanup()
  end
end

return M
