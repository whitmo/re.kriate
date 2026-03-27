-- specs/softcut_zig_voice_spec.lua
-- Tests for the injected-runtime softcut_zig voice backend.

package.path = package.path .. ";./?.lua"

local next_coro_id = 1
local cancelled_coros = {}
local clock_run_fns = {}

rawset(_G, "clock", {
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

local softcut_zig = require("lib/voices/softcut_zig")

local function make_runtime()
  local calls = {}
  local runtime = { calls = calls }
  local methods = {
    "enable",
    "buffer",
    "rec_level",
    "pre_level",
    "loop",
    "loop_start",
    "loop_end",
    "fade_time",
    "level_slew_time",
    "rate_slew_time",
    "level",
    "pan",
    "position",
    "play",
    "rate",
    "level_cut",
  }

  for _, name in ipairs(methods) do
    runtime[name] = function(...)
      table.insert(calls, { method = name, args = {...} })
    end
  end

  runtime.buffer_read_mono = function(path, start_sec, duration)
    table.insert(calls, {
      method = "buffer_read_mono",
      args = {path, start_sec, duration},
    })
  end

  return runtime
end

local function find_last_call(runtime, method)
  for i = #runtime.calls, 1, -1 do
    if runtime.calls[i].method == method then
      return runtime.calls[i]
    end
  end
  return nil
end

local function approx_equal(a, b)
  return math.abs(a - b) < 1e-6
end

describe("softcut_zig voice", function()
  before_each(function()
    next_coro_id = 1
    cancelled_coros = {}
    clock_run_fns = {}
  end)

  it("applies startup config and loads the sample region", function()
    local runtime = make_runtime()

    local voice = softcut_zig.new(2, runtime, {
      sample_path = "/tmp/zig.wav",
      start_sec = 1.25,
      end_sec = 2.75,
      loop = true,
      pan = 0.2,
      attack = 0.05,
      release = 0.3,
      rate_slew = 0.12,
    })

    assert.are.equal(2, voice.voice_id)
    assert.are.same({"/tmp/zig.wav", 1.25, 1.5}, find_last_call(runtime, "buffer_read_mono").args)
    assert.are.same({2, true}, find_last_call(runtime, "enable").args)
    assert.are.same({2, true}, find_last_call(runtime, "loop").args)
    assert.are.same({2, 1.25}, find_last_call(runtime, "loop_start").args)
    assert.are.same({2, 2.75}, find_last_call(runtime, "loop_end").args)
    assert.are.same({2, 0.3}, find_last_call(runtime, "fade_time").args)
    assert.are.same({2, 0.12}, find_last_call(runtime, "rate_slew_time").args)
  end)

  it("maps MIDI note offsets to softcut playback rate", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {
      root_note = 60,
      start_sec = 0.5,
      end_sec = 1.5,
      level = 0.8,
    })

    voice:note_on(72, 0.5)

    assert.are.same({1, 0.5}, find_last_call(runtime, "position").args)
    assert.are.same({1, 0.4}, find_last_call(runtime, "level").args)
    assert.are.same({1, 2}, find_last_call(runtime, "rate").args)
    assert.are.same({1, true}, find_last_call(runtime, "play").args)
  end)

  it("play_note schedules a release through clock", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {
      release = 0.25,
    })

    voice:play_note(60, 1.0, 0.5)

    assert.is_not_nil(voice.active_notes[60])
    assert.is_not_nil(clock_run_fns[voice.active_notes[60]])

    clock_run_fns[voice.active_notes[60]]()

    assert.is_nil(voice.active_note)
    assert.is_nil(voice.active_notes[60])
    assert.are.same({1, 0.25}, find_last_call(runtime, "level_slew_time").args)
    assert.are.same({1, false}, find_last_call(runtime, "play").args)
  end)

  it("set_portamento overrides the configured rate slew until reset", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {
      rate_slew = 0.05,
    })

    voice:set_portamento(0.4)
    assert.are.same({1, 0.4}, find_last_call(runtime, "rate_slew_time").args)

    voice:note_on(60, 0.7)
    assert.are.same({1, 0.4}, find_last_call(runtime, "rate_slew_time").args)

    voice:set_portamento(0)
    assert.are.same({1, 0.05}, find_last_call(runtime, "rate_slew_time").args)
  end)

  it("apply_config updates the region and note_off ignores stale notes", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(3, runtime, {
      sample_path = "/tmp/a.wav",
      start_sec = 0,
      end_sec = 1,
    })

    voice:apply_config({
      sample_path = "/tmp/b.wav",
      start_sec = 2,
      end_sec = 2,
      pan = 2,
    })

    local load_args = find_last_call(runtime, "buffer_read_mono").args
    assert.are.equal("/tmp/b.wav", load_args[1])
    assert.are.equal(2, load_args[2])
    assert.is_true(approx_equal(0.001, load_args[3]))
    assert.are.same({3, 1}, find_last_call(runtime, "pan").args)
    assert.is_true(approx_equal(2.001, find_last_call(runtime, "loop_end").args[2]))

    voice:note_on(64, 0.5)
    voice:note_off(60)
    assert.are.same({3, true}, find_last_call(runtime, "play").args)
  end)

  it("all_notes_off cancels pending note timers and silences playback", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {})

    voice:play_note(60, 0.8, 1)
    local coro_id = voice.active_notes[60]

    voice:all_notes_off()

    assert.is_true(cancelled_coros[coro_id])
    assert.are.same({}, voice.active_notes)
    assert.is_nil(voice.active_note)
    assert.are.same({1, 0}, find_last_call(runtime, "level").args)
    assert.are.same({1, false}, find_last_call(runtime, "play").args)
  end)
end)
