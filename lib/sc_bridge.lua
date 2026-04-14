-- lib/sc_bridge.lua
-- Bidirectional OSC handshake between re.kriate (Lua) and SuperCollider (sclang).
--
-- The bridge keeps a small connection state machine so the UI/demos can tell
-- whether a SuperCollider instance is actually answering on the target port.
--
-- Protocol
-- --------
--   Lua → SC :  /rekriate/ping {reply_host, reply_port, [nonce]}
--   SC  → Lua:  /rekriate/pong {version, feature1, feature2, ...}
--
-- SC replies to the reply_host/reply_port supplied in the ping so the bridge
-- works across hosts (norns or a laptop on a LAN).
--
-- Usage
-- -----
--   local sc_bridge = require("lib/sc_bridge")
--   local bridge = sc_bridge.new({
--     host = "127.0.0.1", port = 57120,   -- SC (sclang) address
--     reply_host = "127.0.0.1", reply_port = 7000, -- where WE listen
--     timeout = 1.5,                       -- seconds before pinging marked offline
--   })
--   bridge:ping()
--   -- on incoming OSC message (from seamstress osc.event or norns osc.event):
--   bridge:handle_osc(path, args, from)
--
-- State values: "disconnected" | "pinging" | "connected"
--
-- The bridge only depends on three globals that both seamstress and norns
-- expose — `osc.send`, `clock.run`, `clock.sleep` (or `clock.sync`). It does
-- NOT install an osc.event handler itself; callers chain handle_osc into
-- whichever dispatcher they already own.

local M = {}

local DEFAULT_TIMEOUT = 1.5  -- seconds
local PING_PATH = "/rekriate/ping"
local PONG_PATH = "/rekriate/pong"

local function now()
  if clock and clock.get_beats then
    -- beats are fine as a monotonic-ish clock for timeout comparisons here;
    -- handshake cadence is coarse (seconds).
    return clock.get_beats()
  end
  return os.time()
end

--- Construct a new bridge.
--- @param opts table {host, port, reply_host?, reply_port?, timeout?}
function M.new(opts)
  opts = opts or {}
  local self = {
    host = opts.host or "127.0.0.1",
    port = opts.port or 57120,
    reply_host = opts.reply_host or "127.0.0.1",
    reply_port = opts.reply_port or 7000,
    timeout = opts.timeout or DEFAULT_TIMEOUT,
    state = "disconnected",
    version = nil,
    features = {},
    last_ping_at = nil,
    last_pong_at = nil,
    pong_listeners = {},  -- callbacks fired on pong
    nonce = 0,
  }

  --- Send a ping. Transitions to "pinging" (from disconnected) until a pong
  --- arrives or the timeout elapses.
  function self:ping()
    self.nonce = self.nonce + 1
    self.last_ping_at = now()
    self._pong_nonce = nil  -- reset per-ping pong merge window
    if self.state ~= "connected" then
      self.state = "pinging"
    end
    osc.send(
      {self.host, self.port},
      PING_PATH,
      {self.reply_host, self.reply_port, self.nonce}
    )
  end

  --- Dispatch an incoming OSC message. Returns true if we handled it
  --- (caller should NOT forward it to other handlers in that case).
  function self:handle_osc(path, args, from)
    if path ~= PONG_PATH then
      return false
    end
    args = args or {}
    -- Merge features: multiple SC scripts (voice + synths + drums) may each
    -- reply to a single ping, so accumulate features across pongs from the
    -- same handshake window (marked by self.nonce). A new ping bumps the
    -- nonce and resets the window.
    if self._pong_nonce ~= self.nonce then
      self._pong_nonce = self.nonce
      self.features = {}
    end
    self.state = "connected"
    self.last_pong_at = now()
    self.version = tostring(args[1] or self.version or "unknown")
    local seen = {}
    for _, f in ipairs(self.features) do seen[f] = true end
    for i = 2, #args do
      local f = tostring(args[i])
      if not seen[f] then
        self.features[#self.features + 1] = f
        seen[f] = true
      end
    end
    for _, cb in ipairs(self.pong_listeners) do
      cb(self)
    end
    return true
  end

  --- Register a callback fired each time a pong arrives. Callback receives
  --- the bridge self so it can read version/features.
  function self:on_pong(cb)
    self.pong_listeners[#self.pong_listeners + 1] = cb
  end

  --- Mark the bridge disconnected if a pong has not arrived within timeout.
  --- Called periodically from a polling metro or at the top of each ping.
  function self:tick()
    if self.state == "pinging" and self.last_ping_at then
      if (now() - self.last_ping_at) > self.timeout then
        self.state = "disconnected"
      end
    end
  end

  --- True if we have a recent pong.
  function self:is_connected()
    return self.state == "connected"
  end

  --- Human-readable one-liner for UI trays / logs.
  function self:status_string()
    if self.state == "connected" then
      local feats = (#self.features > 0) and table.concat(self.features, ",") or "none"
      return string.format("SC %s:%d ok (v%s, %s)",
        self.host, self.port, self.version or "?", feats)
    elseif self.state == "pinging" then
      return string.format("SC %s:%d pinging…", self.host, self.port)
    end
    return string.format("SC %s:%d offline", self.host, self.port)
  end

  --- Change the SC target after construction.
  function self:set_target(host, port)
    self.host = host or self.host
    self.port = port or self.port
    -- A retarget invalidates the prior connection state.
    self.state = "disconnected"
    self.version = nil
    self.features = {}
  end

  --- Convenience: ping, then sleep for `wait` seconds and re-evaluate state.
  --- Requires clock.sleep (norns) or clock.sync (seamstress); if neither is
  --- available the function degrades to a single ping.
  function self:ping_and_wait(wait)
    wait = wait or self.timeout
    self:ping()
    if clock and clock.run then
      clock.run(function()
        if clock.sleep then
          clock.sleep(wait)
        elseif clock.sync then
          clock.sync(wait)
        end
        self:tick()
      end)
    else
      self:tick()
    end
  end

  return self
end

M.PING_PATH = PING_PATH
M.PONG_PATH = PONG_PATH

return M
