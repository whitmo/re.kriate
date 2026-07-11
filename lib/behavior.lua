-- lib/behavior.lua
-- The behavioral event layer: an interface-agnostic vocabulary of sequencer
-- commands and facts on the ctx.events bus, plus the mechanism for stacking
-- abstract behavioral events on top of it.
--
-- Layer model (full rationale in docs/event-layers.md):
--
--   L0 interface events   grid keys, keyboard chars, mouse clicks, OSC
--                         messages. One adapter per interface. The grid is
--                         just one interface — a voice-command listener, a
--                         TUI, or a knob/slider controller would each be a
--                         peer adapter emitting the same L1 commands, never
--                         reaching into grid_ui or sequencer directly.
--
--   L1 behavioral events  this module's vocabulary, in two moods:
--                           commands ("cmd:" prefix)  requests to act, e.g.
--                                     cmd:transport:play. wire_commands()
--                                     subscribes them to the real modules.
--                           facts    (no prefix)      notifications of what
--                                     happened or emerged from state+clock,
--                                     e.g. sequencer:step, voice:note.
--                         The cmd: prefix means one bus:on("cmd:*") sees
--                         every command regardless of interface — the
--                         events bus matches wildcards on the first-colon
--                         prefix — which is what a remote bridge, macro
--                         recorder, or undo log would subscribe to.
--
--   L2 abstract events    compositions built with M.define(): an abstract
--                         event ("section:chorus", "fill", "arp:up",
--                         "song:start") expands into a list of L1 commands
--                         or other L2 events. Expansions nest; a depth
--                         guard stops runaway cycles. This is how song
--                         structure, fills, and arpeggios become
--                         implementable later as pure vocabulary — no new
--                         plumbing.
--
-- Voice behavior follows the same principle: voices are driven through the
-- behavioral layer (cmd:note:play -> voice + voice:note fact) rather than
-- interfaces calling voice methods directly, so anything that can emit an
-- event can play a note — including an L2 arpeggio expansion.

local sequencer = require("lib/sequencer")
local pattern = require("lib/pattern")
local track_mod = require("lib/track")
local mixer = require("lib/mixer")
local preset = require("lib/preset")

local M = {}

-- Maximum nesting depth for define() expansions. Deep enough for any sane
-- song-structure stack (song -> section -> phrase -> commands is 3), small
-- enough that an accidental cycle dies fast and visibly.
M.MAX_DEPTH = 8

-- ============================================================================
-- Vocabulary catalog
-- ============================================================================
-- Every behavioral event, declared as data so tests (specs/behavior_spec.lua)
-- can check the vocabulary for consistency and completeness, and so docs and
-- future interface adapters have one authoritative list.
--
-- Fields:
--   name    canonical bus event name
--   layer   "interface" | "behavioral" | "abstract"
--   mood    "command" (cmd: prefix, requests an action)
--           | "fact" (notification of what happened)
--   payload ordered list of payload field names
--   status  "implemented" (wired/emitted today)
--           | "planned" (declared vocabulary, wiring to come)
--   note    optional clarification

M.VOCAB = {
  -- ---- L0: interface events (facts about raw input) ----
  { name = "grid:key", layer = "interface", mood = "fact",
    payload = {"x", "y", "z"}, status = "implemented" },

  -- ---- L1 commands: transport ----
  { name = "cmd:transport:play", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented" },
  { name = "cmd:transport:pause", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented",
    note = "sequencer has no pause-distinct-from-stop state; aliased to the "
      .. "same handler as cmd:transport:stop, which only halts the clock "
      .. "coroutines and never touches pos/tick, so playheads survive a "
      .. "pause the way they would a real pause" },
  { name = "cmd:transport:stop", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented" },
  { name = "cmd:transport:reset", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented" },

  -- ---- L1 commands: pattern ----
  { name = "cmd:pattern:load", layer = "behavioral", mood = "command",
    payload = {"slot"}, status = "implemented" },
  { name = "cmd:pattern:save", layer = "behavioral", mood = "command",
    payload = {"slot"}, status = "implemented" },

  -- ---- L1 commands: track / loop / note / settings ----
  { name = "cmd:track:set_mute", layer = "behavioral", mood = "command",
    payload = {"track", "muted"}, status = "implemented" },
  { name = "cmd:loop:set", layer = "behavioral", mood = "command",
    payload = {"track", "param", "loop_start", "loop_end"}, status = "implemented" },
  { name = "cmd:note:play", layer = "behavioral", mood = "command",
    payload = {"track", "note", "vel", "dur"}, status = "implemented" },
  { name = "cmd:option:change", layer = "behavioral", mood = "command",
    payload = {"name", "value"}, status = "implemented",
    note = "wired straight to params:set(name, value); a no-op when params "
      .. "or the named option is unavailable (standalone/test contexts)" },

  -- ---- L1 commands: reset family ----
  { name = "cmd:reset:track", layer = "behavioral", mood = "command",
    payload = {"track"}, status = "implemented" },
  { name = "cmd:reset:global", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented",
    note = "alias of cmd:transport:reset kept for vocabulary symmetry with the reset family" },
  { name = "cmd:reset:pattern", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented",
    note = "conservative choice, documented at the wire site: reverts the "
      .. "current pattern slot's tracks to their last-saved state "
      .. "(discarding unsaved edits), falling back to fresh musical "
      .. "defaults if the slot was never saved. Does not touch other slots" },
  { name = "cmd:reset:time", layer = "behavioral", mood = "command",
    payload = {}, status = "implemented",
    note = "clears every param's clock_div tick counter (not pos) across "
      .. "all tracks to realign polymetric phase; distinct from "
      .. "cmd:reset:global/transport:reset, which also snaps pos to loop_start" },

  -- ---- L1 commands: persistence ----
  { name = "cmd:load:preset", layer = "behavioral", mood = "command",
    payload = {"name"}, status = "implemented",
    note = "lib/preset.lua load by name; stops playback first (mirrors "
      .. "app.lua's M.load_preset FR-010 guard) so the load doesn't race "
      .. "clock coroutines. No-op without a name" },
  { name = "cmd:save:state", layer = "behavioral", mood = "command",
    payload = {"name"}, status = "implemented",
    note = "full-session save via lib/preset.lua, by name. No-op without a name" },

  -- ---- L1 facts: emitted by modules today ----
  { name = "sequencer:start", layer = "behavioral", mood = "fact",
    payload = {}, status = "implemented" },
  { name = "sequencer:stop", layer = "behavioral", mood = "fact",
    payload = {}, status = "implemented" },
  { name = "sequencer:reset", layer = "behavioral", mood = "fact",
    payload = {}, status = "implemented" },
  { name = "sequencer:step", layer = "behavioral", mood = "fact",
    payload = {"track", "step", "vals"}, status = "implemented" },
  { name = "voice:note", layer = "behavioral", mood = "fact",
    payload = {"track", "note", "vel", "dur"}, status = "implemented" },
  { name = "track:select", layer = "behavioral", mood = "fact",
    payload = {"track"}, status = "implemented" },
  { name = "track:mute", layer = "behavioral", mood = "fact",
    payload = {"track", "muted"}, status = "implemented",
    note = "deprecated alias of mixer:mute, emitted alongside it by "
      .. "lib/mixer.lua's M.set_mute for existing consumers/tests during a "
      .. "deprecation window (assessment finding #21); new code should use "
      .. "mixer:mute" },
  { name = "page:select", layer = "behavioral", mood = "fact",
    payload = {"page", "prev"}, status = "implemented" },
  { name = "pattern:load", layer = "behavioral", mood = "fact",
    payload = {"slot"}, status = "implemented" },
  { name = "pattern:save", layer = "behavioral", mood = "fact",
    payload = {"slot"}, status = "implemented" },
  { name = "pattern:cue", layer = "behavioral", mood = "fact",
    payload = {"slot"}, status = "implemented" },
  { name = "pattern:cue_cancel", layer = "behavioral", mood = "fact",
    payload = {"slot"}, status = "implemented" },
  { name = "pattern:cue_applied", layer = "behavioral", mood = "fact",
    payload = {"slot"}, status = "implemented" },
  { name = "mixer:level", layer = "behavioral", mood = "fact",
    payload = {"track", "level"}, status = "implemented" },
  { name = "mixer:pan", layer = "behavioral", mood = "fact",
    payload = {"track", "pan"}, status = "implemented" },
  { name = "mixer:mute", layer = "behavioral", mood = "fact",
    payload = {"track", "muted"}, status = "implemented" },
  { name = "meta:start", layer = "behavioral", mood = "fact",
    payload = {"pos", "slot"}, status = "implemented" },
  { name = "meta:step", layer = "behavioral", mood = "fact",
    payload = {"pos", "slot", "loops"}, status = "implemented" },
  { name = "meta:cue_applied", layer = "behavioral", mood = "fact",
    payload = {"slot"}, status = "implemented" },
  { name = "meta:edit", layer = "behavioral", mood = "fact",
    payload = {"step", "slot"}, status = "implemented" },
  { name = "scale:root", layer = "behavioral", mood = "fact",
    payload = {"root_note"}, status = "implemented",
    note = "command-intent hybrid: grid_ui mutates ctx then emits; app.lua's "
      .. "subscriber does the effective work (params sync + rebuild_scale). "
      .. "The one pre-existing precedent for the cmd: pattern; successor is "
      .. "cmd:option:change once wired" },
  { name = "scale:type", layer = "behavioral", mood = "fact",
    payload = {"scale_type"}, status = "implemented",
    note = "command-intent hybrid; see scale:root" },
  { name = "track:direction", layer = "behavioral", mood = "fact",
    payload = {"track", "value"}, status = "implemented",
    note = "command-intent hybrid; see scale:root. grid_ui.alt_track_key and "
      .. "seamstress/keyboard's 'd' handler mutate ctx.tracks[t].direction (a "
      .. "string, see lib/direction.lua's MODES) then emit; app.lua's subscriber "
      .. "reverse-looks-up the string to the direction_N option index before "
      .. "params:set. Closes the one-directional (params->ctx only) sync gap "
      .. "that let a grid/keyboard edit go stale in the params menu and be "
      .. "stomped by a preset reload (assessment #22, root cause of #8)" },
  { name = "track:division", layer = "behavioral", mood = "fact",
    payload = {"track", "value"}, status = "implemented",
    note = "command-intent hybrid; see track:direction. division_N stores the "
      .. "same raw option index (1-7) as ctx.tracks[t].division, so no "
      .. "conversion is needed before params:set" },
  { name = "track:swing", layer = "behavioral", mood = "fact",
    payload = {"track", "value"}, status = "implemented",
    note = "command-intent hybrid; see track:direction. swing_N is a plain "
      .. "0-100 number on both sides, so no conversion is needed before "
      .. "params:set" },
  { name = "app:ready", layer = "behavioral", mood = "fact",
    payload = {}, status = "implemented",
    note = "emitted at the end of app.init (which also sets ctx.ready for "
      .. "late-arriving code); lets adapters/compositions defer setup" },

  -- ---- L2: abstract events (examples; created via M.define by features) ----
  { name = "song:start", layer = "abstract", mood = "command",
    payload = {}, status = "planned",
    note = "worked example in specs/behavior_spec.lua: pattern load + transport play" },
  { name = "song:stop", layer = "abstract", mood = "command",
    payload = {}, status = "planned" },
  { name = "section:change", layer = "abstract", mood = "command",
    payload = {"section"}, status = "planned",
    note = "intro/verse/chorus/bridge/break as expansions over pattern + mute commands" },
  { name = "fill", layer = "abstract", mood = "command",
    payload = {"track"}, status = "planned" },
  { name = "arp:play", layer = "abstract", mood = "command",
    payload = {"track", "root"}, status = "planned",
    note = "worked example in specs/behavior_spec.lua: expansion into cmd:note:play events" },
}

-- ============================================================================
-- Command wiring
-- ============================================================================

--- Subscribe every implemented cmd:* event to the module function that
--- performs it. This is the single junction where interface adapters
--- (grid, keyboard, OSC remote, future voice/TUI/controller) meet the
--- sequencer: adapters emit commands; nothing else needs to know which
--- module implements what.
--- @param ctx table  application context (must have ctx.events)
--- @return function  unwire() — removes every handler this call installed
function M.wire_commands(ctx)
  local bus = ctx.events
  local unsubs = {}
  local function wire(name, fn)
    unsubs[#unsubs + 1] = bus:on(name, fn)
  end

  wire("cmd:transport:play", function() sequencer.start(ctx) end)
  wire("cmd:transport:stop", function() sequencer.stop(ctx) end)
  -- No pause-distinct-from-stop state exists yet; sequencer.stop() only
  -- cancels the clock coroutines and never touches param pos/tick, so
  -- aliasing pause to stop already gives "resume where you left off"
  -- behavior. See the cmd:transport:pause VOCAB note.
  wire("cmd:transport:pause", function() sequencer.stop(ctx) end)
  wire("cmd:transport:reset", function() sequencer.reset(ctx) end)

  wire("cmd:pattern:save", function(data)
    if not data.slot then return end
    pattern.save(ctx, data.slot)
    ctx.pattern_slot = data.slot
    bus:emit("pattern:save", {slot = data.slot})
  end)
  wire("cmd:pattern:load", function(data)
    if not data.slot then return end
    if not pattern.is_populated(ctx.patterns, data.slot) then return end
    -- resolve_tap loads immediately when stopped, or cues/cancels a
    -- quantized transition when playing (and emits its own fact) --
    -- the same decision the grid pattern page makes, in one place.
    pattern.resolve_tap(ctx, data.slot)
  end)

  wire("cmd:track:set_mute", function(data)
    if not data.track then return end
    mixer.set_mute(ctx, data.track, data.muted)
  end)

  wire("cmd:loop:set", function(data)
    local track = data.track and ctx.tracks[data.track]
    local param = track and data.param and track.params[data.param]
    if not param then return end
    track_mod.set_loop(param, data.loop_start, data.loop_end)
  end)

  wire("cmd:note:play", function(data)
    if not (data.track and data.note) then return end
    local vel, dur = data.vel or 0.75, data.dur or 0.25
    sequencer.play_note(ctx, data.track, data.note, vel, dur)
    -- play_note is the low-level "sound this" helper; the voice:note fact
    -- is normally emitted by the step pipeline, so the command path emits
    -- it here to keep the fact's meaning ("a note was played") intact.
    bus:emit("voice:note", {track = data.track, note = data.note, vel = vel, dur = dur})
  end)

  wire("cmd:reset:track", function(data)
    local track = data.track and ctx.tracks[data.track]
    if not track then return end
    for _, p in pairs(track.params) do
      p.pos = p.loop_start
      p.tick = 0
    end
  end)
  wire("cmd:reset:global", function() sequencer.reset(ctx) end)

  -- "Reset pattern": conservative and defensible semantics, chosen because
  -- there's no existing precedent for what a pattern-scoped reset means.
  -- Revert the CURRENT pattern slot's tracks to their last-saved state
  -- (discarding unsaved edits), same as pattern.load would. If the current
  -- slot has never been saved, fall back to fresh musical defaults so the
  -- command is never a silent no-op. Other slots are left untouched.
  wire("cmd:reset:pattern", function()
    local slot = ctx.pattern_slot
    if slot and pattern.is_populated(ctx.patterns, slot) then
      pattern.load(ctx, slot)
    else
      ctx.tracks = track_mod.new_tracks()
    end
  end)

  -- "Reset time": realign polymetric phase by clearing every param's
  -- clock_div tick counter (the "which tick within the division cycle"
  -- counter from track_mod.new_param/M.should_advance), WITHOUT touching
  -- pos. This is deliberately narrower than cmd:reset:global/transport:reset
  -- (sequencer.reset), which also snaps pos back to loop_start and so
  -- restarts patterns from the top.
  wire("cmd:reset:time", function()
    for _, track in ipairs(ctx.tracks) do
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        track.params[name].tick = 0
      end
    end
  end)

  wire("cmd:option:change", function(data)
    if not data.name then return end
    local p = rawget(_G, "params")
    if not p or not p.lookup or not p.set then return end
    if not p.lookup[data.name] then return end
    p:set(data.name, data.value)
  end)

  wire("cmd:save:state", function(data)
    if not data.name then return end
    preset.save(ctx, data.name)
  end)

  wire("cmd:load:preset", function(data)
    if not data.name then return end
    -- Stop playback first so the load doesn't race clock coroutines,
    -- mirroring app.lua's M.load_preset guard (FR-010). Unlike that
    -- params-menu action, this command's payload always carries an
    -- explicit name, so there's no params-configured-name fallback to
    -- replicate here.
    if ctx.playing then
      sequencer.stop(ctx)
    end
    preset.load(ctx, data.name)
  end)

  return function()
    for _, unsub in ipairs(unsubs) do unsub() end
  end
end

-- ============================================================================
-- Stacking: abstract behavioral events
-- ============================================================================

-- Per-bus expansion depth, weakly keyed so buses can be garbage-collected.
local depth_by_bus = setmetatable({}, {__mode = "k"})

--- Define an abstract behavioral event: when `name` is emitted on `bus`,
--- re-emit its expansion. `expansion` is either a static array of
--- {name=, data=} steps or a function(data) returning such an array (so
--- the expansion can read the triggering payload — e.g. an arpeggio
--- reading its root note). Expansions nest: a step may itself be another
--- define()d event. A depth guard (M.MAX_DEPTH) stops runaway cycles.
--- @param bus table  an events bus (lib/events.lua)
--- @param name string  the abstract event name
--- @param expansion table|function  static steps or fn(data) -> steps
--- @return function  unsubscribe
function M.define(bus, name, expansion)
  return bus:on(name, function(data)
    local depth = depth_by_bus[bus] or 0
    if depth >= M.MAX_DEPTH then
      print("[behavior] max expansion depth (" .. M.MAX_DEPTH
        .. ") reached at '" .. name .. "' — possible definition cycle")
      return
    end
    depth_by_bus[bus] = depth + 1
    local steps = expansion
    if type(expansion) == "function" then
      steps = expansion(data)
    end
    for _, step in ipairs(steps or {}) do
      bus:emit(step.name, step.data)
    end
    depth_by_bus[bus] = depth
  end)
end

return M
