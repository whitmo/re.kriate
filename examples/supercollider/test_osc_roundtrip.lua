-- test_osc_roundtrip.lua
-- OSC round-trip verification for re.kriate <-> SuperCollider
--
-- Run with SuperCollider listener (rekriate_sub.scd) active:
--   seamstress -s examples/supercollider/test_osc_roundtrip.lua
--
-- Check both:
--   - Terminal output: shows sent messages
--   - SC post window: shows received messages

local target = {"127.0.0.1", 57120}
local sent = 0

local function send(path, args)
  osc.send(target, path, args)
  sent = sent + 1
end

function init()
  clock.run(function()
    print("")
    print("=== re.kriate OSC round-trip test ===")
    print("Target: 127.0.0.1:57120")
    print("")

    for track = 1, 4 do
      local prefix = "/rekriate/track/" .. track

      -- 1. Set portamento
      print(("  [track %d] portamento: 0.3s"):format(track))
      send(prefix .. "/portamento", {0.3})
      clock.sleep(0.1)

      -- 2. First note (establishes pitch for glide)
      local note1 = 60 + (track * 4)
      print(("  [track %d] note: midi=%d vel=100 dur=0.5"):format(track, note1))
      send(prefix .. "/note", {note1, 100, 0.5})
      clock.sleep(0.3)

      -- 3. Second note (portamento should glide from first pitch)
      local note2 = 64 + (track * 4)
      print(("  [track %d] note: midi=%d vel=80 dur=0.5"):format(track, note2))
      send(prefix .. "/note", {note2, 80, 0.5})
      clock.sleep(0.3)

      -- 4. All notes off
      print(("  [track %d] all_notes_off"):format(track))
      send(prefix .. "/all_notes_off", {})
      clock.sleep(0.2)

      print("")
    end

    print("=== Summary ===")
    print("  Message types exercised: note, portamento, all_notes_off")
    print(("  Total messages sent: %d"):format(sent))
    print("  Tracks tested: 1-4")
    print("")
    print("  NOTE: OSC uses UDP (fire-and-forget).")
    print("  Check the SuperCollider post window to confirm messages were received.")
    print("")
  end)
end
