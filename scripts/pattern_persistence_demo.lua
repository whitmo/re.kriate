-- Quick manual harness for pattern persistence
-- Usage:
--   lua scripts/pattern_persistence_demo.lua save demo
--   lua scripts/pattern_persistence_demo.lua load demo
--
-- Optional env: PP_TMP=/tmp/pp-demo (override data dir)

package.path = "./?.lua;./?/init.lua;" .. package.path

local track = require("lib/track")
local pattern = require("lib/pattern")
local pp = require("lib/pattern_persistence")

local tmp = os.getenv("PP_TMP")
if tmp and tmp ~= "" and pp._test_set_data_dir then
  pp._test_set_data_dir(tmp)
  os.execute('mkdir -p "' .. tmp .. '"')
end

local cmd = arg[1]
local name = arg[2] or "demo"

local function make_ctx()
  return { tracks = track.new_tracks(), patterns = pattern.new_slots() }
end

local function fill_demo(ctx)
  ctx.tracks[1].params.trigger.steps[1] = 1
  ctx.tracks[1].params.note.steps[3] = 7
  ctx.tracks[1].division = 3
  ctx.tracks[2].params.velocity.steps[8] = 5
  ctx.tracks[3].direction = "reverse"
  pattern.save(ctx, 1)
  pattern.save(ctx, 4)
end

if cmd == "save" then
  local ctx = make_ctx()
  fill_demo(ctx)
  local ok, path_or_err = pp.save(ctx, name)
  assert(ok, path_or_err)
  print("saved", name)
elseif cmd == "load" then
  local ctx = make_ctx()
  local ok, err = pp.load(ctx, name)
  if not ok then
    print("load failed", err)
    os.exit(1)
  end
  print("loaded", name)
  print("slot1 populated", ctx.patterns[1].populated)
  print("track1 division", ctx.tracks[1].division)
  print("track3 direction", ctx.tracks[3].direction)
else
  print("usage: lua scripts/pattern_persistence_demo.lua save|load <name>")
  os.exit(1)
end
