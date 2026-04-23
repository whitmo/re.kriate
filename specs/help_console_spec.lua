-- specs/help_console_spec.lua
-- Tests for lib/seamstress/help_console.lua

package.path = package.path .. ";./?.lua"

-- Minimal globals so lib/sequencer and friends can load under busted.
_G.params = _G.params or {
  params = {},
  lookup = {},
  get = function(self, id) return 0 end,
  set = function(self, id, v) end,
}
_G.clock = _G.clock or {
  run = function() return 0 end,
  cancel = function() end,
  sleep = function() end,
  sync = function() end,
  get_tempo = function() return 120 end,
}
_G.metro = _G.metro or {init = function() return {start = function() end, stop = function() end} end}
_G.util = _G.util or {
  clamp = function(v, a, b) if v < a then return a elseif v > b then return b end; return v end,
}

local help_console = require("lib/seamstress/help_console")

local function make_ctx()
  return {
    playing = false,
    active_track = 1,
    active_page = "trigger",
    tracks = {},
    voices = {{kind = "midi"}, {kind = "osc"}, nil, {kind = "none"}},
    clock_sync = {source = "internal"},
  }
end

local function collector()
  local lines = {}
  return lines, function(s) lines[#lines + 1] = s end
end

describe("help_console", function()

  it("install returns a callable namespace with ctx/transport/debug", function()
    local ctx = make_ctx()
    local target = {}
    local obj = help_console.install(ctx, {target = target, sink = function() end})

    assert.is_table(obj)
    assert.are.equal(obj, target.help)
    assert.are.equal(ctx, obj.ctx)
    assert.is_table(obj.transport)
    assert.is_table(obj.debug)
    assert.is_table(obj.topics)
    -- topics must advertise the documented surface
    local joined = table.concat(obj.topics, ",")
    assert.is_truthy(joined:find("ctx"))
    assert.is_truthy(joined:find("transport"))
    assert.is_truthy(joined:find("debug"))
  end)

  it("help() prints an overview listing topics", function()
    local ctx = make_ctx()
    local target = {}
    local lines, sink = collector()
    local obj = help_console.install(ctx, {target = target, sink = sink})
    obj()  -- callable
    local joined = table.concat(lines, "\n")
    assert.is_truthy(joined:find("re.kriate"))
    assert.is_truthy(joined:find("help.ctx"))
    assert.is_truthy(joined:find("help.transport"))
    assert.is_truthy(joined:find("help.debug"))
  end)

  it("help.transport() prints transport reference", function()
    local ctx = make_ctx()
    ctx.playing = true
    ctx.active_track = 3
    local lines, sink = collector()
    local obj = help_console.install(ctx, {target = {}, sink = sink})
    obj.transport()
    local joined = table.concat(lines, "\n")
    assert.is_truthy(joined:find("transport"))
    assert.is_truthy(joined:find("play"))
    assert.is_truthy(joined:find("stop"))
    assert.is_truthy(joined:find("reset"))
    -- current state is surfaced
    assert.is_truthy(joined:find("active_track = 3"))
  end)

  it("help.transport.state() returns live transport snapshot", function()
    local ctx = make_ctx()
    ctx.playing = true
    ctx.active_track = 2
    ctx.active_page = "note"
    local obj = help_console.install(ctx, {target = {}, sink = function() end})
    local s = obj.transport.state()
    assert.are.equal(true, s.playing)
    assert.are.equal(2, s.active_track)
    assert.are.equal("note", s.active_page)
    assert.are.equal("internal", s.source)
  end)

  it("help.transport.play/stop/reset call the sequencer", function()
    package.loaded["lib/sequencer"] = nil
    local calls = {}
    package.loaded["lib/sequencer"] = {
      start = function(c) calls[#calls + 1] = {"start", c} end,
      stop  = function(c) calls[#calls + 1] = {"stop",  c} end,
      reset = function(c) calls[#calls + 1] = {"reset", c} end,
    }
    package.loaded["lib/seamstress/help_console"] = nil
    local hc = require("lib/seamstress/help_console")
    local ctx = make_ctx()
    local obj = hc.install(ctx, {target = {}, sink = function() end})

    assert.are.equal("playing", obj.transport.play())
    assert.are.equal("stopped", obj.transport.stop())
    assert.are.equal("reset",   obj.transport.reset())
    assert.are.equal(3, #calls)
    assert.are.equal("start", calls[1][1])
    assert.are.equal(ctx, calls[1][2])
    assert.are.equal("stop",  calls[2][1])
    assert.are.equal("reset", calls[3][1])

    -- Restore real modules so other tests aren't corrupted.
    package.loaded["lib/sequencer"] = nil
    package.loaded["lib/seamstress/help_console"] = nil
  end)

  it("help.debug() prints debug reference including log path", function()
    local ctx = make_ctx()
    local lines, sink = collector()
    local obj = help_console.install(ctx, {target = {}, sink = sink})
    obj.debug()
    local joined = table.concat(lines, "\n")
    assert.is_truthy(joined:find("debug"))
    assert.is_truthy(joined:find("log"))
    assert.is_truthy(joined:find("tail"))
    assert.is_truthy(joined:find("ctx_dump"))
    assert.is_truthy(joined:find(".re_kriate.log"))
  end)

  it("help.debug.ctx_dump returns the live ctx", function()
    local ctx = make_ctx()
    local obj = help_console.install(ctx, {target = {}, sink = function() end})
    assert.are.equal(ctx, obj.debug.ctx_dump())
  end)

  it("help.debug.voices summarises voice kinds per track", function()
    local ctx = make_ctx()
    local obj = help_console.install(ctx, {target = {}, sink = function() end})
    local v = obj.debug.voices()
    assert.are.equal("midi", v[1])
    assert.are.equal("osc",  v[2])
    -- index 3 is a gap (nil) — ipairs stops there, so only 1-2 appear
    assert.is_nil(v[4])
  end)

  it("help.debug.params_list reflects registered params", function()
    local saved = _G.params
    _G.params = {
      params = {{id = "root_note"}, {id = "scale_type"}, {id = "voice_1"}},
      lookup = {},
      get = function() return 0 end,
      set = function() end,
    }
    local ctx = make_ctx()
    local obj = help_console.install(ctx, {target = {}, sink = function() end})
    local ids = obj.debug.params_list()
    assert.are.equal(3, #ids)
    assert.are.equal("root_note", ids[1])
    _G.params = saved
  end)

  it("install assigns to _G.help when no target is given", function()
    local saved = rawget(_G, "help")
    local ctx = make_ctx()
    help_console.install(ctx, {sink = function() end})
    assert.is_table(_G.help)
    assert.are.equal(ctx, _G.help.ctx)
    _G.help = saved
  end)

  it("help is callable via __call metamethod", function()
    local ctx = make_ctx()
    local obj = help_console.install(ctx, {target = {}, sink = function() end})
    -- No error when invoking via call syntax.
    assert.has_no.errors(function() obj() end)
    assert.has_no.errors(function() obj.transport() end)
    assert.has_no.errors(function() obj.debug() end)
  end)

  it("install rejects non-table ctx", function()
    assert.has_error(function() help_console.install(nil) end)
    assert.has_error(function() help_console.install("ctx") end)
  end)

end)
