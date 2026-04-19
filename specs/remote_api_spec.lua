-- specs/remote_api_spec.lua
-- Tests for the transport-agnostic remote control API

package.path = package.path .. ";./?.lua"

-- Mock norns globals (same pattern as integration_spec)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local param_store = {}
local param_actions = {}
rawset(_G, "params", {
  add_separator = function(self, id, name) end,
  add_group = function(self, id, name, n) end,
  show = function(self, id) end,
  hide = function(self, id) end,
  add_number = function(self, id, name, min, max, default, units, formatter)
    param_store[id] = default
  end,
  add_text = function(self, id, name, default)
    param_store[id] = default
  end,
  add_option = function(self, id, name, options, default)
    param_store[id] = default
  end,
  set_action = function(self, id, fn) param_actions[id] = fn end,
  get = function(self, id) return param_store[id] end,
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
      time = 0, event = nil,
      start = function() end, stop = function() end,
    }
  end,
})

rawset(_G, "screen", {
  clear = function() end, level = function() end,
  move = function() end, text = function() end,
  update = function() end,
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

local app = require("lib/app")
local track_mod = require("lib/track")
local recorder = require("lib/voices/recorder")
local api = require("lib/remote/api")

-- Helper: fresh app context with recorder voices
local function make_ctx()
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  return app.init({ voices = voices }), buffer
end

describe("remote API", function()

  -- ----------------------------------------------------------------
  -- Transport
  -- ----------------------------------------------------------------

  describe("/transport", function()

    it("/play starts sequencer", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/transport/play")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_true(ctx.playing)
    end)

    it("/stop stops sequencer", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/transport/play")
      local ok = api.dispatch(ctx, "/transport/stop")
      assert.is_true(ok)
      assert.is_false(ctx.playing)
    end)

    it("/toggle toggles play state", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/transport/toggle")
      assert.is_true(ctx.playing)
      api.dispatch(ctx, "/transport/toggle")
      assert.is_false(ctx.playing)
    end)

    it("/reset resets all playheads", function()
      local ctx = make_ctx()
      ctx.tracks[1].params.trigger.pos = 8
      ctx.tracks[2].params.note.pos = 12
      api.dispatch(ctx, "/transport/reset")
      assert.are.equal(ctx.tracks[1].params.trigger.pos,
        ctx.tracks[1].params.trigger.loop_start)
      assert.are.equal(ctx.tracks[2].params.note.pos,
        ctx.tracks[2].params.note.loop_start)
    end)

    it("/state returns playing/stopped", function()
      local ctx = make_ctx()
      local state = api.dispatch(ctx, "/transport/state")
      assert.are.equal(state, "stopped")
      api.dispatch(ctx, "/transport/play")
      state = api.dispatch(ctx, "/transport/state")
      assert.are.equal(state, "playing")
    end)

  end)

  -- ----------------------------------------------------------------
  -- Track
  -- ----------------------------------------------------------------

  describe("/track", function()

    it("/select changes active track", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/track/select", {3})
      assert.are.equal(ctx.active_track, 3)
    end)

    it("/select rejects invalid track", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/track/select", {5})
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)

    it("/mute toggles mute", function()
      local ctx = make_ctx()
      assert.is_false(ctx.tracks[2].muted)
      api.dispatch(ctx, "/track/mute", {2})
      assert.is_true(ctx.tracks[2].muted)
      api.dispatch(ctx, "/track/mute", {2})
      assert.is_false(ctx.tracks[2].muted)
    end)

    it("/mute sets explicit value", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/track/mute", {1, 1})
      assert.is_true(ctx.tracks[1].muted)
      api.dispatch(ctx, "/track/mute", {1, 0})
      assert.is_false(ctx.tracks[1].muted)
    end)

    it("/direction sets and gets direction", function()
      local ctx = make_ctx()
      -- set
      local ok = api.dispatch(ctx, "/track/direction", {1, "reverse"})
      assert.is_true(ok)
      assert.are.equal(ctx.tracks[1].direction, "reverse")
      -- get (no second arg)
      local dir = api.dispatch(ctx, "/track/direction", {1})
      assert.are.equal(dir, "reverse")
    end)

    it("/direction rejects invalid mode", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/track/direction", {1, "bogus"})
      assert.is_nil(ok)
      assert.are.equal(err, "invalid direction")
    end)

    it("/division sets and gets division", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/track/division", {2, 5})
      assert.are.equal(ctx.tracks[2].division, 5)
      local d = api.dispatch(ctx, "/track/division", {2})
      assert.are.equal(d, 5)
    end)

    it("/division rejects out of range", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/track/division", {1, 9})
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)

    it("/get returns track info", function()
      local ctx = make_ctx()
      ctx.tracks[3].muted = true
      ctx.tracks[3].direction = "pendulum"
      ctx.tracks[3].division = 4
      local info = api.dispatch(ctx, "/track/get", {3})
      assert.are.equal(info.division, 4)
      assert.is_true(info.muted)
      assert.are.equal(info.direction, "pendulum")
    end)

    it("/active returns active track", function()
      local ctx = make_ctx()
      ctx.active_track = 2
      local t = api.dispatch(ctx, "/track/active")
      assert.are.equal(t, 2)
    end)

  end)

  -- ----------------------------------------------------------------
  -- Step
  -- ----------------------------------------------------------------

  describe("/step", function()

    it("/set sets a step value", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/step/set", {1, "note", 5, 7})
      assert.are.equal(ctx.tracks[1].params.note.steps[5], 7)
    end)

    it("/get reads a step value", function()
      local ctx = make_ctx()
      ctx.tracks[2].params.velocity.steps[3] = 6
      local v = api.dispatch(ctx, "/step/get", {2, "velocity", 3})
      assert.are.equal(v, 6)
    end)

    it("/set rejects invalid param name", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/step/set", {1, "bogus", 1, 1})
      assert.is_nil(ok)
      assert.are.equal(err, "invalid param name")
    end)

    it("/set rejects invalid step", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/step/set", {1, "note", 17, 1})
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)

    it("/set rejects value out of range for trigger", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/step/set", {1, "trigger", 1, 5})
      assert.is_nil(ok)
      assert.truthy(err:find("out of range"))
    end)

    it("/set rejects value out of range for note", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/step/set", {1, "note", 1, 0})
      assert.is_nil(ok)
      assert.truthy(err:find("out of range"))
    end)

    it("/toggle toggles a trigger step", function()
      local ctx = make_ctx()
      local orig = ctx.tracks[1].params.trigger.steps[1]
      api.dispatch(ctx, "/step/toggle", {1, 1})
      assert.are_not.equal(ctx.tracks[1].params.trigger.steps[1], orig)
      api.dispatch(ctx, "/step/toggle", {1, 1})
      assert.are.equal(ctx.tracks[1].params.trigger.steps[1], orig)
    end)

  end)

  -- ----------------------------------------------------------------
  -- Pattern
  -- ----------------------------------------------------------------

  describe("/pattern", function()

    it("/get returns all 16 steps", function()
      local ctx = make_ctx()
      local steps = api.dispatch(ctx, "/pattern/get", {1, "trigger"})
      assert.are.equal(#steps, 16)
    end)

    it("/get returns a copy, not the original", function()
      local ctx = make_ctx()
      local steps = api.dispatch(ctx, "/pattern/get", {1, "note"})
      steps[1] = 999
      assert.are_not.equal(ctx.tracks[1].params.note.steps[1], 999)
    end)

    it("/set writes all 16 steps", function()
      local ctx = make_ctx()
      local vals = {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0}
      local args = {1, "trigger"}
      for _, v in ipairs(vals) do args[#args + 1] = v end
      api.dispatch(ctx, "/pattern/set", args)
      for i = 1, 16 do
        assert.are.equal(ctx.tracks[1].params.trigger.steps[i], vals[i])
      end
    end)

    it("/set rejects out of range values", function()
      local ctx = make_ctx()
      -- note range is 1-7, value 9 should fail
      local args = {1, "note"}
      for i = 1, 16 do args[#args + 1] = (i == 8) and 9 or 4 end
      local ok, err = api.dispatch(ctx, "/pattern/set", args)
      assert.is_nil(ok)
      assert.truthy(err:find("out of range"))
    end)

    it("/set rejects too few values", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/pattern/set", {1, "trigger", 1, 0})
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)

  end)

  -- ----------------------------------------------------------------
  -- Loop
  -- ----------------------------------------------------------------

  describe("/loop", function()

    it("/set changes loop boundaries", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/loop/set", {1, "note", 3, 10})
      local p = ctx.tracks[1].params.note
      assert.are.equal(p.loop_start, 3)
      assert.are.equal(p.loop_end, 10)
    end)

    it("/set rejects start > end", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/loop/set", {1, "note", 10, 3})
      assert.is_nil(ok)
      assert.truthy(err:find("start must be"))
    end)

    it("/set rejects out of range bounds", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/loop/set", {1, "note", 0, 16})
      assert.is_nil(ok)
      assert.truthy(err:find("bounds"))
    end)

    it("/get returns loop info", function()
      local ctx = make_ctx()
      ctx.tracks[2].params.octave.loop_start = 5
      ctx.tracks[2].params.octave.loop_end = 12
      ctx.tracks[2].params.octave.pos = 7
      local info = api.dispatch(ctx, "/loop/get", {2, "octave"})
      assert.are.equal(info.loop_start, 5)
      assert.are.equal(info.loop_end, 12)
      assert.are.equal(info.pos, 7)
    end)

  end)

  -- ----------------------------------------------------------------
  -- Page
  -- ----------------------------------------------------------------

  describe("/page", function()

    it("/select changes active page", function()
      local ctx = make_ctx()
      api.dispatch(ctx, "/page/select", {"velocity"})
      assert.are.equal(ctx.active_page, "velocity")
    end)

    it("/select rejects invalid page", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/page/select", {"bogus"})
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)

    it("/active returns current page", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      local p = api.dispatch(ctx, "/page/active")
      assert.are.equal(p, "ratchet")
    end)

  end)

  -- ----------------------------------------------------------------
  -- Scale
  -- ----------------------------------------------------------------

  describe("/scale", function()

    it("/notes returns scale notes", function()
      local ctx = make_ctx()
      local notes = api.dispatch(ctx, "/scale/notes")
      assert.is_true(#notes > 0)
      -- should be a copy
      notes[1] = -999
      assert.are_not.equal(ctx.scale_notes[1], -999)
    end)

  end)

  -- ----------------------------------------------------------------
  -- State snapshot
  -- ----------------------------------------------------------------

  describe("/state/snapshot", function()

    it("returns full sequencer state", function()
      local ctx = make_ctx()
      ctx.active_track = 3
      ctx.active_page = "octave"
      ctx.tracks[2].muted = true
      ctx.tracks[4].division = 6

      local snap = api.dispatch(ctx, "/state/snapshot")
      assert.is_false(snap.playing)
      assert.are.equal(snap.active_track, 3)
      assert.are.equal(snap.active_page, "octave")
      assert.are.equal(#snap.tracks, 4)
      assert.is_true(snap.tracks[2].muted)
      assert.are.equal(snap.tracks[4].division, 6)
      -- each track has all params
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        assert.is_not_nil(snap.tracks[1].params[name])
        assert.are.equal(#snap.tracks[1].params[name].steps, 16)
      end
    end)

  end)

  -- ----------------------------------------------------------------
  -- Dispatch
  -- ----------------------------------------------------------------

  describe("dispatch", function()

    it("returns error for unknown path", function()
      local ctx = make_ctx()
      local ok, err = api.dispatch(ctx, "/bogus/path")
      assert.is_nil(ok)
      assert.is_not_nil(err)
      assert.truthy(err:find("unknown path"))
    end)

    it("marks grid dirty on commands", function()
      local ctx = make_ctx()
      ctx.grid_dirty = false
      api.dispatch(ctx, "/transport/play")
      assert.is_true(ctx.grid_dirty)
    end)

  end)

  -- ----------------------------------------------------------------
  -- Introspection
  -- ----------------------------------------------------------------

  describe("list_paths", function()

    it("returns sorted array of all paths", function()
      local paths = api.list_paths()
      assert.is_true(#paths > 0)
      -- check sorted
      for i = 2, #paths do
        assert.is_true(paths[i] >= paths[i-1])
      end
      -- spot check known paths
      local found_play = false
      local found_snapshot = false
      for _, p in ipairs(paths) do
        if p == "/transport/play" then found_play = true end
        if p == "/state/snapshot" then found_snapshot = true end
      end
      assert.is_true(found_play)
      assert.is_true(found_snapshot)
    end)

  end)

end)
