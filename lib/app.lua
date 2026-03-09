-- lib/app.lua
-- Top-level app logic: init, cleanup, grid connection, params setup

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")
local sequencer = require("lib/sequencer")
local grid_ui = require("lib/grid_ui")
local pattern = require("lib/pattern")
local direction = require("lib/direction")
local grid_provider = require("lib/grid_provider")
local log = require("lib/log")

local M = {}

local SCALE_NAMES = {
  "Major", "Natural Minor", "Dorian", "Mixolydian",
  "Lydian", "Phrygian", "Locrian", "Harmonic Minor",
  "Melodic Minor", "Major Pentatonic", "Minor Pentatonic",
  "Blues Scale", "Whole Tone", "Chromatic",
}

local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

local VOICE_TYPES = {"midi", "osc", "none"}

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
  else
    ctx.voices[t] = nil
  end
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
    loop_first_press = nil,
    grid_dirty = true,
    scale_notes = {},
    voices = config.voices or {},
    sprite_voices = config.sprite_voices,
    patterns = pattern.new_slots(),
    midi_dev = config.midi_dev,
  }

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
    params:add_group("track_" .. t, "track " .. t, 4)

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

    params:add_option("division_" .. t, "division", div_names, 1)
    params:set_action("division_" .. t, function(val)
      ctx.tracks[t].division = val
    end)

    params:add_option("direction_" .. t, "direction", direction.MODES, 1)
    params:set_action("direction_" .. t, function(val)
      ctx.tracks[t].direction = direction.MODES[val]
    end)
  end

  -- Build initial voices from params (unless config provided voices)
  if not use_config_voices and ctx.midi_dev then
    for t = 1, track_mod.NUM_TRACKS do
      build_voice(ctx, t)
    end
  end

  -- build initial scale
  M.rebuild_scale(ctx)

  -- grid (pluggable: config.grid_provider selects backend)
  ctx.g = grid_provider.connect(config.grid_provider, config.grid_opts)
  ctx.g.key = log.wrap(function(x, y, z)
    grid_ui.key(ctx, x, y, z)
    ctx.grid_dirty = true
  end, "grid.key")

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

  return ctx
end

function M.rebuild_scale(ctx)
  local root = params:get("root_note")
  local scale_type = SCALE_NAMES[params:get("scale_type")]
  local notes = scale_mod.build_scale(root, scale_type)
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
