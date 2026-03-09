-- lib/seamstress/screen_ui.lua
-- Seamstress screen display: title, track/page, play state, step positions

local M = {}

-- Extended page -> primary page mapping
local EXTENDED_TO_PRIMARY = {ratchet = "trigger", alt_note = "note", glide = "octave"}

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

  screen.refresh()
end

return M
