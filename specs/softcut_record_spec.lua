-- specs/softcut_record_spec.lua
-- Tests for softcut_runtime.record and softcut_zig:grab (sample grabbing).

package.path = package.path .. ";./?.lua"

-- Synchronous clock stub: clock.run invokes the function immediately, and
-- clock.sleep is a no-op so records complete inline.
rawset(_G, "clock", {
  run = function(fn) fn(); return 1 end,
  sleep = function(_) end,
  cancel = function() end,
  sync = function() end,
  get_beats = function() return 0 end,
})

local softcut_runtime = require("lib/voices/softcut_runtime")
local softcut_zig = require("lib/voices/softcut_zig")

describe("softcut_runtime.record", function()
  it("rejects invalid voice ids", function()
    local rt = softcut_runtime.new()
    local ok, err = rt.record(99, {duration = 1})
    assert.is_false(ok)
    assert.are.equal("invalid_voice", err)
  end)

  it("marks the voice recording then completed", function()
    local rt = softcut_runtime.new()
    local completed = nil
    local ok = rt.record(1, {duration = 0.5}, function(s) completed = s end)
    assert.is_true(ok)
    -- Synchronous clock — completion ran inline.
    assert.is_true(completed)
    assert.is_false(rt.voices[1].recording)
    assert.is_true(rt.voices[1].sample_loaded)
    assert.are.equal(softcut_runtime.RECORDED_MARKER, rt.voices[1].sample_path)
    assert.are.equal(0.5, rt.voices[1].record_duration)
  end)

  it("defaults duration to the voice's region length", function()
    local rt = softcut_runtime.new()
    local region_len = rt.voices[1].region_end - rt.voices[1].region_start
    rt.record(1)
    assert.are.equal(region_len, rt.voices[1].record_duration)
  end)

  it("clamps duration to the voice's region length", function()
    local rt = softcut_runtime.new()
    local region_len = rt.voices[1].region_end - rt.voices[1].region_start
    rt.record(1, {duration = region_len * 10})
    assert.are.equal(region_len, rt.voices[1].record_duration)
  end)

  it("refuses a second concurrent record", function()
    local rt = softcut_runtime.new()
    -- Use an async clock that never completes so the first record stays live.
    local orig = _G.clock
    rawset(_G, "clock", {
      run = function(_) return 1 end,
      sleep = function() end,
      cancel = function() end,
    })
    rt.record(1, {duration = 1})
    assert.is_true(rt.voices[1].recording)
    local ok, err = rt.record(1, {duration = 1})
    assert.is_false(ok)
    assert.are.equal("already_recording", err)
    rawset(_G, "clock", orig)
  end)

  it("drives _G.softcut record APIs in norns mode", function()
    local calls = {}
    local function track(name)
      return function(...) table.insert(calls, {name, {...}}) end
    end
    rawset(_G, "softcut", {
      enable = track("enable"),
      buffer = track("buffer"),
      loop = track("loop"),
      loop_start = track("loop_start"),
      loop_end = track("loop_end"),
      position = track("position"),
      rate = track("rate"),
      rec_level = track("rec_level"),
      pre_level = track("pre_level"),
      level_input_cut = track("level_input_cut"),
      level = track("level"),
      play = track("play"),
      rec = track("rec"),
      buffer_clear_region = track("buffer_clear_region"),
    })
    local rt = softcut_runtime.new({mode = "norns"})
    rt.record(1, {duration = 1, input_channel = 2})

    local seen = {}
    for _, c in ipairs(calls) do seen[c[1]] = c[2] end

    assert.is_not_nil(seen.buffer_clear_region)
    assert.is_not_nil(seen.rec_level)
    assert.is_not_nil(seen.level_input_cut)
    -- input_channel=2 routed to voice 1
    assert.are.equal(2, seen.level_input_cut[1])
    assert.are.equal(1, seen.level_input_cut[2])
    -- rec toggled on then off across the lifecycle
    local rec_vals = {}
    for _, c in ipairs(calls) do
      if c[1] == "rec" then table.insert(rec_vals, c[2][2]) end
    end
    assert.are.equal(2, #rec_vals)
    assert.are.equal(1, rec_vals[1])
    assert.are.equal(0, rec_vals[2])

    rawset(_G, "softcut", nil)
  end)
end)

describe("softcut_zig:grab", function()
  it("records into the voice's region and becomes playable", function()
    local rt = softcut_runtime.new()
    local voice = softcut_zig.new(1, rt, {sample_path = nil})
    -- Unavailable before grab — no sample.
    assert.is_false(voice.available)

    local ok = voice:grab({duration = 0.5})
    assert.is_true(ok)
    -- Synchronous clock — grab already completed.
    assert.is_true(voice.available)
    assert.is_nil(voice.last_error)
    assert.are.equal(softcut_runtime.RECORDED_MARKER, voice.config.sample_path)
    assert.is_true(rt.voices[1].sample_loaded)
  end)

  it("plays a recorded sample without a file on disk", function()
    local rt = softcut_runtime.new()
    local voice = softcut_zig.new(1, rt, {sample_path = nil})
    voice:grab({duration = 0.5})
    local ok = voice:note_on(60, 0.8)
    assert.is_true(ok)
    assert.are.equal(60, voice.active_note)
  end)

  it("returns an error when the runtime lacks record support", function()
    local legacy_rt = {
      voices = {[1] = {}},
      file_exists = function() return false end,
    }
    local voice = softcut_zig.new(1, legacy_rt, {sample_path = nil})
    local ok, err = voice:grab({duration = 1})
    assert.is_nil(ok)
    assert.are.equal("record_unsupported", err)
  end)
end)
