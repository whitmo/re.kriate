local f = io.open("/tmp/tn.txt", "w")

local app = require("lib/app")
local recorder = require("lib/voices/recorder")
local screen_ui = require("lib/seamstress/screen_ui")
local keyboard = require("lib/seamstress/keyboard")
local sequencer = require("lib/sequencer")
local track_mod = require("lib/track")

f:write("modules loaded\n")
f:flush()

local ctx

function init()
  f:write("init()\n")
  
  local buffer = {}
  local voices = {}
  for i = 1, 4 do
    voices[i] = recorder.new(i, buffer)
  end
  
  local ok, result = pcall(app.init, {voices = voices})
  f:write("app.init: ok=" .. tostring(ok) .. "\n")
  if not ok then
    f:write("  error: " .. tostring(result) .. "\n")
    f:flush()
    f:close()
    return
  end
  
  ctx = result
  f:write("  tracks: " .. #ctx.tracks .. "\n")
  f:write("  playing: " .. tostring(ctx.playing) .. "\n")
  f:write("  scale_notes: " .. #ctx.scale_notes .. "\n")
  
  -- test keyboard
  keyboard.key(ctx, " ", {}, false, 1)
  f:write("  playing after space: " .. tostring(ctx.playing) .. "\n")
  keyboard.key(ctx, " ", {}, false, 1)
  f:write("  stopped: " .. tostring(not ctx.playing) .. "\n")
  
  -- test step
  ctx.tracks[1].params.trigger.steps[1] = 1
  ctx.tracks[1].params.trigger.pos = 1
  sequencer.step_track(ctx, 1)
  f:write("  events after step: " .. #buffer .. "\n")
  
  -- test screen
  local ok2, err2 = pcall(screen_ui.redraw, ctx)
  f:write("screen_ui.redraw: ok=" .. tostring(ok2) .. "\n")
  if not ok2 then f:write("  error: " .. tostring(err2) .. "\n") end
  
  f:write("\nSUCCESS\n")
  f:flush()
  f:close()
end

function redraw()
  if ctx then
    pcall(screen_ui.redraw, ctx)
  end
end

function cleanup()
  if ctx then app.cleanup(ctx) end
end
