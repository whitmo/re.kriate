-- lib/voice_registry.lua
-- The instrument integration boundary: a pluggable registry of voice
-- factories, mirroring lib/grid_provider.lua's register/connect pattern
-- (the controller-hardware boundary) on the output side.
--
-- Integrating a new instrument is one call:
--
--   local voice_registry = require("lib/voice_registry")
--   voice_registry.register("my_synth", function(ctx, track)
--     return {
--       play_note = function(self, note, vel, dur) ... end,
--       all_notes_off = function(self) ... end,
--       -- optional capabilities, see M.OPTIONAL below
--     }
--   end)
--
-- The factory receives (ctx, track) and reads any configuration it needs
-- from params itself — no lib/app.lua edits. The name then appears in the
-- per-track "voice" params menu automatically (app.lua builds that option
-- list from M.names()).
--
-- Interface contract: REQUIRED methods are validated at create() time;
-- OPTIONAL methods are capabilities that callers guard on (`if
-- voice.set_level then ...`), exactly as lib/sequencer.lua and
-- lib/mixer.lua already do.

local M = {}

-- Required on every voice: the minimum the sequencer needs.
M.REQUIRED = {"play_note", "all_notes_off"}

-- Optional capabilities, as observed across the shipped backends.
M.OPTIONAL = {
  "note_on", "note_off", "set_portamento", "set_level", "set_pan",
  "set_target", "set_synthdef", "grab", "apply_config",
}

-- SynthDef names for the sc_synth voice; exported because app.lua's
-- per-track "sc synthdef" params option shares this list with the factory.
M.SC_SYNTHDEFS = {"sub", "fm", "wavetable"}

local factories = {} -- name -> factory(ctx, track) -> voice|nil
local order = {}     -- registration order; names() feeds params option
                     -- menus, and presets store the INDEX, so built-in
                     -- order below must never change.

--- Register an instrument factory under a name.
--- @param name string
--- @param factory function  (ctx, track) -> voice table (or nil for none)
--- @param opts table|nil  {replace = true} to overwrite an existing name
function M.register(name, factory, opts)
  if factories[name] and not (opts and opts.replace) then
    error("voice_registry: '" .. name .. "' is already registered "
      .. "(pass {replace = true} to override)")
  end
  if not factories[name] then
    order[#order + 1] = name
  end
  factories[name] = factory
end

--- Remove a registered instrument (primarily for tests).
function M.unregister(name)
  if not factories[name] then return end
  factories[name] = nil
  for i = #order, 1, -1 do
    if order[i] == name then table.remove(order, i) end
  end
end

--- Registered instrument names in registration order (params menu order).
function M.names()
  local copy = {}
  for i, name in ipairs(order) do copy[i] = name end
  return copy
end

--- Which optional capabilities a voice object supports.
--- @return table  capability name -> true
function M.capabilities(voice)
  local caps = {}
  if type(voice) ~= "table" then return caps end
  for _, method in ipairs(M.OPTIONAL) do
    if type(voice[method]) == "function" then caps[method] = true end
  end
  return caps
end

--- Validate the required voice interface.
--- @return boolean ok, string|nil err
local function validate(name, voice)
  for _, method in ipairs(M.REQUIRED) do
    if type(voice[method]) ~= "function" then
      return false, "voice '" .. name .. "' is missing required method '" .. method .. "'"
    end
  end
  return true
end

--- Create an instrument by name for a track.
--- @param name string  registered instrument name
--- @param ctx table  application context
--- @param track number  track number the voice will serve
--- @return table|nil voice, string|nil err  nil voice with nil err means
---   "deliberately no voice" (the 'none' instrument); nil with err means
---   failure.
function M.create(name, ctx, track)
  local factory = factories[name]
  if not factory then
    return nil, "voice_registry: no instrument registered as '" .. tostring(name) .. "'"
  end
  local voice = factory(ctx, track)
  if voice == nil then
    return nil, nil
  end
  local ok, err = validate(name, voice)
  if not ok then
    return nil, err
  end
  return voice
end

-- ============================================================================
-- Built-in instruments
-- ============================================================================
-- Registration order is load-bearing: presets persist the voice params
-- option INDEX, and this order must match the legacy VOICE_TYPES list
-- {"midi", "osc", "sc_drums", "softcut", "sc_synth", "none"}.

M.register("midi", function(ctx, track)
  local midi_voice = require("lib/voices/midi")
  local ch = (params and params:get("midi_ch_" .. track)) or track
  return midi_voice.new(ctx.midi_dev, ch)
end)

local function osc_target()
  -- osc_host is an option param: params:get returns the index; the host
  -- list currently has one entry, so factories resolve via params:string
  -- when available and fall back to loopback.
  local host = "127.0.0.1"
  if params and params.string then
    local ok, s = pcall(params.string, params, "osc_host")
    if ok and s and s ~= "nil" then host = s end
  end
  local port = (params and params:get("osc_port")) or 57120
  return host, port
end

M.register("osc", function(_, track)
  local osc_voice = require("lib/voices/osc")
  local host, port = osc_target()
  return osc_voice.new(track, host, port)
end)

M.register("sc_drums", function(_, track)
  local sc_drums = require("lib/voices/sc_drums")
  local host, port = osc_target()
  return sc_drums.new(track, host, port)
end)

M.register("softcut", function(ctx, track)
  if not ctx.softcut_runtime then
    local softcut_runtime = require("lib/voices/softcut_runtime")
    ctx.softcut_runtime = softcut_runtime.new()
    -- Announce platform mode once per session so users immediately see
    -- whether they're getting real audio (norns) or dry-mode (seamstress).
    softcut_runtime.announce(ctx.softcut_runtime.mode)
  end
  local softcut_zig = require("lib/voices/softcut_zig")
  local sample_path = params and params:get("sample_path_" .. track) or ""
  local config = {
    sample_path = (sample_path ~= "" and sample_path ~= nil) and sample_path or nil,
    root_note = params and params:get("sample_root_" .. track) or 60,
    start_sec = params and params:get("sample_start_" .. track) or 0,
    end_sec = params and params:get("sample_end_" .. track) or 1,
    loop = (params and params:get("sample_loop_" .. track)) == 2,
  }
  return softcut_zig.new(track, ctx.softcut_runtime, config)
end)

M.register("sc_synth", function(_, track)
  local sc_synth = require("lib/voices/sc_synth")
  local host, port = osc_target()
  local synthdef_idx = (params and params:get("sc_synthdef_" .. track)) or 1
  local synthdef = M.SC_SYNTHDEFS[synthdef_idx] or "sub"
  local voice = sc_synth.new(track, host, port, synthdef)
  -- Announce the selected SynthDef to the SC side so it has fresh state.
  voice:set_synthdef(synthdef)
  return voice
end)

M.register("none", function()
  return nil
end)

return M
