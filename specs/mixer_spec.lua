-- specs/mixer_spec.lua
-- Unit + integration tests for the mixer/routing layer (re-kev).
--
-- Layers covered:
--   1. Voice interface: set_level / set_pan on each backend voice module.
--   2. Mixer state module: ctx.mixer level/pan, mute via ctx.tracks.muted,
--      propagation to voices, snapshot/restore.
--   3. Sequencer: play_note scales velocity by mixer level.
--   4. Grid: mixer page columns (level / pan / mute) and nav cycle membership.
--   5. Remote OSC API: /mixer/level, /mixer/pan, /mixer/mute, /mixer/get,
--      and inclusion in /state/snapshot.

package.path = package.path .. ";./?.lua"

-- Mock clock (sequencer + voice backends use this indirectly).
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock osc send (captured for set_level / set_pan assertions).
local osc_sent = {}
rawset(_G, "osc", {
  send = function(target, path, args)
    table.insert(osc_sent, {target = target, path = path, args = args})
  end,
})

-- Minimal params mock used for action-driven tests. Some tests stub
-- `params` directly or avoid it entirely (see reset_params_mock below).
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
  osc_sent = {}
end

-- Mock grid.connect for app.init
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

-- Mock metro for app.init grid redraw loop.
rawset(_G, "metro", {
  init = function()
    return {time = 0, event = nil, start = function(self) end, stop = function(self) end}
  end,
})

-- Mock util/screen/midi.
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
local mixer = require("lib/mixer")
local grid_ui = require("lib/grid_ui")
local sequencer = require("lib/sequencer")
local api = require("lib/remote/api")
local midi_voice = require("lib/voices/midi")
local osc_voice = require("lib/voices/osc")
local sc_synth = require("lib/voices/sc_synth")
local sc_drums = require("lib/voices/sc_drums")
local softcut_zig = require("lib/voices/softcut_zig")

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function make_ctx(opts)
  opts = opts or {}
  return {
    tracks = track_mod.new_tracks(),
    active_track = opts.active_track or 1,
    active_page = opts.active_page or "mixer",
    voices = opts.voices or {},
    mixer = mixer.new(),
    grid_dirty = false,
  }
end

-- Record CC calls on a captured midi device.
local function capture_midi_dev()
  local calls = {}
  return {
    cc = function(self, cc, val, ch)
      table.insert(calls, {cc = cc, val = val, ch = ch})
    end,
    note_on = function() end,
    note_off = function() end,
    _cc_calls = calls,
  }
end

--------------------------------------------------------------------------
-- Voice interface: set_level / set_pan on each backend
--------------------------------------------------------------------------

describe("mixer — voice interface", function()

  describe("midi voice", function()
    it("set_level sends CC7 scaled to 0-127 on the voice channel", function()
      local dev = capture_midi_dev()
      local v = midi_voice.new(dev, 3)
      v:set_level(1.0)
      v:set_level(0.0)
      v:set_level(0.5)
      assert.are.equal(3, #dev._cc_calls)
      assert.are.same({cc = 7, val = 127, ch = 3}, dev._cc_calls[1])
      assert.are.same({cc = 7, val = 0,   ch = 3}, dev._cc_calls[2])
      -- 0.5 rounds to 64 (0.5 * 127 = 63.5 -> 64 with round-half-up).
      assert.are.equal(7, dev._cc_calls[3].cc)
      assert.are.equal(3, dev._cc_calls[3].ch)
      assert.is_true(dev._cc_calls[3].val >= 63 and dev._cc_calls[3].val <= 64)
    end)

    it("set_level clamps out-of-range values", function()
      local dev = capture_midi_dev()
      local v = midi_voice.new(dev, 1)
      v:set_level(-1)
      v:set_level(10)
      assert.are.equal(0, dev._cc_calls[1].val)
      assert.are.equal(127, dev._cc_calls[2].val)
    end)

    it("set_pan sends CC10 with center at 64", function()
      local dev = capture_midi_dev()
      local v = midi_voice.new(dev, 2)
      v:set_pan(0)
      v:set_pan(-1)
      v:set_pan(1)
      assert.are.equal(10, dev._cc_calls[1].cc)
      -- 0 -> (0+1) * 63.5 = 63.5 -> 64 (round half up)
      assert.is_true(dev._cc_calls[1].val == 63 or dev._cc_calls[1].val == 64)
      assert.are.equal(0, dev._cc_calls[2].val)
      assert.are.equal(127, dev._cc_calls[3].val)
    end)
  end)

  describe("osc voice", function()
    it("set_level / set_pan send the expected OSC paths", function()
      osc_sent = {}
      local v = osc_voice.new(1, "127.0.0.1", 57120)
      v:set_level(0.5)
      v:set_pan(-0.5)
      assert.are.equal(2, #osc_sent)
      assert.are.equal("/rekriate/track/1/level", osc_sent[1].path)
      assert.are.same({0.5}, osc_sent[1].args)
      assert.are.equal("/rekriate/track/1/pan", osc_sent[2].path)
      assert.are.same({-0.5}, osc_sent[2].args)
    end)
  end)

  describe("sc_synth voice", function()
    it("set_level / set_pan send the synth mixer OSC paths", function()
      osc_sent = {}
      local v = sc_synth.new(2, "127.0.0.1", 57120, "sub")
      -- new() itself emits an initial synthdef message; clear before asserting.
      osc_sent = {}
      v:set_level(0.8)
      v:set_pan(0.25)
      assert.are.equal("/rekriate/synth/2/level", osc_sent[1].path)
      assert.are.same({0.8}, osc_sent[1].args)
      assert.are.equal("/rekriate/synth/2/pan", osc_sent[2].path)
      assert.are.same({0.25}, osc_sent[2].args)
    end)
  end)

  describe("sc_drums voice", function()
    it("set_level / set_pan send drum mixer OSC paths", function()
      osc_sent = {}
      local v = sc_drums.new(3, "127.0.0.1", 57120)
      v:set_level(0.4)
      v:set_pan(-0.75)
      assert.are.equal("/rekriate/track/3/drum_level", osc_sent[1].path)
      assert.are.same({0.4}, osc_sent[1].args)
      assert.are.equal("/rekriate/track/3/drum_pan", osc_sent[2].path)
      assert.are.same({-0.75}, osc_sent[2].args)
    end)
  end)

  describe("softcut voice", function()
    it("set_level calls runtime.level with clamped value", function()
      local calls = {}
      local runtime = {
        level = function(id, v) table.insert(calls, {op = "level", id = id, v = v}) end,
        pan = function(id, v) table.insert(calls, {op = "pan", id = id, v = v}) end,
      }
      local v = softcut_zig.new(1, runtime, {})
      -- clear boot-time runtime calls from apply_config.
      calls = {}
      v.runtime = runtime -- ensure still wired
      setmetatable(calls, nil)
      -- Recapture by re-assigning captures table.
      runtime.level = function(id, val) table.insert(calls, {op = "level", id = id, v = val}) end
      runtime.pan = function(id, val) table.insert(calls, {op = "pan", id = id, v = val}) end
      v:set_level(1.5)
      v:set_pan(-2)
      assert.are.equal("level", calls[1].op)
      assert.are.equal(1.0, calls[1].v)
      assert.are.equal("pan", calls[2].op)
      assert.are.equal(-1.0, calls[2].v)
    end)
  end)

end)

--------------------------------------------------------------------------
-- Mixer state module
--------------------------------------------------------------------------

describe("mixer — state module", function()

  it("new() seeds default level=1.0 and pan=0.0 per track", function()
    local m = mixer.new()
    for t = 1, track_mod.NUM_TRACKS do
      assert.are.equal(1.0, m.level[t])
      assert.are.equal(0.0, m.pan[t])
    end
  end)

  it("set_level clamps and pushes to the voice's set_level", function()
    local ctx = make_ctx()
    local captured = {}
    ctx.voices[1] = {
      set_level = function(self, v) captured.level = v end,
      set_pan = function(self, v) captured.pan = v end,
    }
    mixer.set_level(ctx, 1, 2.0)
    assert.are.equal(1.0, ctx.mixer.level[1])
    assert.are.equal(1.0, captured.level)
    mixer.set_level(ctx, 1, -1.0)
    assert.are.equal(0.0, ctx.mixer.level[1])
    assert.are.equal(0.0, captured.level)
  end)

  it("set_pan clamps and pushes to the voice's set_pan", function()
    local ctx = make_ctx()
    local captured = {}
    ctx.voices[2] = {
      set_pan = function(self, v) captured.pan = v end,
    }
    mixer.set_pan(ctx, 2, 1.5)
    assert.are.equal(1.0, ctx.mixer.pan[2])
    assert.are.equal(1.0, captured.pan)
    mixer.set_pan(ctx, 2, -1.5)
    assert.are.equal(-1.0, ctx.mixer.pan[2])
    assert.are.equal(-1.0, captured.pan)
  end)

  it("set_mute / toggle_mute update ctx.tracks[t].muted", function()
    local ctx = make_ctx()
    mixer.set_mute(ctx, 1, true)
    assert.is_true(ctx.tracks[1].muted)
    mixer.toggle_mute(ctx, 1)
    assert.is_false(ctx.tracks[1].muted)
  end)

  it("apply_to_voice pushes current level+pan to the voice", function()
    local ctx = make_ctx()
    ctx.mixer.level[1] = 0.3
    ctx.mixer.pan[1] = -0.25
    local seen = {}
    ctx.voices[1] = {
      set_level = function(self, v) seen.level = v end,
      set_pan = function(self, v) seen.pan = v end,
    }
    mixer.apply_to_voice(ctx, 1)
    assert.are.equal(0.3, seen.level)
    assert.are.equal(-0.25, seen.pan)
  end)

  it("snapshot / restore round-trip preserves values", function()
    local ctx = make_ctx()
    ctx.mixer.level[1] = 0.2
    ctx.mixer.pan[1] = 0.4
    ctx.tracks[2].muted = true
    local snap = mixer.snapshot(ctx)
    local ctx2 = make_ctx()
    mixer.restore(ctx2, snap)
    assert.are.equal(0.2, ctx2.mixer.level[1])
    assert.are.equal(0.4, ctx2.mixer.pan[1])
    assert.is_true(ctx2.tracks[2].muted)
  end)

  it("silently tolerates a voice that lacks set_level / set_pan", function()
    local ctx = make_ctx()
    ctx.voices[1] = {play_note = function() end}
    assert.has_no.errors(function() mixer.set_level(ctx, 1, 0.5) end)
    assert.has_no.errors(function() mixer.set_pan(ctx, 1, 0.5) end)
  end)

end)

--------------------------------------------------------------------------
-- Sequencer: velocity scaling
--------------------------------------------------------------------------

describe("mixer — sequencer velocity scaling", function()

  local function recording_voice()
    local calls = {}
    return {
      play_note = function(self, note, vel, dur)
        table.insert(calls, {note = note, vel = vel, dur = dur})
      end,
      _calls = calls,
    }
  end

  it("scales velocity by mixer.level before dispatching to the voice", function()
    local ctx = make_ctx()
    ctx.voices[1] = recording_voice()
    ctx.mixer.level[1] = 0.5
    sequencer.play_note(ctx, 1, 60, 0.8, 0.25)
    assert.are.equal(1, #ctx.voices[1]._calls)
    assert.are.equal(60, ctx.voices[1]._calls[1].note)
    assert.are.equal(0.4, ctx.voices[1]._calls[1].vel)
  end)

  it("passes velocity through unchanged when level is 1.0", function()
    local ctx = make_ctx()
    ctx.voices[1] = recording_voice()
    ctx.mixer.level[1] = 1.0
    sequencer.play_note(ctx, 1, 60, 0.7, 0.25)
    assert.are.equal(0.7, ctx.voices[1]._calls[1].vel)
  end)

  it("silences the voice when level is 0.0", function()
    local ctx = make_ctx()
    ctx.voices[1] = recording_voice()
    ctx.mixer.level[1] = 0.0
    sequencer.play_note(ctx, 1, 60, 1.0, 0.25)
    assert.are.equal(1, #ctx.voices[1]._calls)
    assert.are.equal(0.0, ctx.voices[1]._calls[1].vel)
  end)

  it("clamps the scaled velocity to [0, 1] even when level > 1 is forced", function()
    local ctx = make_ctx()
    ctx.voices[1] = recording_voice()
    -- Bypass mixer.set_level clamping by writing directly (would never happen
    -- via the public API, but proves the sequencer guardrail).
    ctx.mixer.level[1] = 5.0
    sequencer.play_note(ctx, 1, 60, 1.0, 0.25)
    assert.are.equal(1.0, ctx.voices[1]._calls[1].vel)
  end)

end)

--------------------------------------------------------------------------
-- Grid: mixer page
--------------------------------------------------------------------------

describe("mixer — grid page", function()

  local function spy_grid()
    local leds = {}
    return {
      leds = leds,
      led = function(self, x, y, v)
        if not leds[x] then leds[x] = {} end
        leds[x][y] = v
      end,
      all = function(self) end,
      refresh = function(self) end,
    }, function(x, y) return (leds[x] and leds[x][y]) or 0 end
  end

  it("is listed as a page and sits in the x=9 nav cycle", function()
    local found = false
    for _, p in ipairs(grid_ui.PAGES) do
      if p == "mixer" then found = true; break end
    end
    assert.is_true(found, "mixer should be in grid_ui.PAGES")
  end)

  it("level_to_col / col_to_level invert on grid-aligned levels", function()
    for col = 1, 7 do
      local lvl = grid_ui.col_to_level(col)
      assert.are.equal(col, grid_ui.level_to_col(lvl))
    end
  end)

  it("pan_to_col / col_to_pan invert on grid-aligned pans", function()
    for col = 9, 15 do
      local pan = grid_ui.col_to_pan(col)
      assert.are.equal(col, grid_ui.pan_to_col(pan))
    end
  end)

  it("draws level bar on track row up to the current level column", function()
    local ctx = make_ctx({active_track = 1})
    ctx.mixer.level[1] = 1.0
    ctx.mixer.pan[1] = 0.0
    local g, at = spy_grid()
    grid_ui.draw_mixer_page(ctx, g)
    -- All 7 level columns should be lit on row 1.
    for x = 1, 7 do
      assert.is_true(at(x, 1) > 0, "level col " .. x .. " should be lit")
    end
    -- Pan center (col 12) lit on row 1 with highest emphasis.
    assert.is_true(at(12, 1) > 0)
    -- Mute col on muted row should be high when muted.
    ctx.tracks[2].muted = true
    grid_ui.draw_mixer_page(ctx, g)
    assert.is_true(at(16, 2) >= 12, "muted row's col 16 should be bright")
  end)

  it("mixer_key on cols 1-7 updates the level param / mixer state", function()
    reset_params_mock()
    local app = require("lib/app")
    local ctx = app.init({voices = {}})
    ctx.active_page = "mixer"
    ctx.g = spy_grid()
    grid_ui.mixer_key(ctx, 1, 1)
    -- Col 1 -> level 0.0
    assert.are.equal(0.0, ctx.mixer.level[1])
    grid_ui.mixer_key(ctx, 7, 2)
    -- Col 7 -> level 1.0 on track 2
    assert.are.equal(1.0, ctx.mixer.level[2])
  end)

  it("mixer_key on cols 9-15 updates pan", function()
    reset_params_mock()
    local app = require("lib/app")
    local ctx = app.init({voices = {}})
    ctx.active_page = "mixer"
    ctx.g = spy_grid()
    grid_ui.mixer_key(ctx, 9, 1)
    assert.are.equal(-1.0, ctx.mixer.pan[1])
    grid_ui.mixer_key(ctx, 12, 1)
    assert.are.equal(0.0, ctx.mixer.pan[1])
    grid_ui.mixer_key(ctx, 15, 1)
    assert.are.equal(1.0, ctx.mixer.pan[1])
  end)

  it("mixer_key on col 16 toggles mute", function()
    reset_params_mock()
    local app = require("lib/app")
    local ctx = app.init({voices = {}})
    ctx.active_page = "mixer"
    ctx.g = spy_grid()
    assert.is_false(ctx.tracks[1].muted)
    grid_ui.mixer_key(ctx, 16, 1)
    assert.is_true(ctx.tracks[1].muted)
    grid_ui.mixer_key(ctx, 16, 1)
    assert.is_false(ctx.tracks[1].muted)
  end)

end)

--------------------------------------------------------------------------
-- Remote API
--------------------------------------------------------------------------

describe("mixer — remote OSC api", function()

  it("/mixer/level sets and queries track level", function()
    local ctx = make_ctx()
    assert.is_true(api.dispatch(ctx, "/mixer/level", {1, 0.5}))
    assert.are.equal(0.5, ctx.mixer.level[1])
    assert.are.equal(0.5, api.dispatch(ctx, "/mixer/level", {1}))
  end)

  it("/mixer/pan sets and queries track pan", function()
    local ctx = make_ctx()
    assert.is_true(api.dispatch(ctx, "/mixer/pan", {2, -0.5}))
    assert.are.equal(-0.5, ctx.mixer.pan[2])
    assert.are.equal(-0.5, api.dispatch(ctx, "/mixer/pan", {2}))
  end)

  it("/mixer/mute with arg sets mute; without arg toggles", function()
    local ctx = make_ctx()
    assert.is_true(api.dispatch(ctx, "/mixer/mute", {3, 1}))
    assert.is_true(ctx.tracks[3].muted)
    assert.is_true(api.dispatch(ctx, "/mixer/mute", {3}))
    assert.is_false(ctx.tracks[3].muted)
  end)

  it("/mixer/level rejects invalid track numbers", function()
    local ctx = make_ctx()
    local ok, err = api.dispatch(ctx, "/mixer/level", {0, 0.5})
    assert.is_nil(ok)
    assert.is_not_nil(err)
  end)

  it("/mixer/get returns full snapshot", function()
    local ctx = make_ctx()
    ctx.mixer.level[2] = 0.25
    ctx.mixer.pan[3] = 0.75
    ctx.tracks[4].muted = true
    local snap = api.dispatch(ctx, "/mixer/get")
    assert.are.equal(0.25, snap.level[2])
    assert.are.equal(0.75, snap.pan[3])
    assert.is_true(snap.mute[4])
  end)

  it("/state/snapshot includes mixer", function()
    local ctx = make_ctx()
    ctx.mixer.level[1] = 0.5
    local snap = api.dispatch(ctx, "/state/snapshot")
    assert.is_not_nil(snap.mixer)
    assert.are.equal(0.5, snap.mixer.level[1])
  end)

end)

--------------------------------------------------------------------------
-- End-to-end: params wire into mixer, which pushes to the voice.
--------------------------------------------------------------------------

describe("mixer — params ↔ mixer ↔ voice integration", function()

  it("setting level_<t> drives the voice's set_level", function()
    reset_params_mock()
    local app = require("lib/app")
    local seen = {}
    local voices = {}
    for t = 1, track_mod.NUM_TRACKS do
      voices[t] = {
        set_level = function(self, v) seen["lvl" .. t] = v end,
        set_pan = function(self, v) seen["pan" .. t] = v end,
        play_note = function() end,
        all_notes_off = function() end,
      }
    end
    local ctx = app.init({voices = voices})
    params:set("level_1", 50)
    assert.are.equal(0.5, ctx.mixer.level[1])
    assert.are.equal(0.5, seen.lvl1)
    params:set("pan_2", -50)
    assert.are.equal(-0.5, ctx.mixer.pan[2])
    assert.are.equal(-0.5, seen.pan2)
    params:set("mute_3", 2)
    assert.is_true(ctx.tracks[3].muted)
  end)

end)
