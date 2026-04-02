-- demo_softcut.lua
-- Demonstrates the softcut sampler voice backend for re.kriate
--
-- Prerequisites:
--   - norns (softcut is a norns-native DSP engine, not available in seamstress)
--   - A .wav sample file on the norns filesystem
--   - seamstress 1.4.7+ can run this demo in "dry" mode using softcut_runtime
--     (no audio output, but demonstrates the API and voice lifecycle)
--
-- Usage (norns):
--   Copy to ~/dust/code/rekriate/scripts/ and run from maiden
--
-- Usage (seamstress, dry mode):
--   seamstress -s scripts/demo_softcut.lua
--
-- What it does:
--   1. Creates a softcut voice with the buffer management runtime
--   2. Configures sample playback parameters
--   3. Plays chromatic notes (pitch-shifted via rate)
--   4. Demonstrates portamento (rate slew)
--   5. Shows loop on/off behavior

local softcut_zig = require("lib/voices/softcut_zig")
local softcut_runtime = require("lib/voices/softcut_runtime")

-- Change this to a real sample path on norns:
--   e.g., "/home/we/dust/audio/common/808/kick.wav"
-- For dry-mode demo, we use a placeholder and inject a fake file_exists.
local SAMPLE_PATH = "/home/we/dust/audio/common/808/kick.wav"

function init()
  print("")
  print("=== re.kriate softcut voice demo ===")
  print("")

  -- Create the buffer management runtime.
  -- On norns, this manages 6 voice slots across 2 mono softcut buffers.
  -- In dry mode (seamstress), it tracks state without producing audio.
  local runtime = softcut_runtime.new({
    -- For dry-mode demo: pretend any file exists
    file_exists = function() return true end,
  })

  print("Runtime created: " .. runtime.num_voices .. " voice slots")
  print("Buffer duration: " .. runtime.buffer_dur .. "s per buffer")
  print("")

  -- Create a softcut voice on slot 1
  local config = {
    sample_path = SAMPLE_PATH,
    root_note = 60,      -- C4 is the sample's native pitch
    start_sec = 0,       -- playback start position in buffer
    end_sec = 1,         -- playback end position in buffer
    loop = false,        -- one-shot playback
    level = 0.8,         -- output level 0.0-1.0
    pan = 0.0,           -- center panned
    attack = 0.01,       -- fade-in time (seconds)
    release = 0.05,      -- fade-out time (seconds)
    rate_slew = 0.0,     -- no pitch glide initially
  }

  local voice = softcut_zig.new(1, runtime, config)

  print("Voice created on slot 1")
  print("  sample: " .. SAMPLE_PATH)
  print("  root_note: " .. config.root_note .. " (C4)")
  print("  region: " .. config.start_sec .. "s - " .. config.end_sec .. "s")
  print("  loop: " .. (config.loop and "on" or "off"))
  print("  available: " .. tostring(voice.available))
  print("")

  clock.run(function()
    -- Play chromatic notes: the voice pitch-shifts by adjusting playback rate.
    -- rate = 2^((note - root_note) / 12)
    print("-- Chromatic playback (C4 to C5) --")
    local notes = {60, 62, 64, 65, 67, 69, 71, 72}
    for _, note in ipairs(notes) do
      local rate = softcut_zig.midi_to_rate(note, config.root_note)
      print(("  note=%d rate=%.3f"):format(note, rate))
      voice:play_note(note, 0.8, 0.5)
      clock.sync(0.5)
    end

    clock.sync(1)

    -- Demonstrate portamento (rate slew)
    print("")
    print("-- Portamento (rate slew between pitches) --")
    voice:set_portamento(0.2)
    print("  rate_slew set to 0.2s")

    local glide = {60, 72, 55, 67}
    for _, note in ipairs(glide) do
      print(("  note=%d"):format(note))
      voice:play_note(note, 0.8, 1.0)
      clock.sync(1.0)
    end

    voice:set_portamento(0)
    print("  portamento off")

    clock.sync(0.5)

    -- Demonstrate loop mode
    print("")
    print("-- Loop mode --")
    voice:apply_config({
      sample_path = SAMPLE_PATH,
      root_note = 60,
      start_sec = 0,
      end_sec = 0.5,
      loop = true,        -- enable looping
      level = 0.8,
      attack = 0.01,
      release = 0.1,
    })
    print("  loop enabled, region: 0s - 0.5s")
    print("  playing C4 for 3 beats (loops within region)...")
    voice:play_note(60, 0.8, 3.0)
    clock.sync(3.0)

    -- Clean up
    voice:all_notes_off()
    print("")
    print("-- all_notes_off --")
    print("Demo complete.")
    if #runtime.warnings > 0 then
      print("")
      print("Runtime warnings:")
      for _, w in ipairs(runtime.warnings) do print("  " .. w) end
    end
  end)
end
