-- demo_sc_drums.lua
-- Demonstrates the SuperCollider drum voice backend for re.kriate
--
-- Prerequisites:
--   - SuperCollider running with examples/supercollider/rekriate_drums.scd evaluated
--   - seamstress 1.4.7+
--
-- Usage:
--   seamstress -s scripts/demo_sc_drums.lua
--
-- What it does:
--   1. Creates an sc_drums voice targeting localhost:57120
--   2. Plays each drum type: kick, snare, hat, perc
--   3. Plays a simple drum pattern (kick + hat + snare backbeat)
--   4. Demonstrates velocity dynamics

local sc_drums = require("lib/voices/sc_drums")

local HOST = "127.0.0.1"
local PORT = 57120

-- Drum type is selected by MIDI note % 4:
--   0 = kick, 1 = snare, 2 = hat, 3 = perc
-- We pick base notes that map to each type at a useful pitch.
local KICK  = 60  -- 60 % 4 = 0 -> kick
local SNARE = 61  -- 61 % 4 = 1 -> snare
local HAT   = 62  -- 62 % 4 = 2 -> hat
local PERC  = 63  -- 63 % 4 = 3 -> perc

function init()
  print("")
  print("=== re.kriate SC drums demo ===")
  print("Target: " .. HOST .. ":" .. PORT)
  print("Ensure SuperCollider is running with examples/supercollider/rekriate_drums.scd.")
  print("")
  print("Drum mapping (MIDI note %% 4):")
  print("  0 = kick, 1 = snare, 2 = hat, 3 = perc")
  print("")

  local drums = sc_drums.new(1, HOST, PORT)

  clock.run(function()
    -- Individual drum hits: one of each
    print("-- Individual drum hits --")
    local hits = {
      {KICK,  "kick",  0.8, 0.5},
      {SNARE, "snare", 0.7, 0.2},
      {HAT,   "hat",   0.5, 0.05},
      {PERC,  "perc",  0.6, 0.3},
    }

    for _, hit in ipairs(hits) do
      local note, name, vel, dur = hit[1], hit[2], hit[3], hit[4]
      print(("  %s: midi=%d vel=%.1f dur=%.2f"):format(name, note, vel, dur))
      drums:play_note(note, vel, dur)
      clock.sync(0.75)
    end

    clock.sync(1)

    -- Velocity dynamics: hat at increasing velocity
    print("")
    print("-- Velocity dynamics (hat, soft to loud) --")
    for v = 1, 7 do
      local vel = v / 7
      print(("  hat: vel=%.2f"):format(vel))
      drums:play_note(HAT, vel, 0.05)
      clock.sync(0.25)
    end

    clock.sync(1)

    -- Simple drum pattern: 2 bars of kick + hat + snare backbeat
    print("")
    print("-- 2-bar pattern: kick + hat + snare backbeat --")
    -- 16 sixteenth notes per bar, 2 bars = 32 steps
    local pattern = {}
    for step = 1, 32 do
      local events = {}
      -- Hat on every step (alternating velocity)
      events[#events + 1] = {HAT, step % 2 == 1 and 0.5 or 0.3, 0.03}
      -- Kick on beats 1 and 3 (steps 1, 9, 17, 25)
      if (step - 1) % 8 == 0 then
        events[#events + 1] = {KICK, 0.8, 0.4}
      end
      -- Snare on beats 2 and 4 (steps 5, 13, 21, 29)
      if (step - 1) % 8 == 4 then
        events[#events + 1] = {SNARE, 0.7, 0.15}
      end
      pattern[step] = events
    end

    for step, events in ipairs(pattern) do
      local names = {}
      for _, e in ipairs(events) do
        drums:play_note(e[1], e[2], e[3])
        if e[1] == KICK then names[#names + 1] = "K"
        elseif e[1] == SNARE then names[#names + 1] = "S"
        elseif e[1] == HAT then names[#names + 1] = "h"
        end
      end
      if step <= 16 then  -- only print first bar to keep output readable
        print(("  step %2d: %s"):format(step, table.concat(names, "+")))
      end
      clock.sync(0.25)
    end

    clock.sync(0.5)

    -- Clean up
    drums:all_notes_off()
    print("")
    print("-- all_drums_off --")
    print("Demo complete.")
  end)
end
