-- specs/app_params_spec.lua
-- Focused coverage for app.lua param grouping and voice-specific visibility.

package.path = package.path .. ";./?.lua"

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
  before_each(function()
    reset_params()
    next_coro_id = 1
  end)

  teardown(function()
    _G.params = nil
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
end)
