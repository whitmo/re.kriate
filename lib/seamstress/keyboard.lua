-- lib/seamstress/keyboard.lua
-- Keyboard input handling for seamstress
-- space = play/stop, r = reset, 1-4 = track select
-- q/w/e/t/y = page select (trigger/note/octave/duration/velocity)
-- d = cycle direction mode for active track
-- ctrl+1-9 = save pattern, shift+1-9 = load pattern

local sequencer = require("lib/sequencer")
local pattern = require("lib/pattern")
local grid_ui = require("lib/grid_ui")
local app = require("lib/app")
local direction_mod = require("lib/direction")

local M = {}

-- Keyboard-to-page mapping
local KEY_PAGE = {q = "trigger", w = "note", e = "octave", t = "duration", y = "velocity"}

-- Reverse lookup: extended -> primary
local EXTENDED_TO_PRIMARY = {ratchet = "trigger", alt_note = "note", glide = "octave"}

local function set_status(ctx, text)
  ctx.active_pattern = nil
  ctx.pattern_message = {text = text, time = os.clock()}
end

function M.key(ctx, char, modifiers, is_repeat, state)
  if state ~= 1 then return end
  if is_repeat then return end

  if char == " " then
    if ctx.playing then
      sequencer.stop(ctx)
    else
      sequencer.start(ctx)
    end
  elseif char == "s" and modifiers and modifiers.ctrl then
    local ok, path_or_err = app.save_pattern_bank(ctx)
    if ok then
      set_status(ctx, "saved bank")
    else
      set_status(ctx, "save failed: " .. tostring(path_or_err))
    end
  elseif char == "l" and modifiers and modifiers.ctrl then
    local ok, err = app.load_pattern_bank(ctx)
    if ok then
      set_status(ctx, "loaded bank")
    else
      set_status(ctx, "load failed: " .. tostring(err))
    end
  elseif char == "b" and modifiers and modifiers.ctrl then
    app.list_pattern_banks(ctx)
  elseif char == "d" and modifiers and modifiers.ctrl and modifiers.shift then
    local ok, err = app.delete_pattern_bank(ctx)
    if ok then
      set_status(ctx, "deleted bank")
    else
      set_status(ctx, "delete failed: " .. tostring(err))
    end
  elseif char == "p" and modifiers and modifiers.ctrl then
    ctx.active_page = "probability"
    set_status(ctx, "probability page")
  elseif char == "a" and modifiers and modifiers.ctrl then
    ctx.active_page = "alt_track"
    set_status(ctx, "alt-track page")
  elseif char == "r" then
    sequencer.reset(ctx)
  elseif char >= "1" and char <= "9" and modifiers and modifiers.ctrl and ctx.patterns then
    local slot = tonumber(char)
    pattern.save(ctx, slot)
    ctx.active_pattern = slot
    ctx.pattern_message = {text = "saved " .. slot, time = os.clock()}
  elseif char >= "1" and char <= "9" and modifiers and modifiers.shift and ctx.patterns then
    local slot = tonumber(char)
    if pattern.is_populated(ctx.patterns, slot) then
      pattern.load(ctx, slot)
      ctx.active_pattern = slot
      ctx.pattern_message = {text = "loaded " .. slot, time = os.clock()}
    end
  elseif char >= "1" and char <= "4" then
    ctx.active_track = tonumber(char)
  elseif char == "d" then
    local track = ctx.tracks[ctx.active_track]
    local modes = direction_mod.MODES
    local cur = track.direction or "forward"
    local idx = 1
    for i, m in ipairs(modes) do
      if m == cur then idx = i; break end
    end
    track.direction = modes[(idx % #modes) + 1]
  elseif char == "l" and not (modifiers and modifiers.ctrl) then
    ctx.loop_held = not ctx.loop_held
    if not ctx.loop_held then
      ctx.loop_first_press = nil
    end
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
