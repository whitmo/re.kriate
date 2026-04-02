-- seamstress.lua: kria sequencer entrypoint for seamstress
--
-- Grid: full kria grid UI (same as norns) with virtual grid features:
--   - Ctrl+click = hold keys, Ctrl+Shift+click = lock/toggle keys
--   - Esc = release all locked keys
--   - Ctrl+Shift+T = cycle visual theme
--
-- Keyboard: space=play/stop, r=reset, 1-4=track, q/w/e/t/y=page
--
-- Requires MIDI device on port 1 (configurable via params)

-- seamstress doesn't add the script dir to package.path (norns does)
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

local log = require("lib/log")
local app = require("lib/app")
local sprite_voice = require("lib/voices/sprite")
local sprite_render = require("lib/seamstress/sprite_render")
local keyboard = require("lib/seamstress/keyboard")
local grid_render = require("lib/seamstress/grid_render")
local help_overlay = require("lib/seamstress/help_overlay")
local track_mod = require("lib/track")

local ctx

function init()
  log.session_start()

  -- Configure grid renderer (size, theme, protocol)
  grid_render.configure({
    size = 128,        -- 64, 128, or 256
    theme = "yellow",  -- yellow, red, orange, white
    protocol = "mext", -- mext (varibright), series, 40h
  })

  -- Size window to match configured grid
  if screen.set_size then
    screen.set_size(grid_render.screen_width(), grid_render.screen_height())
  end

  -- Sprite voices (additive visual output, one per track)
  local sprite_voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    sprite_voices[t] = sprite_voice.new(t)
  end

  local rc = grid_render.get_config()
  ctx = app.init({
    midi_dev = midi.connect(1),
    sprite_voices = sprite_voices,
    grid_provider = "simulated",
    grid_opts = {
      cols = rc.cols,
      rows = rc.rows,
      mirror_monome = true,
    },
  })

  -- Keyboard input — track modifiers for grid gestures before forwarding
  screen.key = log.wrap(function(char, modifiers, is_repeat, state)
    -- Always update modifier state (even on key release) for hold/lock gestures
    grid_render.set_modifier("ctrl", modifiers and (modifiers.ctrl or modifiers.super) or false)
    grid_render.set_modifier("shift", modifiers and modifiers.shift or false)

    -- Help overlay toggle (? key)
    if char == "?" and state == 1 and not is_repeat then
      ctx.help_visible = not ctx.help_visible
      if screen.set_size then
        if ctx.help_visible then
          screen.set_size(help_overlay.WIDTH, help_overlay.HEIGHT)
        else
          screen.set_size(grid_render.screen_width(), grid_render.screen_height())
        end
      end
      return
    end

    -- Esc dismisses help overlay if visible, otherwise releases locked keys
    if char == "escape" and state == 1 then
      if ctx.help_visible then
        ctx.help_visible = false
        if screen.set_size then
          screen.set_size(grid_render.screen_width(), grid_render.screen_height())
        end
        return
      end
      grid_render.release_locked_keys(ctx.g)
    end

    -- Ctrl+Shift+T cycles visual theme
    if char == "t" and state == 1 and modifiers and modifiers.ctrl and modifiers.shift then
      local order = grid_render.THEME_ORDER
      local cur = grid_render.get_config().theme
      local idx = 1
      for i, name in ipairs(order) do
        if name == cur then idx = i; break end
      end
      grid_render.configure({theme = order[(idx % #order) + 1]})
      return
    end

    keyboard.key(ctx, char, modifiers, is_repeat, state)
  end, "screen.key")

  -- Mouse input → simulated grid (gesture mode determined by modifier state)
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
  if ctx and ctx.help_visible then
    help_overlay.draw(screen, help_overlay.WIDTH, help_overlay.HEIGHT)
    screen.refresh()
    return
  end
  -- Black canvas background
  screen.color(0, 0, 0, 255)
  screen.move(1, 1)
  screen.rect_fill(grid_render.screen_width(), grid_render.screen_height())
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
  log.info("cleanup complete")
  log.close()
end
