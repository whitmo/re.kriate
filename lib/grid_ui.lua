-- lib/grid_ui.lua
-- Grid display and input for kria sequencer
-- Grid layout (16x8, 1-indexed):
--   Rows 1-7: step data (varies by page)
--   Row 8: navigation (track select, page select)

local track_mod = require("lib/track")

local M = {}

-- Page names matching track_mod.PARAM_NAMES
M.PAGES = {"trigger", "note", "octave", "duration", "velocity"}

-- Nav row (row 8) layout:
-- x=1-4: track select
-- x=6: trigger page
-- x=7: note page
-- x=8: octave page
-- x=9: duration page
-- x=10: velocity page
-- x=12: loop modifier (hold)
-- x=16: play/stop

local NAV_TRACK = {1, 2, 3, 4} -- @@ unused
local NAV_PAGE = {[6] = "trigger", [7] = "note", [8] = "octave", [9] = "duration", [10] = "velocity"}
local NAV_LOOP = 12
local NAV_PLAY = 16

function M.redraw(ctx)
  local g = ctx.g
  if not g then return end
  g:all(0)

  local page = ctx.active_page

  if page == "trigger" then
    M.draw_trigger_page(ctx, g)
  else
    M.draw_value_page(ctx, g, page)
  end

  M.draw_nav(ctx, g)
  g:refresh()
end

-- Trigger page: rows 1-4 = tracks 1-4, columns = steps
function M.draw_trigger_page(ctx, g)
  for t = 1, track_mod.NUM_TRACKS do
    local param = ctx.tracks[t].params.trigger
    for x = 1, track_mod.NUM_STEPS do
      local brightness = 0
      -- loop region indicator
      if x >= param.loop_start and x <= param.loop_end then
        brightness = 2
      end
      -- step value
      if param.steps[x] == 1 then
        brightness = 8
      end
      -- playhead
      if x == param.pos and ctx.playing then
        brightness = 15
      end
      g:led(x, t, brightness)
    end
  end
end

-- Value pages (note, octave, duration, velocity): rows 1-7 = values, columns = steps
-- Active track only. Value shown as bar from bottom (row 7) up to value row.
function M.draw_value_page(ctx, g, page)
  local track = ctx.tracks[ctx.active_track]
  local param = track.params[page]
  for x = 1, track_mod.NUM_STEPS do
    local val = param.steps[x]
    local in_loop = x >= param.loop_start and x <= param.loop_end
    for y = 1, 7 do
      local brightness = 0
      -- value display: row 1 = value 7, row 7 = value 1
      local row_val = 8 - y
      if row_val == val then
        brightness = in_loop and 10 or 4
      elseif row_val < val and in_loop then
        brightness = 3
      end
      -- playhead column
      if x == param.pos and ctx.playing then
        if row_val == val then
          brightness = 15
        elseif row_val < val then
          brightness = 6
        end
      end
      g:led(x, y, brightness)
    end
  end
end

-- Navigation row
function M.draw_nav(ctx, g)
  local y = 8
  -- track select
  for i = 1, 4 do
    g:led(i, y, i == ctx.active_track and 12 or 3)
  end
  -- page select
  for x, page in pairs(NAV_PAGE) do
    g:led(x, y, page == ctx.active_page and 12 or 3)
  end
  -- loop modifier
  g:led(NAV_LOOP, y, ctx.loop_held and 12 or 3)
  -- play/stop
  g:led(NAV_PLAY, y, ctx.playing and 12 or 3)
end

function M.key(ctx, x, y, z)
  if y == 8 then
    M.nav_key(ctx, x, z)
  elseif y >= 1 and y <= 7 then
    M.grid_key(ctx, x, y, z)
  end
end

function M.nav_key(ctx, x, z)
  -- track select (momentary not needed, select on press)
  if x >= 1 and x <= 4 and z == 1 then
    ctx.active_track = x
  end
  -- page select
  if NAV_PAGE[x] and z == 1 then
    ctx.active_page = NAV_PAGE[x]
  end
  -- loop modifier (hold)
  if x == NAV_LOOP then
    ctx.loop_held = z == 1
    if z == 0 then
      ctx.loop_first_press = nil
    end
  end
  -- play/stop
  if x == NAV_PLAY and z == 1 then
    local seq = require("lib/sequencer")
    if ctx.playing then
      seq.stop(ctx)
    else
      seq.start(ctx)
    end
  end
end

function M.grid_key(ctx, x, y, z)
  if z == 0 then return end -- only act on press

  local page = ctx.active_page

  -- loop editing mode
  if ctx.loop_held then
    M.loop_key(ctx, x, page)
    return
  end

  if page == "trigger" then
    M.trigger_key(ctx, x, y)
  else
    M.value_key(ctx, x, y, page)
  end
end

-- Trigger page: toggle step on the appropriate track row
function M.trigger_key(ctx, x, y)
  if y >= 1 and y <= track_mod.NUM_TRACKS then
    track_mod.toggle_step(ctx.tracks[y].params.trigger, x)
  end
end

-- Value page: set step value for active track
function M.value_key(ctx, x, y, page)
  local track = ctx.tracks[ctx.active_track]
  local param = track.params[page]
  -- row 1 = value 7, row 7 = value 1
  local val = 8 - y
  -- toggle: if same value, could clear (but for kria, values are always set)
  track_mod.set_step(param, x, val)
end

-- Loop editing: first press = start, second press = end
function M.loop_key(ctx, x, page)
  local track = ctx.tracks[ctx.active_track]
  -- on trigger page, use active_track's trigger param
  -- on other pages, use that page's param
  local param
  if page == "trigger" then
    param = track.params.trigger
  else
    param = track.params[page]
  end

  if not ctx.loop_first_press then
    ctx.loop_first_press = x
  else
    local s = math.min(ctx.loop_first_press, x)
    local e = math.max(ctx.loop_first_press, x)
    track_mod.set_loop(param, s, e)
    ctx.loop_first_press = nil
  end
end

return M
