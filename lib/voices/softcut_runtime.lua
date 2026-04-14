-- lib/voices/softcut_runtime.lua
-- Buffer management runtime for softcut_zig voice backend.
-- Models 6 voice slots across 2 mono buffers (~5 min each).
-- Provides the runtime interface that softcut_zig.lua expects via injection.
--
-- Platform note
-- -------------
-- Softcut is a norns-native DSP engine — it does not exist in seamstress. This
-- runtime tracks voice state (region, rate, loop points, sample load status)
-- in pure Lua so it works identically on both platforms, but on seamstress
-- nothing downstream actually plays audio. The runtime reports its mode via
-- M.detect_mode() and runtime.mode so scripts and the UI can surface the
-- difference clearly at init.
--
--   mode = "norns" — real softcut engine available (_G.softcut is set)
--   mode = "dry"   — state-only; no audio output (seamstress / busted tests)

local M = {}

M.NUM_VOICES = 6
M.NUM_BUFFERS = 2
M.BUFFER_DUR = 350 -- ~5.8 min at 48kHz

--- Detect the active softcut mode. Returns "norns" when the global softcut
--- table is available with its expected API, otherwise "dry".
function M.detect_mode()
  if rawget(_G, "softcut") and type(_G.softcut) == "table"
      and type(_G.softcut.enable) == "function" then
    return "norns"
  end
  return "dry"
end

--- One-line human-readable status string for logs / screen tray.
function M.status_string(mode)
  mode = mode or M.detect_mode()
  if mode == "norns" then
    return "softcut: norns native (audio enabled)"
  end
  return "softcut: dry-mode (no audio — norns only)"
end

--- Print the status banner. Safe to call at init on any platform.
function M.announce(mode)
  print(M.status_string(mode))
end

local function new_voice_state(buf, region_start, region_end)
  return {
    enabled = false,
    buffer = buf,
    region_start = region_start,
    region_end = region_end,
    level = 0,
    pan = 0,
    rate = 1,
    playing = false,
    position = 0,
    loop = false,
    loop_start = 0,
    loop_end = 1,
    fade_time = 0,
    level_slew_time = 0,
    rate_slew_time = 0,
    sample_path = nil,
    sample_loaded = false,
  }
end

function M.new(opts)
  opts = opts or {}
  local num_voices = opts.num_voices or M.NUM_VOICES
  local buffer_dur = opts.buffer_dur or M.BUFFER_DUR
  local file_check = opts.file_exists

  -- Fixed regions: split voices evenly across 2 buffers.
  -- Voices 1..ceil(n/2) on buffer 1, rest on buffer 2.
  local per_buf = math.ceil(num_voices / 2)
  local region_dur = buffer_dur / per_buf

  local runtime = {
    voices = {},
    num_voices = num_voices,
    buffer_dur = buffer_dur,
    region_dur = region_dur,
    warnings = {},
    mode = opts.mode or M.detect_mode(),
  }

  for i = 1, num_voices do
    local buf = i <= per_buf and 1 or 2
    local slot = i <= per_buf and i or (i - per_buf)
    local start = (slot - 1) * region_dur
    runtime.voices[i] = new_voice_state(buf, start, start + region_dur)
  end

  -- Voice state accessors (called by softcut_zig.lua)

  function runtime.enable(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.enabled = val end
  end

  function runtime.buffer(voice_id, buf)
    local vs = runtime.voices[voice_id]
    if vs then vs.buffer = buf end
  end

  function runtime.level(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.level = val end
  end

  function runtime.pan(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.pan = val end
  end

  function runtime.rate(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.rate = val end
  end

  function runtime.play(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.playing = val end
  end

  function runtime.position(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.position = val end
  end

  function runtime.loop(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.loop = val end
  end

  function runtime.loop_start(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.loop_start = val end
  end

  function runtime.loop_end(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.loop_end = val end
  end

  function runtime.fade_time(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.fade_time = val end
  end

  function runtime.level_slew_time(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.level_slew_time = val end
  end

  function runtime.rate_slew_time(voice_id, val)
    local vs = runtime.voices[voice_id]
    if vs then vs.rate_slew_time = val end
  end

  function runtime.rec_level(_voice_id, _val)
  end

  function runtime.pre_level(_voice_id, _val)
  end

  function runtime.level_cut(_voice_id_a, _voice_id_b, _val)
  end

  function runtime.file_exists(path)
    if file_check then
      return file_check(path)
    end
    if not path or path == "" then return false end
    local fh = io.open(path, "r")
    if fh then
      fh:close()
      return true
    end
    return false
  end

  function runtime.load_sample(voice_id, path, config)
    local vs = runtime.voices[voice_id]
    if not vs then return false, "invalid_voice" end
    if not runtime.file_exists(path) then
      return false, "file_not_found"
    end
    vs.sample_path = path
    vs.sample_loaded = true
    return true
  end

  function runtime.buffer_read_mono(path, start, duration)
    return runtime.file_exists(path)
  end

  function runtime.warn(msg)
    table.insert(runtime.warnings, msg)
  end

  function runtime.status_string()
    return M.status_string(runtime.mode)
  end

  function runtime.is_dry()
    return runtime.mode == "dry"
  end

  return runtime
end

return M
