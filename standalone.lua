-- standalone.lua: re.kriate entrypoint for plain Lua — no norns, no
-- seamstress, no host runtime at all.
--
--   lua standalone.lua [steps]
--
-- The third execution environment (see docs/adapters.md): lib/platform.lua
-- installs the minimal host stubs (params/clock/metro/midi/osc + a genuine
-- pure-Lua musicutil), then the FULL app boots — data model, params
-- registry, behavioral command layer, synthetic grid — and the sequencer
-- is driven by manual stepping (there is no realtime clock in a bare Lua
-- process; sequencing advances the same way the params-menu advance_N
-- triggers do on real hosts).
--
-- Voices are recorders, so the run reports exactly what would have
-- sounded. Exit code 0 = booted, played, and shut down cleanly; non-zero
-- otherwise — which makes this file double as a CI-runnable smoke test of
-- the environment boundary.

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

local platform = require("lib/platform")

local env = platform.detect()
if env ~= "standalone" then
  io.stderr:write("standalone.lua is for plain Lua; detected host: " .. env .. "\n")
  os.exit(1)
end

local handles, err = platform.prepare_standalone()
if not handles then
  io.stderr:write("platform bootstrap failed: " .. tostring(err) .. "\n")
  os.exit(1)
end

local app = require("lib/app")
local sequencer = require("lib/sequencer")
local recorder = require("lib/voices/recorder")
local track_mod = require("lib/track")

-- Recorder voices: capture, don't emit — standalone has no audio device.
local voices = {}
for t = 1, track_mod.NUM_TRACKS do
  voices[t] = recorder.new(t)
end

local ctx = app.init({
  voices = voices,
  grid_provider = "synthetic",
})
assert(ctx.ready, "app.init did not complete")

print("re.kriate standalone")
print("  environment: " .. env)
print("  grid: synthetic 16x8, voices: recorder x" .. track_mod.NUM_TRACKS)

-- Count behavioral facts as they flow.
local fact_counts = {}
ctx.events:on("sequencer:step", function() fact_counts.step = (fact_counts.step or 0) + 1 end)
ctx.events:on("voice:note", function() fact_counts.note = (fact_counts.note or 0) + 1 end)

-- Transport on, via the same behavioral command any interface would emit.
ctx.events:emit("cmd:transport:play", {})
assert(ctx.playing, "cmd:transport:play did not start the transport")

-- Advance the sequencer by manual stepping (no realtime clock here).
local steps = tonumber(arg and arg[1]) or 16
for _ = 1, steps do
  for t = 1, track_mod.NUM_TRACKS do
    sequencer.step_track(ctx, t)
  end
end

ctx.events:emit("cmd:transport:stop", {})
assert(not ctx.playing, "cmd:transport:stop did not stop the transport")

-- Report what played.
local total_notes = 0
for t = 1, track_mod.NUM_TRACKS do
  local notes = voices[t]:get_notes()
  total_notes = total_notes + #notes
  local preview = {}
  for i = 1, math.min(#notes, 8) do preview[i] = tostring(notes[i]) end
  print(string.format("  track %d: %2d notes  [%s%s]",
    t, #notes, table.concat(preview, " "), #notes > 8 and " ..." or ""))
end
print(string.format("  facts: %d sequencer:step, %d voice:note",
  fact_counts.step or 0, fact_counts.note or 0))

app.cleanup(ctx)

if total_notes == 0 then
  io.stderr:write("FAIL: no notes played over " .. steps .. " steps\n")
  os.exit(1)
end
print("ok — " .. total_notes .. " notes over " .. steps .. " steps")
