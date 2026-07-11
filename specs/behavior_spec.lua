-- specs/behavior_spec.lua
-- Tests for lib/behavior.lua: the behavioral event layer.
--
-- Layer model (see docs/event-layers.md):
--   L0 interface events   grid keys, keyboard, mouse, OSC — one adapter per
--                         interface; grid is just one kind (a voice-command,
--                         TUI, or knob/slider controller adapter would sit
--                         beside it, not inside it)
--   L1 behavioral events  interface-agnostic sequencer vocabulary on the
--                         ctx.events bus, in two moods:
--                           commands ("cmd:" prefix) — requests to act
--                           facts (no prefix)        — notifications of what
--                                                      happened / emerged
--   L2 abstract events    compositions that expand into L1 (or other L2)
--                         events via behavior.define — song sections, fills,
--                         arpeggios become implementable as pure data/
--                         expansion functions with no new plumbing.

package.path = package.path .. ";./?.lua"

-- Mock clock (sequencer requires it at load time)
local clock_cancelled = {}
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return #clock_cancelled + 1 end,
  cancel = function(id) clock_cancelled[#clock_cancelled + 1] = id end,
  sync = function() end,
})

local behavior = require("lib/behavior")
local events = require("lib/events")
local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local recorder_voice = require("lib/voices/recorder")

local function make_ctx()
  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    patterns = pattern.new_slots(),
    events = events.new(),
    voices = {},
    clock_ids = nil,
  }
  for t = 1, track_mod.NUM_TRACKS do
    ctx.voices[t] = recorder_voice.new(t)
  end
  return ctx
end

describe("behavior", function()

  -- ==========================================================================
  -- Vocabulary catalog consistency
  -- ==========================================================================

  describe("VOCAB catalog", function()

    it("has unique event names", function()
      local seen = {}
      for _, entry in ipairs(behavior.VOCAB) do
        assert.is_nil(seen[entry.name], "duplicate vocab entry: " .. entry.name)
        seen[entry.name] = true
      end
    end)

    it("uses only known layers and moods", function()
      for _, entry in ipairs(behavior.VOCAB) do
        assert.is_true(entry.layer == "interface" or entry.layer == "behavioral" or entry.layer == "abstract",
          entry.name .. " has unknown layer " .. tostring(entry.layer))
        assert.is_true(entry.mood == "command" or entry.mood == "fact",
          entry.name .. " has unknown mood " .. tostring(entry.mood))
      end
    end)

    it("behavioral-layer commands carry the cmd: prefix; facts and abstract events don't", function()
      -- Deliberate semantics: cmd:* is the RESOLVED PRIMITIVE command
      -- stream. Abstract (L2) events keep their own namespaces (song:,
      -- section:, arp:, fill...) and expand INTO cmd:* events — so a
      -- subscriber on "cmd:*" (macro recorder, remote bridge, undo log)
      -- sees identical traffic whether a human pressed buttons or a song
      -- section fired.
      for _, entry in ipairs(behavior.VOCAB) do
        local has_prefix = entry.name:sub(1, 4) == "cmd:"
        if entry.mood == "command" and entry.layer == "behavioral" then
          assert.is_true(has_prefix, entry.name .. " is a behavioral command but lacks the cmd: prefix")
        else
          assert.is_false(has_prefix, entry.name .. " should not carry the cmd: prefix (mood="
            .. entry.mood .. ", layer=" .. entry.layer .. ")")
        end
      end
    end)

    it("every implemented command has a handler in wire_commands", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      for _, entry in ipairs(behavior.VOCAB) do
        if entry.mood == "command" and entry.status == "implemented" then
          assert.is_true(ctx.events:count(entry.name) > 0,
            entry.name .. " is marked implemented but wire_commands installed no handler")
        end
      end
    end)

    it("covers every event name lib/ actually emits today", function()
      -- Ground truth from a 2026-07-11 inventory of every ctx.events:emit
      -- call site in lib/ (grep 'events:emit' lib/ to re-derive). If you add
      -- an emission with a new name, declare it in behavior.VOCAB — that is
      -- the point of the catalog.
      local emitted_in_lib = {
        "pattern:cue", "pattern:cue_cancel", "pattern:load", "pattern:cue_applied",
        "pattern:save",
        "mixer:level", "mixer:pan", "mixer:mute",
        "meta:start", "meta:step", "meta:cue_applied", "meta:edit",
        "sequencer:start", "sequencer:stop", "sequencer:step", "sequencer:reset",
        "voice:note",
        "grid:key", "page:select", "track:select", "track:mute",
        "scale:root", "scale:type",
      }
      local names = {}
      for _, entry in ipairs(behavior.VOCAB) do names[entry.name] = entry end
      for _, name in ipairs(emitted_in_lib) do
        local entry = names[name]
        assert.is_not_nil(entry, "lib/ emits '" .. name .. "' but VOCAB doesn't declare it")
        assert.are.equal("implemented", entry.status,
          name .. " is emitted by lib/ but cataloged as " .. tostring(entry.status))
      end
    end)

    it("declares the full user-facing behavioral vocabulary, wired or planned", function()
      local names = {}
      for _, entry in ipairs(behavior.VOCAB) do names[entry.name] = true end
      -- The vocabulary requested for the framework: each must at least be
      -- declared (status=planned is fine — but it must be on the map).
      for _, required in ipairs({
        "cmd:transport:play", "cmd:transport:pause", "cmd:transport:stop", "cmd:transport:reset",
        "cmd:pattern:load", "cmd:pattern:save",
        "cmd:track:set_mute",
        "cmd:loop:set",
        "cmd:note:play",
        "cmd:option:change",
        "cmd:reset:track", "cmd:reset:global", "cmd:reset:pattern", "cmd:reset:time",
        "cmd:load:preset", "cmd:save:state",
        "app:ready",
      }) do
        assert.is_true(names[required] == true, "vocabulary missing required entry: " .. required)
      end
    end)

  end)

  -- ==========================================================================
  -- Command wiring: interface-agnostic behavioral commands drive real modules
  -- ==========================================================================

  describe("wire_commands", function()

    it("cmd:transport:play starts the sequencer", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.events:emit("cmd:transport:play", {})
      assert.is_true(ctx.playing)
    end)

    it("cmd:transport:stop stops the sequencer", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.events:emit("cmd:transport:play", {})
      ctx.events:emit("cmd:transport:stop", {})
      assert.is_false(ctx.playing)
    end)

    it("cmd:transport:reset resets playheads to loop start", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.tracks[1].params.trigger.pos = 4
      ctx.events:emit("cmd:transport:reset", {})
      assert.are.equal(ctx.tracks[1].params.trigger.loop_start, ctx.tracks[1].params.trigger.pos)
    end)

    it("cmd:track:set_mute mutes and unmutes a track", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.events:emit("cmd:track:set_mute", {track = 2, muted = true})
      assert.is_true(ctx.tracks[2].muted)
      ctx.events:emit("cmd:track:set_mute", {track = 2, muted = false})
      assert.is_false(ctx.tracks[2].muted)
    end)

    it("cmd:pattern:save then cmd:pattern:load roundtrips track state", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.tracks[1].params.trigger.steps[1] = 1
      ctx.events:emit("cmd:pattern:save", {slot = 3})
      ctx.tracks[1].params.trigger.steps[1] = 0
      ctx.events:emit("cmd:pattern:load", {slot = 3})
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[1])
      assert.are.equal(3, ctx.pattern_slot)
    end)

    it("cmd:pattern:load emits the pattern:load fact", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.events:emit("cmd:pattern:save", {slot = 5})
      local seen = nil
      ctx.events:on("pattern:load", function(data) seen = data end)
      ctx.events:emit("cmd:pattern:load", {slot = 5})
      assert.is_not_nil(seen)
      assert.are.equal(5, seen.slot)
    end)

    it("cmd:loop:set sets a param's loop bounds", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      ctx.events:emit("cmd:loop:set", {track = 1, param = "note", loop_start = 3, loop_end = 9})
      assert.are.equal(3, ctx.tracks[1].params.note.loop_start)
      assert.are.equal(9, ctx.tracks[1].params.note.loop_end)
    end)

    it("cmd:note:play sounds a voice and emits the voice:note fact", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      local fact = nil
      ctx.events:on("voice:note", function(data) fact = data end)
      ctx.events:emit("cmd:note:play", {track = 1, note = 62, vel = 0.8, dur = 0.25})
      local rec = ctx.voices[1]:get_events()
      assert.are.equal(1, #rec)
      assert.are.equal(62, rec[1].note)
      assert.is_not_nil(fact)
      assert.are.equal(62, fact.note)
    end)

    it("returns an unwire function that removes all handlers", function()
      local ctx = make_ctx()
      local unwire = behavior.wire_commands(ctx)
      unwire()
      ctx.events:emit("cmd:transport:play", {})
      assert.is_false(ctx.playing)
    end)

  end)

  -- ==========================================================================
  -- Stacking: abstract behavioral events expanding into L1 (and L2) events
  -- ==========================================================================

  describe("define (event stacking)", function()

    it("expands a static expansion into its constituent events", function()
      local bus = events.new()
      local got = {}
      bus:on("cmd:track:set_mute", function(data) got[#got + 1] = data end)
      behavior.define(bus, "section:break", {
        {name = "cmd:track:set_mute", data = {track = 2, muted = true}},
        {name = "cmd:track:set_mute", data = {track = 3, muted = true}},
        {name = "cmd:track:set_mute", data = {track = 4, muted = true}},
      })
      bus:emit("section:break", {})
      assert.are.equal(3, #got)
      assert.are.equal(2, got[1].track)
      assert.are.equal(4, got[3].track)
    end)

    it("supports functional expansions that read the triggering payload", function()
      local bus = events.new()
      local notes = {}
      bus:on("cmd:note:play", function(data) notes[#notes + 1] = data.note end)
      -- an arpeggio: root, +4, +7 — the kind of abstract musical event the
      -- framework should make implementable with zero new plumbing
      behavior.define(bus, "arp:triad", function(data)
        local out = {}
        for i, interval in ipairs({0, 4, 7}) do
          out[i] = {name = "cmd:note:play", data = {track = data.track, note = data.root + interval, vel = 0.7, dur = 0.1}}
        end
        return out
      end)
      bus:emit("arp:triad", {track = 1, root = 60})
      assert.are.same({60, 64, 67}, notes)
    end)

    it("stacks two levels deep: an abstract event expanding into another abstract event", function()
      local bus = events.new()
      local log = {}
      bus:on("cmd:pattern:load", function(data) log[#log + 1] = "load:" .. data.slot end)
      bus:on("cmd:transport:play", function() log[#log + 1] = "play" end)
      bus:on("cmd:track:set_mute", function(data) log[#log + 1] = "mute:" .. data.track end)

      behavior.define(bus, "section:intro", {
        {name = "cmd:pattern:load", data = {slot = 1}},
        {name = "cmd:track:set_mute", data = {track = 4, muted = true}},
      })
      behavior.define(bus, "song:start", {
        {name = "section:intro", data = {}},
        {name = "cmd:transport:play", data = {}},
      })

      bus:emit("song:start", {})
      assert.are.same({"load:1", "mute:4", "play"}, log)
    end)

    it("drives real modules end-to-end when stacked on wire_commands", function()
      local ctx = make_ctx()
      behavior.wire_commands(ctx)
      pattern.save(ctx, 2)
      behavior.define(ctx.events, "song:start", {
        {name = "cmd:pattern:load", data = {slot = 2}},
        {name = "cmd:transport:play", data = {}},
      })
      ctx.events:emit("song:start", {})
      assert.is_true(ctx.playing)
      assert.are.equal(2, ctx.pattern_slot)
    end)

    it("guards against runaway expansion cycles", function()
      local bus = events.new()
      local count = 0
      bus:on("cycle:a", function() count = count + 1 end)
      behavior.define(bus, "cycle:a", {{name = "cycle:a", data = {}}})
      bus:emit("cycle:a", {})
      assert.is_true(count <= behavior.MAX_DEPTH + 1,
        "cycle expanded " .. count .. " times; guard failed")
    end)

    it("returns an unsubscribe function", function()
      local bus = events.new()
      local fired = 0
      bus:on("cmd:transport:play", function() fired = fired + 1 end)
      local undef = behavior.define(bus, "song:start", {{name = "cmd:transport:play", data = {}}})
      bus:emit("song:start", {})
      undef()
      bus:emit("song:start", {})
      assert.are.equal(1, fired)
    end)

  end)

end)
