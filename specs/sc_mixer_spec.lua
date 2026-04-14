-- specs/sc_mixer_spec.lua
-- Tests for the SuperCollider mixer Lua wrapper (lib/voices/sc_mixer.lua).
--
-- Scope:
--   - OSC send: correct path + clamped/sanitized args for every setter group
--     (channel, aux, master).
--   - Meter enable/disable + incoming meter dispatch to shadow state + callbacks.
--   - State dump trigger + inbound echo → shadow state.
--   - snapshot / restore + sync_to_sc round-trip.
--
-- OSC is mocked at the global `osc.send` hook (same pattern as the other
-- SC voice specs). The module never creates listeners on its own — the
-- wrapper's handle_osc() is invoked directly in the tests.

package.path = package.path .. ";./?.lua"

-- Mock osc — capture sends for assertions.
local osc_sent = {}
rawset(_G, "osc", {
  send = function(target, path, args)
    table.insert(osc_sent, {target = target, path = path, args = args})
  end,
})

local sc_mixer = require("lib/voices/sc_mixer")

local function reset() osc_sent = {} end

local function last() return osc_sent[#osc_sent] end

local function count(path)
  local n = 0
  for _, m in ipairs(osc_sent) do
    if m.path == path then n = n + 1 end
  end
  return n
end

describe("sc_mixer", function()

  before_each(function() reset() end)

  describe("construction", function()
    it("uses sensible defaults for host/port and reply", function()
      local m = sc_mixer.new()
      assert.are.equal("127.0.0.1", m.host)
      assert.are.equal(57120, m.port)
      assert.are.equal("127.0.0.1", m.reply_host)
      assert.are.equal(7000, m.reply_port)
    end)

    it("honors explicit opts", function()
      local m = sc_mixer.new({
        host = "10.0.0.5", port = 57110,
        reply_host = "10.0.0.1", reply_port = 7400,
      })
      assert.are.equal("10.0.0.5", m.host)
      assert.are.equal(57110, m.port)
      assert.are.equal("10.0.0.1", m.reply_host)
      assert.are.equal(7400, m.reply_port)
    end)

    it("populates 4 channels with default shadow state", function()
      local m = sc_mixer.new()
      for n = 1, 4 do
        assert.is_not_nil(m.channels[n])
        assert.are.equal(0.8, m.channels[n].level)
        assert.are.equal(0, m.channels[n].pan)
        assert.are.equal(0, m.channels[n].mute)
        assert.are.equal(10000, m.channels[n].filter_freq)
      end
    end)

    it("populates aux and master defaults", function()
      local m = sc_mixer.new()
      assert.are.equal(0.8, m.aux.level)
      assert.are.equal(0.6, m.aux.reverb_mix)
      assert.are.equal(0.8, m.master.level)
      assert.are.equal(0.5, m.master.aux_return_level)
    end)
  end)

  describe("set_channel", function()
    it("sends correct path and clamped value, updates shadow", function()
      local m = sc_mixer.new()
      local v = m:set_channel(2, "level", 1.25)
      assert.are.equal(1.25, v)
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/mixer/channel/2/level", last().path)
      assert.are.same({1.25}, last().args)
      assert.are.equal(1.25, m.channels[2].level)
    end)

    it("sends to the configured target", function()
      local m = sc_mixer.new({host = "10.0.0.5", port = 57110})
      m:set_channel(1, "pan", 0.3)
      assert.are.same({"10.0.0.5", 57110}, last().target)
    end)

    it("clamps level above range (0..2)", function()
      local m = sc_mixer.new()
      local v = m:set_channel(1, "level", 5.0)
      assert.are.equal(2, v)
      assert.are.same({2}, last().args)
      assert.are.equal(2, m.channels[1].level)
    end)

    it("clamps pan below range (-1..1)", function()
      local m = sc_mixer.new()
      local v = m:set_channel(1, "pan", -5)
      assert.are.equal(-1, v)
      assert.are.same({-1}, last().args)
    end)

    it("rounds mute (int kind) and clamps to 0/1", function()
      local m = sc_mixer.new()
      assert.are.equal(1, m:set_channel(1, "mute", 0.9))
      assert.are.equal(1, last().args[1])
      assert.are.equal(0, m:set_channel(1, "mute", 0.1))
      assert.are.equal(1, m:set_channel(1, "mute", 7))
    end)

    it("rounds filter_type (int kind)", function()
      local m = sc_mixer.new()
      assert.are.equal(2, m:set_channel(1, "filter_type", 2.4))
      assert.are.equal(2, m:set_channel(1, "filter_type", 99))
      assert.are.equal(0, m:set_channel(1, "filter_type", -3))
    end)

    it("clamps filter_freq to 20..18000", function()
      local m = sc_mixer.new()
      assert.are.equal(20, m:set_channel(1, "filter_freq", 1))
      assert.are.equal(18000, m:set_channel(1, "filter_freq", 30000))
    end)

    it("clamps delay_feedback ceiling (0..0.95)", function()
      local m = sc_mixer.new()
      assert.are.equal(0.95, m:set_channel(3, "delay_feedback", 10))
    end)

    it("clamps comp_ratio floor (1..20)", function()
      local m = sc_mixer.new()
      assert.are.equal(1, m:set_channel(1, "comp_ratio", 0.2))
      assert.are.equal(20, m:set_channel(1, "comp_ratio", 50))
    end)

    it("returns nil for unknown param and does not send", function()
      local m = sc_mixer.new()
      local v = m:set_channel(1, "bogus", 0.5)
      assert.is_nil(v)
      assert.are.equal(0, #osc_sent)
      assert.is_nil(m.channels[1].bogus)
    end)

    it("returns nil for out-of-range channel index", function()
      local m = sc_mixer.new()
      assert.is_nil(m:set_channel(0, "level", 0.5))
      assert.is_nil(m:set_channel(5, "level", 0.5))
      assert.are.equal(0, #osc_sent)
    end)

    it("uses default when value is nil / non-numeric", function()
      local m = sc_mixer.new()
      local v = m:set_channel(1, "level", "nope")
      assert.are.equal(0.8, v)  -- level default
      assert.are.same({0.8}, last().args)
    end)
  end)

  describe("set_aux", function()
    it("sends correct path and clamped value", function()
      local m = sc_mixer.new()
      local v = m:set_aux("reverb_mix", 0.75)
      assert.are.equal(0.75, v)
      assert.are.equal("/rekriate/mixer/aux/reverb_mix", last().path)
      assert.are.same({0.75}, last().args)
      assert.are.equal(0.75, m.aux.reverb_mix)
    end)

    it("clamps level to 0..2", function()
      local m = sc_mixer.new()
      assert.are.equal(2, m:set_aux("level", 10))
      assert.are.equal(0, m:set_aux("level", -1))
    end)

    it("clamps delay_time to [0.001, 2.0]", function()
      local m = sc_mixer.new()
      assert.are.equal(0.001, m:set_aux("delay_time", 0))
      assert.are.equal(2.0, m:set_aux("delay_time", 5))
    end)

    it("returns nil for unknown aux param", function()
      local m = sc_mixer.new()
      assert.is_nil(m:set_aux("bogus", 1))
      assert.are.equal(0, #osc_sent)
    end)
  end)

  describe("set_master", function()
    it("sends correct path and clamped value for level", function()
      local m = sc_mixer.new()
      local v = m:set_master("level", 1.2)
      assert.are.equal(1.2, v)
      assert.are.equal("/rekriate/mixer/master/level", last().path)
      assert.are.same({1.2}, last().args)
    end)

    it("clamps aux_return_level to 0..2", function()
      local m = sc_mixer.new()
      assert.are.equal(2, m:set_master("aux_return_level", 99))
      assert.are.equal(0, m:set_master("aux_return_level", -0.5))
    end)

    it("returns nil for unknown master param", function()
      local m = sc_mixer.new()
      assert.is_nil(m:set_master("bogus", 1))
      assert.are.equal(0, #osc_sent)
    end)
  end)

  describe("target reassignment", function()
    it("set_target changes where subsequent messages go", function()
      local m = sc_mixer.new()
      m:set_target("10.0.0.7", 57200)
      m:set_channel(1, "level", 0.5)
      assert.are.same({"10.0.0.7", 57200}, last().target)
    end)

    it("set_reply updates meter target used by enable_meters", function()
      local m = sc_mixer.new()
      m:set_reply("192.168.1.9", 9000)
      m:enable_meters()
      assert.are.equal("/rekriate/mixer/meter/target", last().path)
      assert.are.same({"192.168.1.9", 9000}, last().args)
    end)
  end)

  describe("meters", function()
    it("enable_meters sends target with reply host/port", function()
      local m = sc_mixer.new({reply_host = "10.0.0.3", reply_port = 7400})
      m:enable_meters()
      assert.are.equal("/rekriate/mixer/meter/target", last().path)
      assert.are.same({"10.0.0.3", 7400}, last().args)
      assert.is_true(m.meter_enabled)
    end)

    it("disable_meters sends /meter/off", function()
      local m = sc_mixer.new()
      m:enable_meters()
      m:disable_meters()
      assert.are.equal("/rekriate/mixer/meter/off", last().path)
      assert.are.same({}, last().args)
      assert.is_false(m.meter_enabled)
    end)

    it("handle_osc consumes /meter/channel/{n} and records peaks", function()
      local m = sc_mixer.new()
      local handled = m:handle_osc(
        "/rekriate/mixer/meter/channel/2", {0.4, 0.6})
      assert.is_true(handled)
      assert.are.equal(0.4, m.meter.channels[2].l)
      assert.are.equal(0.6, m.meter.channels[2].r)
    end)

    it("handle_osc consumes /meter/aux and /meter/master", function()
      local m = sc_mixer.new()
      m:handle_osc("/rekriate/mixer/meter/aux", {0.1, 0.2})
      m:handle_osc("/rekriate/mixer/meter/master", {0.3, 0.4})
      assert.are.equal(0.1, m.meter.aux.l)
      assert.are.equal(0.2, m.meter.aux.r)
      assert.are.equal(0.3, m.meter.master.l)
      assert.are.equal(0.4, m.meter.master.r)
    end)

    it("fires on_meter callbacks with (kind, idx, l, r)", function()
      local m = sc_mixer.new()
      local seen = {}
      m:on_meter(function(kind, idx, l, r)
        table.insert(seen, {kind = kind, idx = idx, l = l, r = r})
      end)
      m:handle_osc("/rekriate/mixer/meter/channel/3", {0.5, 0.7})
      m:handle_osc("/rekriate/mixer/meter/aux", {0.1, 0.2})
      m:handle_osc("/rekriate/mixer/meter/master", {0.3, 0.4})
      assert.are.equal(3, #seen)
      assert.are.same({kind = "channel", idx = 3, l = 0.5, r = 0.7}, seen[1])
      assert.are.same({kind = "aux", idx = nil, l = 0.1, r = 0.2}, seen[2])
      assert.are.same({kind = "master", idx = nil, l = 0.3, r = 0.4}, seen[3])
    end)

    it("ignores meters for out-of-range channel ids", function()
      local m = sc_mixer.new()
      local handled = m:handle_osc(
        "/rekriate/mixer/meter/channel/9", {0.5, 0.5})
      -- We still mark it handled (right namespace) but do not explode.
      assert.is_true(handled)
      -- No listener fires for unknown channel.
      local seen = 0
      m:on_meter(function() seen = seen + 1 end)
      m:handle_osc("/rekriate/mixer/meter/channel/9", {0.5, 0.5})
      assert.are.equal(0, seen)
    end)
  end)

  describe("handle_osc", function()
    it("returns false for paths outside the mixer namespace", function()
      local m = sc_mixer.new()
      assert.is_false(m:handle_osc("/rekriate/synth/1/note_on", {60, 1}))
      assert.is_false(m:handle_osc("/something/else", {}))
    end)

    it("absorbs channel param echoes into shadow state", function()
      local m = sc_mixer.new()
      local handled = m:handle_osc(
        "/rekriate/mixer/channel/3/level", {0.55})
      assert.is_true(handled)
      assert.are.equal(0.55, m.channels[3].level)
    end)

    it("clamps values arriving via echo", function()
      local m = sc_mixer.new()
      m:handle_osc("/rekriate/mixer/channel/1/level", {10})
      assert.are.equal(2, m.channels[1].level)
    end)

    it("absorbs aux and master echoes", function()
      local m = sc_mixer.new()
      m:handle_osc("/rekriate/mixer/aux/reverb_mix", {0.33})
      m:handle_osc("/rekriate/mixer/master/level", {1.1})
      assert.are.equal(0.33, m.aux.reverb_mix)
      assert.are.equal(1.1, m.master.level)
    end)

    it("tolerates non-string path", function()
      local m = sc_mixer.new()
      assert.is_false(m:handle_osc(nil, {}))
      assert.is_false(m:handle_osc(42, {}))
    end)

    it("marks unknown mixer sub-paths as unhandled", function()
      local m = sc_mixer.new()
      assert.is_false(m:handle_osc("/rekriate/mixer/nonsense/1", {1}))
    end)
  end)

  describe("dump_state and sync_to_sc", function()
    it("dump_state fires a single /state/dump message", function()
      local m = sc_mixer.new()
      m:dump_state()
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/mixer/state/dump", last().path)
      assert.are.same({}, last().args)
    end)

    it("sync_to_sc pushes every shadow param", function()
      local m = sc_mixer.new()
      m:sync_to_sc()
      -- 17 channel params × 4 channels + 7 aux + 2 master = 77 msgs.
      local chan_total = 0
      for k in pairs(sc_mixer.CHANNEL_PARAMS) do
        chan_total = chan_total + 1
        -- Pin channel 1 sanity check.
        assert.are.equal(1, count("/rekriate/mixer/channel/1/" .. k))
      end
      local expected = chan_total * 4
      for k in pairs(sc_mixer.AUX_PARAMS) do
        expected = expected + 1
        assert.are.equal(1, count("/rekriate/mixer/aux/" .. k))
      end
      for k in pairs(sc_mixer.MASTER_PARAMS) do
        expected = expected + 1
        assert.are.equal(1, count("/rekriate/mixer/master/" .. k))
      end
      assert.are.equal(expected, #osc_sent)
    end)
  end)

  describe("snapshot / restore", function()
    it("snapshot captures all sections", function()
      local m = sc_mixer.new()
      m:set_channel(2, "level", 1.1)
      m:set_aux("delay_mix", 0.55)
      m:set_master("level", 1.3)
      local snap = m:snapshot()
      assert.are.equal(1.1, snap.channels[2].level)
      assert.are.equal(0.55, snap.aux.delay_mix)
      assert.are.equal(1.3, snap.master.level)
      -- Snapshot is a copy — mutating it must not affect live state.
      snap.channels[2].level = 0
      assert.are.equal(1.1, m.channels[2].level)
    end)

    it("restore rehydrates shadow without sending OSC", function()
      local m = sc_mixer.new()
      reset()
      m:restore({
        channels = {[1] = {level = 0.4, pan = 0.5}},
        aux = {reverb_mix = 0.9},
        master = {level = 0.2},
      })
      assert.are.equal(0, #osc_sent)
      assert.are.equal(0.4, m.channels[1].level)
      assert.are.equal(0.5, m.channels[1].pan)
      assert.are.equal(0.9, m.aux.reverb_mix)
      assert.are.equal(0.2, m.master.level)
    end)

    it("restore clamps out-of-range values from external snapshots", function()
      local m = sc_mixer.new()
      m:restore({channels = {[1] = {level = 99}}, aux = {level = -5}})
      assert.are.equal(2, m.channels[1].level)
      assert.are.equal(0, m.aux.level)
    end)

    it("restore ignores unknown keys", function()
      local m = sc_mixer.new()
      m:restore({channels = {[1] = {mystery = 42}}})
      assert.is_nil(m.channels[1].mystery)
    end)

    it("restore tolerates nil / empty snapshots", function()
      local m = sc_mixer.new()
      assert.has_no.errors(function() m:restore(nil) end)
      assert.has_no.errors(function() m:restore({}) end)
      -- Defaults untouched.
      assert.are.equal(0.8, m.channels[1].level)
    end)

    it("snapshot → restore round-trips on a fresh mixer", function()
      local a = sc_mixer.new()
      a:set_channel(1, "level", 1.7)
      a:set_channel(3, "filter_type", 2)
      a:set_aux("delay_time", 0.5)
      a:set_master("aux_return_level", 0.75)
      local snap = a:snapshot()

      local b = sc_mixer.new()
      b:restore(snap)
      assert.are.equal(1.7, b.channels[1].level)
      assert.are.equal(2, b.channels[3].filter_type)
      assert.are.equal(0.5, b.aux.delay_time)
      assert.are.equal(0.75, b.master.aux_return_level)
    end)
  end)

  describe("getters", function()
    it("get_channel / get_aux / get_master return shadow values", function()
      local m = sc_mixer.new()
      m:set_channel(2, "pan", 0.25)
      m:set_aux("level", 1.5)
      m:set_master("level", 0.9)
      assert.are.equal(0.25, m:get_channel(2, "pan"))
      assert.are.equal(1.5, m:get_aux("level"))
      assert.are.equal(0.9, m:get_master("level"))
    end)

    it("get_channel returns nil for bad channel index", function()
      local m = sc_mixer.new()
      assert.is_nil(m:get_channel(99, "level"))
    end)
  end)

end)
