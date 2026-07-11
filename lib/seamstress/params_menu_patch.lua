-- lib/seamstress/params_menu_patch.lua
-- Patch params-menu key handler to support page up/down navigation
-- and guard against unmapped SDL keycodes that crash params-menu.lua:187
-- (seamstress keycodes.lua has no entries for page up/down, so char is nil)

local M = {}

function M.install()
  local SDL_PAGEUP = 0x4000004B
  local SDL_PAGEDOWN = 0x4000004E
  local SDL_BACKSPACE = 8
  local keycodes = require("keycodes")
  local orig_screen_dispatch = _seamstress.screen.key
  _seamstress.screen.key = function(symbol, modifiers_mask, is_repeat, state, window)
    if window == 2 then
      if symbol == SDL_PAGEUP and state == 1 then
        -- Page Up: exit param group (go up to parent level)
        paramsMenu.key({name = "backspace"}, keycodes.modifier(modifiers_mask), false, 1)
        paramsMenu.redraw()
        return
      elseif symbol == SDL_PAGEDOWN and state == 1 then
        -- Page Down: enter param group (drill into current item)
        paramsMenu.key({name = "return"}, keycodes.modifier(modifiers_mask), false, 1)
        paramsMenu.redraw()
        return
      elseif symbol == SDL_BACKSPACE then
        -- Backspace: dispatch directly to params-menu instead of falling through
        -- to orig_screen_dispatch (which may not reach paramsMenu.key if the
        -- C runtime caches the pre-patch function reference)
        paramsMenu.key({name = "backspace"}, keycodes.modifier(modifiers_mask), is_repeat, state)
        paramsMenu.redraw()
        return
      elseif keycodes[symbol] == nil then
        -- Unknown keycode (no entry in keycodes table) — consume to prevent crash
        return
      end
      -- Escape in params edit/map modes: exit group (alt navigation for laptops)
      -- Only intercept in mEDIT(1)/mMAP(2) where escape has no default action;
      -- let it pass through for mTEXT/mPSETSAVE/mPSETEDIT where it cancels input
      local char = keycodes[symbol]
      if type(char) == "table" and char.name == "escape" and state == 1
          and (paramsMenu.mode == 1 or paramsMenu.mode == 2) then
        paramsMenu.key({name = "backspace"}, keycodes.modifier(modifiers_mask), false, 1)
        paramsMenu.redraw()
        return
      end
    elseif window == 1 and keycodes[symbol] == nil then
      -- Unknown keycode in main window — consume (keyboard.lua also guards)
      return
    end
    return orig_screen_dispatch(symbol, modifiers_mask, is_repeat, state, window)
  end
end

return M
