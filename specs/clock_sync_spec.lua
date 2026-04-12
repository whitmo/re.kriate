-- specs/clock_sync_spec.lua
-- Tests for MIDI clock sync state and transport logic (spec 010).

package.path = package.path .. ";./?.lua"

local clock_sync = require("lib/clock_sync")

-- Test helper: an in-memory MIDI output device that captures sent byte arrays.
local function make_out_dev()
  local dev = {sent = {}}
  function dev:send(data)
    table.insert(self.sent, data)
  end
  return dev
end

describe("clock_sync", function()

  describe("new", function()
    it("defaults to internal source, output disabled, transport stopped", function()
      local cs = clock_sync.new()
      assert.are.equal(clock_sync.SOURCE_INTERNAL, cs.source)
      assert.is_false(cs.output_enabled)
      assert.are.equal(clock_sync.TRANSPORT_STOPPED, cs.transport)
      assert.is_nil(cs.external_bpm)
      assert.are.equal(0, cs.pulse_count)
    end)

    it("accepts initial options", function()
      local cs = clock_sync.new({
        source = clock_sync.SOURCE_EXT_MIDI,
        output_enabled = true,
        midi_in_port = 2,
        midi_out_port = 3,
      })
      assert.are.equal(clock_sync.SOURCE_EXT_MIDI, cs.source)
      assert.is_true(cs.output_enabled)
      assert.are.equal(2, cs.midi_in_port)
      assert.are.equal(3, cs.midi_out_port)
    end)
  end)

  describe("set_source", function()
    it("returns true on change, false on no-op", function()
      local cs = clock_sync.new()
      assert.is_true(clock_sync.set_source(cs, clock_sync.SOURCE_EXT_MIDI))
      assert.is_false(clock_sync.set_source(cs, clock_sync.SOURCE_EXT_MIDI))
      assert.is_true(clock_sync.set_source(cs, clock_sync.SOURCE_INTERNAL))
    end)

    it("resets pulse-derived state on change", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      clock_sync.on_pulse(cs, 0)
      clock_sync.on_pulse(cs, 0.020833)  -- ~120 BPM
      assert.is_not_nil(cs.external_bpm)
      assert.is_true(cs.pulse_count > 0)
      clock_sync.set_source(cs, clock_sync.SOURCE_INTERNAL)
      assert.is_nil(cs.external_bpm)
      assert.are.equal(0, cs.pulse_count)
      assert.are.equal(0, #cs.pulse_intervals)
    end)

    it("rejects invalid sources", function()
      local cs = clock_sync.new()
      assert.has_error(function() clock_sync.set_source(cs, "bogus") end)
    end)
  end)

  describe("decode", function()
    it("maps known status bytes", function()
      assert.are.equal("pulse",    clock_sync.decode(0xF8))
      assert.are.equal("start",    clock_sync.decode(0xFA))
      assert.are.equal("continue", clock_sync.decode(0xFB))
      assert.are.equal("stop",     clock_sync.decode(0xFC))
    end)

    it("returns nil for unknown bytes", function()
      assert.is_nil(clock_sync.decode(0x90))
      assert.is_nil(clock_sync.decode(0x00))
      assert.is_nil(clock_sync.decode(0xF9))
    end)
  end)

  describe("on_pulse (US1: external clock BPM derivation)", function()
    it("is a no-op when source is internal", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_INTERNAL})
      clock_sync.on_pulse(cs, 0)
      clock_sync.on_pulse(cs, 0.020833)
      assert.are.equal(0, cs.pulse_count)
      assert.is_nil(cs.external_bpm)
    end)

    it("derives ~120 BPM from 24 PPQ pulses at 20.833ms intervals", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      -- At 120 BPM: 120 beats/min = 2 beats/sec; 24 PPQ = 48 pulses/sec.
      -- Pulse interval = 1/48 = 0.020833... seconds.
      local t = 0
      local dt = 1 / 48
      for _ = 1, 48 do
        clock_sync.on_pulse(cs, t)
        t = t + dt
      end
      assert.is_not_nil(cs.external_bpm)
      assert.is_true(math.abs(cs.external_bpm - 120) < 0.5)
    end)

    it("follows tempo changes from 120 to 90 BPM (US1 acceptance 2)", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      local t = 0
      -- 2 bars at 120 BPM
      for _ = 1, 96 do
        clock_sync.on_pulse(cs, t)
        t = t + 1 / 48
      end
      -- now switch: 2 bars at 90 BPM (pulse interval = 1 / (90*24/60) ≈ 0.02778)
      local slow_dt = 60 / (90 * 24)
      for _ = 1, 96 do
        clock_sync.on_pulse(cs, t)
        t = t + slow_dt
      end
      assert.is_true(math.abs(cs.external_bpm - 90) < 1.0)
    end)

    it("keeps the rolling window bounded", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      local t = 0
      for _ = 1, 200 do
        clock_sync.on_pulse(cs, t)
        t = t + 1 / 48
      end
      assert.is_true(#cs.pulse_intervals <= clock_sync.BPM_WINDOW)
    end)
  end)

  describe("transport messages (US3)", function()
    it("on_start moves to playing and resets pulse state", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      clock_sync.on_pulse(cs, 0)
      clock_sync.on_pulse(cs, 1 / 48)
      clock_sync.on_start(cs)
      assert.are.equal(clock_sync.TRANSPORT_PLAYING, cs.transport)
      assert.are.equal(0, cs.pulse_count)
      assert.is_nil(cs.last_pulse_time)
    end)

    it("on_stop moves transport to paused", function()
      local cs = clock_sync.new()
      clock_sync.on_start(cs)
      clock_sync.on_stop(cs)
      assert.are.equal(clock_sync.TRANSPORT_PAUSED, cs.transport)
    end)

    it("on_continue returns to playing and preserves pulse state", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      clock_sync.on_start(cs)
      clock_sync.on_pulse(cs, 0)
      clock_sync.on_pulse(cs, 1 / 48)
      clock_sync.on_stop(cs)
      local pulses_before = cs.pulse_count
      local result = clock_sync.on_continue(cs)
      assert.are.equal("continue", result)
      assert.are.equal(clock_sync.TRANSPORT_PLAYING, cs.transport)
      assert.are.equal(pulses_before, cs.pulse_count)
    end)

    it("on_continue behaves like start when never started (edge case)", function()
      local cs = clock_sync.new()
      local result = clock_sync.on_continue(cs)
      assert.are.equal("start", result)
      assert.are.equal(clock_sync.TRANSPORT_PLAYING, cs.transport)
    end)
  end)

  describe("process_midi", function()
    it("decodes a mixed stream of status bytes", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      local events = clock_sync.process_midi(cs, {
        clock_sync.MIDI_START,
        clock_sync.MIDI_CLOCK,
        clock_sync.MIDI_CLOCK,
        clock_sync.MIDI_STOP,
      }, 0)
      assert.are.same({"start", "pulse", "pulse", "stop"}, events)
      assert.are.equal(clock_sync.TRANSPORT_PAUSED, cs.transport)
      assert.are.equal(2, cs.pulse_count)
    end)

    it("ignores non-realtime bytes (e.g. note_on)", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      local events = clock_sync.process_midi(cs, {0x90, 0x3C, 0x7F}, 0)
      assert.are.equal(0, #events)
    end)

    it("is safe for non-table input", function()
      local cs = clock_sync.new()
      local events = clock_sync.process_midi(cs, nil, 0)
      assert.are.same({}, events)
    end)
  end)

  describe("outgoing clock (US2)", function()
    it("send_start emits 0xFA only when output is enabled", function()
      local dev = make_out_dev()
      local cs = clock_sync.new({midi_out_dev = dev})
      assert.is_false(clock_sync.send_start(cs))
      assert.are.equal(0, #dev.sent)
      clock_sync.set_output_enabled(cs, true)
      assert.is_true(clock_sync.send_start(cs))
      assert.are.same({clock_sync.MIDI_START}, dev.sent[1])
    end)

    it("send_stop emits 0xFC", function()
      local dev = make_out_dev()
      local cs = clock_sync.new({midi_out_dev = dev, output_enabled = true})
      clock_sync.send_stop(cs)
      assert.are.same({clock_sync.MIDI_STOP}, dev.sent[1])
    end)

    it("send_pulse emits 0xF8 at 24 PPQ", function()
      local dev = make_out_dev()
      local cs = clock_sync.new({midi_out_dev = dev, output_enabled = true})
      for _ = 1, 24 do clock_sync.send_pulse(cs) end
      assert.are.equal(24, #dev.sent)
      for i = 1, 24 do
        assert.are.same({clock_sync.MIDI_CLOCK}, dev.sent[i])
      end
    end)

    it("send_* is a no-op without an output device", function()
      local cs = clock_sync.new({output_enabled = true})
      assert.is_false(clock_sync.send_pulse(cs))
      assert.is_false(clock_sync.send_start(cs))
      assert.is_false(clock_sync.send_stop(cs))
    end)
  end)

  describe("feedback loop detection (FR-012)", function()
    it("detects same-port input+output as a loop", function()
      local cs = clock_sync.new({
        source = clock_sync.SOURCE_EXT_MIDI,
        output_enabled = true,
        midi_in_port = 1,
        midi_out_port = 1,
      })
      assert.is_true(clock_sync.has_feedback_loop(cs))
    end)

    it("does not flag different ports", function()
      local cs = clock_sync.new({
        source = clock_sync.SOURCE_EXT_MIDI,
        output_enabled = true,
        midi_in_port = 1,
        midi_out_port = 2,
      })
      assert.is_false(clock_sync.has_feedback_loop(cs))
    end)

    it("does not flag internal source", function()
      local cs = clock_sync.new({
        source = clock_sync.SOURCE_INTERNAL,
        output_enabled = true,
        midi_in_port = 1,
        midi_out_port = 1,
      })
      assert.is_false(clock_sync.has_feedback_loop(cs))
    end)
  end)

  describe("display (FR-010)", function()
    it("shows internal BPM when source is internal", function()
      local cs = clock_sync.new()
      assert.are.equal("internal 120", clock_sync.display(cs, 120))
    end)

    it("shows external BPM when a recent pulse has been received", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      local t = 0
      for _ = 1, 48 do
        clock_sync.on_pulse(cs, t)
        t = t + 1 / 48
      end
      -- display with 'now' just past the last pulse: still fresh
      local shown = clock_sync.display(cs, 120, t)
      assert.is_true(shown:match("ext MIDI") ~= nil)
      assert.is_true(shown:match("120") ~= nil)
    end)

    it("shows 'no clock' when slaved and no recent pulses", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      assert.are.equal("ext MIDI no clock", clock_sync.display(cs, 120, 5))
    end)

    it("shows 'no clock' when last pulse is stale", function()
      local cs = clock_sync.new({source = clock_sync.SOURCE_EXT_MIDI})
      clock_sync.on_pulse(cs, 0)
      clock_sync.on_pulse(cs, 1 / 48)
      assert.are.equal("ext MIDI no clock", clock_sync.display(cs, 120, 10.0, 1.0))
    end)
  end)
end)
