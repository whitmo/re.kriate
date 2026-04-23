-- lib/clock_sync.lua
-- MIDI clock sync state and transport logic (spec 010).
--
-- State lives on ctx.clock_sync; this module exposes pure functions that
-- manipulate that state plus a small set of side-effecting helpers that
-- send raw MIDI clock/transport bytes through a stored output device.
--
-- Platform wiring (params, midi.event callbacks, sequencer start/stop) is
-- handled by the caller (lib/app.lua). This module only knows about:
--   - decoding incoming MIDI bytes into clock/transport events
--   - tracking transport state (stopped/playing/paused)
--   - estimating BPM from a rolling window of pulse intervals
--   - formatting outgoing MIDI clock/transport bytes

local M = {}

-- MIDI real-time message constants
M.PPQ           = 24    -- MIDI clock standard: 24 pulses per quarter note
M.MIDI_CLOCK    = 0xF8  -- timing clock
M.MIDI_START    = 0xFA  -- transport start
M.MIDI_CONTINUE = 0xFB  -- transport continue
M.MIDI_STOP     = 0xFC  -- transport stop

-- Valid clock source values
M.SOURCE_INTERNAL = "internal"
M.SOURCE_EXT_MIDI = "ext_midi"

-- Transport states
M.TRANSPORT_STOPPED = "stopped"
M.TRANSPORT_PLAYING = "playing"
M.TRANSPORT_PAUSED  = "paused"

-- Rolling window length (in pulses) for BPM estimation. 24 pulses = one beat,
-- so this gives a ~1-beat smoothing which tolerates jitter while still tracking
-- tempo changes within a beat.
M.BPM_WINDOW = 24

--- Create a new clock_sync state table.
--- @param opts table|nil  Optional fields: source, output_enabled,
---                        midi_in_port, midi_out_port, midi_in_dev, midi_out_dev
--- @return table  clock_sync state to be stored on ctx.clock_sync
function M.new(opts)
  opts = opts or {}
  return {
    source          = opts.source or M.SOURCE_INTERNAL,
    output_enabled  = opts.output_enabled and true or false,
    transport       = M.TRANSPORT_STOPPED,
    external_bpm    = nil,
    pulse_count     = 0,
    last_pulse_time = nil,
    pulse_intervals = {},
    midi_in_port    = opts.midi_in_port or 1,
    midi_out_port   = opts.midi_out_port or 1,
    midi_in_dev     = opts.midi_in_dev,
    midi_out_dev    = opts.midi_out_dev,
  }
end

--- Change the clock source. Returns true if the source actually changed.
--- Resets pulse-derived state so stale BPM readings do not leak across a
--- source switch.
--- @param cs table  clock_sync state
--- @param source string  "internal" | "ext_midi"
--- @return boolean
function M.set_source(cs, source)
  if source ~= M.SOURCE_INTERNAL and source ~= M.SOURCE_EXT_MIDI then
    error("clock_sync: invalid source " .. tostring(source))
  end
  if cs.source == source then return false end
  cs.source = source
  cs.external_bpm = nil
  cs.pulse_count = 0
  cs.last_pulse_time = nil
  cs.pulse_intervals = {}
  return true
end

--- Enable or disable MIDI clock output.
function M.set_output_enabled(cs, enabled)
  cs.output_enabled = enabled and true or false
end

--- Detect whether current settings would create a feedback loop:
--- clock input and output are both active on the same MIDI port (FR-012).
function M.has_feedback_loop(cs)
  return cs.source == M.SOURCE_EXT_MIDI
    and cs.output_enabled
    and cs.midi_in_port == cs.midi_out_port
end

--- Decode a MIDI status byte into a clock/transport event name, or nil.
--- @return string|nil  "pulse" | "start" | "continue" | "stop" | nil
function M.decode(byte)
  if byte == M.MIDI_CLOCK    then return "pulse"    end
  if byte == M.MIDI_START    then return "start"    end
  if byte == M.MIDI_CONTINUE then return "continue" end
  if byte == M.MIDI_STOP     then return "stop"     end
  return nil
end

--- Record an incoming MIDI clock pulse. Updates pulse_count, pulse_intervals,
--- last_pulse_time, and external_bpm.
--- No-op when the source is not external MIDI.
--- @param cs table     clock_sync state
--- @param now number|nil  Timestamp in seconds (e.g. os.clock()). Pass nil to
---                        skip BPM estimation when no clock is available.
function M.on_pulse(cs, now)
  if cs.source ~= M.SOURCE_EXT_MIDI then return end
  cs.pulse_count = cs.pulse_count + 1
  if now and cs.last_pulse_time then
    local dt = now - cs.last_pulse_time
    if dt > 0 then
      local intervals = cs.pulse_intervals
      intervals[#intervals + 1] = dt
      if #intervals > M.BPM_WINDOW then
        table.remove(intervals, 1)
      end
      local sum = 0
      for _, v in ipairs(intervals) do sum = sum + v end
      local avg_dt = sum / #intervals
      if avg_dt > 0 then
        -- PPQ pulses per beat; BPM = beats per minute.
        cs.external_bpm = 60 / (avg_dt * M.PPQ)
      end
    end
  end
  cs.last_pulse_time = now
end

--- Handle incoming MIDI Start (0xFA). Resets pulse counters and marks the
--- transport as playing.
function M.on_start(cs)
  cs.transport = M.TRANSPORT_PLAYING
  cs.pulse_count = 0
  cs.pulse_intervals = {}
  cs.last_pulse_time = nil
end

--- Handle incoming MIDI Continue (0xFB). Resumes playback from the current
--- position. If the sequencer has never been started, behaves like Start
--- (edge case from the spec).
--- @return string  "start" or "continue" — the effective action taken.
function M.on_continue(cs)
  if cs.transport == M.TRANSPORT_STOPPED and cs.pulse_count == 0 then
    M.on_start(cs)
    return "start"
  end
  cs.transport = M.TRANSPORT_PLAYING
  return "continue"
end

--- Handle incoming MIDI Stop (0xFC). Moves transport to paused so a subsequent
--- Continue can resume from the current position.
function M.on_stop(cs)
  cs.transport = M.TRANSPORT_PAUSED
end

--- Process a block of raw MIDI bytes (as delivered by midi.event).
--- Updates cs and returns an ordered list of decoded event names.
--- Event names:  "pulse", "start", "continue" (or "start" if never started),
---               "stop".
--- @param cs   table
--- @param data table  raw MIDI byte array
--- @param now  number|nil  timestamp passed through to on_pulse
--- @return table  list of event names in decode order
function M.process_midi(cs, data, now)
  local events = {}
  if type(data) ~= "table" then return events end
  for _, byte in ipairs(data) do
    local ev = M.decode(byte)
    if ev == "pulse" then
      M.on_pulse(cs, now)
      events[#events + 1] = "pulse"
    elseif ev == "start" then
      M.on_start(cs)
      events[#events + 1] = "start"
    elseif ev == "continue" then
      events[#events + 1] = M.on_continue(cs)
    elseif ev == "stop" then
      M.on_stop(cs)
      events[#events + 1] = "stop"
    end
  end
  return events
end

--- Send a single raw MIDI status byte through the output device, iff clock
--- output is enabled and a device is available.
local function send_byte(cs, byte)
  if not cs.output_enabled then return false end
  local dev = cs.midi_out_dev
  if not dev then return false end
  if dev.send then
    dev:send({byte})
    return true
  end
  return false
end

--- Send MIDI Start (0xFA) when clock output is enabled.
function M.send_start(cs)
  return send_byte(cs, M.MIDI_START)
end

--- Send MIDI Stop (0xFC) when clock output is enabled.
function M.send_stop(cs)
  return send_byte(cs, M.MIDI_STOP)
end

--- Send a single MIDI Clock pulse (0xF8) when clock output is enabled.
function M.send_pulse(cs)
  return send_byte(cs, M.MIDI_CLOCK)
end

--- Human-readable label for the current clock source (for display).
function M.source_label(cs)
  if cs.source == M.SOURCE_EXT_MIDI then return "ext MIDI" end
  return "internal"
end

--- Display string: "<source> <bpm>" or "<source> no clock" when slaved and no
--- clock has been received recently (FR-010).
--- @param cs table
--- @param internal_bpm number  BPM from internal clock (e.g. params:get("clock_tempo"))
--- @param now number|nil  current timestamp, used to detect stale external clock
--- @param stale_threshold number|nil  seconds without a pulse before "no clock"
function M.display(cs, internal_bpm, now, stale_threshold)
  stale_threshold = stale_threshold or 1.0
  if cs.source == M.SOURCE_EXT_MIDI then
    if cs.external_bpm and cs.last_pulse_time and now
        and (now - cs.last_pulse_time) <= stale_threshold then
      return string.format("ext MIDI %d", math.floor(cs.external_bpm + 0.5))
    end
    return "ext MIDI no clock"
  end
  if internal_bpm then
    return string.format("internal %d", math.floor(internal_bpm + 0.5))
  end
  return "internal"
end

return M
