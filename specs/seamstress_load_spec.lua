-- specs/seamstress_load_spec.lua
-- T040: Seamstress runtime load test (US-8)
-- Gated on SEAMSTRESS_LOAD_TEST=1 env var — requires real seamstress runtime, ~30s
-- Not included in standard `busted specs/` fast run unless env var is set.

describe("seamstress load test #seamstress", function()
  local SEAMSTRESS_BIN = "/opt/homebrew/opt/seamstress@1/bin/seamstress"
  local DURATION = 30
  local LOG_PATH = os.getenv("HOME") .. "/.re_kriate.log"

  -- Derive project directory from this spec file's location
  local spec_path = debug.getinfo(1, "S").source:match("@(.*/)")
  local PROJECT_DIR = spec_path and spec_path:gsub("specs/$", "") or "."

  local function binary_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
  end

  local function file_size(path)
    local f = io.open(path, "r")
    if not f then return 0 end
    local size = f:seek("end")
    f:close()
    return size
  end

  local function read_from(path, offset)
    local f = io.open(path, "r")
    if not f then return "" end
    f:seek("set", offset)
    local content = f:read("*a") or ""
    f:close()
    return content
  end

  it("T040: initializes, runs " .. DURATION .. "s, and cleans up without errors", function()
    if not os.getenv("SEAMSTRESS_LOAD_TEST") then
      pending("set SEAMSTRESS_LOAD_TEST=1 to run (~30s, requires seamstress v1.4.7)")
      return
    end

    if not binary_exists(SEAMSTRESS_BIN) then
      pending("seamstress v1.4.7 not found at " .. SEAMSTRESS_BIN)
      return
    end

    -- Record log file position before launch
    local log_offset = file_size(LOG_PATH)
    local stderr_file = os.tmpname()

    -- Launch seamstress from project directory with the seamstress.lua entry point.
    -- Use SIGINT for graceful shutdown (triggers cleanup).
    local cmd = string.format(
      "cd %q && %q seamstress.lua 2>%q & SPID=$!; sleep %d; kill -INT $SPID 2>/dev/null; wait $SPID 2>/dev/null; echo EXIT:$?",
      PROJECT_DIR, SEAMSTRESS_BIN, stderr_file, DURATION
    )

    local handle = io.popen(cmd)
    local stdout = handle:read("*a") or ""
    handle:close()

    -- Read captured stderr
    local stderr = ""
    local sf = io.open(stderr_file, "r")
    if sf then
      stderr = sf:read("*a") or ""
      sf:close()
    end
    os.remove(stderr_file)

    -- Read new log entries since launch
    local new_logs = read_from(LOG_PATH, log_offset)
    local all_output = stderr .. "\n" .. new_logs

    -- SC-004 / US-8 scenario 1: init must complete without errors
    assert.is_truthy(
      all_output:find("init complete"),
      "Expected 'init complete' in output.\nstderr:\n" .. stderr .. "\nlog:\n" .. new_logs
    )

    -- US-8 scenario 3: cleanup must run on graceful exit
    assert.is_truthy(
      all_output:find("cleanup complete"),
      "Expected 'cleanup complete' in output.\nstderr:\n" .. stderr .. "\nlog:\n" .. new_logs
    )

    -- No crashes during the 30s run
    assert.is_falsy(
      all_output:find("%[re%.kriate CRASH%]"),
      "Found CRASH in output:\n" .. all_output
    )

    -- No errors during the 30s run
    assert.is_falsy(
      all_output:find("%[re%.kriate ERROR%]"),
      "Found ERROR in output:\n" .. all_output
    )
  end)
end)
