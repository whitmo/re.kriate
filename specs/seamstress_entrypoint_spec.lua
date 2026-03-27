-- specs/seamstress_entrypoint_spec.lua
-- Focused seamstress entrypoint wiring coverage for keyboard persistence hooks

package.path = package.path .. ";./?.lua"

local original_modules = {}
local stubbed_modules = {
  "lib/app",
  "lib/log",
  "lib/seamstress/keyboard",
}

local save_calls
local load_calls
local init_ctx

local function restore_modules()
  for _, name in ipairs(stubbed_modules) do
    package.loaded[name] = original_modules[name]
  end
end

local function install_stubs()
  save_calls = {}
  load_calls = {}
  init_ctx = {
    active_pattern = 2,
    grid_dirty = false,
    g = { cleanup = function() end },
  }

  for _, name in ipairs(stubbed_modules) do
    original_modules[name] = package.loaded[name]
    package.loaded[name] = nil
  end

  package.loaded["lib/log"] = {
    session_start = function() end,
    close = function() end,
    info = function() end,
    warn = function() end,
    error = function() end,
    write = function() end,
    wrap = function(fn)
      return fn
    end,
  }

  package.loaded["lib/app"] = {
    init = function()
      return init_ctx
    end,
    cleanup = function() end,
    save_pattern_bank = function(ctx)
      table.insert(save_calls, ctx)
      return true, "/tmp/test-bank.krp"
    end,
    load_pattern_bank = function(ctx)
      table.insert(load_calls, ctx)
      return true
    end,
  }

  package.loaded["lib/seamstress/keyboard"] = nil
end

describe("seamstress entrypoint keyboard persistence wiring", function()
  before_each(function()
    install_stubs()

    rawset(_G, "clock", {
      get_beats = function() return 0 end,
      run = function() return 1 end,
      cancel = function() end,
      sync = function() end,
    })

    rawset(_G, "params", {
      add_separator = function() end,
      add_group = function() end,
      add_number = function() end,
      add_option = function() end,
      add_text = function() end,
      set_action = function() end,
      get = function() return 1 end,
      set = function() end,
    })

    rawset(_G, "grid", {
      connect = function()
        return {
          key = nil,
          led = function() end,
          refresh = function() end,
          all = function() end,
          cleanup = function() end,
        }
      end,
    })

    rawset(_G, "metro", {
      init = function()
        return {
          time = 0,
          event = nil,
          start = function() end,
          stop = function() end,
        }
      end,
    })

    rawset(_G, "screen", {
      clear = function() end,
      color = function() end,
      move = function() end,
      rect_fill = function() end,
      refresh = function() end,
    })

    rawset(_G, "midi", {
      connect = function()
        return {
          note_on = function() end,
          note_off = function() end,
          cc = function() end,
        }
      end,
    })

    package.loaded["musicutil"] = {
      generate_scale = function(root, _, octaves)
        local notes = {}
        for i = 1, octaves * 7 do
          notes[i] = root + i - 1
        end
        return notes
      end,
    }

    dofile("seamstress.lua")
    init()
  end)

  after_each(function()
    restore_modules()
    package.loaded["musicutil"] = nil
    init = nil
    redraw = nil
    cleanup = nil
  end)

  it("routes ctrl+s through screen.key to app.save_pattern_bank", function()
    screen.key("s", { ctrl = true }, false, 1)

    assert.are.equal(1, #save_calls)
    assert.are.equal(init_ctx, save_calls[1])
    assert.are.equal("saved bank", init_ctx.pattern_message.text)
    assert.is_nil(init_ctx.active_pattern)
    assert.is_true(init_ctx.grid_dirty)
  end)

  it("routes ctrl+l through screen.key to app.load_pattern_bank", function()
    screen.key("l", { ctrl = true }, false, 1)

    assert.are.equal(1, #load_calls)
    assert.are.equal(init_ctx, load_calls[1])
    assert.are.equal("loaded bank", init_ctx.pattern_message.text)
    assert.is_nil(init_ctx.active_pattern)
    assert.is_true(init_ctx.grid_dirty)
  end)
end)
