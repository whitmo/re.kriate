-- demo_midi.lua
-- Demonstrates the MIDI voice backend for re.kriate
--
-- Prerequisites:
--   - A MIDI device connected (hardware synth, DAW, virtual MIDI port)
--   - seamstress 1.4.7+
--
-- Usage:
--   seamstress -s scripts/demo_midi.lua
--
-- What it does:
--   1. Connects to the first available MIDI device
--   2. Plays a short ascending phrase on channel 1
--   3. Demonstrates portamento (glide between notes)
--   4. Sends all-notes-off to clean up

local midi_voice = require("lib/voices/midi")

local voice
local midi_dev

function init()
  -- Connect to the first MIDI device
  midi_dev = midi.connect(1)
  print("")
  print("=== re.kriate MIDI voice demo ===")
  print("MIDI device: " .. (midi_dev.name or "device 1"))
  print("Channel: 1")
  print("")

  -- Create a MIDI voice on channel 1
  voice = midi_voice.new(midi_dev, 1)

  clock.run(function()
    -- Play an ascending C major phrase: C4, E4, G4, C5
    local notes = {60, 64, 67, 72}
    local vel = 0.8   -- velocity 0.0-1.0
    local dur = 0.5   -- duration in beats

    print("-- Playing ascending phrase (C E G C) --")
    for i, note in ipairs(notes) do
      print(("  note_on: %d  vel: %.0f  dur: %.1f beats"):format(
        note, vel * 127, dur))
      voice:play_note(note, vel, dur)
      clock.sync(0.75)  -- space between notes
    end

    clock.sync(1)

    -- Demonstrate portamento (glide)
    print("")
    print("-- Portamento demo (glide between notes) --")
    voice:set_portamento(3)  -- moderate glide time
    print("  portamento set to 3 (CC 65=on, CC 5=54)")

    local glide_notes = {60, 72, 55, 67}
    for _, note in ipairs(glide_notes) do
      print(("  note_on: %d  vel: %.0f  dur: 1.0 beats"):format(note, vel * 127))
      voice:play_note(note, vel, 1.0)
      clock.sync(1.0)
    end

    -- Disable portamento
    voice:set_portamento(0)
    print("  portamento off")

    clock.sync(0.5)

    -- Clean up
    voice:all_notes_off()
    print("")
    print("-- all_notes_off sent --")
    print("Demo complete.")
  end)
end
