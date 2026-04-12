-- specs/softcut_integration_spec.lua
-- Integration: softcut voice wired through app.lua params and sequencer dispatch.

package.path = package.path .. ";./?.lua"

local next_coro_id = 1
local cancelled_coros = {}
local clock_run_fns = {}

rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn)
    local id = next_coro_id
    next_coro_id = next_coro_id + 1
    clock_run_fns[id] = fn
    return id
  end,
  cancel = function(id)
    cancelled_coros[id] = true
    clock_run_fns[id] = nil
  end,
  sync = function() end,
})

local param_store = {}
local param_actions = {}
rawset(_G, "params", {
  add_separator = function(self, id, name) end,
  add_group = function(self, id, name, n) end,
  add_number = function(self, id, name, min, max, default, units, formatter)
    param_store[id] = default
  end,
  add_text = function(self, id, name, default)
    param_store[id] = default
  end,
  add_option = function(self, id, name, options, default)
    param_store[id] = default
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

rawset(_G, "grid", {
  connect = function()
    return {
      key = nil,
      led = function() end,
      refresh = function() end,
      all = function() end,
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

-- Fresh requires for each test file
local app = require("lib/app")
local sequencer = require("lib/sequencer")
local track_mod = require("lib/track")
local pattern_persistence = require("lib/pattern_persistence")

local persistence_tmp = "specs/tmp/softcut_integration_persistence"

local function reset()
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  next_coro_id = 1
  cancelled_coros = {}
  clock_run_fns = {}
  os.execute("mkdir -p " .. persistence_tmp)
  pattern_persistence._test_set_data_dir(persistence_tmp)
end

-- Create a temp sample file for loading tests
local sample_file = "/tmp/rekriate_test_sample.wav"

describe("softcut voice integration", function()

  before_each(function()
    reset()
    os.execute("rm -rf " .. persistence_tmp)
    os.execute("mkdir -p " .. persistence_tmp)
    -- Create a dummy sample file
    local f = io.open(sample_file, "w")
    if f then
      f:write("RIFF")
      f:close()
    end
  end)

  after_each(function()
    os.remove(sample_file)
  end)

  it("VOICE_TYPES includes softcut", function()
    -- Init app to register params, then check voice options
    local ctx = app.init({voices = {}})
    -- Voice param default is 1 (midi); softcut is option 4 (after sc_drums)
    params:set("voice_1", 4)
    assert.are.equal(4, params:get("voice_1"))
    app.cleanup(ctx)
  end)

  it("builds softcut voice when voice param is set to softcut", function()
    local ctx = app.init({})

    -- Set track 1 to softcut with a sample
    params:set("sample_path_1", sample_file)
    params:set("voice_1", 4) -- triggers build_voice

    assert.is_not_nil(ctx.voices[1])
    assert.is_not_nil(ctx.voices[1].play_note)
    assert.is_not_nil(ctx.voices[1].note_on)
    assert.is_not_nil(ctx.voices[1].all_notes_off)
    assert.is_true(ctx.voices[1].available)
    app.cleanup(ctx)
  end)

  it("creates a shared softcut_runtime across tracks", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("voice_1", 4)
    params:set("sample_path_2", sample_file)
    params:set("voice_2", 4)

    assert.is_not_nil(ctx.softcut_runtime)
    -- Both voices share the same runtime
    assert.are.equal(ctx.voices[1].runtime, ctx.voices[2].runtime)
    assert.are.equal(ctx.softcut_runtime, ctx.voices[1].runtime)
    app.cleanup(ctx)
  end)

  it("softcut voice plays notes through sequencer dispatch", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("voice_1", 4)

    -- Play a note via the sequencer
    sequencer.play_note(ctx, 1, 60, 0.8, 0.5)

    -- Voice should have an active note
    assert.are.equal(60, ctx.voices[1].active_note)

    -- Runtime should reflect the play state
    assert.is_true(ctx.softcut_runtime.voices[1].playing)
    assert.is_true(ctx.softcut_runtime.voices[1].level > 0)
    app.cleanup(ctx)
  end)

  it("softcut voice handles missing sample gracefully", function()
    local ctx = app.init({})

    params:set("sample_path_1", "/tmp/nonexistent_sample.wav")
    params:set("voice_1", 4)

    assert.is_not_nil(ctx.voices[1])
    assert.is_false(ctx.voices[1].available)

    -- play_note returns nil without crashing
    local ok, err = ctx.voices[1]:play_note(60, 0.8, 0.5)
    assert.is_nil(ok)
    assert.are.equal("sample_missing", err)
    app.cleanup(ctx)
  end)

  it("softcut voice handles empty sample path gracefully", function()
    local ctx = app.init({})

    -- Default sample_path is "" -> nil -> voice unavailable
    params:set("voice_1", 4)

    assert.is_not_nil(ctx.voices[1])
    assert.is_false(ctx.voices[1].available)
    app.cleanup(ctx)
  end)

  it("rebuilds softcut voice when sample params change", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("voice_1", 4)
    assert.is_true(ctx.voices[1].available)

    -- Change root note — should rebuild the voice
    local old_voice = ctx.voices[1]
    params:set("sample_root_1", 48)
    assert.is_not_nil(ctx.voices[1])
    -- New voice object was created
    assert.are_not.equal(old_voice, ctx.voices[1])
    assert.are.equal(48, ctx.voices[1].config.root_note)
    app.cleanup(ctx)
  end)

  it("switching from softcut to none clears the voice", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("voice_1", 4)
    assert.is_not_nil(ctx.voices[1])

    params:set("voice_1", 6) -- "none"
    assert.is_nil(ctx.voices[1])
    app.cleanup(ctx)
  end)

  it("cleanup calls all_notes_off on softcut voices", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("voice_1", 4)
    sequencer.play_note(ctx, 1, 60, 0.8, 0.5)
    assert.are.equal(60, ctx.voices[1].active_note)

    app.cleanup(ctx)
    -- After cleanup the runtime should show voice stopped
    assert.is_false(ctx.softcut_runtime.voices[1].playing)
  end)

  it("uses sample_start and sample_end from params", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("sample_start_1", 2)
    params:set("sample_end_1", 5)
    params:set("voice_1", 4)

    assert.are.equal(2, ctx.voices[1].config.start_sec)
    assert.are.equal(5, ctx.voices[1].config.end_sec)
    app.cleanup(ctx)
  end)

  it("uses sample_loop from params", function()
    local ctx = app.init({})

    params:set("sample_path_1", sample_file)
    params:set("sample_loop_1", 2) -- "on"
    params:set("voice_1", 4)

    assert.is_true(ctx.voices[1].config.loop)
    app.cleanup(ctx)
  end)
end)
