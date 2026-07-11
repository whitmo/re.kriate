-- specs/app_params_spec.lua
-- Focused coverage for app.lua param grouping and voice-specific visibility.

package.path = package.path .. ";./?.lua"

local host_stubs = require("specs/lib/host_stubs")

-- Host globals this spec fakes; snapshotted/restored per-test (see
-- specs/lib/host_stubs.lua) so the fakes don't leak into whichever spec
-- file happens to run next under --no-auto-insulate. This file runs FIRST
-- alphabetically among the spec suite, so a leaked fake here would have the
-- widest possible blast radius.
local HOST_GLOBALS = {"clock", "params", "osc", "grid", "metro", "screen", "util"}

local next_coro_id = 1
local param_store = {}
local param_actions = {}
local param_visibility = {}
local group_sizes = {}
local group_members = {}
local open_group_id = nil
local open_group_remaining = 0

local SOFTCUT_PARAM_IDS = {
  "sample_path_1",
  "sample_root_1",
  "sample_start_1",
  "sample_end_1",
  "sample_loop_1",
  "sample_grab_len_1",
  "sample_grab_input_1",
  "sample_grab_1",
}

local function reset_params()
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  for k in pairs(param_visibility) do param_visibility[k] = nil end
  for k in pairs(group_sizes) do group_sizes[k] = nil end
  for k in pairs(group_members) do group_members[k] = nil end
  open_group_id = nil
  open_group_remaining = 0
end

local function register_group_param(id, default)
  param_store[id] = default
  if open_group_id and open_group_remaining > 0 then
    table.insert(group_members[open_group_id], id)
    open_group_remaining = open_group_remaining - 1
    if open_group_remaining == 0 then
      open_group_id = nil
    end
  end
end

local function install_host_fakes()
  rawset(_G, "clock", {
    get_beats = function() return 0 end,
    run = function(fn)
      local id = next_coro_id
      next_coro_id = next_coro_id + 1
      return id
    end,
    cancel = function(id) end,
    sync = function() end,
  })

  rawset(_G, "params", {
    add_separator = function(self, id, name) end,
    add_group = function(self, id, name, n)
      group_sizes[id] = n
      group_members[id] = {}
      open_group_id = id
      open_group_remaining = n
    end,
    add_number = function(self, id, name, min, max, default)
      register_group_param(id, default)
    end,
    add_text = function(self, id, name, default)
      register_group_param(id, default)
    end,
    add_option = function(self, id, name, options, default)
      register_group_param(id, default)
    end,
    add_control = function(self, id, name, spec)
      register_group_param(id, 0)
    end,
    set_action = function(self, id, fn)
      param_actions[id] = fn
    end,
    get = function(self, id)
      return param_store[id]
    end,
    set = function(self, id, val)
      param_store[id] = val
      if param_actions[id] then
        param_actions[id](val)
      end
    end,
    show = function(self, id)
      param_visibility[id] = true
    end,
    hide = function(self, id)
      param_visibility[id] = false
    end,
  })

  rawset(_G, "osc", {
    send = function(target, path, args) end,
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
    text = function() end,
    rect_fill = function() end,
    refresh = function() end,
    level = function() end,
    update = function() end,
  })

  rawset(_G, "util", {
    clamp = function(val, min, max)
      if val < min then return min end
      if val > max then return max end
      return val
    end,
  })
end

package.loaded["musicutil"] = {
  generate_scale = function(root, scale_type, octaves)
    local notes = {}
    for i = 1, octaves * 7 do
      notes[i] = root + (i - 1) * 2
    end
    return notes
  end,
}

package.loaded["lib/app"] = nil
local app = require("lib/app")
local track_mod = require("lib/track")
local grid_provider = require("lib/grid_provider")

local function new_midi_dev()
  return {
    note_on = function() end,
    note_off = function() end,
    cc = function() end,
  }
end

local function cleanup_dummy_voices()
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = {
      all_notes_off = function(self) end,
    }
  end
  return voices
end

describe("app params", function()
  local restore_host

  before_each(function()
    restore_host = host_stubs.stub(HOST_GLOBALS, install_host_fakes)
    reset_params()
    next_coro_id = 1
  end)

  after_each(function()
    restore_host()
  end)

  it("keeps track params inside each per-track group", function()
    local ctx = app.init({})

    for t = 1, track_mod.NUM_TRACKS do
      local group_id = "track_" .. t
      assert.are.equal(15, group_sizes[group_id])
      assert.are.same({
        "voice_" .. t,
        "midi_ch_" .. t,
        "sc_synthdef_" .. t,
        "sample_path_" .. t,
        "sample_root_" .. t,
        "sample_start_" .. t,
        "sample_end_" .. t,
        "sample_loop_" .. t,
        "sample_grab_len_" .. t,
        "sample_grab_input_" .. t,
        "sample_grab_" .. t,
        "division_" .. t,
        "direction_" .. t,
        "swing_" .. t,
        "trig_clock_" .. t,
      }, group_members[group_id])
    end

    app.cleanup(ctx)
  end)

  it("shows only the params relevant to the selected voice", function()
    local ctx = app.init({ midi_dev = new_midi_dev() })

    assert.is_true(param_visibility["midi_ch_1"])
    assert.is_false(param_visibility["sc_synthdef_1"])
    for _, id in ipairs(SOFTCUT_PARAM_IDS) do
      assert.is_false(param_visibility[id], id .. " should start hidden for midi")
    end

    params:set("voice_1", 4) -- softcut
    assert.is_false(param_visibility["midi_ch_1"])
    assert.is_false(param_visibility["sc_synthdef_1"])
    for _, id in ipairs(SOFTCUT_PARAM_IDS) do
      assert.is_true(param_visibility[id], id .. " should show for softcut")
    end

    params:set("voice_1", 5) -- sc_synth
    assert.is_false(param_visibility["midi_ch_1"])
    assert.is_true(param_visibility["sc_synthdef_1"])
    for _, id in ipairs(SOFTCUT_PARAM_IDS) do
      assert.is_false(param_visibility[id], id .. " should hide for sc_synth")
    end

    params:set("voice_1", 1) -- midi
    assert.is_true(param_visibility["midi_ch_1"])
    assert.is_false(param_visibility["sc_synthdef_1"])

    app.cleanup(ctx)
  end)

  it("updates visibility even when voices are injected externally", function()
    local ctx = app.init({ voices = cleanup_dummy_voices() })

    assert.is_true(param_visibility["midi_ch_1"])
    params:set("voice_1", 4)
    assert.is_false(param_visibility["midi_ch_1"])
    assert.is_true(param_visibility["sample_path_1"])

    app.cleanup(ctx)
  end)

  it("wires trig clock params into track state", function()
    local ctx = app.init({})

    assert.is_false(ctx.tracks[1].trig_clock)
    params:set("trig_clock_1", 2)
    assert.is_true(ctx.tracks[1].trig_clock)
    params:set("trig_clock_1", 1)
    assert.is_false(ctx.tracks[1].trig_clock)

    app.cleanup(ctx)
  end)

  it("installs the behavioral command layer (cmd:* events drive the app)", function()
    local ctx = app.init({})

    ctx.events:emit("cmd:transport:play", {})
    assert.is_true(ctx.playing)
    ctx.events:emit("cmd:transport:stop", {})
    assert.is_false(ctx.playing)
    ctx.events:emit("cmd:track:set_mute", {track = 2, muted = true})
    assert.is_true(ctx.tracks[2].muted)

    app.cleanup(ctx)
  end)

  it("emits app:ready once init completes", function()
    -- app.init constructs ctx.events itself, so callers can't subscribe
    -- before init; the contract is a re-checkable ctx.ready flag set by
    -- the same code path that emits the app:ready fact.
    local ctx = app.init({})
    assert.is_true(ctx.ready)
    app.cleanup(ctx)
  end)

  -- ========================================================================
  -- Grid/keyboard -> params sync-back for direction/division/swing
  -- (assessment finding #22, root cause of #8)
  -- ========================================================================

  describe("track:direction/division/swing facts sync back into params", function()

    it("converts the direction string to the direction_N option index", function()
      local ctx = app.init({})

      -- direction.MODES = {"forward", "reverse", "pendulum", "drunk", "random"}
      ctx.events:emit("track:direction", {track = 2, value = "pendulum"})
      assert.are.equal(3, param_store["direction_2"])

      ctx.events:emit("track:direction", {track = 3, value = "random"})
      assert.are.equal(5, param_store["direction_3"])

      ctx.events:emit("track:direction", {track = 1, value = "reverse"})
      assert.are.equal(2, param_store["direction_1"])

      app.cleanup(ctx)
    end)

    it("pushes the division_N raw option index straight through (no conversion)", function()
      local ctx = app.init({})

      ctx.events:emit("track:division", {track = 4, value = 5})
      assert.are.equal(5, param_store["division_4"])

      app.cleanup(ctx)
    end)

    it("pushes the swing_N raw 0-100 number straight through (no conversion)", function()
      local ctx = app.init({})

      ctx.events:emit("track:swing", {track = 1, value = 50})
      assert.are.equal(50, param_store["swing_1"])

      app.cleanup(ctx)
    end)

    it("round-trips through the real set_actions without re-emitting (no feedback loop)", function()
      -- The params:set_action for direction_N/division_N/swing_N only
      -- mutates ctx.tracks[t]; it never re-emits track:*, so pushing the
      -- converted value back through params here also lands back on
      -- ctx.tracks[t] as the equivalent value.
      local ctx = app.init({})

      ctx.events:emit("track:direction", {track = 2, value = "drunk"})
      assert.are.equal("drunk", ctx.tracks[2].direction)

      ctx.events:emit("track:division", {track = 2, value = 3})
      assert.are.equal(3, ctx.tracks[2].division)

      ctx.events:emit("track:swing", {track = 2, value = 75})
      assert.are.equal(75, ctx.tracks[2].swing)

      app.cleanup(ctx)
    end)

  end)

  -- ========================================================================
  -- Grid provider param safety (re-# assessment findings #3, #12)
  -- ========================================================================

  describe("grid provider param (#3: simulated boot provider)", function()

    it("does not reconnect the grid when the default param index is re-applied " ..
        "for a seamstress-style boot (grid_provider = \"simulated\")", function()
      -- Before the fix, "simulated" is absent from GRID_PROVIDER_REGISTRY, so
      -- add_grid_params's default_idx lookup falls back to index 1 ("monome")
      -- even though ctx._grid_provider_name is "simulated". Re-applying the
      -- param's own default value would then resolve to the wrong provider
      -- name and force an unwanted reconnect (replacing the live grid).
      local ctx = app.init({ grid_provider = "simulated", grid_opts = { cols = 16, rows = 8 } })
      local old_g = ctx.g
      assert.are.equal("simulated", ctx._grid_provider_name)

      params:set("grid_provider", params:get("grid_provider"))

      assert.are.equal(old_g, ctx.g)
      app.cleanup(ctx)
    end)

    it("can cycle the grid provider away from and back to \"simulated\"", function()
      local ctx = app.init({ grid_provider = "simulated", grid_opts = { cols = 16, rows = 8 } })

      -- GRID_PROVIDER_OPTIONS = {monome, midigrid, push2, launchpad pro, virtual, simulated}
      params:set("grid_provider", 5) -- virtual
      assert.is_function(ctx.g.get_led, "virtual provider should implement get_led")

      params:set("grid_provider", 6) -- simulated
      assert.is_function(ctx.g.get_led, "should be able to return to the simulated provider")
      assert.are.equal(16, ctx.g:cols())

      app.cleanup(ctx)
    end)

  end)

  describe("grid provider param (#12: failed reconnect must not tear down the old grid)", function()
    local orig_connect
    local orig_grid_connect

    before_each(function()
      orig_connect = grid_provider.connect
      orig_grid_connect = _G.grid.connect
    end)

    after_each(function()
      grid_provider.connect = orig_connect
      _G.grid.connect = orig_grid_connect
    end)

    it("leaves ctx.g untouched (not even cleaned up) when the new provider fails to connect", function()
      -- Instrument the "monome" boot grid so we can tell whether the OLD
      -- grid's cleanup() fired. Identity alone can't catch this bug: the
      -- pre-fix code calls ctx.g:cleanup() before attempting the new
      -- connect, so the same table reference survives but its state has
      -- already been torn down.
      local cleanup_calls = 0
      _G.grid.connect = function(device_num)
        return {
          key = nil,
          led = function() end,
          refresh = function() end,
          all = function() end,
          cleanup = function() cleanup_calls = cleanup_calls + 1 end,
        }
      end

      local ctx = app.init({}) -- boots "monome" by default
      local old_g = ctx.g
      assert.are.equal("monome", ctx._grid_provider_name)

      grid_provider.connect = function(name, opts)
        if name == "midigrid" then
          error("midigrid not found — install from github.com/jaggednz/midigrid")
        end
        return orig_connect(name, opts)
      end

      -- GRID_PROVIDER_OPTIONS index 2 = "midigrid"
      params:set("grid_provider", 2)

      assert.are.equal(old_g, ctx.g, "old grid must survive a failed reconnect attempt")
      assert.are.equal("monome", ctx._grid_provider_name, "provider name must not update on failure")
      assert.are.equal(0, cleanup_calls, "old grid's cleanup must not fire before the new provider is confirmed")
      -- The surviving grid must still be functional (not torn down mid-swap).
      assert.has_no.errors(function() ctx.g:led(1, 1, 15) end)

      app.cleanup(ctx)
    end)

  end)
end)
