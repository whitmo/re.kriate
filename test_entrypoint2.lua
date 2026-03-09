local f = io.open("/tmp/te2.txt", "w")
f:write("loading re_kriate_seamstress.lua via dofile\n")
f:flush()

-- Simulate what seamstress does: dofile the entrypoint
local ok, err = pcall(dofile, "/Users/whit/src/re.kriate/re_kriate_seamstress.lua")
f:write("dofile: ok=" .. tostring(ok) .. "\n")
if not ok then f:write("  error: " .. tostring(err) .. "\n") end
f:flush()

-- Call init if dofile succeeded
if ok and init then
  f:write("\ncalling init()...\n")
  f:flush()
  local ok2, err2 = pcall(init)
  f:write("init: ok=" .. tostring(ok2) .. "\n")
  if not ok2 then f:write("  error: " .. tostring(err2) .. "\n") end
end

f:flush()
f:close()
