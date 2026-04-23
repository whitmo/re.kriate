-- demo_sprite.lua
-- Demonstrates the sprite (visual) voice backend for re.kriate
--
-- Prerequisites:
--   - seamstress 1.4.7+ (sprites render on the seamstress screen)
--   - Works on norns too (128x64 OLED), but sprite display is designed for 256px wide
--
-- Usage:
--   seamstress -s scripts/demo_sprite.lua
--
-- What it does:
--   1. Creates sprite voices for 4 tracks (each with a distinct color palette)
--   2. Fires sprite events showing shape, position, and color mapping
--   3. Demonstrates ratchet brightness blending
--   4. Demonstrates ghost sprites (muted track visualization)
--   5. Renders active sprites to the screen in a simple draw loop

local sprite_voice = require("lib/voices/sprite")

local sprites = {}
local running = true

function init()
  print("")
  print("=== re.kriate sprite voice demo ===")
  print("")
  print("Sprite maps sequencer parameters to visual events:")
  print("  note (1-7)     -> shape (circle, rect, triangle, diamond, star, line, dot)")
  print("  octave (1-7)   -> Y position (high octave = top of screen)")
  print("  velocity (1-7) -> size (higher velocity = larger)")
  print("  step position  -> X position (follows playhead)")
  print("")
  print("Track colors:")
  for t = 1, 4 do
    local c = sprite_voice.TRACK_COLORS[t]
    print(("  track %d: rgb(%d, %d, %d)"):format(t, c[1], c[2], c[3]))
  end
  print("")

  -- Create sprite voices for all 4 tracks
  for t = 1, 4 do
    sprites[t] = sprite_voice.new(t)
  end

  clock.run(function()
    -- Fire sprites from each track, varying parameters
    print("-- Spawning sprites across 4 tracks --")

    -- Track 1: ascending shapes (note 1-7)
    print("  Track 1: all 7 shapes")
    for note = 1, 7 do
      sprites[1]:play({
        note = note,
        octave = 4,
        velocity = 4,
        alt_note = 4,
        ratchet = 1,
        glide = 1,
      }, 2.0, {step = note * 2, loop_len = 16})
      clock.sync(0.3)
    end

    clock.sync(0.5)

    -- Track 2: velocity sizes (small to large)
    print("  Track 2: velocity sweep (size 1-7)")
    for vel = 1, 7 do
      sprites[2]:play({
        note = 1,       -- circle
        octave = 5,
        velocity = vel,
        alt_note = 4,
        ratchet = 1,
        glide = 1,
      }, 2.0, {step = vel * 2, loop_len = 16})
      clock.sync(0.3)
    end

    clock.sync(0.5)

    -- Track 3: octave positions (vertical spread)
    print("  Track 3: octave sweep (Y positions 1-7)")
    for oct = 1, 7 do
      sprites[3]:play({
        note = 4,       -- diamond
        octave = oct,
        velocity = 4,
        alt_note = 4,
        ratchet = 1,
        glide = 1,
      }, 2.0, {step = 8, loop_len = 16})
      clock.sync(0.3)
    end

    clock.sync(0.5)

    -- Track 4: ratchet brightness
    print("  Track 4: ratchet intensity (1=base color, 7=white)")
    for ratch = 1, 7 do
      sprites[4]:play({
        note = 5,       -- star
        octave = 3,
        velocity = 5,
        alt_note = 4,
        ratchet = ratch,
        glide = 1,
      }, 2.0, {step = ratch * 2, loop_len = 16})
      clock.sync(0.3)
    end

    clock.sync(1)

    -- Ghost sprites (muted track)
    print("")
    print("-- Ghost sprite (muted=true, 10%% alpha) --")
    sprites[1]:play({
      note = 3,
      octave = 4,
      velocity = 5,
      alt_note = 4,
      ratchet = 1,
      glide = 1,
    }, 3.0, {step = 8, loop_len = 16, muted = true})

    -- Print active event counts
    clock.sync(0.5)
    print("")
    print("-- Active sprite counts --")
    for t = 1, 4 do
      local events = sprites[t]:get_active_events()
      print(("  track %d: %d active events"):format(t, #events))
    end

    -- Let sprites decay
    print("")
    print("Sprites will fade after their duration expires.")
    clock.sync(4)

    -- Show cleanup
    for t = 1, 4 do
      sprites[t]:all_notes_off()
    end
    running = false

    print("")
    print("-- all_notes_off (all tracks) --")
    print("Demo complete.")
  end)
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(2, 8)
  screen.text("sprite voice demo")

  -- Draw active sprites as simple shapes
  for t = 1, 4 do
    if sprites[t] then
      local events = sprites[t]:get_active_events()
      for _, e in ipairs(events) do
        -- Map color alpha to screen level (0-15)
        local level = math.floor(e.color[4] / 255 * 15)
        screen.level(level)

        -- Scale positions for 128x64 norns screen
        local x = math.floor(e.x / 256 * 128)
        local y = math.floor(e.y / 128 * 64)
        local sz = math.max(1, math.floor(e.size / 2))

        local shape = sprite_voice.SHAPES[e.shape] or "dot"
        if shape == "circle" then
          screen.circle(x, y, sz)
          screen.stroke()
        elseif shape == "rect" then
          screen.rect(x - sz, y - sz, sz * 2, sz * 2)
          screen.stroke()
        elseif shape == "dot" then
          screen.pixel(x, y)
          screen.fill()
        else
          -- Default: filled circle for other shapes
          screen.circle(x, y, sz)
          screen.fill()
        end
      end
    end
  end

  if not running then
    screen.level(8)
    screen.move(2, 60)
    screen.text("complete")
  end

  screen.update()
end
