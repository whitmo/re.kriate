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
M.PAGES = {"trigger", "note", "octave", "duration", "velocity", "probability", "mixer", "ratchet", "alt_note", "glide", "alt_track", "meta_pattern", "scale"}

-- Extended page mappings: primary -> extended
M.EXTENDED_PAGES = {trigger = "ratchet", note = "alt_note", octave = "glide"}
-- Reverse: extended -> primary
M.EXTENDED_REVERSE = {ratchet = "trigger", alt_note = "note", glide = "octave"}

-- Nav row (row 8) layout:
-- x=1-4: track select
-- x=5: KEY 1 — time modifier (hold, Ansible KEY 1)
-- x=6: trigger page (press again: ratchet)
-- x=7: note page (press again: alt_note)
-- x=8: octave page (press again: glide)
-- x=9: cycles duration → velocity → probability
-- x=10: KEY 2 — config/alt-track page (press, Ansible KEY 2)
-- x=11: loop modifier (hold)
-- x=12: pattern mode (hold)
-- x=13: mute toggle
-- x=14: probability modifier (hold)
-- x=15: scale
-- x=16: meta (alt-track settings; double-press: meta-pattern sequencer)

local NAV_PAGE = {[6] = "trigger", [7] = "note", [8] = "octave", [9] = "duration"}
-- Page group for x=9: pressing cycles through these pages
local NAV_PAGE_CYCLE_9 = {"duration", "velocity", "probability", "mixer"}
-- Quick lookup: which pages belong to the x=9 cycle group
local NAV_PAGE_CYCLE_9_SET = {duration = true, velocity = true, probability = true, mixer = true}
local NAV_KEY1 = 5    -- Ansible KEY 1: time modifier (hold)
local NAV_KEY2 = 10   -- Ansible KEY 2: config/alt-track (press)
local NAV_LOOP = 11
local NAV_PATTERN = 12
local NAV_MUTE = 13
local NAV_PROB = 14
local NAV_SCALE = 15
local NAV_META = 16

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
  elseif ctx.prob_held then
    -- probability modifier: show per-step probability overlay
    M.draw_value_page(ctx, g, "probability")
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
    elseif page == "ratchet" then
      M.draw_ratchet_page(ctx, g)
    elseif page == "mixer" then
      M.draw_mixer_page(ctx, g)
    else
      -- All other pages (including extended: alt_note, glide) use value display
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
      local in_loop = x >= param.loop_start and x <= param.loop_end
      -- loop region indicator
      if in_loop then
        brightness = 2
      end
      -- step value (dimmer outside loop)
      if param.steps[x] == 1 then
        brightness = in_loop and 8 or 4
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
      elseif row_val < val then
        brightness = in_loop and 3 or 1
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

-- Ratchet page: dedicated sub-gate display (matches kria ansible/n.kria UX)
-- Row 1 (y=1): increment button row (dim markers)
-- Rows 2-6 (y=2-6): subdivision toggles (5 slots, y=2=top/sub5, y=6=bottom/sub1)
-- Row 7 (y=7): decrement button row (dim markers)
function M.draw_ratchet_page(ctx, g)
  local track = ctx.tracks[ctx.active_track]
  local param = track.params.ratchet
  for x = 1, track_mod.NUM_STEPS do
    local count = param.steps[x]
    local bits = param.bits and param.bits[x] or ((1 << count) - 1)
    local in_loop = x >= param.loop_start and x <= param.loop_end
    local is_playhead = x == param.pos and ctx.playing

    -- Row 1: increment
    local inc_brightness = 2
    if is_playhead then inc_brightness = 6 end
    g:led(x, 1, inc_brightness)

    -- Rows 2-6: subdivision toggles
    -- y=2 → bit 4 (subdivision 5, top), y=6 → bit 0 (subdivision 1, bottom)
    for y = 2, 6 do
      local bit_idx = 6 - y  -- y=2→4, y=3→3, y=4→2, y=5→1, y=6→0
      local in_range = bit_idx < count
      local bit_on = (bits >> bit_idx) & 1 == 1
      local brightness = 0

      if in_range and bit_on then
        brightness = in_loop and 12 or 5
      elseif in_range then
        brightness = in_loop and 5 or 2
      end

      if is_playhead and in_range then
        brightness = bit_on and 15 or 6
      end

      g:led(x, y, brightness)
    end

    -- Row 7: decrement
    local dec_brightness = 2
    if is_playhead then dec_brightness = 6 end
    g:led(x, 7, dec_brightness)
  end
end

-- Mixer page: per-track level (cols 1-7), pan (cols 9-15), mute (col 16).
-- Rows 1-4 correspond to tracks 1-4.
--   level: lit columns form a bar from col 1 up to the current level column.
--          col 1 = ~0.0, col 7 = 1.0 (linear).
--   pan:   single lit column at pan position.
--          col 9 = hard left, col 12 = center, col 15 = hard right.
--   mute:  bright when muted.
-- The active track row is highlighted.
function M.level_to_col(level)
  local v = level or 1.0
  if v < 0 then v = 0 end
  if v > 1 then v = 1 end
  local col = math.floor(v * 6 + 0.5) + 1 -- 0.0 -> 1, 1.0 -> 7
  if col < 1 then col = 1 end
  if col > 7 then col = 7 end
  return col
end

function M.col_to_level(col)
  if col < 1 then col = 1 end
  if col > 7 then col = 7 end
  return (col - 1) / 6
end

function M.pan_to_col(pan)
  local v = pan or 0
  if v < -1 then v = -1 end
  if v > 1 then v = 1 end
  -- map [-1, 1] -> [9, 15], center (0) -> 12. Symmetric round-half-away-from-zero.
  local sign = (v < 0) and -1 or 1
  local col = 12 + sign * math.floor(math.abs(v) * 3 + 0.5)
  if col < 9 then col = 9 end
  if col > 15 then col = 15 end
  return col
end

function M.col_to_pan(col)
  if col < 9 then col = 9 end
  if col > 15 then col = 15 end
  return (col - 12) / 3
end

function M.draw_mixer_page(ctx, g)
  local active_track = ctx.active_track or 1
  local mx = ctx.mixer or {level = {}, pan = {}}
  for t = 1, track_mod.NUM_TRACKS do
    local track = ctx.tracks[t]
    local is_active = (t == active_track)
    local is_muted = track and track.muted

    local level = mx.level and mx.level[t] or 1.0
    local level_col = M.level_to_col(level)
    -- Level bar: lit from col 1 to level_col.
    for x = 1, 7 do
      local brightness = 0
      if x <= level_col then
        brightness = (x == level_col) and 12 or 4
        if is_active then brightness = math.min(15, brightness + 3) end
        if is_muted then brightness = math.max(1, brightness - 2) end
      else
        brightness = is_active and 2 or 1
      end
      g:led(x, t, brightness)
    end

    -- Gap column (x=8): unused.
    g:led(8, t, 0)

    -- Pan: center marker dim at col 12, active position bright.
    local pan = mx.pan and mx.pan[t] or 0
    local pan_col = M.pan_to_col(pan)
    for x = 9, 15 do
      local brightness = 1
      if x == 12 then
        brightness = 3 -- center marker
      end
      if x == pan_col then
        brightness = 12
        if is_active then brightness = 15 end
        if is_muted then brightness = math.max(3, brightness - 3) end
      end
      g:led(x, t, brightness)
    end

    -- Mute (col 16).
    local mute_b = is_muted and 15 or (is_active and 4 or 2)
    g:led(16, t, mute_b)
  end
  -- Rows 5-7 stay blank on the mixer page.
  for y = 5, 7 do
    for x = 1, 16 do
      g:led(x, y, 0)
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

-- Value-page row-to-param mapping shared by draw_time_page and time_key so a
-- press on row N edits the same param that row N visually represents.
-- Row 1 = active param (the page's own param). Rows 2-7 = other PARAM_NAMES
-- in order, skipping the active one. Returns nil when row has no mapping.
local function value_page_row_to_param(active_name, row)
  if row == 1 then return active_name end
  local next_row = 2
  for _, name in ipairs(track_mod.PARAM_NAMES) do
    if name ~= active_name then
      if next_row == row then return name end
      next_row = next_row + 1
      if next_row > 7 then return nil end
    end
  end
  return nil
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
    if track.params[param_name] then
      for row = 1, 7 do
        local name = value_page_row_to_param(param_name, row)
        if name then
          local p = track.params[name]
          if p then
            local is_active_row = (row == 1)
            for x = 1, 7 do
              local brightness
              if is_active_row then
                brightness = (x == p.clock_div) and 15 or 3
              else
                brightness = (x == p.clock_div) and 6 or 1
              end
              g:led(x, row, brightness)
            end
          end
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
    local is_cued = (slot == ctx.cued_pattern_slot)
    local brightness = 2
    if is_cued then
      -- cued: distinct mid-bright level so it stands out from current/populated
      brightness = 13
    elseif populated and is_current then
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
-- Row 5: x=1-12 interactive custom-scale mask editor. When scale_type == 15
--        (Custom), LEDs reflect ctx.custom_intervals and row-5 presses toggle
--        semitones. Otherwise shows which chromatic notes are in the active
--        preset scale (read-only visualization).
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

  -- Row 5: custom mask editor (when custom) or preset visualization
  if scale_idx == 15 then
    local mask = ctx.custom_intervals
    for x = 1, 12 do
      local on = mask and mask[x]
      g:led(x, 5, on and 15 or 2)
    end
  elseif ctx.scale_notes and #ctx.scale_notes > 0 then
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
  -- x=5: KEY 1 (time modifier)
  g:led(NAV_KEY1, y, ctx.time_held and 12 or 0)
  -- page select x=6-9 (highlight correct button even when on extended page)
  local active_primary = M.EXTENDED_REVERSE[ctx.active_page] or ctx.active_page
  local on_extended = M.EXTENDED_REVERSE[ctx.active_page] ~= nil
  for x = 6, 8 do
    if NAV_PAGE[x] == active_primary then
      g:led(x, y, on_extended and 8 or 12)
    else
      g:led(x, y, 3)
    end
  end
  -- x=9: lit if current page is in the cycle group (duration/velocity/probability)
  g:led(9, y, NAV_PAGE_CYCLE_9_SET[ctx.active_page] and 12 or 3)
  -- x=10: KEY 2 (config/alt-track)
  local config_active = ctx.active_page == "alt_track" or ctx.active_page == "meta_pattern"
  g:led(NAV_KEY2, y, config_active and 12 or 0)
  -- modifiers (x=11-14)
  g:led(NAV_LOOP, y, ctx.loop_held and 12 or 3)
  g:led(NAV_PATTERN, y, ctx.pattern_held and 12 or 3)
  local muted = ctx.tracks[ctx.active_track] and ctx.tracks[ctx.active_track].muted
  g:led(NAV_MUTE, y, muted and 12 or 3)
  g:led(NAV_PROB, y, ctx.prob_held and 12 or 3)
  -- scale (x=15)
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
  -- KEY 1: time modifier hold (x=5)
  if x == NAV_KEY1 then
    ctx.time_held = (z == 1)
  end
  -- KEY 2: config/alt-track (x=10, press only)
  if x == NAV_KEY2 and z == 1 then
    local old_page = ctx.active_page
    ctx.active_page = "alt_track"
    if ctx.active_page ~= old_page and ctx.events then
      ctx.events:emit("page:select", {page=ctx.active_page, prev=old_page})
    end
  end
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
  -- probability modifier hold (x=14)
  if x == NAV_PROB then
    ctx.prob_held = (z == 1)
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

  -- probability modifier: edit probability values regardless of active page
  if ctx.prob_held then
    M.value_key(ctx, x, y, "probability")
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
  elseif page == "ratchet" then
    M.ratchet_key(ctx, x, y)
  elseif page == "mixer" then
    M.mixer_key(ctx, x, y)
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

-- Mixer page key: row = track (1-4). Sections:
--   x 1-7  -> level for that track (col 1 = 0.0, col 7 = 1.0)
--   x 9-15 -> pan  for that track (col 9 = -1.0, col 12 = 0, col 15 = +1.0)
--   x 16   -> toggle mute
-- Selecting a level/pan cell also selects the active track so subsequent
-- non-mixer interactions target the tapped row without a separate nav step.
function M.mixer_key(ctx, x, y)
  if y < 1 or y > track_mod.NUM_TRACKS then return end
  local mixer = require("lib/mixer")
  local t = y
  ctx.active_track = t
  local params_available = params and params.lookup

  if x >= 1 and x <= 7 then
    local level = M.col_to_level(x)
    if params_available and params.lookup["level_" .. t] then
      -- Params action drives mixer.set_level so voice + events fire once.
      params:set("level_" .. t, math.floor(level * 100 + 0.5))
    else
      mixer.set_level(ctx, t, level)
    end
  elseif x >= 9 and x <= 15 then
    local pan = M.col_to_pan(x)
    if params_available and params.lookup["pan_" .. t] then
      params:set("pan_" .. t, math.floor(pan * 100 + 0.5))
    else
      mixer.set_pan(ctx, t, pan)
    end
  elseif x == 16 then
    local new_muted = not (ctx.tracks[t] and ctx.tracks[t].muted)
    if params_available and params.lookup["mute_" .. t] then
      params:set("mute_" .. t, new_muted and 2 or 1)
    else
      mixer.toggle_mute(ctx, t)
    end
  end
end

-- Ratchet page key: increment/decrement count or toggle sub-gate bits
function M.ratchet_key(ctx, x, y)
  local track = ctx.tracks[ctx.active_track]
  local param = track.params.ratchet

  if y == 1 then
    -- Increment subdivision count
    track_mod.delta_ratchet_count(param, x, 1)
  elseif y == 7 then
    -- Decrement subdivision count
    track_mod.delta_ratchet_count(param, x, -1)
  elseif y >= 2 and y <= 6 then
    -- Toggle sub-gate bit: y=2→bit4, y=3→bit3, y=4→bit2, y=5→bit1, y=6→bit0
    local bit_idx = 6 - y
    track_mod.toggle_ratchet_bit(param, x, bit_idx)
  end
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
-- When playing: queue a quantized transition (applied at next track-1 loop
-- boundary). Pressing the current or already-cued slot cancels the cue.
-- When stopped: load immediately so patterns can be auditioned.
function M.pattern_key(ctx, x, y)
  if x < 1 or x > 8 or y < 1 or y > 2 then return end
  local slot = (y - 1) * 8 + x

  if not ctx.playing then
    ctx.pattern_slot = slot
    pattern.load(ctx, slot)
    if ctx.events then
      ctx.events:emit("pattern:load", {slot=slot})
    end
    return
  end

  -- Playing: cue quantized transition
  if slot == ctx.pattern_slot or slot == ctx.cued_pattern_slot then
    pattern.cancel_cue(ctx)
  else
    pattern.cue(ctx, slot)
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
  elseif y == 5 and x >= 1 and x <= 12 then
    -- Row 5 toggles a semitone in the custom mask and switches to
    -- scale_type=15 (Custom). Preset masks in rows 3-4 are preserved and
    -- resume when the user selects a preset again.
    if not ctx.custom_intervals then
      ctx.custom_intervals = {}
      for i = 1, 12 do ctx.custom_intervals[i] = false end
      ctx.custom_intervals[1] = true  -- ensure root is present
    end
    ctx.custom_intervals[x] = not ctx.custom_intervals[x]
    ctx.scale_type = 15
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
    -- On value pages: each row targets the param shown there (row 1 = active
    -- param, rows 2-7 = other params, same order as draw_time_page). Press
    -- sets that row's param clock_div to x.
    local name = value_page_row_to_param(param_name, y)
    if name then
      local track = ctx.tracks[ctx.active_track]
      local p = track.params[name]
      if p then
        p.clock_div = x
        p.tick = 0
      end
    end
  end
end

return M
