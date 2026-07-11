-- lib/seamstress/clock_guard.lua
-- Guards seamstress clock.resume against cancelled-but-still-scheduled coroutines.
-- clock.cancel nils the thread table entry, but the C scheduler may still fire
-- a wakeup for that id, causing coroutine.resume(nil) → crash.
-- This is exacerbated by ratchet's rapid fire-and-cancel pattern.

local M = {}

function M.install()
  if _seamstress and _seamstress.clock then
    local _clock = _seamstress.clock
    local _original_resume = _clock.resume
    _clock.resume = function(id, ...)
      if _clock.threads[id] == nil then return end
      return _original_resume(id, ...)
    end
  end
end

return M
