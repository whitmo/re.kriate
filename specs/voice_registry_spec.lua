-- specs/voice_registry_spec.lua
-- Tests for lib/voice_registry.lua: the instrument integration boundary.
--
-- The contract (see docs/adapters.md): integrating a new instrument is ONE
-- voice_registry.register("name", factory) call. The factory receives
-- (ctx, track), reads any config it needs from params itself, and returns
-- an object satisfying the voice interface (required: play_note,
-- all_notes_off; everything else is an optional capability callers guard
-- on). No edits to lib/app.lua required.

package.path = package.path .. ";./?.lua"

rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function() return 1 end,
  cancel = function() end,
  sync = function() end,
})

-- osc global (sc_synth/sc_drums/osc voices send via it at play/announce time)
if rawget(_G, "osc") == nil then
  rawset(_G, "osc", { send = function() end })
end

-- Minimal params stub: get/set by id with defaults the factories expect.
local function stub_params(values)
  local store = values or {}
  rawset(_G, "params", {
    get = function(_, id) return store[id] end,
    set = function(_, id, v) store[id] = v end,
    string = function(_, id) return tostring(store[id]) end,
    lookup = {},
  })
  return store
end

local voice_registry = require("lib/voice_registry")

local function make_ctx()
  return {
    voices = {},
    mixer = require("lib/mixer").new(),
    midi_dev = {
      note_on = function() end,
      note_off = function() end,
      cc = function() end,
    },
  }
end

describe("voice_registry", function()

  local saved_params

  before_each(function()
    saved_params = rawget(_G, "params")
  end)

  after_each(function()
    rawset(_G, "params", saved_params)
    voice_registry.unregister("test_instrument")
  end)

  describe("built-in registrations", function()

    it("preserves the legacy VOICE_TYPES order (preset index compatibility)", function()
      assert.are.same({"midi", "osc", "sc_drums", "softcut", "sc_synth", "none"},
        voice_registry.names())
    end)

    it("creates a midi voice from params + ctx.midi_dev", function()
      stub_params({["midi_ch_1"] = 3})
      local ctx = make_ctx()
      local voice = voice_registry.create("midi", ctx, 1)
      assert.is_not_nil(voice)
      assert.is_function(voice.play_note)
      assert.is_function(voice.all_notes_off)
    end)

    it("creates an osc voice from params", function()
      stub_params({["osc_host"] = 1, ["osc_port"] = 57120})
      local ctx = make_ctx()
      local voice = voice_registry.create("osc", ctx, 2)
      assert.is_not_nil(voice)
      assert.is_function(voice.play_note)
    end)

    it("creates an sc_synth voice announcing its synthdef", function()
      stub_params({["osc_host"] = 1, ["osc_port"] = 57120, ["sc_synthdef_1"] = 2})
      local ctx = make_ctx()
      local voice = voice_registry.create("sc_synth", ctx, 1)
      assert.is_not_nil(voice)
      assert.is_function(voice.play_note)
    end)

    it("returns nil for 'none' without error", function()
      stub_params({})
      local ctx = make_ctx()
      local voice, err = voice_registry.create("none", ctx, 1)
      assert.is_nil(voice)
      assert.is_nil(err)
    end)

  end)

  describe("custom instrument integration (the whole point)", function()

    it("register + create is the complete integration path", function()
      stub_params({})
      local notes = {}
      voice_registry.register("test_instrument", function(ctx, track)
        return {
          track = track,
          play_note = function(self, note, vel, dur) notes[#notes + 1] = note end,
          all_notes_off = function(self) end,
        }
      end)
      local ctx = make_ctx()
      local voice = voice_registry.create("test_instrument", ctx, 3)
      assert.is_not_nil(voice)
      assert.are.equal(3, voice.track)
      voice:play_note(64, 0.8, 0.25)
      assert.are.same({64}, notes)
      -- and it appears in the params-menu name list, after the built-ins
      local names = voice_registry.names()
      assert.are.equal("test_instrument", names[#names])
    end)

    it("rejects a factory result missing the required interface", function()
      stub_params({})
      voice_registry.register("test_instrument", function()
        return { play_note = function() end } -- missing all_notes_off
      end)
      local voice, err = voice_registry.create("test_instrument", make_ctx(), 1)
      assert.is_nil(voice)
      assert.is_truthy(tostring(err):find("all_notes_off"))
    end)

    it("returns nil, err for an unknown instrument name", function()
      local voice, err = voice_registry.create("no_such_instrument", make_ctx(), 1)
      assert.is_nil(voice)
      assert.is_truthy(tostring(err):find("no_such_instrument"))
    end)

    it("register refuses to overwrite an existing name unless told to", function()
      voice_registry.register("test_instrument", function() end)
      assert.has_error(function()
        voice_registry.register("test_instrument", function() end)
      end)
      -- explicit replace is allowed
      voice_registry.register("test_instrument", function() end, {replace = true})
    end)

  end)

  describe("capabilities", function()

    it("reports which optional methods a voice supports", function()
      local voice = {
        play_note = function() end,
        all_notes_off = function() end,
        set_level = function() end,
        set_pan = function() end,
      }
      local caps = voice_registry.capabilities(voice)
      assert.is_true(caps.set_level)
      assert.is_true(caps.set_pan)
      assert.is_falsy(caps.set_portamento)
      assert.is_falsy(caps.set_synthdef)
    end)

  end)

end)
