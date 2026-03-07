local f = io.open("/tmp/tw.txt", "w")
dofile("re_kriate_seamstress.lua")

local real_init = init
local real_redraw = redraw
local real_cleanup = cleanup

function init()
  f:write("INIT start\n"); f:flush()
  local ok, err = pcall(real_init)
  f:write("INIT: ok=" .. tostring(ok) .. "\n")
  if not ok then f:write("  " .. tostring(err) .. "\n") end
  f:flush()
end

function redraw()
  local ok, err = pcall(real_redraw)
  if not ok then
    f:write("REDRAW ERROR: " .. tostring(err) .. "\n")
    f:flush()
  end
end

function cleanup()
  f:write("CLEANUP called\n"); f:flush()
  pcall(real_cleanup)
  f:close()
end
