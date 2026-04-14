-- lib/voices/sc_mixer.lua
-- Lua-side client for the SuperCollider mixer engine (sc/rekriate-mixer.scd).
--
-- Distinct from lib/mixer.lua — that module owns per-track voice mixer state
-- (level/pan/mute routed through the voice interface). This module is a thin
-- OSC wrapper around the dedicated SC mixer: 4 channel strips (filter /
-- reverb / delay / compressor / level / mute / pan / send), a shared aux
-- (reverb + delay), a master bus (level + aux_return + soft-clip), plus
-- metering and bulk state dump.
--
-- OSC outbound (Lua → SC):
--   /rekriate/mixer/channel/{n}/{param}  (n 1..4, param: level, pan, mute,
--       send, filter_type, filter_freq, filter_res, reverb_mix, reverb_room,
--       reverb_damp, delay_mix, delay_time, delay_feedback, comp_thresh,
--       comp_ratio, comp_attack, comp_release)
--   /rekriate/mixer/aux/{param}          (level, reverb_mix, reverb_room,
--       reverb_damp, delay_mix, delay_time, delay_feedback)
--   /rekriate/mixer/master/{param}       (level, aux_return_level)
--   /rekriate/mixer/meter/target  host port   (configure meter forwarding)
--   /rekriate/mixer/meter/off                 (disable meter forwarding)
--   /rekriate/mixer/state/dump                (request full state echo)
--
-- OSC inbound (SC → Lua) — dispatched via `mixer:handle_osc(path, args)`:
--   /rekriate/mixer/meter/channel/{n}  l r
--   /rekriate/mixer/meter/aux          l r
--   /rekriate/mixer/meter/master       l r
--   /rekriate/mixer/channel/{n}/{k}    v   (echoed from state/dump)
--   /rekriate/mixer/aux/{k}            v
--   /rekriate/mixer/master/{k}         v
--
-- Depends on globals `osc.send` (seamstress/norns). Never installs an
-- osc.event handler itself — the host app wires incoming messages through
-- `mixer:handle_osc(path, args, from)`, matching the sc_bridge pattern.

local M = {}

local NUM_CHANNELS = 4

-- Param metadata: range clamps match the SC-side `.clip(...)` bounds plus the
-- channel-responder ranges declared in rekriate-mixer.scd. `kind="int"`
-- means the value is floored on the way out (e.g. mute, filter_type).
local CHANNEL_PARAMS = {
  level          = {lo = 0,     hi = 2,     default = 0.8,    kind = "float"},
  pan            = {lo = -1,    hi = 1,     default = 0.0,    kind = "float"},
  mute           = {lo = 0,     hi = 1,     default = 0,      kind = "int"},
  send           = {lo = 0,     hi = 1,     default = 0.0,    kind = "float"},
  filter_type    = {lo = 0,     hi = 2,     default = 0,      kind = "int"},
  filter_freq    = {lo = 20,    hi = 18000, default = 10000,  kind = "float"},
  filter_res     = {lo = 0,     hi = 1,     default = 0.3,    kind = "float"},
  reverb_mix     = {lo = 0,     hi = 1,     default = 0.0,    kind = "float"},
  reverb_room    = {lo = 0,     hi = 1,     default = 0.5,    kind = "float"},
  reverb_damp    = {lo = 0,     hi = 1,     default = 0.5,    kind = "float"},
  delay_mix      = {lo = 0,     hi = 1,     default = 0.0,    kind = "float"},
  delay_time     = {lo = 0.001, hi = 2.0,   default = 0.375,  kind = "float"},
  delay_feedback = {lo = 0,     hi = 0.95,  default = 0.3,    kind = "float"},
  comp_thresh    = {lo = 0,     hi = 1,     default = 0.5,    kind = "float"},
  comp_ratio     = {lo = 1,     hi = 20,    default = 1.0,    kind = "float"},
  comp_attack    = {lo = 0.001, hi = 0.5,   default = 0.01,   kind = "float"},
  comp_release   = {lo = 0.01,  hi = 1.0,   default = 0.1,    kind = "float"},
}

local AUX_PARAMS = {
  level          = {lo = 0,     hi = 2,     default = 0.8,    kind = "float"},
  reverb_mix     = {lo = 0,     hi = 1,     default = 0.6,    kind = "float"},
  reverb_room    = {lo = 0,     hi = 1,     default = 0.7,    kind = "float"},
  reverb_damp    = {lo = 0,     hi = 1,     default = 0.4,    kind = "float"},
  delay_mix      = {lo = 0,     hi = 1,     default = 0.3,    kind = "float"},
  delay_time     = {lo = 0.001, hi = 2.0,   default = 0.375,  kind = "float"},
  delay_feedback = {lo = 0,     hi = 0.95,  default = 0.4,    kind = "float"},
}

local MASTER_PARAMS = {
  level            = {lo = 0, hi = 2, default = 0.8, kind = "float"},
  aux_return_level = {lo = 0, hi = 2, default = 0.5, kind = "float"},
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function sanitize(def, val)
  local n = tonumber(val)
  if n == nil then n = def.default end
  n = clamp(n, def.lo, def.hi)
  if def.kind == "int" then
    -- Round half-up so 0.5 → 1. Matches SC's `.asInteger` for positive values.
    n = math.floor(n + 0.5)
  end
  return n
end

local function copy_table(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- Construct a new SC mixer client.
--- @param opts table {host?, port?, reply_host?, reply_port?}
---   host/port         — sclang / scsynth OSC target (where setters are sent)
---   reply_host/port   — local listener for meter + state/dump echoes
function M.new(opts)
  opts = opts or {}
  local self = {
    host = opts.host or "127.0.0.1",
    port = opts.port or 57120,
    reply_host = opts.reply_host or "127.0.0.1",
    reply_port = opts.reply_port or 7000,
    channels = {},
    aux = {},
    master = {},
    meter = {channels = {}, aux = {l = 0, r = 0}, master = {l = 0, r = 0}},
    meter_enabled = false,
    _meter_listeners = {},
  }

  for n = 1, NUM_CHANNELS do
    local ch = {}
    for k, def in pairs(CHANNEL_PARAMS) do ch[k] = def.default end
    self.channels[n] = ch
    self.meter.channels[n] = {l = 0, r = 0}
  end
  for k, def in pairs(AUX_PARAMS) do self.aux[k] = def.default end
  for k, def in pairs(MASTER_PARAMS) do self.master[k] = def.default end

  local function target() return {self.host, self.port} end

  --- Update the SC target after construction.
  function self:set_target(host, port)
    self.host = host or self.host
    self.port = port or self.port
  end

  --- Update the reply address (where meters / state dumps are sent back).
  --- Call enable_meters() after this to re-arm the SC side.
  function self:set_reply(host, port)
    self.reply_host = host or self.reply_host
    self.reply_port = port or self.reply_port
  end

  --- Set a channel parameter. Clamps to spec range, updates shadow state,
  --- and sends the OSC message. Returns the clamped value, or nil if the
  --- param/channel is unknown.
  function self:set_channel(n, param, val)
    local def = CHANNEL_PARAMS[param]
    if not def or n < 1 or n > NUM_CHANNELS then return nil end
    local v = sanitize(def, val)
    self.channels[n][param] = v
    osc.send(target(),
      "/rekriate/mixer/channel/" .. n .. "/" .. param,
      {v})
    return v
  end

  --- Set an aux parameter.
  function self:set_aux(param, val)
    local def = AUX_PARAMS[param]
    if not def then return nil end
    local v = sanitize(def, val)
    self.aux[param] = v
    osc.send(target(), "/rekriate/mixer/aux/" .. param, {v})
    return v
  end

  --- Set a master parameter.
  function self:set_master(param, val)
    local def = MASTER_PARAMS[param]
    if not def then return nil end
    local v = sanitize(def, val)
    self.master[param] = v
    osc.send(target(), "/rekriate/mixer/master/" .. param, {v})
    return v
  end

  --- Read a shadow value (what we believe SC is holding). Returns nil for
  --- unknown param names so callers can distinguish "unset" from "zero".
  function self:get_channel(n, param)
    local ch = self.channels[n]
    if not ch then return nil end
    return ch[param]
  end

  function self:get_aux(param) return self.aux[param] end
  function self:get_master(param) return self.master[param] end

  --- Ask SC to start forwarding meters to reply_host:reply_port. After this
  --- call, /rekriate/mixer/meter/{channel|aux|master} messages arrive; feed
  --- them to handle_osc().
  function self:enable_meters()
    self.meter_enabled = true
    osc.send(target(), "/rekriate/mixer/meter/target",
      {self.reply_host, self.reply_port})
  end

  --- Turn meter forwarding off on the SC side.
  function self:disable_meters()
    self.meter_enabled = false
    osc.send(target(), "/rekriate/mixer/meter/off", {})
  end

  --- Ask SC to replay current state back to the configured meter target.
  --- Requires enable_meters() to have been called first.
  function self:dump_state()
    osc.send(target(), "/rekriate/mixer/state/dump", {})
  end

  --- Push all shadow state to SC (useful after preset restore or reconnect).
  --- Sends every channel / aux / master param currently held locally.
  function self:sync_to_sc()
    for n = 1, NUM_CHANNELS do
      for param, v in pairs(self.channels[n]) do
        osc.send(target(),
          "/rekriate/mixer/channel/" .. n .. "/" .. param, {v})
      end
    end
    for param, v in pairs(self.aux) do
      osc.send(target(), "/rekriate/mixer/aux/" .. param, {v})
    end
    for param, v in pairs(self.master) do
      osc.send(target(), "/rekriate/mixer/master/" .. param, {v})
    end
  end

  --- Register a callback fired on every meter message.
  ---   cb(kind, index_or_nil, l, r)
  ---   kind   — "channel" | "aux" | "master"
  ---   index  — channel number for "channel", nil otherwise
  function self:on_meter(cb)
    self._meter_listeners[#self._meter_listeners + 1] = cb
  end

  local function emit_meter(kind, idx, l, r)
    for _, cb in ipairs(self._meter_listeners) do
      cb(kind, idx, l, r)
    end
  end

  --- Dispatch an incoming OSC message. Returns true if it was handled
  --- (callers should stop further dispatch in that case).
  function self:handle_osc(path, args, _from)
    if type(path) ~= "string" then return false end
    if path:sub(1, 16) ~= "/rekriate/mixer/" then return false end
    args = args or {}
    local tail = path:sub(17)

    -- Meter: /rekriate/mixer/meter/channel/{n} | /aux | /master
    local chan_str = tail:match("^meter/channel/(%d+)$")
    if chan_str then
      local n = tonumber(chan_str)
      local l = tonumber(args[1]) or 0
      local r = tonumber(args[2]) or 0
      if n and self.meter.channels[n] then
        self.meter.channels[n].l = l
        self.meter.channels[n].r = r
        emit_meter("channel", n, l, r)
      end
      return true
    end
    if tail == "meter/aux" then
      local l = tonumber(args[1]) or 0
      local r = tonumber(args[2]) or 0
      self.meter.aux.l = l
      self.meter.aux.r = r
      emit_meter("aux", nil, l, r)
      return true
    end
    if tail == "meter/master" then
      local l = tonumber(args[1]) or 0
      local r = tonumber(args[2]) or 0
      self.meter.master.l = l
      self.meter.master.r = r
      emit_meter("master", nil, l, r)
      return true
    end

    -- Channel param echo: /rekriate/mixer/channel/{n}/{key}
    local n_str, key = tail:match("^channel/(%d+)/([%w_]+)$")
    if n_str and key then
      local n = tonumber(n_str)
      local def = CHANNEL_PARAMS[key]
      if n and def and self.channels[n] then
        local v = sanitize(def, args[1])
        self.channels[n][key] = v
      end
      return true
    end

    -- Aux param echo: /rekriate/mixer/aux/{key}
    local aux_key = tail:match("^aux/([%w_]+)$")
    if aux_key then
      local def = AUX_PARAMS[aux_key]
      if def then self.aux[aux_key] = sanitize(def, args[1]) end
      return true
    end

    -- Master param echo: /rekriate/mixer/master/{key}
    local master_key = tail:match("^master/([%w_]+)$")
    if master_key then
      local def = MASTER_PARAMS[master_key]
      if def then self.master[master_key] = sanitize(def, args[1]) end
      return true
    end

    return false
  end

  --- Capture shadow state as a plain table (preset persistence, diagnostics).
  function self:snapshot()
    local snap = {channels = {}, aux = copy_table(self.aux),
                  master = copy_table(self.master)}
    for n = 1, NUM_CHANNELS do
      snap.channels[n] = copy_table(self.channels[n])
    end
    return snap
  end

  --- Restore shadow state from a snapshot. Does NOT send OSC; call
  --- sync_to_sc() afterwards to push to SC. Missing fields are left alone.
  function self:restore(snap)
    if not snap then return end
    if snap.channels then
      for n = 1, NUM_CHANNELS do
        local src = snap.channels[n]
        if src then
          for k, def in pairs(CHANNEL_PARAMS) do
            if src[k] ~= nil then
              self.channels[n][k] = sanitize(def, src[k])
            end
          end
        end
      end
    end
    if snap.aux then
      for k, def in pairs(AUX_PARAMS) do
        if snap.aux[k] ~= nil then
          self.aux[k] = sanitize(def, snap.aux[k])
        end
      end
    end
    if snap.master then
      for k, def in pairs(MASTER_PARAMS) do
        if snap.master[k] ~= nil then
          self.master[k] = sanitize(def, snap.master[k])
        end
      end
    end
  end

  return self
end

-- Exposed for tests / external introspection.
M.NUM_CHANNELS = NUM_CHANNELS
M.CHANNEL_PARAMS = CHANNEL_PARAMS
M.AUX_PARAMS = AUX_PARAMS
M.MASTER_PARAMS = MASTER_PARAMS

return M
