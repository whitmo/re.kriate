-- lib/seamstress/keyboard.lua
-- Keyboard input handling for seamstress
-- space = play/stop, r = reset, 1-4 = track select
-- q/w/e/t/y = page select (trigger/note/octave/duration/velocity)
-- d = cycle direction mode for active track
-- ctrl+1-9 = save pattern, shift+1-9 = load pattern

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

  -- Function keys: seamstress keycodes.lua returns a table {name = "F1"} for
  -- non-printable keys. Match on the name before the string-only guard below,
  -- so Ansible KEY 1/2 emulation actually fires.
  if type(char) == "table" then
    if char.name == "F1" then
      ctx.time_held = not ctx.time_held
      ctx.grid_dirty = true
    elseif char.name == "F2" then
      ctx.active_page = "alt_track"
      ctx.grid_dirty = true
    end
    return
  end

  if type(char) ~= "string" then return end

  if char == " " then
    -- Controller-adapter contract (docs/event-layers.md): interfaces emit
    -- behavioral commands; behavior.wire_commands (installed by app.init)
    -- performs them. The keyboard is the first migrated adapter.
    if ctx.playing then
      ctx.events:emit("cmd:transport:stop", {})
    else
      ctx.events:emit("cmd:transport:play", {})
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
    ctx.prob_held = not ctx.prob_held
  elseif char == "a" and modifiers and modifiers.ctrl then
    ctx.active_page = "alt_track"
    set_status(ctx, "alt-track page")
  elseif char == "r" then
    ctx.events:emit("cmd:transport:reset", {})
  elseif char >= "1" and char <= "9" and modifiers and modifiers.ctrl and ctx.patterns then
    local slot = tonumber(char)
    ctx.events:emit("cmd:pattern:save", {slot = slot})
    ctx.active_pattern = slot
    ctx.pattern_message = {text = "saved " .. slot, time = os.clock()}
  elseif char >= "1" and char <= "9" and modifiers and modifiers.shift and ctx.patterns then
    local slot = tonumber(char)
    if pattern.is_populated(ctx.patterns, slot) then
      ctx.events:emit("cmd:pattern:load", {slot = slot})
      ctx.active_pattern = slot
      -- cmd:pattern:load resolves synchronously (Bus:emit calls handlers
      -- inline), so ctx.cued_pattern_slot already reflects the outcome:
      -- cued (still playing, quantized) vs. loaded (stopped, immediate).
      local text = (ctx.cued_pattern_slot == slot) and ("cued " .. slot) or ("loaded " .. slot)
      ctx.pattern_message = {text = text, time = os.clock()}
    end
  elseif char >= "1" and char <= "4" then
    ctx.active_track = tonumber(char)
    if ctx.events then
      ctx.events:emit("track:select", {track=ctx.active_track})
    end
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
      ctx.loop_first_y = nil
    end
  elseif KEY_PAGE[char] then
    local target = KEY_PAGE[char]
    local old_page = ctx.active_page
    if ctx.active_page == target and grid_ui.EXTENDED_PAGES[target] then
      ctx.active_page = grid_ui.EXTENDED_PAGES[target]
    elseif EXTENDED_TO_PRIMARY[ctx.active_page] == target then
      ctx.active_page = target
    else
      ctx.active_page = target
    end
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
    end
  end

  ctx.grid_dirty = true
end

return M
