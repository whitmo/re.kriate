-- lib/seamstress/grid_render.lua
-- Grid LED → screen renderer for simulated grid
--
-- Renders a 16x8 grid of colored rectangles on the seamstress screen.
-- LED brightness (0-15) maps to warm amber RGB colors.
-- Mouse clicks on grid cells generate grid key events.

local M = {}

local CELL_SIZE = 14
local CELL_PITCH = 16
local GRID_COLS = 16
local GRID_ROWS = 8

--- Map grid brightness (0-15) to warm amber RGB color.
--- @param brightness number  Brightness level 0-15
--- @return number, number, number  R, G, B values (0-255)
function M.brightness_to_rgb(brightness)
  local ratio = brightness / 15
  local r = math.floor(ratio * 255)
  local g = math.floor(ratio * 255 * 0.7)
  local b = math.floor(ratio * 255 * 0.4)
  return r, g, b
end

--- Convert grid cell to top-left screen pixel position.
--- @param gx number  Grid column (1-indexed)
--- @param gy number  Grid row (1-indexed)
--- @return number, number  Pixel x, y
function M.grid_to_pixel(gx, gy)
  return (gx - 1) * CELL_PITCH, (gy - 1) * CELL_PITCH
end

--- Convert screen pixel to grid cell coordinates.
--- @param px number  Pixel x
--- @param py number  Pixel y
--- @return number|nil, number|nil  Grid x, y (1-indexed) or nil if out of bounds
function M.pixel_to_grid(px, py)
  if px < 0 or py < 0 then return nil end
  local gx = math.floor(px / CELL_PITCH) + 1
  local gy = math.floor(py / CELL_PITCH) + 1
  if gx < 1 or gx > GRID_COLS or gy < 1 or gy > GRID_ROWS then return nil end
  return gx, gy
end

--- Draw the simulated grid to the screen.
--- @param grid table  Grid provider with get_led(x, y)
--- @param scr table  Screen object with color(r,g,b,a), move(x,y), rect_fill(w,h)
function M.draw(grid, scr)
  for y = 1, GRID_ROWS do
    for x = 1, GRID_COLS do
      local brightness = grid:get_led(x, y)
      local r, g, b = M.brightness_to_rgb(brightness)
      scr.color(r, g, b, 255)
      local px, py = M.grid_to_pixel(x, y)
      scr.move(px, py)
      scr.rect_fill(CELL_SIZE, CELL_SIZE)
    end
  end
end

--- Handle mouse click on the simulated grid.
--- @param grid table  Grid provider with key callback
--- @param px number  Pixel x
--- @param py number  Pixel y
--- @param state number  1 for press, 0 for release
--- @param button number  Mouse button (1=left, 2=right, 3=middle)
function M.handle_click(grid, px, py, state, button)
  if button ~= 1 then return end
  local gx, gy = M.pixel_to_grid(px, py)
  if not gx then return end
  if grid.key then
    grid.key(gx, gy, state)
  end
end

return M
