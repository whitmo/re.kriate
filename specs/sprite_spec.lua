-- specs/sprite_spec.lua
-- Tests for sprite voice backend and renderer

package.path = package.path .. ";./?.lua"

-- Mock clock
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock screen for renderer tests
local screen_calls = {}
rawset(_G, "screen", {
  color = function(r, g, b, a) table.insert(screen_calls, {fn = "color", r = r, g = g, b = b, a = a}) end,
  move = function(x, y) table.insert(screen_calls, {fn = "move", x = x, y = y}) end,
  circle_fill = function(r) table.insert(screen_calls, {fn = "circle_fill", r = r}) end,
  rect_fill = function(w, h) table.insert(screen_calls, {fn = "rect_fill", w = w, h = h}) end,
  triangle = function(ax, ay, bx, by, cx, cy) table.insert(screen_calls, {fn = "triangle"}) end,
  quad = function(ax, ay, bx, by, cx, cy, dx, dy) table.insert(screen_calls, {fn = "quad"}) end,
  line = function(bx, by) table.insert(screen_calls, {fn = "line"}) end,
  pixel = function(x, y) table.insert(screen_calls, {fn = "pixel"}) end,
})

local sprite = require("lib/voices/sprite")
local sprite_render = require("lib/seamstress/sprite_render")

-- Helper: count events by type
local function count_events(events, field, value)
  local n = 0
  for _, e in ipairs(events) do
    if e[field] == value then n = n + 1 end
  end
  return n
end

-- Helper: find first event by field
local function find_event(events, field, value)
  for _, e in ipairs(events) do
    if e[field] == value then return e end
  end
  return nil
end

-- Helper: count screen calls by fn name
local function count_screen_calls(fn_name)
  local n = 0
  for _, call in ipairs(screen_calls) do
    if call.fn == fn_name then n = n + 1 end
  end
  return n
end

-- Helper: find screen calls by fn name
local function find_screen_call(fn_name)
  for _, call in ipairs(screen_calls) do
    if call.fn == fn_name then return call end
  end
  return nil
end

describe("sprite voice", function()

  before_each(function()
    beat_counter = 0
  end)

  describe("construction", function()
    it("creates a sprite voice for a track", function()
      local sv = sprite.new(1)
      assert.are.equal(1, sv.track_num)
      assert.are.same({}, sv.active_events)
    end)

    it("assigns track color palette", function()
      local sv1 = sprite.new(1)
      assert.are.same({255, 120, 50, 255}, sv1.base_color)
      local sv2 = sprite.new(2)
      assert.are.same({50, 180, 255, 255}, sv2.base_color)
      local sv3 = sprite.new(3)
      assert.are.same({80, 230, 120, 255}, sv3.base_color)
      local sv4 = sprite.new(4)
      assert.are.same({200, 80, 255, 255}, sv4.base_color)
    end)

    it("falls back to track 1 color for unknown track", function()
      local sv = sprite.new(5)
      assert.are.same({255, 120, 50, 255}, sv.base_color)
    end)
  end)

  describe("play", function()
    it("spawns a main sprite event from kria vals", function()
      local sv = sprite.new(1)
      local vals = {note = 3, octave = 5, alt_note = 2, velocity = 6}
      sv:play(vals, 0.5, {step = 4, loop_len = 16})

      -- Main sprite is first event
      local e = sv.active_events[1]
      assert.are.equal(3, e.shape)
      -- X from step position: step 4 of 16 across 256px
      assert.are.equal(sprite.step_to_x(4, 16), e.x)
      assert.are.equal(sprite.Y_MAP[5], e.y)
      assert.are.equal(sprite.SIZE_MAP[6], e.size)
      assert.are.equal(0.5, e.duration)
      assert.are.equal(0, e.spawn_beat)
      assert.is_false(e.is_echo)
    end)

    it("records spawn_beat from clock", function()
      beat_counter = 8.5
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      assert.are.equal(8.5, sv.active_events[1].spawn_beat)
    end)

    it("uses track color", function()
      local sv = sprite.new(2)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      assert.are.same({50, 180, 255, 255}, sv.active_events[1].color)
    end)

    it("handles missing vals with defaults", function()
      local sv = sprite.new(1)
      sv:play({}, 1)
      local e = sv.active_events[1]
      assert.are.equal(1, e.shape)
      assert.are.equal(128, e.x)  -- default alt_note=4 -> 128
      assert.are.equal(64, e.y)   -- default octave=4 -> 64
      assert.are.equal(10, e.size) -- default velocity=4 -> 10
    end)

    it("accumulates multiple events (main + echo per play)", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      sv:play({note = 3, octave = 2, alt_note = 6, velocity = 7}, 0.5)
      -- 2 plays = 2 main + 2 echo = 4 events
      assert.are.equal(4, #sv.active_events)
    end)

    it("distributes sprites spatially across steps", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 1, velocity = 4}, 1, {step = 1, loop_len = 16})
      sv:play({note = 3, octave = 4, alt_note = 1, velocity = 4}, 1, {step = 8, loop_len = 16})
      sv:play({note = 5, octave = 4, alt_note = 1, velocity = 4}, 1, {step = 16, loop_len = 16})

      local e1 = sv.active_events[1]  -- step 1
      local e2 = sv.active_events[3]  -- step 8
      local e3 = sv.active_events[5]  -- step 16

      -- Different steps must produce different X positions
      assert.are_not.equal(e1.x, e2.x)
      assert.are_not.equal(e2.x, e3.x)
      assert.are_not.equal(e1.x, e3.x)

      -- Verify they match expected step-based positions
      assert.are.equal(sprite.step_to_x(1, 16), e1.x)
      assert.are.equal(sprite.step_to_x(8, 16), e2.x)
      assert.are.equal(sprite.step_to_x(16, 16), e3.x)

      -- Step 1 should be near left, step 16 near right
      assert.is_true(e1.x < 32)
      assert.is_true(e3.x > 224)
    end)

    it("falls back to effective degree for X when no step info", function()
      local sv = sprite.new(1)
      -- note=3, alt_note=4 -> effective = ((3-1)+(4-1))%7+1 = 6
      sv:play({note = 3, octave = 4, alt_note = 4, velocity = 4}, 1)
      local e = sv.active_events[1]
      assert.are.equal(sprite.X_MAP[6], e.x)
    end)

    it("uses step position for X when step info provided", function()
      local sv = sprite.new(1)
      sv:play({note = 3, octave = 4, alt_note = 4, velocity = 4}, 1, {step = 10, loop_len = 16})
      local e = sv.active_events[1]
      assert.are.equal(sprite.step_to_x(10, 16), e.x)
      -- Step 10 of 16 should be past center
      assert.is_true(e.x > 128)
    end)

    it("spans full display width across 16 steps", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1, {step = 1, loop_len = 16})
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1, {step = 16, loop_len = 16})
      local e_first = sv.active_events[1]
      local e_last = sv.active_events[3]  -- skip echo at [2]
      -- First step near left edge, last step near right edge
      assert.is_true(e_first.x < 20)
      assert.is_true(e_last.x > 236)
      -- Total span should cover most of the 256px width
      assert.is_true(e_last.x - e_first.x > 200)
    end)

    it("stores track_num on events", function()
      local sv = sprite.new(3)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      assert.are.equal(3, sv.active_events[1].track_num)
    end)
  end)

  describe("echo sprites", function()
    it("spawns an echo sprite alongside main sprite", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)

      assert.are.equal(2, #sv.active_events)
      local main = sv.active_events[1]
      local echo = sv.active_events[2]
      assert.is_false(main.is_echo)
      assert.is_true(echo.is_echo)
    end)

    it("echo has larger size than main", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)

      local main = sv.active_events[1]
      local echo = sv.active_events[2]
      assert.are.equal(main.size * sprite.ECHO_SIZE_MULT, echo.size)
    end)

    it("echo has lower alpha than main", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)

      local main = sv.active_events[1]
      local echo = sv.active_events[2]
      assert.are.equal(math.floor(main.color[4] * sprite.ECHO_ALPHA_MULT), echo.color[4])
    end)

    it("echo has longer duration than main", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)

      local main = sv.active_events[1]
      local echo = sv.active_events[2]
      assert.are.equal(main.duration * sprite.ECHO_DURATION_MULT, echo.duration)
    end)

    it("echo has same position as main", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)

      local main = sv.active_events[1]
      local echo = sv.active_events[2]
      assert.are.equal(main.x, echo.x)
      assert.are.equal(main.y, echo.y)
    end)

    it("echo has same shape as main", function()
      local sv = sprite.new(1)
      sv:play({note = 3, octave = 4, alt_note = 4, velocity = 4}, 1)

      local main = sv.active_events[1]
      local echo = sv.active_events[2]
      assert.are.equal(main.shape, echo.shape)
    end)
  end)

  describe("ratchet visual flag", function()
    it("stores ratchet value on events", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4, ratchet = 3}, 1)
      assert.are.equal(3, sv.active_events[1].ratchet)
    end)

    it("ratcheted notes have brighter/whiter color", function()
      local sv = sprite.new(1)
      -- Normal note
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4, ratchet = 1}, 1)
      local normal = sv.active_events[1]
      -- Ratcheted note
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4, ratchet = 5}, 1)
      local ratcheted = sv.active_events[3]  -- skip echo at [2]

      -- Ratcheted should be closer to white (higher RGB values)
      assert.is_true(ratcheted.color[1] >= normal.color[1])
      assert.is_true(ratcheted.color[2] >= normal.color[2])
      assert.is_true(ratcheted.color[3] >= normal.color[3])
      -- At least one channel should be strictly brighter
      assert.is_true(
        ratcheted.color[1] > normal.color[1] or
        ratcheted.color[2] > normal.color[2] or
        ratcheted.color[3] > normal.color[3]
      )
    end)

    it("ratchet=1 produces unmodified base color", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4, ratchet = 1}, 1)
      local e = sv.active_events[1]
      assert.are.equal(255, e.color[1])  -- track 1 base red
      assert.are.equal(120, e.color[2])  -- track 1 base green
      assert.are.equal(50, e.color[3])   -- track 1 base blue
    end)
  end)

  describe("glide visual flag", function()
    it("stores glide value on events", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4, glide = 4}, 1)
      assert.are.equal(4, sv.active_events[1].glide)
    end)

    it("sets glide_from when glide > 1 and previous event exists", function()
      local sv = sprite.new(1)
      -- First note (no glide_from since no previous)
      sv:play({note = 1, octave = 3, alt_note = 2, velocity = 4, glide = 3}, 1)
      assert.is_nil(sv.active_events[1].glide_from)

      -- Second note with glide -- should reference first note position
      sv:play({note = 2, octave = 5, alt_note = 6, velocity = 4, glide = 3}, 1)
      local second = sv.active_events[3]  -- skip echo at [2]
      assert.is_not_nil(second.glide_from)
      assert.are.equal(sprite.X_MAP[2], second.glide_from.x)
      assert.are.equal(sprite.Y_MAP[3], second.glide_from.y)
    end)

    it("no glide_from when glide == 1", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 3, alt_note = 2, velocity = 4}, 1)
      sv:play({note = 2, octave = 5, alt_note = 6, velocity = 4, glide = 1}, 1)
      local second = sv.active_events[3]
      assert.is_nil(second.glide_from)
    end)
  end)

  describe("muted tracks (ghost sprites)", function()
    it("produces ghost sprites with very low alpha when muted", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1, {muted = true})
      local e = sv.active_events[1]
      assert.is_true(e.is_ghost)
      -- Alpha should be 10% of base (255 * 0.1 = 25)
      assert.are.equal(math.floor(255 * 0.1), e.color[4])
    end)

    it("does not spawn echo for muted notes", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1, {muted = true})
      -- Only main ghost sprite, no echo
      assert.are.equal(1, #sv.active_events)
      assert.is_true(sv.active_events[1].is_ghost)
    end)

    it("non-muted notes are not ghosts", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      assert.is_false(sv.active_events[1].is_ghost)
    end)
  end)

  describe("get_active_events", function()
    it("returns non-expired events", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
      beat_counter = 1
      local events = sv:get_active_events()
      -- Both main and echo still alive
      assert.are.equal(2, #events)
    end)

    it("prunes expired events", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      beat_counter = 5  -- well past both main (1) and echo (1.5) durations
      local events = sv:get_active_events()
      assert.are.equal(0, #events)
    end)

    it("keeps young events and prunes old ones", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      beat_counter = 0.5
      sv:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 2)
      beat_counter = 1.6  -- past first main (1) and first echo (1.5), but not second
      local events = sv:get_active_events()
      -- Second pair (main dur=2 and echo dur=3) both alive
      assert.are.equal(2, #events)
      -- Surviving main event should be shape 2
      local main = find_event(events, "is_echo", false)
      assert.are.equal(2, main.shape)
    end)
  end)

  describe("all_notes_off", function()
    it("clears all active events", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 10)
      sv:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 10)
      assert.are.equal(4, #sv.active_events)  -- 2 main + 2 echo
      sv:all_notes_off()
      assert.are.equal(0, #sv.active_events)
    end)

    it("clears last_event reference", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      assert.is_not_nil(sv.last_event)
      sv:all_notes_off()
      assert.is_nil(sv.last_event)
    end)
  end)

  describe("parameter maps", function()
    it("has 7 shapes", function()
      assert.are.equal(7, #sprite.SHAPES)
    end)

    it("maps all 7 velocity values to sizes", function()
      for v = 1, 7 do
        assert.is_not_nil(sprite.SIZE_MAP[v])
      end
      -- sizes increase with velocity
      for v = 2, 7 do
        assert.is_true(sprite.SIZE_MAP[v] > sprite.SIZE_MAP[v - 1])
      end
    end)

    it("maps all 7 octave values to Y positions", function()
      for o = 1, 7 do
        assert.is_not_nil(sprite.Y_MAP[o])
      end
      -- higher octave = lower Y (higher on screen)
      for o = 2, 7 do
        assert.is_true(sprite.Y_MAP[o] < sprite.Y_MAP[o - 1])
      end
    end)

    it("maps all 7 alt_note values to X positions", function()
      for a = 1, 7 do
        assert.is_not_nil(sprite.X_MAP[a])
      end
      -- higher alt_note = higher X (further right)
      for a = 2, 7 do
        assert.is_true(sprite.X_MAP[a] > sprite.X_MAP[a - 1])
      end
    end)

    it("has 4 track colors", function()
      for t = 1, 4 do
        assert.is_not_nil(sprite.TRACK_COLORS[t])
        assert.are.equal(4, #sprite.TRACK_COLORS[t])
      end
    end)
  end)

  describe("step_to_x", function()
    it("maps step 1 of 16 near left edge", function()
      local x = sprite.step_to_x(1, 16)
      assert.is_true(x >= 0 and x < 20)
    end)

    it("maps step 16 of 16 near right edge", function()
      local x = sprite.step_to_x(16, 16)
      assert.is_true(x > 236 and x <= 256)
    end)

    it("maps step 8 of 16 near center", function()
      local x = sprite.step_to_x(8, 16)
      assert.is_true(x > 100 and x < 140)
    end)

    it("increases monotonically with step", function()
      for s = 2, 16 do
        assert.is_true(sprite.step_to_x(s, 16) > sprite.step_to_x(s - 1, 16))
      end
    end)

    it("handles short loops", function()
      -- 4-step loop should still span width
      local x1 = sprite.step_to_x(1, 4)
      local x4 = sprite.step_to_x(4, 4)
      assert.is_true(x4 - x1 > 150)
    end)

    it("returns center for invalid input", function()
      assert.are.equal(128, sprite.step_to_x(nil, 16))
      assert.are.equal(128, sprite.step_to_x(1, nil))
      assert.are.equal(128, sprite.step_to_x(1, 0))
    end)
  end)
end)

describe("sprite renderer", function()

  before_each(function()
    beat_counter = 0
    screen_calls = {}
  end)

  describe("beat grid", function()
    it("draws beat grid lines", function()
      sprite_render.draw({})
      -- Should have drawn 4 vertical grid lines (move + line each)
      local line_count = count_screen_calls("line")
      assert.is_true(line_count >= 4)
    end)

    it("beat grid has bright flash at beat boundary", function()
      beat_counter = 0.0  -- exactly on beat
      sprite_render.draw({})
      -- First color call should be for beat grid, alpha should be 80 (bright)
      local color_call = screen_calls[1]
      assert.are.equal("color", color_call.fn)
      assert.are.equal(80, color_call.a)
    end)

    it("beat grid is dim off-beat", function()
      beat_counter = 0.5  -- mid-beat
      sprite_render.draw({})
      local color_call = screen_calls[1]
      assert.are.equal("color", color_call.fn)
      assert.are.equal(20, color_call.a)
    end)
  end)

  describe("playhead indicators", function()
    it("draws playhead dots for tracks", function()
      local ctx = {
        tracks = {
          {params = {trigger = {pos = 4, loop_end = 16}}},
          {params = {trigger = {pos = 8, loop_end = 16}}},
        },
      }
      sprite_render.draw(ctx)
      -- Should have circle_fill calls for playhead dots
      local circle_count = count_screen_calls("circle_fill")
      assert.is_true(circle_count >= 2)
    end)

    it("does nothing without tracks", function()
      screen_calls = {}
      -- draw_playheads is called inside draw() -- just verify no crash
      sprite_render.draw_playheads({})
      assert.are.equal(0, #screen_calls)
    end)
  end)

  describe("sprite rendering", function()
    it("draws active events with correct color", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}

      sprite_render.draw(ctx)

      -- Find sprite color calls (after beat grid color calls)
      local color_calls = {}
      for _, call in ipairs(screen_calls) do
        if call.fn == "color" then table.insert(color_calls, call) end
      end
      -- Should have: beat grid color, then sprite colors (main + echo)
      assert.is_true(#color_calls >= 3)
      -- Last two sprite color calls should have track 1's orange hue
      local main_color = color_calls[#color_calls - 1]
      assert.are.equal(255, main_color.r)
      assert.are.equal(120, main_color.g)
      assert.are.equal(50, main_color.b)
    end)

    it("fades alpha based on age", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
      beat_counter = 1  -- halfway through duration

      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)

      -- Find the main sprite color call (not beat grid, not echo)
      -- Main sprite should have alpha around 127
      local sprite_colors = {}
      for _, call in ipairs(screen_calls) do
        if call.fn == "color" and call.r == 255 and call.g == 120 then
          table.insert(sprite_colors, call)
        end
      end
      assert.is_true(#sprite_colors >= 1)
      -- Main sprite alpha should be approximately half
      local main_alpha = sprite_colors[1].a
      assert.is_true(main_alpha >= 100 and main_alpha <= 155,
        "expected main alpha ~127, got " .. tostring(main_alpha))
    end)

    it("draws circle for shape 1", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      assert.is_true(count_screen_calls("circle_fill") > 0)
    end)

    it("draws rect for shape 2", function()
      local sv = sprite.new(1)
      sv:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      assert.is_true(count_screen_calls("rect_fill") > 0)
    end)

    it("draws triangle for shape 3", function()
      local sv = sprite.new(1)
      sv:play({note = 3, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      assert.is_true(count_screen_calls("triangle") > 0)
    end)

    it("draws diamond (quad) for shape 4", function()
      local sv = sprite.new(1)
      sv:play({note = 4, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      assert.is_true(count_screen_calls("quad") > 0)
    end)

    it("draws star (two triangles) for shape 5", function()
      local sv = sprite.new(1)
      sv:play({note = 5, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      -- Main + echo each draw 2 triangles = 4
      assert.is_true(count_screen_calls("triangle") >= 2)
    end)

    it("draws line for shape 6", function()
      local sv = sprite.new(1)
      sv:play({note = 6, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      -- line calls: 4 from beat grid + at least 1 from sprite
      assert.is_true(count_screen_calls("line") > 4)
    end)

    it("draws dot (small circle) for shape 7", function()
      local sv = sprite.new(1)
      sv:play({note = 7, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv}}
      sprite_render.draw(ctx)
      -- Should have circle_fill with r=2 for dot shapes
      local found = false
      for _, call in ipairs(screen_calls) do
        if call.fn == "circle_fill" and call.r ~= nil and call.r < 3 then found = true; break end
      end
      assert.is_true(found)
    end)

    it("renders events from multiple tracks", function()
      local sv1 = sprite.new(1)
      local sv2 = sprite.new(2)
      sv1:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
      sv2:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 2)
      local ctx = {sprite_voices = {sv1, sv2}}

      sprite_render.draw(ctx)

      -- Should have color calls for both tracks' sprites
      local track1_colors = 0
      local track2_colors = 0
      for _, call in ipairs(screen_calls) do
        if call.fn == "color" then
          if call.r == 255 and call.g == 120 then track1_colors = track1_colors + 1 end
          if call.r == 50 and call.g == 180 then track2_colors = track2_colors + 1 end
        end
      end
      assert.is_true(track1_colors >= 1, "expected track 1 color calls")
      assert.is_true(track2_colors >= 1, "expected track 2 color calls")
    end)
  end)

  describe("movement calculations", function()
    it("calculates horizontal drift based on track number", function()
      local e1 = {track_num = 1}
      local e4 = {track_num = 4}
      local dx1, _ = sprite_render.calc_movement(e1, 1.0)
      local dx4, _ = sprite_render.calc_movement(e4, 1.0)
      -- Track 1 should drift left (negative), track 4 right (positive)
      assert.is_true(dx1 < 0)
      assert.is_true(dx4 > 0)
    end)

    it("calculates upward vertical float", function()
      local e = {track_num = 2}
      local _, dy = sprite_render.calc_movement(e, 1.0)
      -- Should float upward (negative Y)
      assert.is_true(dy < 0)
    end)

    it("movement increases with age", function()
      local e = {track_num = 3}
      local dx1, dy1 = sprite_render.calc_movement(e, 0.5)
      local dx2, dy2 = sprite_render.calc_movement(e, 1.0)
      -- More drift at higher age
      assert.is_true(math.abs(dx2) > math.abs(dx1))
      assert.is_true(math.abs(dy2) > math.abs(dy1))
    end)

    it("no movement at age 0", function()
      local e = {track_num = 2}
      local dx, dy = sprite_render.calc_movement(e, 0)
      assert.are.equal(0, dx)
      assert.are.equal(0, dy)
    end)
  end)

  describe("beat pulse", function()
    it("pulse is maximum at beat boundary", function()
      local pulse_on = sprite_render.calc_pulse(0.0)
      local pulse_off = sprite_render.calc_pulse(0.5)
      -- At beat=0, cos(0)=1, pulse=1.2
      -- At beat=0.5, cos(pi)=-1, pulse=0.8
      assert.is_true(pulse_on > pulse_off)
      assert.is_true(math.abs(pulse_on - 1.2) < 0.01)
      assert.is_true(math.abs(pulse_off - 0.8) < 0.01)
    end)

    it("pulse is centered around 1.0", function()
      -- At quarter beat, cos(pi/2)=0, pulse=1.0
      local pulse_mid = sprite_render.calc_pulse(0.25)
      assert.is_true(math.abs(pulse_mid - 1.0) < 0.01)
    end)
  end)

  describe("glide line rendering", function()
    it("draws glide connecting line for gliding sprites", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 3, alt_note = 2, velocity = 4, glide = 3}, 2)
      sv:play({note = 2, octave = 5, alt_note = 6, velocity = 4, glide = 3}, 2)
      local ctx = {sprite_voices = {sv}}

      sprite_render.draw(ctx)

      -- Should have extra line calls beyond just beat grid (4 grid lines)
      -- The glide line adds an additional line call
      local line_count = count_screen_calls("line")
      assert.is_true(line_count > 4, "expected glide lines beyond beat grid")
    end)
  end)
end)
