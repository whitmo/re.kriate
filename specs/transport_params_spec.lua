-- specs/transport_params_spec.lua
-- Transport params (re-9d9): advance_<t>, transport_play, transport_stop.
-- Verifies params are added by app.init and their actions drive the
-- sequencer (for MIDI-mapping via PMAP).

package.path = package.path .. ";./?.lua"

rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

rawset(_G, "osc", {send = function() end})

local param_store, param_actions, param_defs = {}, {}, {}
rawset(_G, "params", {
  lookup = {},
  add_separator = function(self, id, name) end,
  add_group = function(self, id, name, n) end,
  add_number = function(self, id, name, min, max, default)
    param_store[id] = default
    param_defs[id] = {type = "number", min = min, max = max, default = default}
    self.lookup[id] = true
  end,
  add_option = function(self, id, name, options, default)
    param_store[id] = default
    param_defs[id] = {type = "option", options = options, default = default}
    self.lookup[id] = true
  end,
  add_text = function(self, id, name, default)
    param_store[id] = default
    param_defs[id] = {type = "text", default = default}
    self.lookup[id] = true
  end,
  add_control = function(self, id, name, spec)
    param_store[id] = (spec and spec.default) or 0
    param_defs[id] = {type = "control"}
    self.lookup[id] = true
  end,
  set_action = function(self, id, fn) param_actions[id] = fn end,
  get = function(self, id) return param_store[id] end,
  set = function(self, id, val)
    param_store[id] = val
    if param_actions[id] then param_actions[id](val) end
  end,
})

local function reset_params_mock()
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  for k in pairs(param_defs) do param_defs[k] = nil end
  for k in pairs(params.lookup) do params.lookup[k] = nil end
end

rawset(_G, "grid", {
  connect = function()
    return {
      key = nil,
      led = function(self, x, y, val) end,
      refresh = function(self) end,
      all = function(self, val) end,
    }
  end,
})

rawset(_G, "metro", {
  init = function()
    return {time = 0, event = nil, start = function(self) end, stop = function(self) end}
  end,
})

rawset(_G, "util", {
  clamp = function(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end,
})
rawset(_G, "screen", setmetatable({}, {__index = function() return function() end end}))
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
  generate_scale = function(root, kind, octaves)
    local notes = {}
    for i = 1, octaves * 7 do notes[i] = root + (i - 1) * 2 end
    return notes
  end,
}

local track_mod = require("lib/track")

describe("transport params (re-9d9)", function()

  local function make_voices()
    local voices = {}
    for t = 1, track_mod.NUM_TRACKS do
      voices[t] = {
        play_note = function() end,
        all_notes_off = function() end,
        set_level = function() end,
        set_pan = function() end,
      }
    end
    return voices
  end

  before_each(function()
    reset_params_mock()
    -- Force fresh require each test so set_action closures bind to the new ctx.
    package.loaded["lib/app"] = nil
  end)

  it("registers advance_<t> params for every track", function()
    local app = require("lib/app")
    app.init({voices = make_voices()})
    for t = 1, track_mod.NUM_TRACKS do
      assert.is_true(params.lookup["advance_" .. t],
        "missing param advance_" .. t)
      assert.are.equal("option", param_defs["advance_" .. t].type)
    end
  end)

  it("registers transport_play and transport_stop params", function()
    local app = require("lib/app")
    app.init({voices = make_voices()})
    assert.is_true(params.lookup["transport_play"])
    assert.is_true(params.lookup["transport_stop"])
  end)

  it("firing advance_<t> steps that track's trigger position by one", function()
    local app = require("lib/app")
    local ctx = app.init({voices = make_voices()})
    local track = ctx.tracks[2]
    local start_pos = track.params.trigger.pos
    params:set("advance_2", 2)
    assert.are_not.equal(start_pos, track.params.trigger.pos)
    -- Action param auto-resets to 1 so the next MIDI pulse edge re-fires.
    assert.are.equal(1, params:get("advance_2"))
  end)

  it("advance_<t> only affects the named track", function()
    local app = require("lib/app")
    local ctx = app.init({voices = make_voices()})
    local t1_pos = ctx.tracks[1].params.trigger.pos
    local t3_pos = ctx.tracks[3].params.trigger.pos
    params:set("advance_3", 2)
    assert.are.equal(t1_pos, ctx.tracks[1].params.trigger.pos)
    assert.are_not.equal(t3_pos, ctx.tracks[3].params.trigger.pos)
  end)

  it("transport_play starts the sequencer; transport_stop stops it", function()
    local app = require("lib/app")
    local ctx = app.init({voices = make_voices()})
    assert.is_falsy(ctx.playing)
    params:set("transport_play", 2)
    assert.is_true(ctx.playing)
    assert.are.equal(1, params:get("transport_play"))
    params:set("transport_stop", 2)
    assert.is_false(ctx.playing)
    assert.are.equal(1, params:get("transport_stop"))
  end)

  it("mute_<t> param continues to drive ctx.tracks[t].muted (regression)", function()
    local app = require("lib/app")
    local ctx = app.init({voices = make_voices()})
    assert.is_falsy(ctx.tracks[2].muted)
    params:set("mute_2", 2)
    assert.is_true(ctx.tracks[2].muted)
    params:set("mute_2", 1)
    assert.is_false(ctx.tracks[2].muted)
  end)

end)
