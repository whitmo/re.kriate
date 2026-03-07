-- lib/seamstress/screen_ui.lua
-- Minimal seamstress screen display: title, track/page, play state, step positions

local M = {}

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

  -- Track + page
  screen.color(150, 150, 180, 255)
  screen.move(10, 40)
  screen.text("track " .. ctx.active_track .. "  |  " .. ctx.active_page)

  -- Play state
  if ctx.playing then
    screen.color(100, 255, 100, 255)
  else
    screen.color(255, 100, 100, 255)
  end
  screen.move(10, 60)
  screen.text(ctx.playing and "playing" or "stopped")

  -- Track step positions
  screen.color(120, 120, 150, 255)
  if ctx.tracks then
    for t = 1, 4 do
      local track = ctx.tracks[t]
      if track then
        local trig = track.params.trigger
        screen.move(10, 75 + (t - 1) * 12)
        screen.text("T" .. t .. " step " .. trig.pos .. "/" .. trig.loop_end)
      end
    end
  end

  screen.refresh()
end

return M
