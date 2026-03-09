-- lib/seamstress/sprite_render.lua
-- Renders active sprite events to the seamstress screen
-- Features: movement, pulsing, echo trails, beat grid, playhead, glide lines

local sprite_mod = require("lib/voices/sprite")

local M = {}

-- Screen dimensions
local SCREEN_W = 256
local SCREEN_H = 128

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

--- Calculate movement offsets for a sprite event based on age.
--- @param e table  sprite event
--- @param age number  age in beats
--- @return number dx  horizontal offset
--- @return number dy  vertical offset
function M.calc_movement(e, age)
  local track_num = e.track_num or 1
  -- Horizontal drift: track 1 drifts left, track 4 drifts right
  local dx = (track_num - 2.5) * sprite_mod.DRIFT_SPEED * age
  -- Vertical float: sprites rise upward
  local dy = -age * sprite_mod.FLOAT_SPEED
  return dx, dy
end

--- Calculate beat pulse multiplier.
--- @param beat number  current beat (from clock.get_beats())
--- @return number  size multiplier (centered around 1.0)
function M.calc_pulse(beat)
  local beat_frac = beat % 1
  return 1.0 + 0.2 * math.cos(beat_frac * 2 * math.pi)
end

--- Draw faint vertical beat grid lines with flash on beat.
--- @param beat number  current beat from clock.get_beats()
function M.draw_beat_grid(beat)
  local beat_frac = beat % 1
  -- Bright flash near beat boundary (first 10% of beat)
  local alpha = beat_frac < 0.1 and 80 or 20
  screen.color(120, 120, 140, alpha)
  -- Draw 4 evenly-spaced vertical reference lines
  for i = 1, 4 do
    local x = math.floor(i * SCREEN_W / 5)
    screen.move(x, 0)
    screen.line(x, SCREEN_H)
  end
end

--- Draw playhead indicators for each track.
--- Shows current step position as a subtle dot.
--- @param ctx table  context with tracks
function M.draw_playheads(ctx)
  if not ctx.tracks then return end
  local num_tracks = #ctx.tracks
  for t = 1, num_tracks do
    local track = ctx.tracks[t]
    if track and track.params and track.params.trigger then
      local trig = track.params.trigger
      local y = math.floor(t * SCREEN_H / (num_tracks + 1))
      local x = math.floor((trig.pos / trig.loop_end) * SCREEN_W)
      -- Very subtle indicator
      local color = sprite_mod.TRACK_COLORS[t] or sprite_mod.TRACK_COLORS[1]
      screen.color(color[1], color[2], color[3], 40)
      screen.move(x, y)
      screen.circle_fill(2)
    end
  end
end

--- Draw a glide line connecting a sprite to its previous position.
--- @param e table  sprite event with glide_from field
--- @param render_x number  current rendered x position
--- @param render_y number  current rendered y position
--- @param alpha number  current alpha value
local function draw_glide_line(e, render_x, render_y, alpha)
  if not e.glide_from then return end
  local glide_alpha = math.floor(alpha * 0.5)
  if glide_alpha < 1 then return end
  screen.color(e.color[1], e.color[2], e.color[3], glide_alpha)
  screen.move(e.glide_from.x, e.glide_from.y)
  screen.line(render_x, render_y)
end

function M.draw(ctx)
  local current_beat = clock.get_beats()

  -- Beat grid (behind everything)
  M.draw_beat_grid(current_beat)

  -- Playhead indicators (subtle, behind sprites)
  M.draw_playheads(ctx)

  if not ctx.sprite_voices then return end

  local pulse = M.calc_pulse(current_beat)

  for t = 1, #ctx.sprite_voices do
    local sv = ctx.sprite_voices[t]
    if sv then
      local events = sv:get_active_events()
      for _, e in ipairs(events) do
        -- Age and life fraction for fade
        local age = current_beat - e.spawn_beat
        local life = age / e.duration
        local alpha = math.floor(e.color[4] * (1.0 - life))
        if alpha < 0 then alpha = 0 end

        -- Movement offsets
        local dx, dy = M.calc_movement(e, age)
        local render_x = e.x + dx
        local render_y = e.y + dy

        -- Clamp to screen bounds
        render_x = math.max(0, math.min(SCREEN_W, render_x))
        render_y = math.max(0, math.min(SCREEN_H, render_y))

        -- Pulse size on the beat (echoes pulse less)
        local size_mult = e.is_echo and (1.0 + (pulse - 1.0) * 0.5) or pulse
        local render_size = e.size * size_mult

        -- Draw glide connecting line (before shape, so shape draws on top)
        if e.glide_from and not e.is_echo then
          draw_glide_line(e, render_x, render_y, alpha)
        end

        -- Set color and draw shape
        screen.color(e.color[1], e.color[2], e.color[3], alpha)
        local draw_fn = SHAPE_DRAW[e.shape] or SHAPE_DRAW[1]
        draw_fn(render_x, render_y, render_size)
      end
    end
  end
end

return M
