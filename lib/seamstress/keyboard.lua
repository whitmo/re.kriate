-- lib/seamstress/keyboard.lua
-- Keyboard input handling for seamstress
-- space = play/stop, r = reset, 1-4 = track select
-- q/w/e/t/y = page select (trigger/note/octave/duration/velocity)
-- ctrl+1-9 = save pattern, shift+1-9 = load pattern

local sequencer = require("lib/sequencer")
local pattern = require("lib/pattern")
local grid_ui = require("lib/grid_ui")

local M = {}

-- Keyboard-to-page mapping
local KEY_PAGE = {q = "trigger", w = "note", e = "octave", t = "duration", y = "velocity"}

-- Reverse lookup: extended -> primary
local EXTENDED_TO_PRIMARY = {ratchet = "trigger", alt_note = "note", glide = "octave"}

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
  elseif KEY_PAGE[char] then
    local target = KEY_PAGE[char]
    if ctx.active_page == target and grid_ui.EXTENDED_PAGES[target] then
      ctx.active_page = grid_ui.EXTENDED_PAGES[target]
    elseif EXTENDED_TO_PRIMARY[ctx.active_page] == target then
      ctx.active_page = target
    else
      ctx.active_page = target
    end
  end

  ctx.grid_dirty = true
end

return M
