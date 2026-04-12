-- specs/clock_sync_integration_spec.lua
-- Integration tests: clock_sync wired through app.init/sequencer (spec 010).

package.path = package.path .. ";./?.lua"

-- Mock clock
local clock_run_queue = {}
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn)
    table.insert(clock_run_queue, fn)
    return #clock_run_queue
  end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock params
local param_store = {}
local param_actions = {}
local param_lookup = {}
rawset(_G, "params", {
  lookup = param_lookup,
  add_separator = function(self, id, name) end,
  add_group = function(self, id, name, n) end,
  add_number = function(self, id, name, min, max, default, units, formatter)
    param_store[id] = default
    param_lookup[id] = true
  end,
  add_text = function(self, id, name, default)
    param_store[id] = default
    param_lookup[id] = true
  end,
  add_option = function(self, id, name, options, default)
    param_store[id] = default
    param_lookup[id] = true
  end,
  set_action = function(self, id, fn)
    param_actions[id] = fn
  end,
  get = function(self, id) return param_store[id] end,
  set = function(self, id, val)
    param_store[id] = val
    if param_actions[id] then param_actions[id](val) end
  end,
})

-- Mock grid / metro / screen / util
rawset(_G, "grid", {connect = function()
  return {key = nil, led = function() end, refresh = function() end, all = function() end}
end})
rawset(_G, "metro", {init = function()
  return {time = 0, event = nil, start = function() end, stop = function() end}
end})
rawset(_G, "screen", {
  clear = function() end, color = function() end, move = function() end,
  text = function() end, rect_fill = function() end, refresh = function() end,
  level = function() end, update = function() end,
})
rawset(_G, "util", {clamp = function(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end})
package.loaded["musicutil"] = {
  generate_scale = function(root, _, octaves)
    local notes = {}
    for i = 1, octaves * 7 do notes[i] = root + (i - 1) * 2 end
    return notes
  end,
}

local app = require("lib/app")
local sequencer = require("lib/sequencer")
local clock_sync = require("lib/clock_sync")
local track_mod = require("lib/track")
local recorder = require("lib/voices/recorder")
local pattern_persistence = require("lib/pattern_persistence")

local persistence_tmp = "specs/tmp/clock_sync_integration"

-- Helper: build a capturing midi device that exposes both .send (output) and
-- .event (input) hooks so we can drive incoming clock and observe outgoing.
local function make_midi_dev()
  local dev = {sent = {}, event = nil}
  function dev:send(data) table.insert(self.sent, data) end
  return dev
end

local function make_app(opts)
  opts = opts or {}
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  for k in pairs(param_lookup) do param_lookup[k] = nil end
  clock_run_queue = {}
  os.execute("mkdir -p " .. persistence_tmp)
  pattern_persistence._test_set_data_dir(persistence_tmp)

  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  local config = {voices = voices}
  if opts.midi_dev then config.midi_dev = opts.midi_dev end
  return app.init(config), buffer
end

describe("clock_sync integration", function()

  before_each(function()
    os.execute("rm -rf " .. persistence_tmp)
    os.execute("mkdir -p " .. persistence_tmp)
    pattern_persistence._test_set_data_dir(persistence_tmp)
  end)

  it("initializes ctx.clock_sync with internal source and output off", function()
    local ctx = make_app()
    assert.is_not_nil(ctx.clock_sync)
    assert.are.equal(clock_sync.SOURCE_INTERNAL, ctx.clock_sync.source)
    assert.is_false(ctx.clock_sync.output_enabled)
  end)

  it("clock_source_mode param switches source (FR-001)", function()
    local ctx = make_app()
    params:set("clock_source_mode", 2)
    assert.are.equal(clock_sync.SOURCE_EXT_MIDI, ctx.clock_sync.source)
    params:set("clock_source_mode", 1)
    assert.are.equal(clock_sync.SOURCE_INTERNAL, ctx.clock_sync.source)
  end)

  it("clock_output param toggles output_enabled (FR-004)", function()
    local ctx = make_app()
    assert.is_false(ctx.clock_sync.output_enabled)
    params:set("clock_output", 2)
    assert.is_true(ctx.clock_sync.output_enabled)
    params:set("clock_output", 1)
    assert.is_false(ctx.clock_sync.output_enabled)
  end)

  it("stops the sequencer when switching source while playing (FR-009)", function()
    local ctx = make_app()
    sequencer.start(ctx)
    assert.is_true(ctx.playing)
    params:set("clock_source_mode", 2)
    assert.is_false(ctx.playing)
  end)

  it("sends MIDI Start on sequencer.start when output is enabled (FR-006)", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    params:set("clock_output", 2)
    sequencer.start(ctx)
    local found_start = false
    for _, d in ipairs(dev.sent) do
      if d[1] == clock_sync.MIDI_START then found_start = true end
    end
    assert.is_true(found_start)
  end)

  it("sends MIDI Stop on sequencer.stop when output is enabled (FR-007)", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    params:set("clock_output", 2)
    sequencer.start(ctx)
    local sent_before = #dev.sent
    sequencer.stop(ctx)
    local found_stop = false
    for i = sent_before + 1, #dev.sent do
      if dev.sent[i][1] == clock_sync.MIDI_STOP then found_stop = true end
    end
    assert.is_true(found_stop)
  end)

  it("does not send transport when output is disabled", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    sequencer.start(ctx)
    sequencer.stop(ctx)
    for _, d in ipairs(dev.sent) do
      assert.is_not.equal(clock_sync.MIDI_START, d[1])
      assert.is_not.equal(clock_sync.MIDI_STOP, d[1])
    end
  end)

  it("incoming MIDI Start starts the sequencer when slaved (FR-008)", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    params:set("clock_source_mode", 2)
    assert.is_not_nil(dev.event)
    dev.event({clock_sync.MIDI_START})
    assert.is_true(ctx.playing)
    assert.are.equal(clock_sync.TRANSPORT_PLAYING, ctx.clock_sync.transport)
  end)

  it("incoming MIDI Stop stops the sequencer when slaved", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    params:set("clock_source_mode", 2)
    dev.event({clock_sync.MIDI_START})
    dev.event({clock_sync.MIDI_STOP})
    assert.is_false(ctx.playing)
    assert.are.equal(clock_sync.TRANSPORT_PAUSED, ctx.clock_sync.transport)
  end)

  it("incoming MIDI Continue resumes without resetting (FR-008)", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    params:set("clock_source_mode", 2)
    dev.event({clock_sync.MIDI_START})
    dev.event({clock_sync.MIDI_STOP})
    dev.event({clock_sync.MIDI_CONTINUE})
    assert.is_true(ctx.playing)
    assert.are.equal(clock_sync.TRANSPORT_PLAYING, ctx.clock_sync.transport)
  end)

  it("incoming transport is ignored when source is internal", function()
    local dev = make_midi_dev()
    local ctx = make_app({midi_dev = dev})
    -- default source = internal
    dev.event({clock_sync.MIDI_START})
    assert.is_false(ctx.playing)
  end)

  it("preserves any pre-existing midi.event handler (chain, not stomp)", function()
    local dev = make_midi_dev()
    local received = {}
    dev.event = function(data) table.insert(received, data) end
    local ctx = make_app({midi_dev = dev})
    params:set("clock_source_mode", 2)
    dev.event({clock_sync.MIDI_START})
    assert.is_true(ctx.playing)
    assert.are.equal(1, #received)
  end)

end)
