-- specs/sc_bridge_spec.lua
-- Tests for the Lua side of the SuperCollider ↔ re.kriate OSC handshake.

package.path = package.path .. ";./?.lua"

-- Minimal osc mock: captures sends for assertion.
local osc_sent
rawset(_G, "osc", {
  send = function(target, path, args)
    table.insert(osc_sent, { target = target, path = path, args = args })
  end,
})

-- clock mock compatible with the coroutine-based helpers in sc_bridge.
local clock_runs, clock_time
rawset(_G, "clock", {
  get_beats = function() return clock_time end,
  run = function(fn)
    table.insert(clock_runs, fn)
    return #clock_runs
  end,
  sleep = function(_) end,
  sync = function(_) end,
})

local sc_bridge = require("lib/sc_bridge")

local function reset()
  osc_sent = {}
  clock_runs = {}
  clock_time = 0
end

local function new_bridge(overrides)
  local opts = {
    host = "127.0.0.1", port = 57120,
    reply_host = "127.0.0.1", reply_port = 7000,
    timeout = 1.0,
  }
  for k, v in pairs(overrides or {}) do opts[k] = v end
  return sc_bridge.new(opts)
end

describe("sc_bridge", function()
  before_each(reset)

  describe("construction", function()
    it("defaults to disconnected state with empty features", function()
      local br = new_bridge()
      assert.are.equal("disconnected", br.state)
      assert.is_nil(br.version)
      assert.are.same({}, br.features)
    end)

    it("stores host/port/reply_host/reply_port/timeout", function()
      local br = new_bridge({
        host = "10.0.0.1", port = 57121,
        reply_host = "10.0.0.2", reply_port = 8000,
        timeout = 2.5,
      })
      assert.are.equal("10.0.0.1", br.host)
      assert.are.equal(57121, br.port)
      assert.are.equal("10.0.0.2", br.reply_host)
      assert.are.equal(8000, br.reply_port)
      assert.are.equal(2.5, br.timeout)
    end)
  end)

  describe("ping", function()
    it("sends /rekriate/ping with reply host/port + nonce", function()
      local br = new_bridge()
      br:ping()
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/ping", osc_sent[1].path)
      assert.are.same({"127.0.0.1", 57120}, osc_sent[1].target)
      assert.are.equal("127.0.0.1", osc_sent[1].args[1])
      assert.are.equal(7000, osc_sent[1].args[2])
      assert.are.equal(1, osc_sent[1].args[3])
    end)

    it("transitions disconnected → pinging", function()
      local br = new_bridge()
      br:ping()
      assert.are.equal("pinging", br.state)
    end)

    it("increments nonce on each ping", function()
      local br = new_bridge()
      br:ping()
      br:ping()
      br:ping()
      assert.are.equal(1, osc_sent[1].args[3])
      assert.are.equal(2, osc_sent[2].args[3])
      assert.are.equal(3, osc_sent[3].args[3])
    end)
  end)

  describe("handle_osc", function()
    it("returns false and ignores non-pong paths", function()
      local br = new_bridge()
      local handled = br:handle_osc("/some/other/path", {1, 2, 3})
      assert.is_false(handled)
      assert.are.equal("disconnected", br.state)
    end)

    it("transitions to connected on /rekriate/pong", function()
      local br = new_bridge()
      br:ping()
      local handled = br:handle_osc("/rekriate/pong", {"v1", "voice", "mixer"})
      assert.is_true(handled)
      assert.are.equal("connected", br.state)
      assert.are.equal("v1", br.version)
      assert.are.same({"voice", "mixer"}, br.features)
    end)

    it("fires pong listeners", function()
      local br = new_bridge()
      local seen
      br:on_pong(function(b) seen = b.version end)
      br:ping()
      br:handle_osc("/rekriate/pong", {"v2", "sc_synth"})
      assert.are.equal("v2", seen)
    end)

    it("merges features across pongs within the same ping window", function()
      local br = new_bridge()
      br:ping()
      br:handle_osc("/rekriate/pong", {"voice-1", "voice", "mixer"})
      br:handle_osc("/rekriate/pong", {"synth-1", "sc_synth", "sub", "fm"})
      br:handle_osc("/rekriate/pong", {"drums-1", "sc_drums"})
      assert.are.equal("connected", br.state)
      -- Features accumulate in arrival order, deduped.
      assert.are.same(
        {"voice", "mixer", "sc_synth", "sub", "fm", "sc_drums"},
        br.features
      )
    end)

    it("resets feature set on a new ping window", function()
      local br = new_bridge()
      br:ping()
      br:handle_osc("/rekriate/pong", {"v1", "voice"})
      assert.are.same({"voice"}, br.features)

      br:ping()  -- bumps nonce → new window
      br:handle_osc("/rekriate/pong", {"v2", "sc_synth"})
      assert.are.same({"sc_synth"}, br.features)
    end)

    it("dedupes repeated features within a window", function()
      local br = new_bridge()
      br:ping()
      br:handle_osc("/rekriate/pong", {"v1", "voice", "mixer"})
      br:handle_osc("/rekriate/pong", {"v1", "voice", "mixer"})
      assert.are.same({"voice", "mixer"}, br.features)
    end)

    it("accepts a pong with just a version and no features", function()
      local br = new_bridge()
      br:handle_osc("/rekriate/pong", {"v1"})
      assert.are.equal("v1", br.version)
      assert.are.same({}, br.features)
    end)
  end)

  describe("tick / timeout", function()
    it("marks pinging as disconnected after timeout", function()
      local br = new_bridge({ timeout = 1.0 })
      clock_time = 10
      br:ping()
      clock_time = 10.5  -- within window
      br:tick()
      assert.are.equal("pinging", br.state)
      clock_time = 11.5  -- outside window
      br:tick()
      assert.are.equal("disconnected", br.state)
    end)

    it("does not clobber connected state on tick", function()
      local br = new_bridge()
      br:ping()
      br:handle_osc("/rekriate/pong", {"v1", "voice"})
      clock_time = 100
      br:tick()
      assert.are.equal("connected", br.state)
    end)
  end)

  describe("set_target", function()
    it("updates host/port and invalidates connection", function()
      local br = new_bridge()
      br:ping()
      br:handle_osc("/rekriate/pong", {"v1", "voice"})
      assert.are.equal("connected", br.state)

      br:set_target("10.0.0.9", 55555)
      assert.are.equal("10.0.0.9", br.host)
      assert.are.equal(55555, br.port)
      assert.are.equal("disconnected", br.state)
      assert.is_nil(br.version)
      assert.are.same({}, br.features)
    end)
  end)

  describe("status_string", function()
    it("reports offline when never pinged", function()
      local br = new_bridge()
      assert.is_truthy(br:status_string():match("offline"))
    end)

    it("reports pinging after ping but before pong", function()
      local br = new_bridge()
      br:ping()
      assert.is_truthy(br:status_string():match("pinging"))
    end)

    it("reports ok with version + features when connected", function()
      local br = new_bridge()
      br:ping()
      br:handle_osc("/rekriate/pong", {"v1", "voice", "mixer"})
      local s = br:status_string()
      assert.is_truthy(s:match("ok"))
      assert.is_truthy(s:match("v1"))
      assert.is_truthy(s:match("voice"))
      assert.is_truthy(s:match("mixer"))
    end)
  end)

  describe("is_connected", function()
    it("matches the state transitions", function()
      local br = new_bridge()
      assert.is_false(br:is_connected())
      br:ping()
      assert.is_false(br:is_connected())
      br:handle_osc("/rekriate/pong", {"v1"})
      assert.is_true(br:is_connected())
    end)
  end)
end)
