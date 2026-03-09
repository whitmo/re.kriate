-- lib/seamstress/sprite_render.lua
-- Renders active sprite events to the seamstress screen

local M = {}

-- Shape drawing functions: each takes (x, y, size)
-- screen.color must be set before calling

local function draw_circle(x, y, size)
  screen.move(x, y)
  screen.circle_fill(size)
end

local function draw_rect(x, y, size)
  screen.move(x - size, y - size)
  screen.rect_fill(size * 2, size * 2)
end

local function draw_triangle(x, y, size)
  screen.triangle(
    x, y - size,
    x - size, y + size,
    x + size, y + size
  )
end

local function draw_diamond(x, y, size)
  screen.quad(
    x, y - size,
    x + size, y,
    x, y + size,
    x - size, y
  )
end

local function draw_star(x, y, size)
  -- Two overlapping triangles (hexagram)
  screen.triangle(
    x, y - size,
    x - size, y + size * 0.6,
    x + size, y + size * 0.6
  )
  screen.triangle(
    x, y + size,
    x - size, y - size * 0.6,
    x + size, y - size * 0.6
  )
end

local function draw_line(x, y, size)
  screen.move(x - size, y)
  screen.line(x + size, y)
end

local function draw_dot(x, y, _size)
  screen.move(x, y)
  screen.circle_fill(2)
end

-- Shape dispatch table (indexed 1-7 matching note values)
local SHAPE_DRAW = {
  draw_circle,
  draw_rect,
  draw_triangle,
  draw_diamond,
  draw_star,
  draw_line,
  draw_dot,
}

function M.draw(ctx)
  if not ctx.sprite_voices then return end

  for t = 1, #ctx.sprite_voices do
    local sv = ctx.sprite_voices[t]
    if sv then
      local events = sv:get_active_events()
      for _, e in ipairs(events) do
        -- Fade alpha based on age
        local current_beat = clock.get_beats()
        local age = current_beat - e.spawn_beat
        local life = age / e.duration
        local alpha = math.floor(e.color[4] * (1.0 - life))
        if alpha < 0 then alpha = 0 end

        screen.color(e.color[1], e.color[2], e.color[3], alpha)

        local draw_fn = SHAPE_DRAW[e.shape] or SHAPE_DRAW[1]
        draw_fn(e.x, e.y, e.size)
      end
    end
  end
end

return M
