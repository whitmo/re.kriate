-- lib/seamstress/keyboard.lua
-- Keyboard input handling for seamstress
-- space = play/stop, r = reset, 1-4 = track select
-- q/w/e/t/y = page select (trigger/note/octave/duration/velocity)
-- ctrl+1-9 = save pattern, shift+1-9 = load pattern

local sequencer = require("lib/sequencer")
local pattern = require("lib/pattern")

local M = {}

function M.key(ctx, char, modifiers, is_repeat, state)
  if state ~= 1 then return end
  if is_repeat then return end

  if char == " " then
    if ctx.playing then
      sequencer.stop(ctx)
    else
      sequencer.start(ctx)
    end
  elseif char == "r" then
    sequencer.reset(ctx)
  elseif char >= "1" and char <= "9" and modifiers and modifiers.ctrl and ctx.patterns then
    pattern.save(ctx, tonumber(char))
  elseif char >= "1" and char <= "9" and modifiers and modifiers.shift and ctx.patterns then
    pattern.load(ctx, tonumber(char))
  elseif char >= "1" and char <= "4" then
    ctx.active_track = tonumber(char)
  elseif char == "q" then
    ctx.active_page = "trigger"
  elseif char == "w" then
    ctx.active_page = "note"
  elseif char == "e" then
    ctx.active_page = "octave"
  elseif char == "t" then
    ctx.active_page = "duration"
  elseif char == "y" then
    ctx.active_page = "velocity"
  end

  ctx.grid_dirty = true
end

return M
