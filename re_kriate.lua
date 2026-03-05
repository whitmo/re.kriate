-- re_kriate: a kria sequencer for norns and seamstress
-- inspired by monome ansible's kria
--
-- E1: select track
-- E2: select page
-- K2: play/stop
-- K3: reset
--
-- Grid row 8: navigation
--   1-4: track select
--   6-10: page select (trig/note/oct/dur/vel)
--   12: loop edit (hold)
--   16: play/stop

local app = require("lib/app")

local ctx

function init()
  ctx = app.init()
end

function redraw()
  app.redraw(ctx)
end

function key(n, z)
  app.key(ctx, n, z)
end

function enc(n, d)
  app.enc(ctx, n, d)
end

function cleanup()
  app.cleanup(ctx)
end
