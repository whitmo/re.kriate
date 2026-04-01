-- test_drums_roundtrip.lua
-- OSC round-trip verification for re.kriate drum voice <-> SuperCollider
--
-- Run with SuperCollider drum listener (rekriate_drums.scd) active:
--   seamstress -s examples/supercollider/test_drums_roundtrip.lua
--
-- Check both:
--   - Terminal output: shows sent messages
--   - SC post window: shows received messages

local target = {"127.0.0.1", 57120}
local sent = 0

local drum_names = {"kick", "snare", "hat", "perc"}

local function send(path, args)
  osc.send(target, path, args)
  sent = sent + 1
end

function init()
  clock.run(function()
    print("")
    print("=== re.kriate DRUM OSC round-trip test ===")
    print("Target: 127.0.0.1:57120")
    print("Drum mapping: MIDI note % 4 (0=kick, 1=snare, 2=hat, 3=perc)")
    print("")

    for track = 1, 4 do
      local prefix = "/rekriate/track/" .. track

      -- 1. Set portamento (drums mostly ignore, but test the path)
      print(("  [track %d] drum_portamento: 0.1s"):format(track))
      send(prefix .. "/drum_portamento", {0.1})
      clock.sleep(0.1)

      -- 2. Play each drum type via MIDI note selection
      for drum_idx = 0, 3 do
        -- Choose MIDI note that maps to this drum type: base + drum_idx
        local midi_note = 60 + drum_idx + (track - 1) * 12
        local vel = 0.5 + drum_idx * 0.1
        local dur = 0.1 + drum_idx * 0.1
        print(("  [track %d] drum %s: midi=%d vel=%.1f dur=%.1f"):format(
          track, drum_names[drum_idx + 1], midi_note, vel, dur))
        send(prefix .. "/drum", {midi_note, vel, dur})
        clock.sleep(0.3)
      end

      -- 3. Drum off for the last note
      local last_note = 60 + 3 + (track - 1) * 12
      print(("  [track %d] drum_off: midi=%d"):format(track, last_note))
      send(prefix .. "/drum_off", {last_note})
      clock.sleep(0.1)

      -- 4. All drums off
      print(("  [track %d] all_drums_off"):format(track))
      send(prefix .. "/all_drums_off", {})
      clock.sleep(0.2)

      print("")
    end

    print("=== Summary ===")
    print("  Message types exercised: drum, drum_off, all_drums_off, drum_portamento")
    print(("  Total messages sent: %d"):format(sent))
    print("  Tracks tested: 1-4")
    print("  Drum types tested: kick, snare, hat, perc (via MIDI note % 4)")
    print("")
    print("  NOTE: OSC uses UDP (fire-and-forget).")
    print("  Check the SuperCollider post window to confirm messages were received.")
    print("")
  end)
end
