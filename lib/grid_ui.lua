-- lib/grid_ui.lua
-- Grid display and input for kria sequencer
-- Grid layout (16x8, 1-indexed):
--   Rows 1-7: step data (varies by page)
--   Row 8: navigation (track select, page select)

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local direction_mod = require("lib/direction")

local M = {}

-- Page names (primary + extended)
M.PAGES = {"trigger", "note", "octave", "duration", "velocity", "probability", "ratchet", "alt_note", "glide", "alt_track"}

-- Extended page mappings: primary -> extended
M.EXTENDED_PAGES = {trigger = "ratchet", note = "alt_note", octave = "glide"}
-- Reverse: extended -> primary
M.EXTENDED_REVERSE = {ratchet = "trigger", alt_note = "note", glide = "octave"}

-- Nav row (row 8) layout:
-- x=1-4: track select
-- x=6: trigger page (double-tap: ratchet)
-- x=7: note page (double-tap: alt_note)
-- x=8: octave page (double-tap: glide)
-- x=9: duration page
-- x=10: velocity page
-- x=11: probability page
-- x=5: mute toggle
-- x=12: loop modifier (hold)
-- x=13: time modifier (hold) — per-param clock division
-- x=14: pattern mode (hold)
-- x=15: alt-track page (direction/division/swing/mute)
-- x=16: play/stop

local NAV_TRACK = {1, 2, 3, 4} -- @@ unused
local NAV_MUTE = 5
local NAV_PAGE = {[6] = "trigger", [7] = "note", [8] = "octave", [9] = "duration", [10] = "velocity", [11] = "probability", [15] = "alt_track"}
local NAV_LOOP = 12
local NAV_TIME = 13
local NAV_PATTERN = 14
local NAV_PLAY = 16

local ALT_DIRECTIONS = {"forward", "reverse", "pendulum", "drunk", "random"}
local ALT_DIVISIONS = {1,2,3,4,5,6,7}
local ALT_SWING = {0, 50, 100}

function M.redraw(ctx)
  local g = ctx.g
  if not g then return end
  g:all(0)

  if ctx.pattern_held then
    -- pattern mode: show pattern slots on rows 1-2, cols 1-8
    M.draw_pattern_slots(ctx, g)
  elseif ctx.time_held then
    -- time modifier: show per-param clock division selector
    M.draw_time_page(ctx, g)
  else
    local page = ctx.active_page

    if page == "trigger" then
      M.draw_trigger_page(ctx, g)
    elseif page == "alt_track" then
      M.draw_alt_track_page(ctx, g)
    else
      -- All other pages (including extended: ratchet, alt_note, glide) use value display
      M.draw_value_page(ctx, g, page)
    end
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

-- Alt-track settings page (rows = tracks)
-- x1-5: direction (forward, reverse, pendulum, drunk, random)
-- x6-12: division (1..7)
-- x13-15: swing (0,50,100)
-- x16: mute toggle
function M.draw_alt_track_page(ctx, g)
  local active_track = ctx.active_track or 1
  for t = 1, track_mod.NUM_TRACKS do
    local track = ctx.tracks[t]
    local is_active_row = (t == active_track)
    local is_muted = track.muted
    -- directions
    for i, dir in ipairs(ALT_DIRECTIONS) do
      local selected = (track.direction == dir)
      local brightness = selected and 10 or 2
      if is_active_row then brightness = math.min(12, brightness + 2) end
      if is_muted and not selected then brightness = math.max(1, brightness - 1) end
      g:led(i, t, brightness)
    end
    -- division
    for idx, div in ipairs(ALT_DIVISIONS) do
      local x = 5 + idx
      local selected = (track.division == div)
      local brightness = selected and 10 or 2
      if is_active_row then brightness = math.min(12, brightness + 2) end
      if is_muted and not selected then brightness = math.max(1, brightness - 1) end
      g:led(x, t, brightness)
    end
    -- swing (coarse buckets)
    for idx, swing in ipairs(ALT_SWING) do
      local x = 12 + idx -- 13..15
      local selected = (track.swing == swing)
      local base = selected and 10 or 2
      if is_active_row then base = math.min(12, base + 2) end
      if is_muted and not selected then base = math.max(1, base - 1) end
      g:led(x, t, base)
    end
    -- mute
    local mute_brightness = track.muted and 15 or (is_active_row and 4 or 2)
    g:led(16, t, mute_brightness)
  end
  -- trigger clocking toggles (row 5, x=1-4 = tracks 1-4)
  for t = 1, track_mod.NUM_TRACKS do
    local track = ctx.tracks[t]
    g:led(t, 5, track.trig_clock and 12 or 2)
  end
end

-- Time page: per-parameter clock division selector
-- On trigger page: rows 1-4 = tracks, columns 1-7 = division values for trigger param
-- On value pages: rows 1-4 = core params visible as labels, columns 1-7 = division value
-- Active page's param is highlighted on row 1; other params shown dimly below
function M.draw_time_page(ctx, g)
  local page = ctx.active_page
  -- Resolve extended page to primary for param lookup
  local param_name = M.EXTENDED_REVERSE[page] or page

  if page == "trigger" then
    -- Trigger page: show each track's trigger clock_div
    for t = 1, track_mod.NUM_TRACKS do
      local p = ctx.tracks[t].params.trigger
      local is_active = (t == ctx.active_track)
      for x = 1, 7 do
        local brightness = 2
        if x == p.clock_div then
          brightness = is_active and 15 or 10
        elseif is_active then
          brightness = 3
        end
        g:led(x, t, brightness)
      end
    end
  elseif page == "alt_track" then
    -- Alt-track page: show all params for active track, one param per row
    local track = ctx.tracks[ctx.active_track]
    for row, name in ipairs(track_mod.PARAM_NAMES) do
      if row > 7 then break end
      local p = track.params[name]
      for x = 1, 7 do
        local brightness = 2
        if x == p.clock_div then
          brightness = 10
        end
        g:led(x, row, brightness)
      end
    end
  else
    -- Value page: show active param's clock_div prominently on row 1,
    -- plus other params dimly below for context
    local track = ctx.tracks[ctx.active_track]
    local active_param = track.params[param_name]
    if active_param then
      -- Row 1: active param
      for x = 1, 7 do
        local brightness = 3
        if x == active_param.clock_div then
          brightness = 15
        end
        g:led(x, 1, brightness)
      end
      -- Rows 2-7: other core params for context (skip active)
      local row = 2
      for _, name in ipairs(track_mod.PARAM_NAMES) do
        if name ~= param_name and row <= 7 then
          local p = track.params[name]
          for x = 1, 7 do
            local brightness = 1
            if x == p.clock_div then
              brightness = 6
            end
            g:led(x, row, brightness)
          end
          row = row + 1
        end
      end
    end
  end
end

-- Pattern slots display: rows 1-2, cols 1-8 (16 slots total)
function M.draw_pattern_slots(ctx, g)
  if not ctx.patterns then return end
  for slot = 1, 16 do
    local col = ((slot - 1) % 8) + 1
    local row = ((slot - 1) < 8) and 1 or 2
    local populated = pattern.is_populated(ctx.patterns, slot)
    local is_current = (slot == ctx.pattern_slot)
    local brightness = 2
    if populated and is_current then
      brightness = 15
    elseif populated then
      brightness = 10
    elseif is_current then
      brightness = 6
    end
    g:led(col, row, brightness)
  end
end

-- Navigation row
function M.draw_nav(ctx, g)
  local y = 8
  -- track select
  for i = 1, 4 do
    g:led(i, y, i == ctx.active_track and 12 or 3)
  end
  -- mute indicator (x=5)
  local muted = ctx.tracks[ctx.active_track] and ctx.tracks[ctx.active_track].muted
  g:led(NAV_MUTE, y, muted and 12 or 3)
  -- page select (highlight correct button even when on extended page)
  local active_primary = M.EXTENDED_REVERSE[ctx.active_page] or ctx.active_page
  for x, page in pairs(NAV_PAGE) do
    g:led(x, y, page == active_primary and 12 or 3)
  end
  -- loop modifier
  g:led(NAV_LOOP, y, ctx.loop_held and 12 or 3)
  -- time modifier
  g:led(NAV_TIME, y, ctx.time_held and 12 or 3)
  -- pattern mode
  g:led(NAV_PATTERN, y, ctx.pattern_held and 12 or 3)
  -- play/stop
  g:led(NAV_PLAY, y, ctx.playing and 12 or 3)
end

function M.key(ctx, x, y, z)
  -- emit grid:key event for all key presses
  if ctx.events then
    ctx.events:emit("grid:key", {x=x, y=y, z=z})
  end

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
    if ctx.events then
      ctx.events:emit("track:select", {track=x})
    end
  end
  -- mute toggle (x=5)
  if x == NAV_MUTE and z == 1 then
    local track = ctx.tracks[ctx.active_track]
    track.muted = not track.muted
    if ctx.events then
      ctx.events:emit("track:mute", {track=ctx.active_track, muted=track.muted})
    end
  end
  -- page select with extended page toggle
  if NAV_PAGE[x] and z == 1 then
    local old_page = ctx.active_page
    local target_page = NAV_PAGE[x]
    if ctx.active_page == target_page then
      -- Same button pressed: toggle to extended page if one exists
      if M.EXTENDED_PAGES[target_page] then
        ctx.active_page = M.EXTENDED_PAGES[target_page]
      end
      -- If no extended page (duration, velocity), stay on same page
    elseif M.EXTENDED_REVERSE[ctx.active_page] == target_page then
      -- Currently on extended page, pressing its primary button: toggle back
      ctx.active_page = target_page
    else
      -- Different page button: switch to primary page (clear extended)
      ctx.active_page = target_page
    end
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
    end
  end
  -- loop modifier (hold)
  if x == NAV_LOOP then
    ctx.loop_held = z == 1
    if z == 0 then
      ctx.loop_first_press = nil
    end
  end
  -- time modifier (hold x=13)
  if x == NAV_TIME then
    ctx.time_held = (z == 1)
  end
  -- pattern mode (hold x=14)
  if x == NAV_PATTERN then
    ctx.pattern_held = (z == 1)
  end
  -- alt-track page toggle (x=15)
  if x == 15 and z == 1 then
    ctx.active_page = "alt_track"
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

  -- pattern slot selection mode
  if ctx.pattern_held then
    M.pattern_key(ctx, x, y)
    return
  end

  -- time modifier: set per-param clock division
  if ctx.time_held then
    M.time_key(ctx, x, y)
    return
  end

  -- alt-track page (bypasses loop/pattern edits)
  if ctx.active_page == "alt_track" then
    if z == 1 then
      M.alt_track_key(ctx, x, y)
    end
    return
  end

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
  -- row 1 = value 7, row 7 = value 1 (all value pages including probability)
  local val = 8 - y
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

-- Pattern slot selection: rows 1-2, cols 1-8 = 16 slots
function M.pattern_key(ctx, x, y)
  if x < 1 or x > 8 or y < 1 or y > 2 then return end
  local slot = (y - 1) * 8 + x
  ctx.pattern_slot = slot
  pattern.load(ctx, slot)
  if ctx.events then
    ctx.events:emit("pattern:load", {slot=slot})
  end
end

-- Alt-track interaction
function M.alt_track_key(ctx, x, y)
  -- trigger clocking toggles (row 5, x=1-4)
  if y == 5 and x >= 1 and x <= track_mod.NUM_TRACKS then
    local track = ctx.tracks[x]
    if track then
      track.trig_clock = not track.trig_clock
    end
    return
  end

  if y < 1 or y > track_mod.NUM_TRACKS then return end
  local track = ctx.tracks[y]
  if not track then return end

  if x >= 1 and x <= #ALT_DIRECTIONS then
    track.direction = ALT_DIRECTIONS[x]
    ctx.active_track = y
    return
  end

  if x >= 6 and x <= 12 then
    local idx = x - 5
    if ALT_DIVISIONS[idx] then
      track.division = ALT_DIVISIONS[idx]
      ctx.active_track = y
      return
    end
  end

  if x >= 13 and x <= 15 then
    local idx = x - 12
    if ALT_SWING[idx] ~= nil then
      track.swing = ALT_SWING[idx]
      ctx.active_track = y
      return
    end
  end

  if x == 16 then
    track.muted = not track.muted
    ctx.active_track = y
  end
end

-- Time modifier key: set per-param clock division
-- x=1-7 sets clock_div value; y selects target depending on page
function M.time_key(ctx, x, y)
  if x < 1 or x > 7 then return end
  local page = ctx.active_page
  local param_name = M.EXTENDED_REVERSE[page] or page

  if page == "trigger" then
    -- On trigger page: y=1-4 selects track, sets trigger param clock_div
    if y >= 1 and y <= track_mod.NUM_TRACKS then
      ctx.tracks[y].params.trigger.clock_div = x
      ctx.tracks[y].params.trigger.tick = 0
    end
  elseif page == "alt_track" then
    -- On alt_track page: y=1-7 maps to param names
    if y >= 1 and y <= #track_mod.PARAM_NAMES and y <= 7 then
      local name = track_mod.PARAM_NAMES[y]
      local p = ctx.tracks[ctx.active_track].params[name]
      if p then
        p.clock_div = x
        p.tick = 0
      end
    end
  else
    -- On value pages: any press sets the active param's clock_div
    local track = ctx.tracks[ctx.active_track]
    local p = track.params[param_name]
    if p then
      p.clock_div = x
      p.tick = 0
    end
  end
end

return M
