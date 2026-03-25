-- specs/osc_voice_spec.lua
-- Tests for OSC voice integration (004)

package.path = package.path .. ";./?.lua"

-- Mock clock
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock params system
local param_store = {}
local param_actions = {}
local param_defs = {}
rawset(_G, "params", {
  add_separator = function(self, id, name) end,
  add_number = function(self, id, name, min, max, default)
    param_store[id] = default
    param_defs[id] = { type = "number", min = min, max = max, default = default }
  end,
  add_option = function(self, id, name, options, default)
    param_store[id] = default
    param_defs[id] = { type = "option", options = options, default = default }
  end,
  add_text = function(self, id, name, default)
    param_store[id] = default
    param_defs[id] = { type = "text", default = default }
  end,
  set_action = function(self, id, fn)
    param_actions[id] = fn
  end,
  get = function(self, id)
    return param_store[id]
  end,
  set = function(self, id, val)
    param_store[id] = val
    if param_actions[id] then param_actions[id](val) end
  end,
})

-- Mock grid
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

-- Mock metro
rawset(_G, "metro", {
  init = function()
    return {
      time = 0,
      event = nil,
      start = function(self) end,
      stop = function(self) end,
    }
  end,
})

-- Mock screen
rawset(_G, "screen", {
  clear = function() end,
  color = function(...) end,
  move = function(x, y) end,
  text = function(s) end,
  rect_fill = function(w, h) end,
  refresh = function() end,
  level = function(l) end,
  update = function() end,
})

-- Mock util
rawset(_G, "util", {
  clamp = function(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
  end,
})

-- Mock musicutil
package.loaded["musicutil"] = {
  generate_scale = function(root, scale_type, octaves)
    local notes = {}
    for i = 1, octaves * 7 do
      notes[i] = root + (i - 1) * 2
    end
    return notes
  end,
}

-- Mock midi
rawset(_G, "midi", {
  connect = function(port)
    return {
      note_on = function(self, note, vel, ch) end,
      note_off = function(self, note, vel, ch) end,
      cc = function(self, cc, val, ch) end,
    }
  end,
})

-- Mock osc — capture sends for test assertions
local osc_sent = {}
rawset(_G, "osc", {
  send = function(target, path, args)
    table.insert(osc_sent, { target = target, path = path, args = args })
  end,
})

local osc_voice = require("lib/voices/osc")
local midi_voice = require("lib/voices/midi")
local track_mod = require("lib/track")
local app = require("lib/app")
local sprite_voice = require("lib/voices/sprite")

-- Helper: reset all state between tests
local function reset()
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  for k in pairs(param_defs) do param_defs[k] = nil end
  beat_counter = 0
  osc_sent = {}
end

-- Helper: simulate seamstress.lua init (create voices, params, call app.init)
local function seamstress_init()
  reset()
  local midi_dev = midi.connect(1)
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = midi_voice.new(midi_dev, t)
  end
  local sprite_voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    sprite_voices[t] = sprite_voice.new(t)
  end
  -- MIDI channel params
  params:add_separator("midi_config", "MIDI")
  for t = 1, track_mod.NUM_TRACKS do
    params:add_number("midi_ch_" .. t, "track " .. t .. " channel", 1, 16, t)
    params:set_action("midi_ch_" .. t, function(val)
      voices[t].channel = val
    end)
  end
  -- Load seamstress.lua voice/osc param setup (to be implemented)
  -- For now, call app.init directly
  local ctx = app.init({
    voices = voices,
    sprite_voices = sprite_voices,
  })
  ctx._voices_ref = voices
  ctx._midi_dev = midi_dev
  return ctx
end

describe("osc voice integration", function()

  -- Phase 2: Voice Backend Param (FR-001, FR-008)
  describe("voice backend params", function()

    it("T003: voice_backend_1 exists and defaults to 1 (midi)", function()
      local ctx = seamstress_init()
      assert.is_not_nil(params:get("voice_backend_1"),
        "voice_backend_1 param should exist after init")
      assert.are.equal(1, params:get("voice_backend_1"),
        "voice_backend_1 should default to 1 (midi)")
    end)

    it("T004: all 4 tracks have voice_backend params defaulting to 1", function()
      local ctx = seamstress_init()
      for t = 1, track_mod.NUM_TRACKS do
        local id = "voice_backend_" .. t
        assert.is_not_nil(params:get(id),
          id .. " param should exist")
        assert.are.equal(1, params:get(id),
          id .. " should default to 1 (midi)")
      end
    end)

    it("T005: with defaults, all voices are MIDI (have midi_dev field)", function()
      local ctx = seamstress_init()
      for t = 1, track_mod.NUM_TRACKS do
        assert.is_not_nil(ctx.voices[t].midi_dev,
          "track " .. t .. " voice should have midi_dev field (MIDI voice)")
      end
    end)

  end)

  -- Phase 3: OSC Target Params (FR-003, FR-009)
  describe("osc target params", function()

    it("T007: osc_host_1 defaults to 127.0.0.1, osc_port_1 defaults to 57120", function()
      local ctx = seamstress_init()
      assert.are.equal("127.0.0.1", params:get("osc_host_1"),
        "osc_host_1 should default to 127.0.0.1")
      assert.are.equal(57120, params:get("osc_port_1"),
        "osc_port_1 should default to 57120")
    end)

    it("T008: all 4 tracks have osc_host and osc_port params with defaults", function()
      local ctx = seamstress_init()
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal("127.0.0.1", params:get("osc_host_" .. t),
          "osc_host_" .. t .. " should default to 127.0.0.1")
        assert.are.equal(57120, params:get("osc_port_" .. t),
          "osc_port_" .. t .. " should default to 57120")
      end
    end)

    it("T009: osc_port param is constrained to 1-65535", function()
      local ctx = seamstress_init()
      local def = param_defs["osc_port_1"]
      assert.is_not_nil(def, "osc_port_1 param definition should exist")
      assert.are.equal(1, def.min, "osc_port min should be 1")
      assert.are.equal(65535, def.max, "osc_port max should be 65535")
    end)

  end)

end)
