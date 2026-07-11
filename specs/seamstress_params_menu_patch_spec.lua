-- specs/seamstress_params_menu_patch_spec.lua
-- Unit coverage for the extracted seamstress params-menu key-navigation
-- patch module (lib/seamstress/params_menu_patch.lua).
--
-- Full behavioral coverage of the patch (page up/down, escape-mode
-- handling per paramsMenu.mode, backspace interception, unknown-keycode
-- guarding in both windows) already lives in
-- specs/seamstress_entrypoint_spec.lua's "seamstress params-menu key
-- navigation patch" describe block, which exercises this exact logic end
-- to end via seamstress.lua's init() (now delegating to this module) and
-- is left unmodified by this extraction -- it continues to pass, which is
-- the behavior-preservation evidence for the move.
--
-- This spec covers module structure and a couple of smoke-level checks
-- calling install() directly against mocked seamstress-runtime globals.

package.path = package.path .. ";./?.lua"

local function make_keycodes_mock()
  local kc = {}
  kc.__index = function(t, index)
    if t == kc then
      if type(index) == "number" and index >= 0 and index <= 255 then
        return string.char(index)
      end
      return nil
    end
  end
  setmetatable(kc, kc)
  kc[27] = {name = "escape"}
  kc[8] = {name = "backspace"}
  kc[13] = {name = "return"}
  kc.modifier = function() return {} end
  return kc
end

describe("lib/seamstress/params_menu_patch", function()
  local UNSET = {}
  local saved_module
  local saved_keycodes
  local saved_seamstress
  local saved_params_menu

  before_each(function()
    saved_module = package.loaded["lib/seamstress/params_menu_patch"] == nil and UNSET
      or package.loaded["lib/seamstress/params_menu_patch"]
    package.loaded["lib/seamstress/params_menu_patch"] = nil

    saved_keycodes = package.loaded["keycodes"] == nil and UNSET or package.loaded["keycodes"]
    package.loaded["keycodes"] = make_keycodes_mock()

    saved_seamstress = rawget(_G, "_seamstress") == nil and UNSET or rawget(_G, "_seamstress")
    saved_params_menu = rawget(_G, "paramsMenu") == nil and UNSET or rawget(_G, "paramsMenu")

    rawset(_G, "_seamstress", {
      screen = { key = function() end },
    })
    rawset(_G, "paramsMenu", {
      key = function() end,
      redraw = function() end,
      mode = 1, -- mEDIT
    })
  end)

  local function restore(key, value, is_global)
    local resolved = nil
    if value ~= UNSET then
      resolved = value
    end
    if is_global then
      rawset(_G, key, resolved)
    else
      package.loaded[key] = resolved
    end
  end

  after_each(function()
    restore("lib/seamstress/params_menu_patch", saved_module, false)
    restore("keycodes", saved_keycodes, false)
    restore("_seamstress", saved_seamstress, true)
    restore("paramsMenu", saved_params_menu, true)
  end)

  it("exposes an install function", function()
    local patch = require("lib/seamstress/params_menu_patch")
    assert.is_table(patch)
    assert.is_function(patch.install)
  end)

  it("install() replaces _seamstress.screen.key without erroring", function()
    local original = _seamstress.screen.key
    local patch = require("lib/seamstress/params_menu_patch")

    assert.has_no.errors(function()
      patch.install()
    end)

    assert.is_function(_seamstress.screen.key)
    assert.are_not.equal(original, _seamstress.screen.key)
  end)

  it("routes page-up in the params window to paramsMenu.key backspace (smoke)", function()
    local calls = {}
    paramsMenu.key = function(char, modifiers, is_repeat, state)
      table.insert(calls, char)
    end

    local patch = require("lib/seamstress/params_menu_patch")
    patch.install()

    _seamstress.screen.key(0x4000004B, 0, false, 1, 2)

    assert.are.equal(1, #calls)
    assert.are.equal("backspace", calls[1].name)
  end)

  it("falls through to the original dispatch for a normal key in the params window", function()
    local orig_called_with
    _seamstress.screen.key = function(symbol, modifiers_mask, is_repeat, state, window)
      orig_called_with = { symbol, modifiers_mask, is_repeat, state, window }
    end

    local patch = require("lib/seamstress/params_menu_patch")
    patch.install()

    -- 'a' key (ASCII 97) is present in the keycodes mock and isn't one of
    -- the intercepted symbols, so it should fall through unchanged.
    _seamstress.screen.key(97, 0, false, 1, 2)

    assert.is_not_nil(orig_called_with)
    assert.are.same({ 97, 0, false, 1, 2 }, orig_called_with)
  end)
end)
