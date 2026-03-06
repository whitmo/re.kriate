-- re_kriate_seamstress: kria sequencer for seamstress
--
-- Grid: full kria grid UI (same as norns)
-- Keyboard: space=play/stop, r=reset, 1-4=track, q/w/e/t/y=page
--
-- Requires MIDI device on port 1 (configurable via params)

local app = require("lib/app")
local midi_voice = require("lib/voices/midi")
local screen_ui = require("lib/seamstress/screen_ui")
local keyboard = require("lib/seamstress/keyboard")
local track_mod = require("lib/track")

local ctx

function init()
  -- MIDI device setup
  local midi_dev = midi.connect(1)

  -- Create MIDI voices (one per track, channel = track number)
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = midi_voice.new(midi_dev, t)
  end

  -- MIDI channel params
  params:add_separator("midi_config", "MIDI")
  for t = 1, track_mod.NUM_TRACKS do
    params:add_number("midi_ch_" .. t, "track " .. t .. " channel", 1, 16, t)
    params:set_action("midi_ch_" .. t, function(val)
      voices[t].channel = val
    end)
  end

  ctx = app.init({
    voices = voices,
    screen_mod = screen_ui,
  })

  -- Keyboard input
  screen.key = function(char, modifiers, is_repeat, state)
    keyboard.key(ctx, char, modifiers, is_repeat, state)
  end

  -- Screen refresh metro
  ctx.screen_metro = metro.init()
  ctx.screen_metro.time = 1 / 15
  ctx.screen_metro.event = function()
    redraw()
  end
  ctx.screen_metro:start()
end

function redraw()
  screen_ui.redraw(ctx)
end

function cleanup()
  app.cleanup(ctx)
  if ctx and ctx.screen_metro then
    ctx.screen_metro:stop()
  end
end
