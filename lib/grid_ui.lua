-- lib/grid_ui.lua
-- Grid display and input for kria sequencer
-- Grid layout (16x8, 1-indexed):
--   Rows 1-7: step data (varies by page)
--   Row 8: navigation (track select, page select)

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local meta_pattern = require("lib/meta_pattern")
local direction_mod = require("lib/direction")

local M = {}

-- Page names (primary + extended)
M.PAGES = {"trigger", "note", "octave", "duration", "velocity", "probability", "ratchet", "alt_note", "glide", "alt_track", "meta_pattern", "scale"}

-- Extended page mappings: primary -> extended
M.EXTENDED_PAGES = {trigger = "ratchet", note = "alt_note", octave = "glide"}
-- Reverse: extended -> primary
M.EXTENDED_REVERSE = {ratchet = "trigger", alt_note = "note", glide = "octave"}

-- Nav row (row 8) layout:
-- x=1-4: track select
-- x=5: (blank)
-- x=6: trigger page (press again: ratchet)
-- x=7: note page (press again: alt_note)
-- x=8: octave page (press again: glide)
-- x=9: cycles duration → velocity → probability
-- x=10: (blank)
-- x=11: loop modifier (hold)
-- x=12: pattern mode (hold)
-- x=13: mute toggle
-- x=14: scale
-- x=15: meta (alt-track settings; double-press: meta-pattern sequencer)
-- x=16: (available)

local NAV_PAGE = {[6] = "trigger", [7] = "note", [8] = "octave", [9] = "duration"}
-- Page group for x=9: pressing cycles through these pages
local NAV_PAGE_CYCLE_9 = {"duration", "velocity", "probability"}
-- Quick lookup: which pages belong to the x=9 cycle group
local NAV_PAGE_CYCLE_9_SET = {duration = true, velocity = true, probability = true}
local NAV_LOOP = 11
local NAV_PATTERN = 12
local NAV_MUTE = 13
local NAV_SCALE = 14
local NAV_META = 15

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
  elseif ctx.loop_held and ctx.active_page ~= "alt_track" then
    -- loop modifier: show loop boundaries for editing
    M.draw_loop_page(ctx, g)
  else
    local page = ctx.active_page

    if page == "trigger" then
      M.draw_trigger_page(ctx, g)
    elseif page == "alt_track" then
      M.draw_alt_track_page(ctx, g)
    elseif page == "meta_pattern" then
      M.draw_meta_pattern_page(ctx, g)
    elseif page == "scale" then
      M.draw_scale_page(ctx, g)
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

-- Loop editing display: shows loop boundaries for current page
-- Trigger page: rows 1-4 = tracks, columns show trigger loop region
-- Value pages: columns show loop region for active param (full height)
function M.draw_loop_page(ctx, g)
  local page = ctx.active_page

  if page == "trigger" then
    for t = 1, track_mod.NUM_TRACKS do
      local param = ctx.tracks[t].params.trigger
      local is_active = (t == ctx.active_track)
      for x = 1, track_mod.NUM_STEPS do
        local in_loop = x >= param.loop_start and x <= param.loop_end
        local brightness = 0
        if is_active and ctx.loop_first_press and x == ctx.loop_first_press then
          brightness = 15
        elseif in_loop then
          brightness = is_active and 10 or 4
        elseif is_active then
          brightness = 2
        end
        g:led(x, t, brightness)
      end
    end
  else
    local track = ctx.tracks[ctx.active_track]
    local param = track.params[page]
    if not param then return end
    for x = 1, track_mod.NUM_STEPS do
      local in_loop = x >= param.loop_start and x <= param.loop_end
      local brightness
      if ctx.loop_first_press and x == ctx.loop_first_press then
        brightness = 15
      elseif in_loop then
        brightness = 10
      else
        brightness = 2
      end
      for y = 1, 7 do
        g:led(x, y, brightness)
      end
    end
  end
end

-- Scale page: root note selection, scale type selection, scale visualization
-- Row 1: x=1-12 chromatic note class (C=1, C#=2, ..., B=12)
-- Row 2: x=1-10 octave 0-9
-- Row 3: x=1-7 scale types 1-7
-- Row 4: x=1-7 scale types 8-14
-- Row 5: x=1-12 scale note visualization (which chromatic notes are in scale)
function M.draw_scale_page(ctx, g)
  local root = ctx.root_note or 60
  local pitch_class = root % 12  -- 0-11
  local octave = math.floor(root / 12)  -- 0-10
  local scale_idx = ctx.scale_type or 1

  -- Row 1: chromatic note selection (x=1-12)
  for x = 1, 12 do
    local selected = (x - 1) == pitch_class
    g:led(x, 1, selected and 15 or 3)
  end

  -- Row 2: octave selection (x=1-10)
  for x = 1, 10 do
    local selected = (x - 1) == octave
    g:led(x, 2, selected and 15 or 3)
  end

  -- Row 3: scale types 1-7
  for x = 1, 7 do
    local selected = x == scale_idx
    g:led(x, 3, selected and 15 or 3)
  end

  -- Row 4: scale types 8-14
  for x = 1, 7 do
    local selected = (x + 7) == scale_idx
    g:led(x, 4, selected and 15 or 3)
  end

  -- Row 5: scale note visualization
  if ctx.scale_notes and #ctx.scale_notes > 0 then
    local in_scale = {}
    for _, note in ipairs(ctx.scale_notes) do
      in_scale[note % 12] = true
    end
    for x = 1, 12 do
      g:led(x, 5, in_scale[x - 1] and 8 or 1)
    end
  end
end

-- Navigation row
function M.draw_nav(ctx, g)
  local y = 8
  -- track select (x=1-4)
  for i = 1, 4 do
    g:led(i, y, i == ctx.active_track and 12 or 3)
  end
  -- x=5: blank (no LED)
  -- page select x=6-9 (highlight correct button even when on extended page)
  local active_primary = M.EXTENDED_REVERSE[ctx.active_page] or ctx.active_page
  for x = 6, 8 do
    g:led(x, y, NAV_PAGE[x] == active_primary and 12 or 3)
  end
  -- x=9: lit if current page is in the cycle group (duration/velocity/probability)
  g:led(9, y, NAV_PAGE_CYCLE_9_SET[ctx.active_page] and 12 or 3)
  -- x=10: blank (no LED)
  -- modifiers (x=11-13)
  g:led(NAV_LOOP, y, ctx.loop_held and 12 or 3)
  g:led(NAV_PATTERN, y, ctx.pattern_held and 12 or 3)
  local muted = ctx.tracks[ctx.active_track] and ctx.tracks[ctx.active_track].muted
  g:led(NAV_MUTE, y, muted and 12 or 3)
  -- scale (x=14)
  g:led(NAV_SCALE, y, ctx.active_page == "scale" and 12 or 3)
  -- meta (x=15): alt-track or meta-pattern
  local meta_active = ctx.active_page == "alt_track" or ctx.active_page == "meta_pattern"
  g:led(NAV_META, y, meta_active and 12 or 3)
  -- x=16: blank (no LED)
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
  -- track select x=1-4 (select on press)
  if x >= 1 and x <= 4 and z == 1 then
    ctx.active_track = x
    if ctx.events then
      ctx.events:emit("track:select", {track=x})
    end
  end
  -- page select x=6-8 with extended page toggle
  if x >= 6 and x <= 8 and NAV_PAGE[x] and z == 1 then
    local old_page = ctx.active_page
    local target_page = NAV_PAGE[x]
    if ctx.active_page == target_page then
      -- Same button pressed: toggle to extended page if one exists
      if M.EXTENDED_PAGES[target_page] then
        ctx.active_page = M.EXTENDED_PAGES[target_page]
      end
    elseif M.EXTENDED_REVERSE[ctx.active_page] == target_page then
      -- Currently on extended page, pressing its primary button: toggle back
      ctx.active_page = target_page
    else
      -- Different page button: switch to primary page
      ctx.active_page = target_page
    end
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
    end
  end
  -- page select x=9: cycle through duration → velocity → probability
  if x == 9 and z == 1 then
    local old_page = ctx.active_page
    -- Find current position in cycle group
    local idx = nil
    for i, p in ipairs(NAV_PAGE_CYCLE_9) do
      if ctx.active_page == p then idx = i; break end
    end
    if idx then
      -- Advance to next in cycle (wrap around)
      ctx.active_page = NAV_PAGE_CYCLE_9[(idx % #NAV_PAGE_CYCLE_9) + 1]
    else
      -- Not currently on a cycle-9 page: go to first (duration)
      ctx.active_page = NAV_PAGE_CYCLE_9[1]
    end
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
    end
  end
  -- loop modifier hold (x=11)
  if x == NAV_LOOP then
    ctx.loop_held = z == 1
    if z == 0 then
      ctx.loop_first_press = nil
    end
  end
  -- pattern mode hold (x=12)
  if x == NAV_PATTERN then
    ctx.pattern_held = (z == 1)
  end
  -- mute toggle (x=13)
  if x == NAV_MUTE and z == 1 then
    local track = ctx.tracks[ctx.active_track]
    track.muted = not track.muted
    if ctx.events then
      ctx.events:emit("track:mute", {track=ctx.active_track, muted=track.muted})
    end
  end
  -- scale (x=14)
  if x == NAV_SCALE and z == 1 then
    local old_page = ctx.active_page
    ctx.active_page = "scale"
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
    end
  end
  -- meta / alt-track (x=15): double-press toggles alt_track <-> meta_pattern
  if x == NAV_META and z == 1 then
    local old_page = ctx.active_page
    if ctx.active_page == "alt_track" then
      ctx.active_page = "meta_pattern"
    elseif ctx.active_page == "meta_pattern" then
      ctx.active_page = "alt_track"
    else
      ctx.active_page = "alt_track"
    end
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
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

  -- scale page
  if ctx.active_page == "scale" then
    M.scale_key(ctx, x, y)
    return
  end

  -- meta-pattern page
  if ctx.active_page == "meta_pattern" then
    if z == 1 then
      M.meta_pattern_key(ctx, x, y)
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

-- Scale page key: set root note or scale type
function M.scale_key(ctx, x, y)
  local root = ctx.root_note or 60

  if y == 1 and x >= 1 and x <= 12 then
    -- Set pitch class, keep octave
    local octave = math.floor(root / 12)
    local new_root = octave * 12 + (x - 1)
    ctx.root_note = math.min(127, new_root)
    if ctx.events then
      ctx.events:emit("scale:root", {root_note = ctx.root_note})
    end
  elseif y == 2 and x >= 1 and x <= 10 then
    -- Set octave, keep pitch class
    local pc = root % 12
    local new_root = (x - 1) * 12 + pc
    ctx.root_note = math.min(127, new_root)
    if ctx.events then
      ctx.events:emit("scale:root", {root_note = ctx.root_note})
    end
  elseif y == 3 and x >= 1 and x <= 7 then
    -- Scale types 1-7
    ctx.scale_type = x
    if ctx.events then
      ctx.events:emit("scale:type", {scale_type = ctx.scale_type})
    end
  elseif y == 4 and x >= 1 and x <= 7 then
    -- Scale types 8-14
    ctx.scale_type = x + 7
    if ctx.events then
      ctx.events:emit("scale:type", {scale_type = ctx.scale_type})
    end
  end
end

-- Meta-pattern page display
-- Row 1-2: Pattern slot selector (16 slots across 2 rows, same as pattern mode)
-- Row 3: Loop count for selected meta-step (cols 1-7)
-- Row 5: Meta-sequence overview (cols 1-16 = meta-steps)
-- Row 7: Controls (x=1 = toggle active)
function M.draw_meta_pattern_page(ctx, g)
  local meta = ctx.meta
  if not meta then return end

  local sel = meta.selected_step
  local step = meta.steps[sel]

  -- Rows 1-2: Pattern slot selector for selected meta-step
  for slot = 1, 16 do
    local col = ((slot - 1) % 8) + 1
    local row = ((slot - 1) < 8) and 1 or 2
    local populated = pattern.is_populated(ctx.patterns, slot)
    local is_assigned = (step.slot == slot and slot > 0)
    local brightness = 2
    if is_assigned and populated then
      brightness = 15
    elseif is_assigned then
      brightness = 12
    elseif populated then
      brightness = 8
    end
    g:led(col, row, brightness)
  end

  -- Row 3: Loop count bar (1-7)
  for x = 1, 7 do
    local brightness = 2
    if x == step.loops then
      brightness = 15
    elseif x < step.loops then
      brightness = 6
    end
    g:led(x, 3, brightness)
  end

  -- Row 5: Meta-sequence overview
  for i = 1, meta_pattern.MAX_STEPS do
    local is_playback = (meta.active and meta.pos == i)
    local is_selected = (sel == i)
    local has_pattern = (meta.steps[i].slot > 0)
    local brightness = 2
    if is_playback then
      brightness = 15
    elseif is_selected then
      brightness = 12
    elseif has_pattern then
      brightness = 8
    end
    g:led(i, 5, brightness)
  end

  -- Row 6: Cued pattern indicator
  if meta.cued_slot then
    for x = 1, 16 do
      g:led(x, 6, x == meta.cued_slot and 10 or 0)
    end
  end

  -- Row 7: Controls
  g:led(1, 7, meta.active and 15 or 4)
end

-- Meta-pattern page key handler
function M.meta_pattern_key(ctx, x, y)
  local meta = ctx.meta
  if not meta then return end

  -- Rows 1-2: Assign pattern slot to selected meta-step
  if y >= 1 and y <= 2 and x >= 1 and x <= 8 then
    local slot = (y - 1) * 8 + x
    local sel = meta.selected_step
    if meta.steps[sel].slot == slot then
      -- Toggle off: clear step
      meta_pattern.clear_step(meta, sel)
    else
      meta_pattern.set_step(meta, sel, slot, meta.steps[sel].loops)
    end
    if ctx.events then
      ctx.events:emit("meta:edit", { step = sel, slot = meta.steps[sel].slot })
    end
    return
  end

  -- Row 3: Set loop count (1-7)
  if y == 3 and x >= 1 and x <= 7 then
    local sel = meta.selected_step
    meta.steps[sel].loops = x
    return
  end

  -- Row 5: Select meta-step for editing
  if y == 5 and x >= 1 and x <= meta_pattern.MAX_STEPS then
    meta.selected_step = x
    return
  end

  -- Row 6: Cue a pattern slot (press to cue, press again to cancel)
  if y == 6 and x >= 1 and x <= 16 then
    if meta.cued_slot == x then
      meta_pattern.cancel_cue(meta)
    else
      meta_pattern.cue(meta, x)
    end
    return
  end

  -- Row 7: Controls
  if y == 7 and x == 1 then
    meta_pattern.toggle(meta, ctx)
    return
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
