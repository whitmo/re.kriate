-- lib/app.lua
-- Top-level app logic: init, cleanup, grid connection, params setup

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")
local sequencer = require("lib/sequencer")
local grid_ui = require("lib/grid_ui")
local pattern = require("lib/pattern")
local pattern_persistence = require("lib/pattern_persistence")
local preset_persistence = require("lib/preset")
local meta_pattern = require("lib/meta_pattern")
local direction = require("lib/direction")
local grid_provider = require("lib/grid_provider")
local events = require("lib/events")
local log = require("lib/log")
local clock_sync = require("lib/clock_sync")
local mixer = require("lib/mixer")
local stock_presets = require("lib/stock_presets")

local M = {}

-- Page tray: groups of pages with 2-char abbreviated labels
-- Extended pages (ratchet, alt_note, glide) share a slot with their primary page
local PAGE_TRAY = {
  {pages = {"trigger", "ratchet"},    labels = {"tr", "ra"}},
  {pages = {"note", "alt_note"},      labels = {"no", "an"}},
  {pages = {"octave", "glide"},       labels = {"oc", "gl"}},
  {pages = {"duration"},              labels = {"du"}},
  {pages = {"velocity"},              labels = {"ve"}},
  {pages = {"probability"},           labels = {"pr"}},
  {pages = {"mixer"},                 labels = {"mx"}},
  {pages = {"alt_track"},             labels = {"at"}},
  {pages = {"meta_pattern"},          labels = {"mp"}},
  {pages = {"scale"},                 labels = {"sc"}},
}

local SCALE_NAMES = {
  "Major", "Natural Minor", "Dorian", "Mixolydian",
  "Lydian", "Phrygian", "Locrian", "Harmonic Minor",
  "Melodic Minor", "Major Pentatonic", "Minor Pentatonic",
  "Blues Scale", "Whole Tone", "Chromatic",
  "Custom",
}

-- Default custom-scale mask: major intervals (1,3,5,6,8,10,12 semitones set).
-- Gives a musical starting point when the user first selects the Custom scale.
local DEFAULT_CUSTOM_INTERVALS = {
  true, false, true, false, true, true, false,
  true, false, true, false, true,
}

local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

local VOICE_TYPES = {"midi", "osc", "sc_drums", "softcut", "sc_synth", "none"}
local SC_SYNTHDEFS = {"sub", "fm", "wavetable"}
local DEFAULT_PATTERN_BANK = "default"
local PATTERN_MESSAGE_KEY = "pattern" .. "_message"

local CLOCK_SOURCE_OPTIONS = {"internal", "external MIDI"}
local CLOCK_OUTPUT_OPTIONS = {"off", "on"}

-- Grid provider selector options (user-facing labels → registry names)
local GRID_PROVIDER_OPTIONS = {"monome", "midigrid", "push2", "launchpad pro", "virtual"}
local GRID_PROVIDER_REGISTRY = {"monome", "midigrid", "push2", "launchpad_pro", "virtual"}

local DEFAULT_PRESET_NAME = "default"
local PRESET_MESSAGE_KEY = "preset" .. "_message"

local function preset_autosave_enabled()
  if not params or not params.lookup or not params.lookup["preset_autosave"] then
    return false
  end
  return params:get("preset_autosave") == 2
end

--- Convert a MIDI note number to a human-readable note name (C0 = MIDI 0)
local function note_name(midi_num)
  return NOTE_NAMES[midi_num % 12 + 1] .. math.floor(midi_num / 12)
end

--- Formatter for the root_note param (receives the Control param object)
local function note_formatter(param)
  return note_name(param:get())
end

--- Build or rebuild a voice for a given track based on current param values
local function build_voice(ctx, t)
  local voice_idx = params:get("voice_" .. t)
  local voice_type = VOICE_TYPES[voice_idx]
  if voice_type == "midi" then
    local midi_voice = require("lib/voices/midi")
    local ch = params:get("midi_ch_" .. t)
    ctx.voices[t] = midi_voice.new(ctx.midi_dev, ch)
  elseif voice_type == "osc" then
    local osc_voice = require("lib/voices/osc")
    local host = params:get("osc_host")
    local port = params:get("osc_port")
    ctx.voices[t] = osc_voice.new(t, host, port)
  elseif voice_type == "sc_drums" then
    local sc_drums = require("lib/voices/sc_drums")
    local host = params:get("osc_host")
    local port = params:get("osc_port")
    ctx.voices[t] = sc_drums.new(t, host, port)
  elseif voice_type == "sc_synth" then
    local sc_synth = require("lib/voices/sc_synth")
    local host = params:get("osc_host")
    local port = params:get("osc_port")
    local synthdef_idx = params:get("sc_synthdef_" .. t)
    local synthdef = SC_SYNTHDEFS[synthdef_idx] or "sub"
    local voice = sc_synth.new(t, host, port, synthdef)
    -- Announce the selected SynthDef to the SC side so it has fresh state.
    voice:set_synthdef(synthdef)
    ctx.voices[t] = voice
  elseif voice_type == "softcut" then
    if not ctx.softcut_runtime then
      local softcut_runtime = require("lib/voices/softcut_runtime")
      ctx.softcut_runtime = softcut_runtime.new()
      -- Announce platform mode once per session so users immediately see
      -- whether they're getting real audio (norns) or dry-mode (seamstress).
      softcut_runtime.announce(ctx.softcut_runtime.mode)
    end
    local softcut_zig = require("lib/voices/softcut_zig")
    local sample_path = params:get("sample_path_" .. t)
    local config = {
      sample_path = (sample_path ~= "") and sample_path or nil,
      root_note = params:get("sample_root_" .. t),
      start_sec = params:get("sample_start_" .. t),
      end_sec = params:get("sample_end_" .. t),
      loop = params:get("sample_loop_" .. t) == 2,
    }
    ctx.voices[t] = softcut_zig.new(t, ctx.softcut_runtime, config)
  else
    ctx.voices[t] = nil
  end
  -- Re-apply mixer state to the freshly built voice (level/pan per track).
  if ctx.voices[t] then
    mixer.apply_to_voice(ctx, t)
  end
end

local function pattern_bank_name(name)
  if name and name ~= "" then
    return name
  end
  return DEFAULT_PATTERN_BANK
end

local function set_param_if_needed(id, value)
  if not params or not params.get or not params.set then
    return
  end
  if params:get(id) ~= value then
    params:set(id, value)
  end
end

local function set_pattern_status(ctx, text)
  if not ctx then
    return
  end
  ctx.active_pattern = nil
  ctx[PATTERN_MESSAGE_KEY] = {text = text, time = os.clock()}
end

local function format_bank_list(names)
  if #names == 0 then
    return "banks: none"
  end
  return "banks: " .. table.concat(names, ", ")
end

local function preset_name(name)
  if name and name ~= "" then
    return name
  end
  if params and params.get and params.lookup and params.lookup["preset_name"] then
    local param_name = params:get("preset_name")
    if param_name and param_name ~= "" then
      return param_name
    end
  end
  return DEFAULT_PRESET_NAME
end

local function set_preset_status(ctx, text)
  if not ctx then return end
  ctx[PRESET_MESSAGE_KEY] = {text = text, time = os.clock()}
end

local function format_preset_list(names)
  if #names == 0 then
    return "presets: none"
  end
  return "presets: " .. table.concat(names, ", ")
end

local function add_preset_persistence_params(ctx)
  if not params or not params.add_text or not params.add_option then
    return
  end

  params:add_group("preset_persistence", "preset persistence", 6)
  params:add_text("preset_name", "preset name", DEFAULT_PRESET_NAME)
  params:add_option("preset_autosave", "autosave on exit", {"off", "on"}, 2)
  params:add_option("preset_save", "save preset", {"-", "save"}, 1)
  params:add_option("preset_load", "load preset", {"-", "load"}, 1)
  params:add_option("preset_list", "list presets", {"-", "list"}, 1)
  params:add_option("preset_delete", "delete preset", {"-", "delete"}, 1)

  local resetting_param = false
  local function reset_action_param(id)
    if resetting_param then return end
    resetting_param = true
    set_param_if_needed(id, 1)
    resetting_param = false
  end

  params:set_action("preset_save", function(value)
    if resetting_param or value ~= 2 then return end
    M.save_preset(ctx)
    reset_action_param("preset_save")
  end)

  params:set_action("preset_load", function(value)
    if resetting_param or value ~= 2 then return end
    M.load_preset(ctx)
    reset_action_param("preset_load")
  end)

  params:set_action("preset_list", function(value)
    if resetting_param or value ~= 2 then return end
    M.list_presets(ctx)
    reset_action_param("preset_list")
  end)

  params:set_action("preset_delete", function(value)
    if resetting_param or value ~= 2 then return end
    M.delete_preset(ctx)
    reset_action_param("preset_delete")
  end)
end

--- Attach a MIDI input callback that routes clock/transport bytes into
--- ctx.clock_sync and drives sequencer start/stop/reset via transport messages.
--- The callback chains onto any existing midi_in_dev.event handler so this does
--- not stomp user-installed handlers.
local function attach_midi_input(ctx)
  local dev = ctx.clock_sync and ctx.clock_sync.midi_in_dev
  if not dev then return end
  local sequencer = require("lib/sequencer")
  local prev_event = dev.event
  dev.event = log.wrap(function(data)
    local events_fired = clock_sync.process_midi(ctx.clock_sync, data, os.clock())
    for _, ev in ipairs(events_fired) do
      if ctx.clock_sync.source == clock_sync.SOURCE_EXT_MIDI then
        if ev == "start" then
          sequencer.reset(ctx)
          sequencer.start(ctx)
        elseif ev == "continue" then
          sequencer.start(ctx)
        elseif ev == "stop" then
          sequencer.stop(ctx)
        end
      end
    end
    if prev_event then prev_event(data) end
  end, "clock_sync.midi_event")
end

--- Apply the current clock source to the platform. On norns there is a global
--- "clock_source" param (1=internal, 2=midi). If it is absent (e.g. seamstress
--- or test harness) this is a no-op.
local function apply_platform_clock_source(ctx)
  if not params or not params.lookup or not params.set then return end
  local sys_id = "clock_source"
  if not params.lookup[sys_id] then return end
  local platform_value = (ctx.clock_sync.source == clock_sync.SOURCE_EXT_MIDI) and 2 or 1
  if params:get(sys_id) ~= platform_value then
    params:set(sys_id, platform_value)
  end
end

--- Transport params (advance, play, stop): trigger-style option params that
--- auto-reset to "-" after firing, mirroring the preset_save/load pattern.
--- These expose grid transport actions to the norns/seamstress param system so
--- they can be MIDI-mapped via PMAP (re-9d9).
local function add_transport_params(ctx)
  if not params or not params.add_group then return end
  params:add_group("transport", "transport", track_mod.NUM_TRACKS + 2)

  local resetting = {}
  local function reset_action_param(id)
    if resetting[id] then return end
    resetting[id] = true
    set_param_if_needed(id, 1)
    resetting[id] = false
  end

  for t = 1, track_mod.NUM_TRACKS do
    local id = "advance_" .. t
    params:add_option(id, "track " .. t .. " advance", {"-", "advance"}, 1)
    params:set_action(id, function(val)
      if resetting[id] or val ~= 2 then return end
      sequencer.step_track(ctx, t)
      reset_action_param(id)
    end)
  end

  params:add_option("transport_play", "play", {"-", "play"}, 1)
  params:set_action("transport_play", function(val)
    if resetting["transport_play"] or val ~= 2 then return end
    sequencer.start(ctx)
    reset_action_param("transport_play")
  end)

  params:add_option("transport_stop", "stop", {"-", "stop"}, 1)
  params:set_action("transport_stop", function(val)
    if resetting["transport_stop"] or val ~= 2 then return end
    sequencer.stop(ctx)
    reset_action_param("transport_stop")
  end)
end

local function add_clock_sync_params(ctx)
  if not params or not params.add_group then return end
  params:add_group("clock_sync", "clock sync", 2)
  params:add_option("clock_source_mode", "clock source", CLOCK_SOURCE_OPTIONS, 1)
  params:add_option("clock_output", "clock output", CLOCK_OUTPUT_OPTIONS, 1)

  params:set_action("clock_source_mode", function(val)
    local sequencer = require("lib/sequencer")
    local desired = (val == 2) and clock_sync.SOURCE_EXT_MIDI or clock_sync.SOURCE_INTERNAL
    if ctx.clock_sync.source == desired then return end
    -- FR-009: switching while playing must stop and silence all voices first.
    if ctx.playing then
      sequencer.stop(ctx)
    end
    clock_sync.set_source(ctx.clock_sync, desired)
    apply_platform_clock_source(ctx)
  end)

  params:set_action("clock_output", function(val)
    clock_sync.set_output_enabled(ctx.clock_sync, val == 2)
  end)
end

--- Connect (or reconnect) the grid based on config + provider selection.
--- Cleanly tears down any existing grid before swapping in a new one.
local function connect_grid(ctx, provider_name, opts)
  if ctx.g and ctx.g.cleanup then
    pcall(function() ctx.g:cleanup() end)
  end
  ctx.g = grid_provider.connect(provider_name, opts or {})
  ctx.g.key = log.wrap(function(x, y, z)
    grid_ui.key(ctx, x, y, z)
    ctx.grid_dirty = true
  end, "grid.key")
  ctx.grid_dirty = true
end

--- Translate the user-facing grid_provider option index to a registry name.
local function grid_option_to_name(idx)
  return GRID_PROVIDER_REGISTRY[idx] or "monome"
end

local function add_grid_params(ctx, config)
  if not params or not params.add_group then return end
  params:add_group("grid", "grid", 2)

  -- Default param to whatever the script booted with (preserves existing behavior).
  local default_idx = 1
  local boot_name = config.grid_provider or "monome"
  for i, name in ipairs(GRID_PROVIDER_REGISTRY) do
    if name == boot_name then default_idx = i break end
  end
  params:add_option("grid_provider", "grid provider", GRID_PROVIDER_OPTIONS, default_idx)
  params:add_number("grid_midi_device", "grid midi device", 1, 16,
    (config.grid_opts and config.grid_opts.device) or 1)

  -- Reconnect on provider change; uses current grid_midi_device value for midi grids.
  params:set_action("grid_provider", function(val)
    local name = grid_option_to_name(val)
    if ctx.g and ctx._grid_provider_name == name then return end
    local opts = {}
    if name == "push2" or name == "launchpad_pro" or name == "midigrid" then
      opts.device = params:get("grid_midi_device")
    elseif config.grid_opts then
      -- Preserve original opts (dims/mirror) for monome/virtual-like providers
      for k, v in pairs(config.grid_opts) do opts[k] = v end
    end
    local ok, err = pcall(connect_grid, ctx, name, opts)
    if ok then
      ctx._grid_provider_name = name
      log.info("grid reconnected: " .. name)
    else
      log.warn("grid reconnect failed (" .. name .. "): " .. tostring(err))
    end
  end)
end

function M.init(config)
  config = config or {}

  local use_config_voices = config.voices ~= nil

  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    time_held = false,
    loop_first_press = nil,
    loop_first_y = nil,
    grid_dirty = true,
    scale_notes = {},
    voices = config.voices or {},
    sprite_voices = config.sprite_voices,
    patterns = pattern.new_slots(),
    events = events.new(),
    pattern_held = false,
    pattern_slot = 1,
    cued_pattern_slot = nil,
    meta = meta_pattern.new(),
    midi_dev = config.midi_dev,
    custom_intervals = {},
    mixer = mixer.new(),
  }
  for i = 1, 12 do
    ctx.custom_intervals[i] = DEFAULT_CUSTOM_INTERVALS[i]
  end

  -- Clock sync state: MIDI clock input/output + transport (spec 010).
  -- Input/output default to the shared midi_dev; consumers can override later.
  ctx.clock_sync = clock_sync.new({
    midi_in_dev = config.clock_midi_in_dev or config.midi_dev,
    midi_out_dev = config.clock_midi_out_dev or config.midi_dev,
    midi_in_port = config.clock_midi_in_port or 1,
    midi_out_port = config.clock_midi_out_port or 1,
  })

  -- params: global settings
  params:add_separator("re_kriate", "re.kriate")

  params:add_number("root_note", "root note", 0, 127, 60, nil, note_formatter)
  params:set_action("root_note", function() M.rebuild_scale(ctx) end)

  params:add_option("scale_type", "scale", SCALE_NAMES, 1)
  params:set_action("scale_type", function() M.rebuild_scale(ctx) end)

  -- params: output group
  params:add_group("output", "output", 2)
  params:add_option("osc_host", "osc host", {"127.0.0.1"}, 1)
  params:add_number("osc_port", "osc port", 1, 65535, 57120)

  -- params: per-track groups
  local div_names = {"1/16", "1/12", "1/8", "1/6", "1/4", "1/2", "1/1"}
  for t = 1, track_mod.NUM_TRACKS do
    params:add_group("track_" .. t, "track " .. t, 10)

    params:add_option("voice_" .. t, "voice", VOICE_TYPES, 1)
    if not use_config_voices then
      params:set_action("voice_" .. t, function()
        build_voice(ctx, t)
      end)
    end

    params:add_number("midi_ch_" .. t, "midi ch", 1, 16, t)
    if not use_config_voices then
      params:set_action("midi_ch_" .. t, function(val)
        -- Only rebuild if current voice type is midi
        local voice_idx = params:get("voice_" .. t)
        if VOICE_TYPES[voice_idx] == "midi" then
          build_voice(ctx, t)
        end
      end)
    end

    -- sc_synth SynthDef selector (used when voice = "sc_synth")
    params:add_option("sc_synthdef_" .. t, "sc synthdef", SC_SYNTHDEFS, 1)
    if not use_config_voices then
      params:set_action("sc_synthdef_" .. t, function()
        local voice_idx = params:get("voice_" .. t)
        if VOICE_TYPES[voice_idx] == "sc_synth" then
          build_voice(ctx, t)
        end
      end)
    end

    -- softcut sample params (used when voice = "softcut")
    params:add_text("sample_path_" .. t, "sample path", "")
    params:add_number("sample_root_" .. t, "sample root", 0, 127, 60, nil, note_formatter)
    params:add_number("sample_start_" .. t, "sample start", 0, 350, 0)
    params:add_number("sample_end_" .. t, "sample end", 0, 350, 1)
    params:add_option("sample_loop_" .. t, "sample loop", {"off", "on"}, 1)
    params:add_number("sample_grab_len_" .. t, "grab length (s)", 1, 30, 4)
    params:add_number("sample_grab_input_" .. t, "grab input", 1, 2, 1)
    params:add_option("sample_grab_" .. t, "grab sample", {"-", "grab"}, 1)
    if not use_config_voices then
      local function rebuild_if_softcut()
        local voice_idx = params:get("voice_" .. t)
        if VOICE_TYPES[voice_idx] == "softcut" then
          build_voice(ctx, t)
        end
      end
      params:set_action("sample_path_" .. t, rebuild_if_softcut)
      params:set_action("sample_root_" .. t, rebuild_if_softcut)
      params:set_action("sample_start_" .. t, rebuild_if_softcut)
      params:set_action("sample_end_" .. t, rebuild_if_softcut)
      params:set_action("sample_loop_" .. t, rebuild_if_softcut)
      params:set_action("sample_grab_" .. t, function(val)
        if val ~= 2 then return end
        -- Reset the action param so subsequent grabs can fire.
        params:set("sample_grab_" .. t, 1)
        M.grab_sample(ctx, t)
      end)
    end

    params:add_option("division_" .. t, "division", div_names, 1)
    params:set_action("division_" .. t, function(val)
      ctx.tracks[t].division = val
    end)

    params:add_option("direction_" .. t, "direction", direction.MODES, 1)
    params:set_action("direction_" .. t, function(val)
      ctx.tracks[t].direction = direction.MODES[val]
    end)
  end

  -- params: per-track swing
  for t = 1, track_mod.NUM_TRACKS do
    params:add_number("swing_" .. t, "track " .. t .. " swing", 0, 100, 0)
    params:set_action("swing_" .. t, function(val)
      ctx.tracks[t].swing = val
    end)
  end

  -- params: mixer (level, pan, mute per track).
  -- Level is stored as percent (0-100) and pan as percent (-100..+100) to
  -- keep the param UI friendly on norns; ctx.mixer holds the float source
  -- of truth (0.0-1.0 / -1.0..+1.0) that is pushed to voice backends.
  params:add_group("mixer", "mixer", track_mod.NUM_TRACKS * 3)
  for t = 1, track_mod.NUM_TRACKS do
    params:add_number("level_" .. t, "track " .. t .. " level", 0, 100, 100)
    params:set_action("level_" .. t, function(val)
      mixer.set_level(ctx, t, (val or 0) / 100)
    end)
    params:add_number("pan_" .. t, "track " .. t .. " pan", -100, 100, 0)
    params:set_action("pan_" .. t, function(val)
      mixer.set_pan(ctx, t, (val or 0) / 100)
    end)
    params:add_option("mute_" .. t, "track " .. t .. " mute", {"off", "on"}, 1)
    params:set_action("mute_" .. t, function(val)
      mixer.set_mute(ctx, t, val == 2)
    end)
  end

  add_transport_params(ctx)
  add_clock_sync_params(ctx)
  add_preset_persistence_params(ctx)
  add_grid_params(ctx, config)

  -- Build initial voices from params (unless config provided voices)
  if not use_config_voices and ctx.midi_dev then
    for t = 1, track_mod.NUM_TRACKS do
      build_voice(ctx, t)
    end
  end

  -- build initial scale
  M.rebuild_scale(ctx)

  -- sync grid scale changes to params
  ctx.events:on("scale:root", function(data)
    params:set("root_note", data.root_note)
  end)
  ctx.events:on("scale:type", function(data)
    params:set("scale_type", data.scale_type)
    -- Custom scale: mask may have changed even when scale_type already == 15,
    -- so force a rebuild to keep ctx.scale_notes in sync with ctx.custom_intervals.
    if SCALE_NAMES[data.scale_type] == "Custom" then
      M.rebuild_scale(ctx)
    end
  end)

  -- grid (pluggable: config.grid_provider selects backend; runtime switching via
  -- the "grid provider" param — see add_grid_params / connect_grid).
  ctx._grid_provider_name = config.grid_provider or "monome"
  connect_grid(ctx, ctx._grid_provider_name, config.grid_opts)

  -- grid redraw metro
  ctx.grid_metro = metro.init()
  ctx.grid_metro.time = 1 / 30
  ctx.grid_metro.event = log.wrap(function()
    if ctx.grid_dirty then
      grid_ui.redraw(ctx)
      ctx.grid_dirty = false
    end
  end, "grid_metro.event")
  ctx.grid_metro:start()

  attach_midi_input(ctx)

  -- Seed stock presets on first run (re-2yn). Gives a fresh install something
  -- to load/audition without having to build patterns from scratch. Runs
  -- before autorestore so stock presets exist if the user opts to browse
  -- them, but never overwrites an existing preset library. Gated on an
  -- explicit config flag so hermetic tests that mock params/filesystem
  -- don't accidentally write stock files into the real user data dir.
  if config.seed_stock_presets then
    local seeded, seed_errs = stock_presets.seed_if_empty(preset_persistence)
    if seeded and seeded > 0 then
      log.info("stock presets seeded: " .. tostring(seeded))
    end
    if seed_errs then
      for name, err in pairs(seed_errs) do
        log.warn("stock preset seed failed (" .. name .. "): " .. tostring(err))
      end
    end
  end

  -- Autorestore last session if an autosave exists and autosave is enabled
  -- (FR-009). Silent no-op if no autosave present or autosave disabled.
  if preset_autosave_enabled() and preset_persistence.exists(preset_persistence.AUTOSAVE_NAME) then
    local ok, err = preset_persistence.load_autosave(ctx)
    if not ok then
      log.warn("preset autoload skipped: " .. tostring(err))
    else
      log.info("preset autoload restored previous session")
    end
  end

  return ctx
end

function M.save_pattern_bank(ctx, name)
  -- pattern_persistence now carries ctx.tracks at payload top-level (FR-007b),
  -- so save no longer needs to clobber pattern slot 1 as a scratch buffer.
  local ok, path_or_err = pattern_persistence.save(ctx, pattern_bank_name(name))
  if ok then
    local message = "saved bank"
    log.info(message)
    set_pattern_status(ctx, message)
    return ok, path_or_err
  end

  local message = "save failed: " .. tostring(path_or_err)
  log.warn(message)
  set_pattern_status(ctx, message)
  return nil, path_or_err
end

function M.load_pattern_bank(ctx, name)
  local ok, err = pattern_persistence.load(ctx, pattern_bank_name(name))
  if ok then
    local message = "loaded bank"
    log.info(message)
    set_pattern_status(ctx, message)
    return true
  end

  local message = "load failed: " .. tostring(err)
  log.warn(message)
  set_pattern_status(ctx, message)
  return nil, err
end

function M.list_pattern_banks(ctx)
  local names = pattern_persistence.list()
  local message = format_bank_list(names)
  log.info(message)
  set_pattern_status(ctx, message)
  return names
end

function M.save_preset(ctx, name)
  local ok, path_or_err = preset_persistence.save(ctx, preset_name(name))
  if ok then
    local message = "saved preset"
    log.info(message)
    set_preset_status(ctx, message)
    return ok, path_or_err
  end
  local message = "preset save failed: " .. tostring(path_or_err)
  log.warn(message)
  set_preset_status(ctx, message)
  return nil, path_or_err
end

function M.load_preset(ctx, name)
  -- Stop playback first so the load doesn't race clock coroutines (FR-010).
  if ctx and ctx.playing then
    sequencer.stop(ctx)
  end
  local ok, err = preset_persistence.load(ctx, preset_name(name))
  if ok then
    local message = "loaded preset"
    log.info(message)
    set_preset_status(ctx, message)
    return true
  end
  local message = "preset load failed: " .. tostring(err)
  log.warn(message)
  set_preset_status(ctx, message)
  return nil, err
end

function M.list_presets(ctx)
  local names = preset_persistence.list()
  local message = format_preset_list(names)
  log.info(message)
  set_preset_status(ctx, message)
  return names
end

function M.delete_preset(ctx, name)
  local ok, err = preset_persistence.delete(preset_name(name))
  if ok then
    local message = "deleted preset"
    log.info(message)
    set_preset_status(ctx, message)
    return true
  end
  local message = "preset delete failed: " .. tostring(err)
  log.warn(message)
  set_preset_status(ctx, message)
  return nil, err
end

function M.delete_pattern_bank(ctx, name)
  local ok, err = pattern_persistence.delete(pattern_bank_name(name))
  if ok then
    local message = "deleted bank"
    log.info(message)
    set_pattern_status(ctx, message)
    return true
  end

  local message = "delete failed: " .. tostring(err)
  log.warn(message)
  set_pattern_status(ctx, message)
  return nil, err
end

--- Trigger a softcut sample-grab on track `t`: records live ADC audio into
--- the track's softcut buffer region, then marks the voice playable.
--- No-ops when the track isn't a softcut voice or lacks a :grab method.
function M.grab_sample(ctx, t)
  local voice = ctx and ctx.voices and ctx.voices[t]
  if not voice or type(voice.grab) ~= "function" then
    return nil, "not_softcut"
  end
  local duration, input_ch = 4, 1
  if params and params.get then
    local ok_len = pcall(function() duration = params:get("sample_grab_len_" .. t) end)
    local ok_in = pcall(function() input_ch = params:get("sample_grab_input_" .. t) end)
    if not ok_len then duration = 4 end
    if not ok_in then input_ch = 1 end
  end
  return voice:grab({ duration = duration, input_channel = input_ch })
end

function M.rebuild_scale(ctx)
  local root = params:get("root_note")
  local scale_idx = params:get("scale_type")
  local scale_type = SCALE_NAMES[scale_idx]
  ctx.root_note = root
  ctx.scale_type = scale_idx
  local notes
  if scale_type == "Custom" then
    notes = scale_mod.build_custom_scale(root, ctx.custom_intervals)
  else
    notes = scale_mod.build_scale(root, scale_type)
  end
  if notes then ctx.scale_notes = notes end
end

function M.redraw(ctx)
   -- screen UI: minimal info display
  screen.clear()
  screen.level(15)
  screen.move(5, 10)
  screen.text("re.kriate")
  screen.level(8)
  screen.move(5, 25)
  screen.text("track " .. ctx.active_track .. " | " .. ctx.active_page)
  screen.move(5, 40)
  screen.text(ctx.playing and "playing" or "stopped")

  -- clock sync status line (spec 010 FR-010)
  if ctx.clock_sync then
    local internal_bpm = nil
    if params and params.get and params.lookup and params.lookup["clock_tempo"] then
      internal_bpm = params:get("clock_tempo")
    end
    screen.move(5, 52)
    screen.text(clock_sync.display(ctx.clock_sync, internal_bpm, os.clock()))
  end

  -- page indicator tray along bottom
  local tray_y = 62
  local tray_x = 2
  local tray_spacing = 14
  for i, group in ipairs(PAGE_TRAY) do
    local x = tray_x + (i - 1) * tray_spacing
    local label = group.labels[1]
    local active = false
    for j, p in ipairs(group.pages) do
      if ctx.active_page == p then
        label = group.labels[j]
        active = true
        break
      end
    end
    screen.level(active and 15 or 3)
    screen.move(x, tray_y)
    screen.text(label)
  end

  screen.update()
end

function M.key(ctx, n, z)
  if n == 2 and z == 1 then
    -- K2: play/stop
    if ctx.playing then
      sequencer.stop(ctx)
    else
      sequencer.start(ctx)
    end
  elseif n == 3 and z == 1 then
    -- K3: reset playheads
    sequencer.reset(ctx)
  end
  ctx.grid_dirty = true
end

function M.enc(ctx, n, d)
  if n == 1 then
    -- E1: select track
    ctx.active_track = util.clamp(ctx.active_track + d, 1, track_mod.NUM_TRACKS)
  elseif n == 2 then
    -- E2: select page
    local pages = grid_ui.PAGES
    local idx = 1
    for i, p in ipairs(pages) do
      if p == ctx.active_page then idx = i; break end
    end
    idx = util.clamp(idx + d, 1, #pages)
    ctx.active_page = pages[idx]
  end
  ctx.grid_dirty = true
end

function M.cleanup(ctx)
  sequencer.stop(ctx)
  -- Autosave session state if enabled (FR-009). Gated on a param so tests
  -- and headless harnesses that never register the param stay hermetic.
  if ctx and preset_autosave_enabled() then
    local ok, err = preset_persistence.save_autosave(ctx)
    if not ok then
      log.warn("preset autosave failed: " .. tostring(err))
    end
  end
  if ctx.voices then
    for _, voice in ipairs(ctx.voices) do
      voice:all_notes_off()
    end
  end
  if ctx.sprite_voices then
    for _, sv in ipairs(ctx.sprite_voices) do
      sv:all_notes_off()
    end
  end
  if ctx.grid_metro then
    ctx.grid_metro:stop()
  end
  if ctx.g and ctx.g.cleanup then
    ctx.g:cleanup()
  end
end

return M
