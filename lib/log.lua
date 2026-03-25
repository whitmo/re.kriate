-- lib/log.lua
-- Captures coroutine crash tracebacks to a log file for easy sharing.
--
-- Usage:
--   local log = require("lib/log")
--   clock.run(log.wrap(function() ... end))
--   metro.event = log.wrap(function() ... end)
--
-- Crashes are written to ~/.re_kriate.log with timestamps and tracebacks.

local M = {}

local log_path = os.getenv("HOME") .. "/.re_kriate.log"
local log_file = nil

local function ensure_file()
  if not log_file then
    log_file = io.open(log_path, "a")
    if log_file then
      log_file:setvbuf("line")
    end
  end
  return log_file
end

local function timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

function M.write(level, msg)
  local f = ensure_file()
  if f then
    f:write(string.format("[%s] %s: %s\n", timestamp(), level, msg))
  end
  -- also print to stderr so seamstress console shows it
  io.stderr:write(string.format("[re.kriate %s] %s\n", level, msg))
end

function M.info(msg) M.write("INFO", msg) end
function M.warn(msg) M.write("WARN", msg) end
function M.error(msg) M.write("ERROR", msg) end

--- Wrap a function so coroutine crashes are caught and logged.
-- Returns a function safe to pass to clock.run() or metro.event.
function M.wrap(fn, label)
  label = label or "coroutine"
  return function(...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then
      M.write("CRASH", label .. ": " .. tostring(err))
    end
  end
end

--- Log session start marker (call from init)
function M.session_start()
  local f = ensure_file()
  if f then
    f:write(string.format("\n--- re.kriate session start %s ---\n", timestamp()))
  end
end

--- Flush and close the log file (call from cleanup)
function M.close()
  if log_file then
    log_file:close()
    log_file = nil
  end
end

return M
