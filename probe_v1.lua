local f = io.open("/tmp/probe_v1_out.txt", "w")
f:write("TOP LEVEL\n")
f:flush()
function init()
  f:write("INIT\n")
  f:flush()
  f:close()
end
