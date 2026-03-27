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

local function make_runtime(opts)
  opts = opts or {}
  local calls = {}
  local warnings = {}
  local runtime = { calls = calls, warnings = warnings }
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

  runtime.file_exists = function(_path)
    return opts.file_exists ~= false
  end

  runtime.warn = function(msg)
    table.insert(warnings, msg)
  end

  runtime.load_sample = function(voice_id, path, config)
    table.insert(calls, {
      method = "load_sample",
      args = {voice_id, path, config.start_sec, config.end_sec},
    })
    if opts.load_ok == false then
      return false, "load_failed"
    end
    return true
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

local function find_calls_since(runtime, start_idx)
  local names = {}
  for i = start_idx, #runtime.calls do
    table.insert(names, runtime.calls[i].method)
  end
  return names
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
    assert.are.same({2, "/tmp/zig.wav", 1.25, 2.75}, find_last_call(runtime, "load_sample").args)
    assert.are.same({2, true}, find_last_call(runtime, "enable").args)
    assert.are.same({2, true}, find_last_call(runtime, "loop").args)
    assert.are.same({2, 1.25}, find_last_call(runtime, "loop_start").args)
    assert.are.same({2, 2.75}, find_last_call(runtime, "loop_end").args)
    assert.are.same({2, 0.05}, find_last_call(runtime, "fade_time").args)
    assert.are.same({2, 0.12}, find_last_call(runtime, "rate_slew_time").args)
  end)

  it("maps MIDI note offsets to softcut playback rate", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {
      sample_path = "/tmp/zig.wav",
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
      sample_path = "/tmp/zig.wav",
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
      sample_path = "/tmp/zig.wav",
      rate_slew = 0.05,
    })

    voice:set_portamento(0.4)
    assert.are.same({1, 0.4}, find_last_call(runtime, "rate_slew_time").args)
    assert.are.equal(0.4, voice.config.rate_slew)

    voice:note_on(60, 0.7)
    assert.are.same({1, 0.4}, find_last_call(runtime, "rate_slew_time").args)

    voice:set_portamento(0)
    assert.are.same({1, 0}, find_last_call(runtime, "rate_slew_time").args)
  end)

  it("retrigger cancels the prior note-off and restarts in a stable order", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {
      sample_path = "/tmp/zig.wav",
      start_sec = 0.25,
      end_sec = 1.25,
      attack = 0.01,
      release = 0.07,
      rate_slew = 0.05,
    })

    voice:play_note(60, 1.0, 1)
    local first_coro = voice.note_off_coro
    local start_idx = #runtime.calls + 1

    voice:play_note(67, 0.6, 1)

    assert.is_true(cancelled_coros[first_coro])
    assert.are.same(
      {"fade_time", "level_slew_time", "play", "fade_time", "rate_slew_time", "position", "level", "rate", "play"},
      find_calls_since(runtime, start_idx)
    )
    assert.are.same({1, 0.07}, runtime.calls[start_idx].args)
    assert.are.same({1, false}, runtime.calls[start_idx + 2].args)
    assert.are.same({1, 0.01}, runtime.calls[start_idx + 3].args)
    assert.are.same({1, true}, runtime.calls[start_idx + 8].args)
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

    local load_args = find_last_call(runtime, "load_sample").args
    assert.are.equal("/tmp/b.wav", load_args[2])
    assert.are.equal(2, load_args[3])
    assert.is_true(approx_equal(2.001, load_args[4]))
    assert.are.same({3, 1}, find_last_call(runtime, "pan").args)
    assert.is_true(approx_equal(2.001, find_last_call(runtime, "loop_end").args[2]))

    voice:note_on(64, 0.5)
    voice:note_off(60)
    assert.are.same({3, true}, find_last_call(runtime, "play").args)
  end)

  it("all_notes_off cancels pending note timers and silences playback", function()
    local runtime = make_runtime()
    local voice = softcut_zig.new(1, runtime, {
      sample_path = "/tmp/zig.wav",
    })

    voice:play_note(60, 0.8, 1)
    local coro_id = voice.active_notes[60]

    voice:all_notes_off()

    assert.is_true(cancelled_coros[coro_id])
    assert.are.same({}, voice.active_notes)
    assert.is_nil(voice.active_note)
    assert.are.same({1, 0}, find_last_call(runtime, "level").args)
    assert.are.same({1, false}, find_last_call(runtime, "play").args)
  end)

  it("returns a soft failure when the sample is missing", function()
    local runtime = make_runtime({ file_exists = false })
    local voice = softcut_zig.new(1, runtime, {
      sample_path = "/tmp/missing.wav",
    })

    local ok, err = voice:play_note(60, 0.8, 1)

    assert.is_nil(ok)
    assert.are.equal("sample_missing", err)
    assert.is_false(voice.available)
    assert.is_nil(find_last_call(runtime, "rate"))
    assert.is_true(#runtime.warnings > 0)
  end)

  it("returns a distinct error when sample loading fails", function()
    local runtime = make_runtime({ load_ok = false })
    local voice = softcut_zig.new(1, runtime, {
      sample_path = "/tmp/zig.wav",
    })

    local ok, err = voice:play_note(60, 0.8, 1)

    assert.is_nil(ok)
    assert.are.equal("load_failed", err)
    assert.are.equal("load_failed", voice.last_error)
    assert.is_false(voice.available)
  end)
end)
