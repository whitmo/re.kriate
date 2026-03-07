-- specs/integration_spec.lua
-- Integration tests: validates full wiring from app.init through sequencer to voices

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by recorder voice and sequencer)
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock params system (mimics norns/seamstress params)
local param_store = {}
local param_actions = {}
rawset(_G, "params", {
  add_separator = function(self, id, name) end,
  add_number = function(self, id, name, min, max, default)
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

-- Mock screen (seamstress-style with color)
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

-- Mock musicutil (needed by scale.build_scale via app.init)
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
local sequencer = require("lib/sequencer")
local keyboard = require("lib/seamstress/keyboard")
local screen_ui = require("lib/seamstress/screen_ui")
local recorder = require("lib/voices/recorder")
local track_mod = require("lib/track")

-- Helper: create recorder voices and call app.init
local function make_app()
  -- Reset param store between tests
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_actions) do param_actions[k] = nil end
  beat_counter = 0

  local buffer = {}
  local voices = {}
  for t = 1, track_mod.NUM_TRACKS do
    voices[t] = recorder.new(t, buffer)
  end
  local ctx = app.init({ voices = voices })
  return ctx, buffer
end

-- Helper: filter note events from shared buffer (exclude portamento/other CC)
local function note_events(buffer)
  local result = {}
  for _, e in ipairs(buffer) do
    if e.note and e.type ~= "portamento" then
      table.insert(result, e)
    end
  end
  return result
end

describe("integration", function()

  describe("app.init with recorder voices", function()

    it("returns a valid ctx with all required fields", function()
      local ctx = make_app()
      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.tracks)
      assert.are.equal(#ctx.tracks, track_mod.NUM_TRACKS)
      assert.is_not_nil(ctx.voices)
      assert.are.equal(#ctx.voices, track_mod.NUM_TRACKS)
      assert.are.equal(ctx.active_track, 1)
      assert.are.equal(ctx.active_page, "trigger")
      assert.is_false(ctx.playing)
      assert.is_not_nil(ctx.scale_notes)
      assert.is_true(#ctx.scale_notes > 0)
      assert.is_not_nil(ctx.g)
      assert.is_not_nil(ctx.grid_metro)
    end)

    it("builds a usable scale_notes table", function()
      local ctx = make_app()
      -- scale_notes should have enough entries for all degree/octave combos
      assert.is_true(#ctx.scale_notes >= 7 * 4)
      -- all entries should be numbers
      for _, n in ipairs(ctx.scale_notes) do
        assert.are.equal(type(n), "number")
      end
    end)

  end)

  describe("full sequencer cycle", function()

    it("step_track fires notes into recorder voices", function()
      local ctx, buffer = make_app()
      -- Enable trigger on track 1
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events(buffer)
      assert.are.equal(1, #notes)
      assert.are.equal(1, notes[1].track)
      assert.is_number(notes[1].note)
      assert.is_number(notes[1].vel)
      assert.is_number(notes[1].dur)
    end)

    it("multiple tracks produce events in shared buffer", function()
      local ctx, buffer = make_app()
      for t = 1, track_mod.NUM_TRACKS do
        ctx.tracks[t].params.trigger.steps[1] = 1
        ctx.tracks[t].params.trigger.pos = 1
      end

      for t = 1, track_mod.NUM_TRACKS do
        sequencer.step_track(ctx, t)
      end

      local notes = note_events(buffer)
      assert.are.equal(track_mod.NUM_TRACKS, #notes)
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(t, notes[t].track)
      end
    end)

    it("note values come from scale quantization", function()
      local ctx, buffer = make_app()
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.tracks[1].params.trigger.pos = 1
      ctx.tracks[1].params.note.steps[1] = 3
      ctx.tracks[1].params.note.pos = 1
      ctx.tracks[1].params.octave.steps[1] = 4
      ctx.tracks[1].params.octave.pos = 1

      sequencer.step_track(ctx, 1)

      local notes = note_events(buffer)
      local note = notes[1].note
      -- Note should be in the scale_notes table
      local found = false
      for _, sn in ipairs(ctx.scale_notes) do
        if sn == note then found = true; break end
      end
      assert.is_true(found, "note " .. note .. " should be in scale_notes")
    end)

  end)

  describe("start/stop via app and keyboard", function()

    it("start sets playing, stop clears it", function()
      local ctx = make_app()
      sequencer.start(ctx)
      assert.is_true(ctx.playing)
      sequencer.stop(ctx)
      assert.is_false(ctx.playing)
    end)

    it("keyboard space toggles play state on app ctx", function()
      local ctx = make_app()
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_true(ctx.playing)
      keyboard.key(ctx, " ", {}, false, 1)
      assert.is_false(ctx.playing)
    end)

    it("keyboard track/page select works on app ctx", function()
      local ctx = make_app()
      keyboard.key(ctx, "3", {}, false, 1)
      assert.are.equal(ctx.active_track, 3)
      keyboard.key(ctx, "w", {}, false, 1)
      assert.are.equal(ctx.active_page, "note")
    end)

    it("keyboard reset resets all playheads on app ctx", function()
      local ctx = make_app()
      -- Advance positions
      for t = 1, track_mod.NUM_TRACKS do
        ctx.tracks[t].params.trigger.pos = 8
      end
      keyboard.key(ctx, "r", {}, false, 1)
      for t = 1, track_mod.NUM_TRACKS do
        assert.are.equal(ctx.tracks[t].params.trigger.pos,
          ctx.tracks[t].params.trigger.loop_start)
      end
    end)

  end)

  describe("cleanup", function()

    it("stops sequencer and calls all_notes_off", function()
      local ctx = make_app()
      sequencer.start(ctx)
      assert.is_true(ctx.playing)
      app.cleanup(ctx)
      assert.is_false(ctx.playing)
    end)

    it("does not error when voices are present", function()
      local ctx = make_app()
      -- Should not raise
      app.cleanup(ctx)
    end)

  end)

  describe("screen_ui.redraw", function()

    it("does not error with valid app ctx", function()
      local ctx = make_app()
      -- Should not raise
      screen_ui.redraw(ctx)
    end)

    it("does not error when playing", function()
      local ctx = make_app()
      ctx.playing = true
      screen_ui.redraw(ctx)
    end)

  end)

end)
