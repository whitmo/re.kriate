local f = io.open("/tmp/tm2.txt", "w")

-- Test require musicutil
local ok, mu = pcall(require, "musicutil")
f:write("musicutil: ok=" .. tostring(ok) .. "\n")
if not ok then f:write("  " .. tostring(mu) .. "\n") end

-- Test require lib/track
local ok2, t = pcall(require, "lib/track")
f:write("lib/track: ok=" .. tostring(ok2) .. "\n")
if not ok2 then f:write("  " .. tostring(t) .. "\n") end

-- Test require lib/scale
local ok3, s = pcall(require, "lib/scale")
f:write("lib/scale: ok=" .. tostring(ok3) .. "\n")
if not ok3 then f:write("  " .. tostring(s) .. "\n") end

-- Test require lib/app
local ok4, a = pcall(require, "lib/app")
f:write("lib/app: ok=" .. tostring(ok4) .. "\n")
if not ok4 then f:write("  " .. tostring(a) .. "\n") end

f:flush()

function init()
  f:write("\nINIT called\n")
  
  if ok4 then
    local ok5, ctx = pcall(a.init, {voices = {}})
    f:write("app.init: ok=" .. tostring(ok5) .. "\n")
    if not ok5 then f:write("  " .. tostring(ctx) .. "\n") end
  end
  
  f:flush()
  f:close()
end
