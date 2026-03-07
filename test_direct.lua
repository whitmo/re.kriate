-- Patch init to capture diagnostics
local f = io.open("/tmp/ss_direct.txt", "w")
f:write("script loading...\n")

-- Load the real entrypoint
dofile("re_kriate_seamstress.lua")

-- Wrap init
local real_init = init
function init()
  f:write("init() starting\n")
  f:flush()
  local ok, err = pcall(real_init)
  f:write("init: ok=" .. tostring(ok) .. "\n")
  if not ok then f:write("  error: " .. tostring(err) .. "\n") end
  f:flush()
  f:close()
end
