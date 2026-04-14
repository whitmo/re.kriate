-- lib/seamstress/screen_ui.lua
-- Seamstress screen display: title, track/page, play state, step positions
--
-- Two rendering paths:
--   - M.redraw(ctx)                         — legacy single-pane layout (tests)
--   - M.draw_side_panel(ctx, base_x, ...)   — vertical info panel to the right
--                                             of the simulated grid (runtime)

local pattern = require("lib/pattern")

local M = {}

-- ============================================================================
-- Page naming
-- ============================================================================

local EXTENDED_TO_PRIMARY = {ratchet = "trigger", alt_note = "note", glide = "octave"}

-- Short (abbreviated) labels used by the legacy bottom tray and screen_ui_spec.
local PAGE_TRAY = {
  {pages = {"trigger", "ratchet"},    labels = {"TR", "RA"}},
  {pages = {"note", "alt_note"},      labels = {"NO", "AN"}},
  {pages = {"octave", "glide"},       labels = {"OC", "GL"}},
  {pages = {"duration"},              labels = {"DU"}},
  {pages = {"velocity"},              labels = {"VE"}},
  {pages = {"probability"},           labels = {"PR"}},
  {pages = {"alt_track"},             labels = {"AT"}},
  {pages = {"meta_pattern"},          labels = {"MP"}},
  {pages = {"scale"},                 labels = {"SC"}},
}

-- Full names shown in the side panel (more data, fewer abbreviations per the
-- re-1mo aesthetic review).
local PAGE_FULL_NAME = {
  trigger      = "trigger",
  ratchet      = "ratchet",
  note         = "note",
  alt_note     = "alt note",
  octave       = "octave",
  glide        = "glide",
  duration     = "duration",
  velocity     = "velocity",
  probability  = "probability",
  alt_track    = "alt track",
  meta_pattern = "meta pattern",
  scale        = "scale",
}

-- ============================================================================
-- Side panel sizing
-- ============================================================================

-- Horizontal panel to the right of the grid. 120px gives room for page names
-- like "probability" and 4 track status lines with step counters.
M.TRAY_WIDTH = 120

-- Kept for backwards compatibility with any caller that still references the
-- old bottom-tray height. The runtime no longer uses it.
M.TRAY_HEIGHT = 20

-- ============================================================================
-- Pattern slot indicator colors (shared)
-- ============================================================================

local SLOT_DIM = {40, 40, 60, 255}
local SLOT_MEDIUM = {100, 100, 140, 255}
local SLOT_BRIGHT = {200, 200, 255, 255}

-- Draw 9 pattern slot indicators at given base_y (legacy tray + side panel).
local function draw_pattern_slots_centered(ctx, base_y)
  local start_x = math.floor((256 - 122) / 2) -- center 9 slots of width 10 with 14px pitch
  for i = 1, 9 do
    local color = SLOT_DIM
    if ctx.patterns and pattern.is_populated(ctx.patterns, i) then
      color = SLOT_MEDIUM
    end
    if ctx.active_pattern == i then
      color = SLOT_BRIGHT
    end
    screen.color(color[1], color[2], color[3], color[4])
    screen.move(start_x + (i - 1) * 14, base_y + 12)
    screen.rect_fill(10, 5)
  end
end

-- Draw 9 pattern slot indicators spanning the panel width at the given y.
local function draw_pattern_slots_panel(ctx, base_x, panel_w, y)
  local slot_w = 8
  local slot_h = 6
  local padding = 6
  local available = panel_w - padding * 2
  local pitch = math.floor(available / 9)
  local origin_x = base_x + padding + math.floor((available - pitch * 9) / 2)
  for i = 1, 9 do
    local color = SLOT_DIM
    if ctx.patterns and pattern.is_populated(ctx.patterns, i) then
      color = SLOT_MEDIUM
    end
    if ctx.active_pattern == i then
      color = SLOT_BRIGHT
    end
    screen.color(color[1], color[2], color[3], color[4])
    screen.move(origin_x + (i - 1) * pitch, y)
    screen.rect_fill(slot_w, slot_h)
  end
end

-- Legacy transient pattern message (centered above bottom tray).
local function draw_pattern_message_legacy(ctx, base_y)
  if not ctx.pattern_message then return end
  if os.clock() - ctx.pattern_message.time >= 1.5 then
    ctx.pattern_message = nil
    return
  end
  screen.color(200, 200, 255, 255)
  screen.move(80, base_y + 2)
  screen.text(ctx.pattern_message.text)
end

-- ============================================================================
-- Legacy bottom tray (still used by M.redraw for tests)
-- ============================================================================

--- Draw page tray, pattern slots, and pattern message as an overlay.
--- @param ctx table  Application context
--- @param base_y number  Y pixel offset for the top of the tray area
function M.draw_tray(ctx, base_y)
  local tray_spacing = 28
  local tray_x = 5
  for i, group in ipairs(PAGE_TRAY) do
    local x = tray_x + (i - 1) * tray_spacing
    local label = group.labels[1]
    local active = false
    for j, p in ipairs(group.pages) do
      if ctx.active_page == p then
        label = group.labels[j]
        active = true
        break
      end
    end
    if active then
      screen.color(200, 200, 255, 255)
    else
      screen.color(60, 60, 80, 255)
    end
    screen.move(x, base_y + 2)
    screen.text(label)
  end

  draw_pattern_slots_centered(ctx, base_y)
  draw_pattern_message_legacy(ctx, base_y)
end

-- ============================================================================
-- Side panel (runtime layout — right of the grid)
-- ============================================================================

-- Remember the most recent click so the dynamic panel always shows *something*
-- useful after the first press, even across long idle windows.
local LAST_KEY_STALE = 30.0

local function draw_text(x, y, str, rgba)
  screen.color(rgba[1], rgba[2], rgba[3], rgba[4] or 255)
  screen.move(x, y)
  screen.text(str)
end

local function page_label_for(page)
  return PAGE_FULL_NAME[page] or page or "—"
end

local function draw_transport_line(ctx, base_x, y)
  if ctx.playing then
    draw_text(base_x + 8, y, "playing", {100, 255, 140, 255})
  else
    draw_text(base_x + 8, y, "stopped", {255, 120, 120, 255})
  end
end

local function draw_tracks(ctx, base_x, y0)
  if not ctx.tracks then return y0 end
  local line_h = 10
  for t = 1, 4 do
    local track = ctx.tracks[t]
    if track then
      local trig = track.params.trigger
      local is_active = ctx.active_track == t
      local col
      if track.muted then
        col = {110, 110, 130, 255}
      elseif is_active then
        col = {220, 220, 255, 255}
      else
        col = {160, 160, 190, 255}
      end
      local marker = is_active and ">" or " "
      local tail = track.muted and " mute" or ""
      local line = string.format("%sT%d %2d/%2d%s", marker, t, trig.pos, trig.loop_end, tail)
      draw_text(base_x + 6, y0 + (t - 1) * line_h, line, col)
    end
  end
  return y0 + line_h * 4
end

local function draw_active_page(ctx, base_x, panel_w, y)
  local page = ctx.active_page or "—"
  local primary = EXTENDED_TO_PRIMARY[page]
  local page_text
  if primary then
    page_text = page_label_for(primary) .. " > " .. page_label_for(page)
  else
    page_text = page_label_for(page)
  end
  draw_text(base_x + 6, y, "page", {130, 130, 160, 255})
  draw_text(base_x + 6, y + 10, page_text, {220, 220, 255, 255})
  return y + 22
end

local function draw_active_track(ctx, base_x, y)
  draw_text(base_x + 6, y, "track", {130, 130, 160, 255})
  draw_text(base_x + 6, y + 10, "track " .. tostring(ctx.active_track or "—"),
    {220, 220, 255, 255})
  return y + 22
end

local function draw_last_key(ctx, base_x, y)
  draw_text(base_x + 6, y, "last press", {130, 130, 160, 255})
  local lk = ctx.last_key
  if lk and (os.clock() - (lk.time or 0) < LAST_KEY_STALE) then
    local arrow = lk.z == 1 and "▼" or "▲"
    local fresh = (os.clock() - (lk.time or 0)) < 0.25
    local col = fresh and {255, 240, 180, 255} or {180, 190, 210, 255}
    draw_text(base_x + 6, y + 10,
      string.format("(%2d,%d) %s", lk.x or 0, lk.y or 0, arrow), col)
  else
    draw_text(base_x + 6, y + 10, "(—)", {100, 100, 120, 255})
  end
  return y + 22
end

local function draw_pattern_line(ctx, base_x, panel_w, y)
  draw_text(base_x + 6, y, "patterns", {130, 130, 160, 255})
  draw_pattern_slots_panel(ctx, base_x, panel_w, y + 10)
  -- Transient save/load message below the indicators, self-expiring.
  if ctx.pattern_message then
    if os.clock() - ctx.pattern_message.time >= 1.5 then
      ctx.pattern_message = nil
    else
      draw_text(base_x + 6, y + 22, ctx.pattern_message.text, {220, 220, 255, 255})
    end
  end
  return y + 34
end

--- Render the runtime side panel to the right of the simulated grid.
--- @param ctx table  Application context
--- @param base_x number  Left edge of the panel in screen pixels
--- @param panel_w number  Panel width in pixels
--- @param panel_h number  Panel height in pixels
function M.draw_side_panel(ctx, base_x, panel_w, panel_h)
  -- Subtle panel background distinct from grid canvas.
  screen.color(14, 14, 22, 255)
  screen.move(base_x, 0)
  screen.rect_fill(panel_w, panel_h)

  -- 1px left divider against the grid.
  screen.color(40, 40, 60, 255)
  screen.move(base_x, 0)
  screen.rect_fill(1, panel_h)

  local y = 6
  draw_text(base_x + 6, y, "re.kriate", {220, 220, 255, 255})
  y = y + 12
  draw_transport_line(ctx, base_x, y)
  y = y + 12

  -- Track rows
  y = draw_tracks(ctx, base_x, y)
  y = y + 4

  y = draw_active_page(ctx, base_x, panel_w, y)
  y = draw_active_track(ctx, base_x, y)
  y = draw_last_key(ctx, base_x, y)
  draw_pattern_line(ctx, base_x, panel_w, y)
end

-- ============================================================================
-- Legacy single-pane redraw (consumed only by specs/screen_ui_spec.lua and
-- specs/pattern_bank_ui_spec.lua). Kept stable so existing tests continue to
-- describe screen_ui's contract.
-- ============================================================================

function M.redraw(ctx)
  screen.clear()

  -- Background
  screen.color(10, 10, 20, 255)
  screen.move(1, 1)
  screen.rect_fill(256, 128)

  -- Title
  screen.color(200, 200, 255, 255)
  screen.move(10, 20)
  screen.text("re.kriate")

  -- Track + page (with extended page indicator)
  screen.color(150, 150, 180, 255)
  screen.move(10, 40)
  local page = ctx.active_page
  local primary = EXTENDED_TO_PRIMARY[page]
  if primary then
    screen.text("track " .. ctx.active_track .. "  |  " .. primary .. " > " .. page)
  else
    screen.text("track " .. ctx.active_track .. "  |  " .. page)
  end

  -- Play state
  if ctx.playing then
    screen.color(100, 255, 100, 255)
  else
    screen.color(255, 100, 100, 255)
  end
  screen.move(10, 60)
  screen.text(ctx.playing and "playing" or "stopped")

  -- Track step positions
  if ctx.tracks then
    for t = 1, 4 do
      local track = ctx.tracks[t]
      if track then
        local trig = track.params.trigger
        screen.move(10, 75 + (t - 1) * 12)
        if track.muted then
          screen.color(80, 80, 100, 255)
          screen.text("T" .. t .. " mute  " .. trig.pos .. "/" .. trig.loop_end)
        else
          screen.color(120, 120, 150, 255)
          screen.text("T" .. t .. " step " .. trig.pos .. "/" .. trig.loop_end)
        end
      end
    end
  end

  -- Page indicator tray + pattern bank overlay
  M.draw_tray(ctx, 110)

  screen.refresh()
end

return M
