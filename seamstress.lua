-- seamstress.lua: kria sequencer entrypoint for seamstress
--
-- Grid: full kria grid UI (same as norns)
-- Keyboard: space=play/stop, r=reset, 1-4=track, q/w/e/t/y=page
--
-- Requires MIDI device on port 1 (configurable via params)

-- seamstress doesn't add the script dir to package.path (norns does)
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

local log = require("lib/log")
local app = require("lib/app")
local sprite_voice = require("lib/voices/sprite")
local screen_ui = require("lib/seamstress/screen_ui")
local sprite_render = require("lib/seamstress/sprite_render")
local keyboard = require("lib/seamstress/keyboard")
local grid_render = require("lib/seamstress/grid_render")
local track_mod = require("lib/track")
local log = require("lib/log")

local GRID_WIDTH = 16 * 16  -- cols * pitch
local GRID_HEIGHT = 8 * 16  -- rows * pitch

local ctx

function init()
  log.session_start()

  -- Size window to the simulated grid so it fills the view
  if screen.set_size then
    screen.set_size(GRID_WIDTH, GRID_HEIGHT)
  end

  -- Sprite voices (additive visual output, one per track)
  local sprite_voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    sprite_voices[t] = sprite_voice.new(t)
  end

  ctx = app.init({
    midi_dev = midi.connect(1),
    sprite_voices = sprite_voices,
    screen_mod = screen_ui,
    grid_provider = "simulated",
  })

  -- Keyboard input
  screen.key = log.wrap(function(char, modifiers, is_repeat, state)
    keyboard.key(ctx, char, modifiers, is_repeat, state)
  end, "screen.key")

  -- Mouse input → simulated grid
  screen.click = log.wrap(function(x, y, state, button)
    grid_render.handle_click(ctx.g, x, y, state, button)
  end, "grid_click")

  -- Screen refresh metro
  ctx.screen_metro = metro.init()
  ctx.screen_metro.time = 1 / 30
  ctx.screen_metro.event = log.wrap(function()
    redraw()
  end, "screen_metro.event")
  ctx.screen_metro:start()

  log.info("init complete")
end

function redraw()
  screen.clear()
  -- Black canvas background
  screen.color(0, 0, 0, 255)
  screen.move(1, 1)
  screen.rect_fill(256, 128)
  -- Simulated grid
  grid_render.draw(ctx.g, screen)
  -- Sprites on top
  sprite_render.draw(ctx)
  screen.refresh()
end

function cleanup()
  app.cleanup(ctx)
  if ctx and ctx.screen_metro then
    ctx.screen_metro:stop()
  end
  log.close()
end
