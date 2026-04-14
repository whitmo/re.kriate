-- lib/voices/softcut_zig.lua
-- Softcut sampler voice with injected runtime (test-friendly)

local M = {}

local DEFAULTS = {
  sample_path = nil,
  root_note = 60,
  start_sec = 0,
  end_sec = 1,
  loop = false,
  level = 1.0,
  pan = 0.0,
  attack = 0.01,
  release = 0.05,
  rate_slew = 0.0,
}

local function midi_to_rate(note, root_note)
  return 2 ^ ((note - root_note) / 12)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function merge_config(cfg)
  local merged = {}
  for k, v in pairs(DEFAULTS) do merged[k] = v end
  for k, v in pairs(cfg or {}) do merged[k] = v end
  if merged.end_sec <= merged.start_sec then
    merged.end_sec = merged.start_sec + 0.001
  end
  return merged
end

local function file_exists(path)
  if not path or path == "" then
    return false
  end
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    return true
  end
  return false
end

function M.new(voice_id, runtime, config)
  local self = {
    voice_id = voice_id,
    runtime = runtime or {},
    config = merge_config(config),
    active_notes = {},
    active_note = nil,
    note_off_coro = nil,
    portamento_override = nil,
    available = false,
    last_error = nil,
  }

  local clock = rawget(_G, "clock") or {
    run = function() return nil end,
    cancel = function() end,
    sync = function() end,
  }
  self.clock = clock

  local function warn(msg)
    if self.runtime.warn then
      self.runtime.warn(msg)
    end
  end

  local function current_slew()
    if self.portamento_override and self.portamento_override > 0 then
      return self.portamento_override
    end
    return self.config.rate_slew or 0
  end

  local function stop_current(cancel_pending)
    if cancel_pending and self.note_off_coro then
      self.clock.cancel(self.note_off_coro)
      self.note_off_coro = nil
    end
    if self.runtime.fade_time then
      self.runtime.fade_time(self.voice_id, self.config.release)
    end
    if self.runtime.level_slew_time then
      self.runtime.level_slew_time(self.voice_id, self.config.release)
    end
    if self.runtime.play then
      self.runtime.play(self.voice_id, false)
    end
    self.active_note = nil
  end

  function self:apply_config(cfg)
    self.config = merge_config(cfg)
    local start_sec = self.config.start_sec or 0
    local duration = (self.config.end_sec or 0) - start_sec

    local recorded_marker = self.runtime.RECORDED_MARKER
        or (package.loaded["lib/voices/softcut_runtime"]
            and package.loaded["lib/voices/softcut_runtime"].RECORDED_MARKER)
        or "__recorded__"

    if not self.config.sample_path then
      self.available = false
      self.last_error = "sample_missing"
      warn("softcut_zig: missing sample path")
    elseif self.config.sample_path == recorded_marker then
      -- Buffer holds a live-recorded sample; no file I/O needed.
      self.available = true
      self.last_error = nil
    else
      local exists = self.runtime.file_exists or file_exists
      if not exists(self.config.sample_path) then
        self.available = false
        self.last_error = "sample_missing"
        warn("softcut_zig: sample missing: " .. self.config.sample_path)
      elseif self.runtime.load_sample then
        local ok, err = self.runtime.load_sample(self.voice_id, self.config.sample_path, self.config)
        if ok == false then
          self.available = false
          self.last_error = err or "load_failed"
          warn("softcut_zig: sample load failed: " .. tostring(self.last_error))
        else
          self.available = true
          self.last_error = nil
        end
      elseif self.runtime.buffer_read_mono then
        self.runtime.buffer_read_mono(self.config.sample_path, start_sec, duration)
        self.available = true
        self.last_error = nil
      else
        self.available = true
        self.last_error = nil
      end
    end

    if self.runtime.enable then self.runtime.enable(self.voice_id, true) end
    if self.runtime.loop then self.runtime.loop(self.voice_id, self.config.loop and true or false) end
    if self.runtime.loop_start then self.runtime.loop_start(self.voice_id, start_sec) end
    if self.runtime.loop_end then self.runtime.loop_end(self.voice_id, start_sec + duration) end
    if self.runtime.position then self.runtime.position(self.voice_id, start_sec) end
    if self.runtime.fade_time then self.runtime.fade_time(self.voice_id, self.config.attack) end
    if self.runtime.rate_slew_time then self.runtime.rate_slew_time(self.voice_id, current_slew()) end
    if self.runtime.pan then self.runtime.pan(self.voice_id, clamp(self.config.pan or 0, -1, 1)) end
    if self.runtime.level then self.runtime.level(self.voice_id, self.config.level or 1) end
    if self.runtime.play then self.runtime.play(self.voice_id, false) end
  end

  function self:set_level(val)
    local v = val or 0
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    self.config.level = v
    if self.runtime.level then
      self.runtime.level(self.voice_id, v)
    end
  end

  function self:set_pan(val)
    local v = val or 0
    if v < -1 then v = -1 end
    if v > 1 then v = 1 end
    self.config.pan = v
    if self.runtime.pan then
      self.runtime.pan(self.voice_id, v)
    end
  end

  function self:set_portamento(val)
    self.portamento_override = val or 0
    self.config.rate_slew = self.portamento_override
    if self.runtime.rate_slew_time then
      self.runtime.rate_slew_time(self.voice_id, current_slew())
    end
  end

  function self:note_on(note, vel)
    if not self.available then
      return nil, self.last_error or "sample_missing"
    end

    if self.active_note ~= nil then
      stop_current(true)
    end

    if self.runtime.fade_time then
      self.runtime.fade_time(self.voice_id, self.config.attack)
    end
    if self.runtime.rate_slew_time then
      self.runtime.rate_slew_time(self.voice_id, current_slew())
    end
    if self.runtime.position then
      self.runtime.position(self.voice_id, self.config.start_sec)
    end
    if self.runtime.level then
      self.runtime.level(self.voice_id, clamp((vel or 1) * (self.config.level or 1), 0, 1))
    end
    if self.runtime.rate then
      self.runtime.rate(self.voice_id, midi_to_rate(note, self.config.root_note))
    end
    if self.runtime.play then
      self.runtime.play(self.voice_id, true)
    end
    self.active_note = note
    return true
  end

  function self:note_off(note)
    if self.active_note ~= note then
      return
    end
    if self.note_off_coro then
      self.clock.cancel(self.note_off_coro)
      self.note_off_coro = nil
    end
    self.active_notes[note] = nil
    stop_current(false)
  end

  function self:play_note(note, vel, dur)
    local ok, err = self:note_on(note, vel)
    if not ok then
      return nil, err
    end
    local coro_id
    coro_id = self.clock.run(function()
      self.clock.sync(dur)
      if self.note_off_coro == coro_id then
        self:note_off(note)
      end
    end)
    self.active_notes[note] = coro_id
    self.note_off_coro = coro_id
    return true
  end

  --- Record live audio from an ADC input into this voice's buffer region.
  --- On completion the voice is immediately playable (no file on disk).
  --- opts: { duration = seconds, input_channel = 1|2, clear = true }
  --- cb:   optional on_complete(true) callback.
  function self:grab(opts, cb)
    if not self.runtime.record then
      return nil, "record_unsupported"
    end
    self:all_notes_off()
    local marker = self.runtime.RECORDED_MARKER
        or (package.loaded["lib/voices/softcut_runtime"]
            and package.loaded["lib/voices/softcut_runtime"].RECORDED_MARKER)
        or "__recorded__"
    local ok, err = self.runtime.record(self.voice_id, opts, function(success)
      if success then
        local vs = self.runtime.voices and self.runtime.voices[self.voice_id]
        local start_sec = vs and vs.region_start or 0
        local duration = (opts and opts.duration)
            or (vs and (vs.region_end - vs.region_start))
            or 1
        self.config.sample_path = marker
        self.config.start_sec = start_sec
        self.config.end_sec = start_sec + duration
        self.available = true
        self.last_error = nil
        self:apply_config(self.config)
      end
      if cb then cb(success) end
    end)
    if not ok then
      return nil, err
    end
    return true
  end

  function self:all_notes_off()
    for note, coro in pairs(self.active_notes) do
      self.clock.cancel(coro)
      self.active_notes[note] = nil
    end
    self.note_off_coro = nil
    self.active_note = nil
    if self.runtime.level then self.runtime.level(self.voice_id, 0) end
    if self.runtime.play then self.runtime.play(self.voice_id, false) end
  end

  self:apply_config(self.config)
  return self
end

M.midi_to_rate = midi_to_rate

return M
