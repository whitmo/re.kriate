-- lib/seamstress/help_console.lua
-- Installs a callable `help()` object into the seamstress Lua console so the
-- user can discover re.kriate internals interactively. `help` is both
-- callable (prints an overview) and a namespace exposing:
--   help.ctx        — live application context table
--   help.transport  — sequencer play/stop/reset + state (also callable)
--   help.debug      — log access, ctx dump, voice + params introspection

local M = {}

local LOG_PATH = os.getenv("HOME") .. "/.re_kriate.log"

-- Lightweight printer: uses the global print (seamstress console) if no
-- sink is injected. Tests override sink to capture output.
local function printlines(sink, ...)
  local lines = {...}
  for _, line in ipairs(lines) do
    sink(line)
  end
end

local function make_callable(tbl, callfn)
  return setmetatable(tbl, {
    __call = function(self, ...) return callfn(self, ...) end,
    __tostring = function() return "<re.kriate help namespace>" end,
  })
end

local function voice_kind(v)
  if type(v) ~= "table" then return type(v) end
  -- Voice modules vary in shape; surface whatever identifier they expose.
  return v.kind or v._kind or v.type or "table"
end

local function build_transport(ctx, sink)
  local sequencer = require("lib/sequencer")
  local tbl = {}

  function tbl.state()
    local bpm
    if params and params.get and params.lookup and params.lookup["clock_tempo"] then
      bpm = params:get("clock_tempo")
    end
    return {
      playing = ctx.playing and true or false,
      source = ctx.clock_sync and ctx.clock_sync.source or nil,
      bpm = bpm,
      active_track = ctx.active_track,
      active_page = ctx.active_page,
    }
  end

  function tbl.play() sequencer.start(ctx); return "playing" end
  function tbl.stop() sequencer.stop(ctx); return "stopped" end
  function tbl.reset() sequencer.reset(ctx); return "reset" end

  local function describe()
    printlines(sink,
      "transport:",
      "  help.transport.state()  -> {playing, source, bpm, active_track, active_page}",
      "  help.transport.play()   -> start sequencer",
      "  help.transport.stop()   -> stop sequencer",
      "  help.transport.reset()  -> reset playheads",
      "",
      "current:",
      "  playing      = " .. tostring(ctx.playing and true or false),
      "  active_track = " .. tostring(ctx.active_track),
      "  active_page  = " .. tostring(ctx.active_page)
    )
  end

  return make_callable(tbl, describe)
end

local function build_debug(ctx, sink)
  local log = require("lib/log")
  local remote_api = require("lib/remote/api")
  local tbl = {}

  tbl.log_path = LOG_PATH

  function tbl.ctx_dump() return ctx end

  function tbl.voices()
    local out = {}
    if ctx.voices then
      for i, v in ipairs(ctx.voices) do
        out[i] = voice_kind(v)
      end
    end
    return out
  end

  function tbl.params_list()
    local ids = {}
    if params and params.params then
      for _, p in ipairs(params.params) do
        if p.id then ids[#ids + 1] = p.id end
      end
    end
    return ids
  end

  function tbl.api_paths() return remote_api.list_paths() end

  function tbl.log_info(msg) log.info(tostring(msg)) end

  function tbl.tail(n)
    n = tonumber(n) or 20
    local f = io.open(LOG_PATH, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    local out = {}
    for i = math.max(1, #lines - n + 1), #lines do
      out[#out + 1] = lines[i]
    end
    return out
  end

  local function describe()
    printlines(sink,
      "debug:",
      "  help.debug.log_path       path to re.kriate log file",
      "  help.debug.tail(n)        last n lines of log (default 20)",
      "  help.debug.log_info(msg)  append an INFO line to the log",
      "  help.debug.ctx_dump()     live ctx reference",
      "  help.debug.voices()       per-track voice kind summary",
      "  help.debug.params_list()  registered param ids",
      "  help.debug.api_paths()    remote API paths (see lib/remote/api)",
      "",
      "log path: " .. LOG_PATH
    )
  end

  return make_callable(tbl, describe)
end

--- Install `help` on the target namespace (default: _G).
--- @param ctx table  The re.kriate application context
--- @param opts table|nil  { target = <table>, sink = function(line) }
--- @return table  The help object (already assigned to target.help)
function M.install(ctx, opts)
  assert(type(ctx) == "table", "help_console.install requires a ctx table")
  opts = opts or {}
  local target = opts.target or _G
  local sink = opts.sink or print

  local obj = {}
  obj.ctx = ctx
  obj.transport = build_transport(ctx, sink)
  obj.debug = build_debug(ctx, sink)
  obj.topics = {"ctx", "transport", "debug"}

  local function overview()
    printlines(sink,
      "re.kriate console help",
      "  help()           show this overview",
      "  help.ctx         live application context",
      "  help.transport   play/stop/reset + transport state",
      "  help.debug       log path, log tail, ctx dump, voices, params",
      "",
      "call help.transport() or help.debug() for per-topic details."
    )
  end

  setmetatable(obj, {
    __call = function() overview() end,
    __tostring = function() return "re.kriate help - call help() for overview" end,
  })

  target.help = obj
  return obj
end

return M
