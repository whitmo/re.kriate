-- specs/seamstress_entrypoint_spec.lua
-- Seamstress entrypoint wiring coverage

package.path = package.path .. ";./?.lua"

local UNSET = {}

local function capture_modules(names)
  local saved = {}
  for _, name in ipairs(names) do
    saved[name] = package.loaded[name] == nil and UNSET or package.loaded[name]
  end
  return saved
end

local function restore_modules(saved)
  for name, original in pairs(saved) do
    package.loaded[name] = original == UNSET and nil or original
  end
end

local function capture_globals(names)
  local saved = {}
  for _, name in ipairs(names) do
    saved[name] = rawget(_G, name) == nil and UNSET or rawget(_G, name)
  end
  return saved
end

local function restore_globals(saved)
  for name, original in pairs(saved) do
    rawset(_G, name, original == UNSET and nil or original)
  end
end

describe("seamstress entrypoint keyboard persistence wiring", function()
  local saved_modules
  local saved_globals

  local save_calls
  local load_calls
  local list_calls
  local init_ctx
  local save_ok
  local save_value
  local load_ok
  local load_value

  before_each(function()
    saved_modules = capture_modules({
      "lib/app",
      "lib/log",
      "lib/seamstress/keyboard",
      "lib/seamstress/help_overlay",
      "musicutil",
    })
    saved_globals = capture_globals({
      "clock",
      "params",
      "grid",
      "metro",
      "screen",
      "midi",
      "init",
      "redraw",
      "cleanup",
    })

    save_calls = {}
    load_calls = {}
    list_calls = {}
    save_ok = true
    save_value = "/tmp/test-bank.krp"
    load_ok = true
    load_value = nil
    init_ctx = {
      active_pattern = 2,
      grid_dirty = false,
      g = { cleanup = function() end },
    }

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
        return save_ok, save_value
      end,
      load_pattern_bank = function(ctx)
        table.insert(load_calls, ctx)
        return load_ok, load_value
      end,
      list_pattern_banks = function(ctx)
        table.insert(list_calls, ctx)
        ctx.pattern_message = { text = "banks: alpha-bank, beta-bank", time = os.clock() }
        return { "alpha-bank", "beta-bank" }
      end,
      delete_pattern_bank = function()
        return true
      end,
    }

    package.loaded["lib/seamstress/keyboard"] = nil
    package.loaded["musicutil"] = {
      generate_scale = function(root, _, octaves)
        local notes = {}
        for i = 1, octaves * 7 do
          notes[i] = root + i - 1
        end
        return notes
      end,
    }

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

    dofile("seamstress.lua")
    init()
  end)

  after_each(function()
    restore_modules(saved_modules)
    restore_globals(saved_globals)
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

  it("routes ctrl+b through screen.key to app.list_pattern_banks", function()
    screen.key("b", { ctrl = true }, false, 1)

    assert.are.equal(1, #list_calls)
    assert.are.equal(init_ctx, list_calls[1])
    assert.are.equal("banks: alpha-bank, beta-bank", init_ctx.pattern_message.text)
    assert.is_true(init_ctx.grid_dirty)
  end)

  it("surfaces save failures through the seamstress keyboard path", function()
    save_ok = nil
    save_value = "disk_full"

    screen.key("s", { ctrl = true }, false, 1)

    assert.are.equal(1, #save_calls)
    assert.are.equal("save failed: disk_full", init_ctx.pattern_message.text)
    assert.is_nil(init_ctx.active_pattern)
    assert.is_true(init_ctx.grid_dirty)
  end)

  it("surfaces load failures through the seamstress keyboard path", function()
    load_ok = nil
    load_value = "checksum_mismatch"

    screen.key("l", { ctrl = true }, false, 1)

    assert.are.equal(1, #load_calls)
    assert.are.equal("load failed: checksum_mismatch", init_ctx.pattern_message.text)
    assert.is_nil(init_ctx.active_pattern)
    assert.is_true(init_ctx.grid_dirty)
  end)
end)

describe("seamstress entrypoint hardware mirroring wiring", function()
  local saved_modules
  local saved_globals

  local captured_app_config
  local captured_ctx
  local app_cleanup_ctx
  local info_messages
  local log_closed

  before_each(function()
    saved_modules = capture_modules({
      "lib/app",
      "lib/log",
      "lib/track",
      "lib/voices/sprite",
      "lib/seamstress/screen_ui",
      "lib/seamstress/sprite_render",
      "lib/seamstress/keyboard",
      "lib/seamstress/grid_render",
      "lib/seamstress/help_overlay",
    })
    saved_globals = capture_globals({
      "init",
      "redraw",
      "cleanup",
      "midi",
      "screen",
      "metro",
    })

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
      wrap = function(fn)
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
      configure = function() end,
      screen_width = function() return 256 end,
      screen_height = function() return 128 end,
      get_config = function() return {cols = 16, rows = 8} end,
      set_modifier = function() end,
      release_locked_keys = function() end,
      THEME_ORDER = {"yellow", "red", "orange", "white"},
    }
    package.loaded["lib/seamstress/help_overlay"] = {
      draw = function() end,
      get_sections = function() return {} end,
      WIDTH = 400,
      HEIGHT = 380,
    }

    dofile("seamstress.lua")
  end)

  after_each(function()
    restore_modules(saved_modules)
    restore_globals(saved_globals)
  end)

  it("passes simulated provider with monome mirroring into app.init", function()
    init()

    assert.are.equal("simulated", captured_app_config.grid_provider)
    assert.is_table(captured_app_config.grid_opts)
    assert.is_true(captured_app_config.grid_opts.mirror_monome)
  end)

  it("? key toggles help_visible on ctx", function()
    init()
    assert.is_falsy(captured_ctx.help_visible)
    screen.key("?", {}, false, 1)
    assert.is_true(captured_ctx.help_visible)
    screen.key("?", {}, false, 1)
    assert.is_falsy(captured_ctx.help_visible)
  end)

  it("escape dismisses help overlay when visible", function()
    init()
    screen.key("?", {}, false, 1)
    assert.is_true(captured_ctx.help_visible)
    screen.key("escape", {}, false, 1)
    assert.is_falsy(captured_ctx.help_visible)
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
