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
    it("spawns a sprite event from kria vals", function()
      local sv = sprite.new(1)
      local vals = {note = 3, octave = 5, alt_note = 2, velocity = 6}
      sv:play(vals, 0.5)

      assert.are.equal(1, #sv.active_events)
      local e = sv.active_events[1]
      assert.are.equal(3, e.shape)
      assert.are.equal(sprite.X_MAP[2], e.x)
      assert.are.equal(sprite.Y_MAP[5], e.y)
      assert.are.equal(sprite.SIZE_MAP[6], e.size)
      assert.are.equal(0.5, e.duration)
      assert.are.equal(0, e.spawn_beat)
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

    it("accumulates multiple events", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      sv:play({note = 3, octave = 2, alt_note = 6, velocity = 7}, 0.5)
      assert.are.equal(2, #sv.active_events)
    end)
  end)

  describe("get_active_events", function()
    it("returns non-expired events", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
      beat_counter = 1
      local events = sv:get_active_events()
      assert.are.equal(1, #events)
    end)

    it("prunes expired events", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      beat_counter = 2
      local events = sv:get_active_events()
      assert.are.equal(0, #events)
    end)

    it("keeps young events and prunes old ones", function()
      local sv = sprite.new(1)
      beat_counter = 0
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 1)
      beat_counter = 0.5
      sv:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 2)
      beat_counter = 1.5
      local events = sv:get_active_events()
      assert.are.equal(1, #events)
      assert.are.equal(2, events[1].shape)
    end)
  end)

  describe("all_notes_off", function()
    it("clears all active events", function()
      local sv = sprite.new(1)
      sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 10)
      sv:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 10)
      assert.are.equal(2, #sv.active_events)
      sv:all_notes_off()
      assert.are.equal(0, #sv.active_events)
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
end)

describe("sprite renderer", function()

  before_each(function()
    beat_counter = 0
    screen_calls = {}
  end)

  it("does nothing with no sprite_voices", function()
    sprite_render.draw({})
    assert.are.equal(0, #screen_calls)
  end)

  it("draws active events with correct color", function()
    local sv = sprite.new(1)
    sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    -- Should have a color call followed by shape drawing
    assert.is_true(#screen_calls > 0)
    local color_call = screen_calls[1]
    assert.are.equal("color", color_call.fn)
    assert.are.equal(255, color_call.r)  -- track 1 red
    assert.are.equal(120, color_call.g)  -- track 1 green
    assert.are.equal(50, color_call.b)   -- track 1 blue
    assert.are.equal(255, color_call.a)  -- full alpha at age 0
  end)

  it("fades alpha based on age", function()
    local sv = sprite.new(1)
    beat_counter = 0
    sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
    beat_counter = 1  -- halfway through duration
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local color_call = screen_calls[1]
    assert.are.equal("color", color_call.fn)
    -- Alpha should be ~127 (half of 255)
    assert.is_true(color_call.a >= 126 and color_call.a <= 128)
  end)

  it("draws circle for shape 1", function()
    local sv = sprite.new(1)
    sv:play({note = 1, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    -- Find circle_fill call
    local found = false
    for _, call in ipairs(screen_calls) do
      if call.fn == "circle_fill" then found = true; break end
    end
    assert.is_true(found)
  end)

  it("draws rect for shape 2", function()
    local sv = sprite.new(1)
    sv:play({note = 2, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local found = false
    for _, call in ipairs(screen_calls) do
      if call.fn == "rect_fill" then found = true; break end
    end
    assert.is_true(found)
  end)

  it("draws triangle for shape 3", function()
    local sv = sprite.new(1)
    sv:play({note = 3, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local found = false
    for _, call in ipairs(screen_calls) do
      if call.fn == "triangle" then found = true; break end
    end
    assert.is_true(found)
  end)

  it("draws diamond (quad) for shape 4", function()
    local sv = sprite.new(1)
    sv:play({note = 4, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local found = false
    for _, call in ipairs(screen_calls) do
      if call.fn == "quad" then found = true; break end
    end
    assert.is_true(found)
  end)

  it("draws star (two triangles) for shape 5", function()
    local sv = sprite.new(1)
    sv:play({note = 5, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local tri_count = 0
    for _, call in ipairs(screen_calls) do
      if call.fn == "triangle" then tri_count = tri_count + 1 end
    end
    assert.are.equal(2, tri_count)
  end)

  it("draws line for shape 6", function()
    local sv = sprite.new(1)
    sv:play({note = 6, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local found = false
    for _, call in ipairs(screen_calls) do
      if call.fn == "line" then found = true; break end
    end
    assert.is_true(found)
  end)

  it("draws dot (small circle) for shape 7", function()
    local sv = sprite.new(1)
    sv:play({note = 7, octave = 4, alt_note = 4, velocity = 4}, 2)
    local ctx = {sprite_voices = {sv}}

    sprite_render.draw(ctx)

    local found = false
    for _, call in ipairs(screen_calls) do
      if call.fn == "circle_fill" and call.r == 2 then found = true; break end
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

    -- Should have color calls for both tracks
    local color_calls = {}
    for _, call in ipairs(screen_calls) do
      if call.fn == "color" then table.insert(color_calls, call) end
    end
    assert.are.equal(2, #color_calls)
    -- Track 1: orange
    assert.are.equal(255, color_calls[1].r)
    -- Track 2: cyan
    assert.are.equal(50, color_calls[2].r)
  end)
end)
