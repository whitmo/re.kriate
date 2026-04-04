-- lib/seamstress/screen_ui.lua
-- Seamstress screen display: title, track/page, play state, step positions

local pattern = require("lib/pattern")

local M = {}

-- Extended page -> primary page mapping
local EXTENDED_TO_PRIMARY = {ratchet = "trigger", alt_note = "note", glide = "octave"}

-- Page tray: groups of pages with abbreviated labels
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

-- Pattern slot indicator colors
local SLOT_DIM = {40, 40, 60, 255}
local SLOT_MEDIUM = {100, 100, 140, 255}
local SLOT_BRIGHT = {200, 200, 255, 255}

-- Draw 9 pattern slot indicators
local function draw_pattern_slots(ctx)
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
    screen.move(start_x + (i - 1) * 14, 122)
    screen.rect_fill(10, 5)
  end
end

-- Draw transient pattern message if not expired
local function draw_pattern_message(ctx)
  if not ctx.pattern_message then return end
  if os.clock() - ctx.pattern_message.time >= 1.5 then
    ctx.pattern_message = nil
    return
  end
  screen.color(200, 200, 255, 255)
  screen.move(80, 112)
  screen.text(ctx.pattern_message.text)
end

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

  -- Page indicator tray
  local tray_y = 112
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
    screen.move(x, tray_y)
    screen.text(label)
  end

  -- Pattern bank indicators and transient message
  draw_pattern_slots(ctx)
  draw_pattern_message(ctx)

  screen.refresh()
end

return M
