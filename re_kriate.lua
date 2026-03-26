-- re_kriate: a kria sequencer for norns
-- inspired by monome ansible's kria
--
-- E1: select track
-- E2: select page
-- K2: play/stop
-- K3: reset
--
-- Grid row 8: navigation
--   1-4: track select
--   6-10: page select (trig/note/oct/dur/vel)
--   12: loop edit (hold)
--   16: play/stop

local log = require("lib/log")
local app = require("lib/app")
local nb_voice = require("lib/norns/nb_voice")
local track_mod = require("lib/track")

local ctx

function init()
  log.session_start()

  local nb = require("nb")
  nb.voice_count = track_mod.NUM_TRACKS
  nb:init()

  -- nb voice params
  for t = 1, track_mod.NUM_TRACKS do
    nb:add_param("voice_" .. t, "voice " .. t)
  end
  nb:add_player_params()

  -- Create voice wrappers
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = nb_voice.new("voice_" .. t)
  end

  ctx = app.init({ voices = voices, grid_provider = "monome" })

  -- Screen refresh metro at 15fps
  ctx.screen_metro = metro.init()
  ctx.screen_metro.time = 1 / 15
  ctx.screen_metro.event = function()
    redraw()
  end
  ctx.screen_metro:start()
end

function redraw()
  app.redraw(ctx)
end

function key(n, z)
  app.key(ctx, n, z)
end

function enc(n, d)
  app.enc(ctx, n, d)
end

function cleanup()
  if not ctx then return end
  if ctx.screen_metro then
    ctx.screen_metro:stop()
  end
  app.cleanup(ctx)
  log.close()
end
