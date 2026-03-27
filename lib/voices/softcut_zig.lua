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
  return merged
end

function M.new(voice_id, runtime, config)
  local self = {
    voice_id = voice_id,
    runtime = runtime or {},
    config = merge_config(config),
    active_notes = {},
    active_note = nil,
    portamento_override = nil,
  }

  local clock = rawget(_G, "clock") or {
    run = function(fn) return fn() end,
    cancel = function() end,
    sync = function() end,
  }
  self.clock = clock

  function self:apply_config(cfg)
    self.config = merge_config(cfg)
    local start_sec = self.config.start_sec or 0
    local duration = (self.config.end_sec or 0) - start_sec
    if duration <= 0 then duration = 0.001 end

    if self.runtime.buffer_read_mono and self.config.sample_path then
      self.runtime.buffer_read_mono(self.config.sample_path, start_sec, duration)
    end
    if self.runtime.enable then self.runtime.enable(self.voice_id, true) end
    if self.runtime.loop then self.runtime.loop(self.voice_id, self.config.loop) end
    if self.runtime.loop_start then self.runtime.loop_start(self.voice_id, start_sec) end
    if self.runtime.loop_end then self.runtime.loop_end(self.voice_id, start_sec + duration) end
    if self.runtime.fade_time then self.runtime.fade_time(self.voice_id, self.config.release) end
    local slew = self.portamento_override
    if not slew or slew == 0 then slew = self.config.rate_slew or 0 end
    if self.runtime.rate_slew_time then self.runtime.rate_slew_time(self.voice_id, slew) end
    if self.runtime.pan then self.runtime.pan(self.voice_id, clamp(self.config.pan or 0, -1, 1)) end
  end

  function self:set_portamento(val)
    self.portamento_override = val
    local slew = val
    if not slew or slew == 0 then slew = self.config.rate_slew or 0 end
    if self.runtime.rate_slew_time then
      self.runtime.rate_slew_time(self.voice_id, slew)
    end
  end

  local function apply_rate_slew(self)
    local slew = self.portamento_override
    if not slew or slew == 0 then slew = self.config.rate_slew or 0 end
    if self.runtime.rate_slew_time then
      self.runtime.rate_slew_time(self.voice_id, slew)
    end
  end

  function self:note_on(note, vel)
    apply_rate_slew(self)
    if self.runtime.position then
      self.runtime.position(self.voice_id, self.config.start_sec)
    end
    if self.runtime.level then
      self.runtime.level(self.voice_id, (vel or 1) * (self.config.level or 1))
    end
    if self.runtime.rate then
      self.runtime.rate(self.voice_id, midi_to_rate(note, self.config.root_note))
    end
    if self.runtime.play then
      self.runtime.play(self.voice_id, true)
    end
    self.active_note = note
  end

  function self:note_off(note)
    if self.active_note ~= note then
      return
    end
    local coro = self.active_notes[note]
    if coro then
      self.clock.cancel(coro)
      self.active_notes[note] = nil
    end
    self.active_note = nil
    if self.runtime.level_slew_time then
      self.runtime.level_slew_time(self.voice_id, self.config.release)
    end
    if self.runtime.play then
      self.runtime.play(self.voice_id, false)
    end
  end

  function self:play_note(note, vel, dur)
    self:note_on(note, vel)
    local coro_id = self.clock.run(function()
      self.clock.sync(dur)
      self:note_off(note)
    end)
    self.active_notes[note] = coro_id
    return true
  end

  function self:all_notes_off()
    for note, coro in pairs(self.active_notes) do
      self.clock.cancel(coro)
      self.active_notes[note] = nil
    end
    self.active_note = nil
    if self.runtime.level then self.runtime.level(self.voice_id, 0) end
    if self.runtime.play then self.runtime.play(self.voice_id, false) end
  end

  self:apply_config(self.config)
  return self
end

M.midi_to_rate = midi_to_rate

return M
