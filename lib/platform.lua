-- lib/platform.lua
-- The execution-environment boundary. re.kriate targets three
-- environments (see docs/adapters.md):
--
--   norns       hardware — norns runtime provides params/clock/metro/
--               midi/grid/screen/osc globals; entrypoint re_kriate.lua
--   seamstress  desktop — seamstress v1 provides the same global surface
--               (plus _seamstress internals); entrypoint seamstress.lua
--   standalone  plain Lua, no host runtime — busted tests and
--               standalone.lua. Host services are stubs installed by
--               M.prepare_standalone(); there is no realtime clock, so
--               sequencing advances by manual stepping (see
--               standalone.lua) rather than clock coroutines.
--
-- Detection probes host-identity globals; capabilities() probes the
-- service globals individually so callers ask "is there a screen?"
-- rather than "am I on norns?" wherever possible.

local M = {}

--- Which environment is this process running in?
--- @return string  "norns" | "seamstress" | "standalone"
function M.detect()
  if rawget(_G, "norns") ~= nil then return "norns" end
  if rawget(_G, "_seamstress") ~= nil then return "seamstress" end
  return "standalone"
end

--- Probe the host service surface.
--- @return table  {env, params, clock, metro, midi, grid, screen, osc}
function M.capabilities()
  return {
    env = M.detect(),
    params = rawget(_G, "params") ~= nil,
    clock = rawget(_G, "clock") ~= nil,
    metro = rawget(_G, "metro") ~= nil,
    midi = rawget(_G, "midi") ~= nil,
    grid = rawget(_G, "grid") ~= nil,
    screen = rawget(_G, "screen") ~= nil,
    osc = rawget(_G, "osc") ~= nil,
  }
end

-- ============================================================================
-- Standalone host stubs
-- ============================================================================

--- Build a params stub implementing the constructor/action/lookup surface
--- lib/app.lua and friends actually use. Values live in the returned
--- store; set() fires registered actions like the real params system.
local function make_params_stub()
  local store = {}
  local actions = {}
  local options = {} -- id -> option label list (for :string)

  local p = {}
  p.lookup = {}

  local function register(id, default, opts_list)
    store[id] = default
    p.lookup[id] = { id = id }
    if opts_list then options[id] = opts_list end
  end

  function p:add_separator(id, name) end
  function p:add_group(id, name, n) end
  function p:add_number(id, name, min, max, default, formatter)
    register(id, default or 0)
  end
  function p:add_option(id, name, opts_list, default)
    register(id, default or 1, opts_list)
  end
  function p:add_text(id, name, default)
    register(id, default or "")
  end
  function p:set_action(id, fn)
    actions[id] = fn
  end
  function p:get(id)
    return store[id]
  end
  function p:set(id, v)
    store[id] = v
    if actions[id] then actions[id](v) end
  end
  function p:string(id)
    local opts_list = options[id]
    local v = store[id]
    if opts_list and type(v) == "number" then
      return tostring(opts_list[v])
    end
    return tostring(v)
  end
  function p:lookup_param(id)
    local self_p = p
    return { get = function() return self_p:get(id) end }
  end
  function p:show(id) end
  function p:hide(id) end
  function p:bang() end

  return p, store
end

--- Manual clock stub: clock.run registers the coroutine function but does
--- not schedule it — standalone has no realtime scheduler. Sequencing in
--- standalone advances via sequencer.step_track (manual stepping), the
--- same mechanism the params-menu advance_N triggers use on hosts.
local function make_clock_stub()
  local next_id = 1
  return {
    get_beats = function() return 0 end,
    get_beat_sec = function() return 0.5 end,
    run = function(fn, ...)
      local id = next_id
      next_id = next_id + 1
      return id
    end,
    cancel = function(id) end,
    sync = function(n) end,
    sleep = function(s) end,
  }
end

local function make_metro_stub()
  return {
    init = function()
      return {
        time = 0,
        event = nil,
        start = function(self) end,
        stop = function(self) end,
      }
    end,
  }
end

local function make_midi_stub()
  local dummy_dev = {
    note_on = function() end,
    note_off = function() end,
    cc = function() end,
    send = function() end,
    start = function() end,
    stop = function() end,
    continue = function() end,
    clock = function() end,
  }
  return {
    connect = function(port) return dummy_dev end,
    devices = {},
  }
end

-- Real scale intervals for the standalone musicutil implementation —
-- these are actual musical scales, not test fakes, because standalone is
-- a genuine execution environment: notes it quantizes should be correct.
local SCALE_INTERVALS = {
  ["major"] = {0, 2, 4, 5, 7, 9, 11},
  ["natural minor"] = {0, 2, 3, 5, 7, 8, 10},
  ["dorian"] = {0, 2, 3, 5, 7, 9, 10},
  ["mixolydian"] = {0, 2, 4, 5, 7, 9, 10},
  ["lydian"] = {0, 2, 4, 6, 7, 9, 11},
  ["phrygian"] = {0, 1, 3, 5, 7, 8, 10},
  ["locrian"] = {0, 1, 3, 5, 6, 8, 10},
  ["harmonic minor"] = {0, 2, 3, 5, 7, 8, 11},
  ["melodic minor"] = {0, 2, 3, 5, 7, 9, 11},
  ["major pentatonic"] = {0, 2, 4, 7, 9},
  ["minor pentatonic"] = {0, 3, 5, 7, 10},
  ["blues scale"] = {0, 3, 5, 6, 7, 10},
  ["whole tone"] = {0, 2, 4, 6, 8, 10},
  ["chromatic"] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
}

local function make_musicutil()
  return {
    generate_scale = function(root, scale_type, octaves)
      local intervals = SCALE_INTERVALS[tostring(scale_type):lower()]
        or SCALE_INTERVALS["chromatic"]
      local notes = {}
      for oct = 0, (octaves or 1) - 1 do
        for _, semi in ipairs(intervals) do
          local note = root + oct * 12 + semi
          if note <= 127 then notes[#notes + 1] = note end
        end
      end
      return notes
    end,
  }
end

--- Install the minimal host-service stubs a standalone (plain Lua)
--- process needs to boot the full app: params, clock, metro, midi, osc,
--- and a genuine pure-Lua musicutil (a require'd module on real hosts).
--- Refuses to run on a real host — stubbing over norns/seamstress
--- services would break the live app.
--- @return table|nil handles, string|nil err  handles = {params_store}
function M.prepare_standalone()
  local env = M.detect()
  if env ~= "standalone" then
    return nil, "prepare_standalone refused: running on " .. env
  end

  local params_stub, store = make_params_stub()
  rawset(_G, "params", params_stub)
  rawset(_G, "clock", make_clock_stub())
  rawset(_G, "metro", make_metro_stub())
  rawset(_G, "midi", make_midi_stub())
  if rawget(_G, "osc") == nil then
    rawset(_G, "osc", { send = function() end })
  end
  if package.loaded["musicutil"] == nil then
    package.loaded["musicutil"] = make_musicutil()
  end

  return { params_store = store }
end

return M
