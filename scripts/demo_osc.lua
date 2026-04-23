-- demo_osc.lua
-- Demonstrates the OSC voice backend for re.kriate
--
-- Prerequisites:
--   - SuperCollider running with rekriate-voice.scd evaluated
--     (or any OSC listener on port 57120)
--   - seamstress 1.4.7+
--
-- Usage:
--   seamstress -s scripts/demo_osc.lua
--
-- What it does:
--   1. Creates an OSC voice targeting localhost:57120
--   2. Plays a melodic phrase on track 1
--   3. Demonstrates portamento (pitch glide via SC's Lag)
--   4. Shows multi-track output (tracks 1 and 2 simultaneously)

local osc_voice = require("lib/voices/osc")

local HOST = "127.0.0.1"
local PORT = 57120

function init()
  print("")
  print("=== re.kriate OSC voice demo ===")
  print("Target: " .. HOST .. ":" .. PORT)
  print("Ensure SuperCollider is running with sc/rekriate-voice.scd evaluated.")
  print("")

  -- Create OSC voices for tracks 1 and 2
  local v1 = osc_voice.new(1, HOST, PORT)
  local v2 = osc_voice.new(2, HOST, PORT)

  clock.run(function()
    -- Play a phrase on track 1
    local phrase = {60, 63, 67, 70, 72}
    print("-- Track 1: minor pentatonic phrase --")
    for _, note in ipairs(phrase) do
      local vel = 0.7
      local dur = 0.5
      print(("  [track 1] note=%d vel=%.1f dur=%.1f"):format(note, vel, dur))
      v1:play_note(note, vel, dur)
      clock.sync(0.5)
    end

    clock.sync(1)

    -- Demonstrate portamento on track 1
    print("")
    print("-- Track 1: portamento (glide) --")
    v1:set_portamento(0.3)
    print("  portamento set to 0.3s")

    local glide = {60, 72, 65, 69}
    for _, note in ipairs(glide) do
      print(("  [track 1] note=%d vel=0.8 dur=1.0"):format(note))
      v1:play_note(note, 0.8, 1.0)
      clock.sync(1.0)
    end

    v1:set_portamento(0)
    print("  portamento off")
    clock.sync(0.5)

    -- Multi-track: tracks 1 and 2 playing together
    print("")
    print("-- Tracks 1 + 2: simultaneous playback --")
    for i = 1, 4 do
      local n1 = 48 + (i - 1) * 5  -- bass line on track 1
      local n2 = 72 + (i - 1) * 3  -- melody on track 2
      print(("  [track 1] note=%d  [track 2] note=%d"):format(n1, n2))
      v1:play_note(n1, 0.6, 0.75)
      v2:play_note(n2, 0.7, 0.5)
      clock.sync(0.75)
    end

    clock.sync(1)

    -- Clean up
    v1:all_notes_off()
    v2:all_notes_off()
    print("")
    print("-- all_notes_off (both tracks) --")
    print("Demo complete.")
  end)
end
