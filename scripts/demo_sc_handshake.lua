-- scripts/demo_sc_handshake.lua
-- Demonstrates the re.kriate ↔ SuperCollider handshake.
--
-- Prerequisites:
--   - SuperCollider running with one of:
--       bin/start-sc                                (full bootstrap)
--       sc/rekriate-voice.scd evaluated             (voice/mixer only)
--       examples/supercollider/rekriate_synths.scd  (sc_synth only)
--       examples/supercollider/rekriate_drums.scd   (sc_drums only)
--   - seamstress 1.4.7+
--
-- Usage:
--   seamstress -s scripts/demo_sc_handshake.lua
--
-- What it does:
--   1. Creates an sc_bridge targeting localhost:57120
--   2. Chains the bridge into osc.event so pongs from SC flow in
--   3. Sends a ping, waits, prints the resulting connection state
--   4. Repeats 3 times to exercise the pong-merge window

local sc_bridge = require("lib/sc_bridge")

local SC_HOST = "127.0.0.1"
local SC_PORT = 57120
local REPLY_PORT = 7000  -- seamstress default OSC listen port

function init()
  print("")
  print("=== re.kriate ↔ SuperCollider handshake demo ===")
  print("SC target : " .. SC_HOST .. ":" .. SC_PORT)
  print("Reply on  : localhost:" .. REPLY_PORT)
  print("")

  local bridge = sc_bridge.new({
    host = SC_HOST,
    port = SC_PORT,
    reply_host = "127.0.0.1",
    reply_port = REPLY_PORT,
    timeout = 1.5,
  })

  -- Chain bridge:handle_osc into the global osc.event dispatcher.
  local prev_handler = osc.event
  osc.event = function(path, args, from)
    if bridge:handle_osc(path, args, from) then
      return
    end
    if prev_handler then prev_handler(path, args, from) end
  end

  bridge:on_pong(function(br)
    print(("  ← pong: version=%s features=[%s]"):format(
      br.version or "?", table.concat(br.features, ", ")))
  end)

  clock.run(function()
    for round = 1, 3 do
      print(("-- round %d: sending ping"):format(round))
      bridge:ping()
      clock.sleep(1.0)
      bridge:tick()
      print("  status: " .. bridge:status_string())
      clock.sleep(0.5)
    end

    print("")
    if bridge:is_connected() then
      print("Handshake OK — re.kriate and SuperCollider are talking.")
    else
      print("No pong received. Is SC running with a companion .scd loaded?")
      print("Try: bin/start-sc")
    end
    print("Demo complete.")
  end)
end
