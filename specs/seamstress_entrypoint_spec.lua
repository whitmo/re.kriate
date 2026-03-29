-- specs/seamstress_entrypoint_spec.lua
-- Tests for seamstress platform entrypoint wiring

package.path = package.path .. ";./?.lua"

local UNSET = {}

local STUBBED_MODULES = {
  "lib/app",
  "lib/log",
  "lib/track",
  "lib/voices/sprite",
  "lib/seamstress/screen_ui",
  "lib/seamstress/sprite_render",
  "lib/seamstress/keyboard",
  "lib/seamstress/grid_render",
}

local ORIGINAL_MODULES = {}
for _, name in ipairs(STUBBED_MODULES) do
  ORIGINAL_MODULES[name] = package.loaded[name] == nil and UNSET or package.loaded[name]
end

local ORIGINAL_GLOBALS = {
  init = rawget(_G, "init") == nil and UNSET or rawget(_G, "init"),
  redraw = rawget(_G, "redraw") == nil and UNSET or rawget(_G, "redraw"),
  cleanup = rawget(_G, "cleanup") == nil and UNSET or rawget(_G, "cleanup"),
  midi = rawget(_G, "midi") == nil and UNSET or rawget(_G, "midi"),
  screen = rawget(_G, "screen") == nil and UNSET or rawget(_G, "screen"),
  metro = rawget(_G, "metro") == nil and UNSET or rawget(_G, "metro"),
}

local captured_app_config
local captured_ctx
local app_cleanup_ctx
local info_messages
local log_closed

local function restore_modules()
  for name, original in pairs(ORIGINAL_MODULES) do
    package.loaded[name] = original == UNSET and nil or original
  end
end

local function restore_globals()
  for name, original in pairs(ORIGINAL_GLOBALS) do
    rawset(_G, name, original == UNSET and nil or original)
  end
end

local function install_stubs()
  captured_app_config = nil
  captured_ctx = nil
  app_cleanup_ctx = nil
  info_messages = {}
  log_closed = false

  rawset(_G, "midi", {
    connect = function(port)
      return { port = port }
    end,
  })

  rawset(_G, "screen", {
    clear = function() end,
    color = function() end,
    move = function() end,
    rect_fill = function() end,
    refresh = function() end,
  })

  rawset(_G, "metro", {
    init = function()
      return {
        time = 0,
        event = nil,
        _started = false,
        _stopped = false,
        start = function(self)
          self._started = true
        end,
        stop = function(self)
          self._stopped = true
        end,
      }
    end,
  })

  package.loaded["lib/app"] = {
    init = function(config)
      captured_app_config = config
      captured_ctx = {
        g = {
          cleanup = function() end,
        },
        voices = config.voices or {},
        sprite_voices = config.sprite_voices or {},
      }
      return captured_ctx
    end,
    cleanup = function(ctx)
      app_cleanup_ctx = ctx
    end,
  }

  package.loaded["lib/log"] = {
    session_start = function() end,
    info = function(msg)
      info_messages[#info_messages + 1] = msg
    end,
    warn = function() end,
    error = function() end,
    close = function()
      log_closed = true
    end,
    wrap = function(fn, label)
      return fn
    end,
  }

  package.loaded["lib/track"] = {
    NUM_TRACKS = 4,
  }

  package.loaded["lib/voices/sprite"] = {
    new = function(track_num)
      return {
        track_num = track_num,
        all_notes_off = function() end,
      }
    end,
  }

  package.loaded["lib/seamstress/screen_ui"] = {}
  package.loaded["lib/seamstress/sprite_render"] = {
    draw = function() end,
  }
  package.loaded["lib/seamstress/keyboard"] = {
    key = function() end,
  }
  package.loaded["lib/seamstress/grid_render"] = {
    draw = function() end,
    handle_click = function() end,
  }
end

describe("seamstress entrypoint", function()
  before_each(function()
    install_stubs()
    dofile("seamstress.lua")
  end)

  after_each(function()
    restore_modules()
    restore_globals()
  end)

  it("passes simulated provider with monome mirroring into app.init", function()
    init()

    assert.are.equal("simulated", captured_app_config.grid_provider)
    assert.is_table(captured_app_config.grid_opts)
    assert.is_true(captured_app_config.grid_opts.mirror_monome)
  end)

  it("logs cleanup completion and stops the screen metro", function()
    init()
    assert.is_true(captured_ctx.screen_metro._started)

    cleanup()

    local found_cleanup_log = false
    for _, msg in ipairs(info_messages) do
      if msg == "cleanup complete" then
        found_cleanup_log = true
        break
      end
    end

    assert.is_true(found_cleanup_log, "expected cleanup to emit a completion log line")
    assert.are.equal(captured_ctx, app_cleanup_ctx)
    assert.is_true(captured_ctx.screen_metro._stopped)
    assert.is_true(log_closed)
  end)
end)
