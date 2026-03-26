-- lib/log.lua
-- Error capture and leveled logging

local M = {}

local LOG_PATH = os.getenv("HOME") .. "/.re_kriate.log"
local log_file = nil

local LEVELS = { INFO = "INFO", WARN = "WARN", ERROR = "ERROR" }

local function ensure_open()
  if not log_file then
    log_file = io.open(LOG_PATH, "a")
  end
  return log_file
end

local function write_line(level, msg)
  local f = ensure_open()
  if f then
    f:write(string.format("[%s] %s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), level, msg))
    f:flush()
  end
end

--- Log an info message
function M.info(msg)
  write_line(LEVELS.INFO, msg)
end

--- Log a warning message
function M.warn(msg)
  write_line(LEVELS.WARN, msg)
end

--- Log an error message
function M.error(msg)
  write_line(LEVELS.ERROR, msg)
end

--- Log session start marker
function M.session_start()
  local f = ensure_open()
  if f then
    f:write(string.format("\n=== re.kriate session start %s ===\n", os.date("%Y-%m-%d %H:%M:%S")))
    f:flush()
  end
end

--- Flush and close the log file
function M.close()
  if log_file then
    log_file:flush()
    log_file:close()
    log_file = nil
  end
end

--- Wrap a function for xpcall; logs crashes to the log file
--- @param fn function  The function to wrap
--- @param label string  A label for the crash log entry
--- @return function  A wrapped function that catches and logs errors
function M.wrap(fn, label)
  return function(...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then
      M.error(string.format("[%s] %s", label, tostring(err)))
    end
    return ok, err
  end
end

return M
