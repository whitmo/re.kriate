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

local app = require("lib/app")
local nb_voice = require("lib/norns/nb_voice")
local track_mod = require("lib/track")

local ctx

function init()
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

  ctx = app.init({ voices = voices })
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
  app.cleanup(ctx)
end
