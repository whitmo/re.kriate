-- lib/button_events.lua
-- Layer 1 of the declarative UI spec framework: classifies raw press/
-- release events into semantic button events, independent of what those
-- events MEAN in any given page or mode. That resolution — "this button
-- event, in this context" — is layer 2 (see ui_spec.lua).
--
-- Recognized events (returned by M.press):
--   press          -- the default: a fresh press of a control
--   double_press   -- this control's previous release was within
--                     DOUBLE_PRESS_WINDOW seconds, with no other control
--                     pressed in between
--   combo          -- a different control is currently down (checked
--                     before double_press, so it takes priority)
--
-- "hold" is deliberately not a discrete event here. Every current
-- hold-modifier in this codebase (loop/pattern/time/prob, see
-- ui_spec.lua's `modifier` kind) needs to know it's held from the
-- instant of press, not after some threshold elapses — so "hold" is
-- simply the ongoing is_down() state between a control's press and
-- release, of any duration. Callers wanting classic long-press-vs-tap
-- behavior (e.g. a future grid-based pattern save) compare press/release
-- timestamps themselves; this module doesn't presume a threshold.

local M = {}

M.DOUBLE_PRESS_WINDOW = 0.35 -- seconds

--- Create a new, empty button-event tracker.
function M.new()
  return {
    down = {},            -- id -> press timestamp, for controls currently held
    last_release = {},    -- id -> release timestamp, for double-press detection
    last_activity_id = nil, -- id of whichever control most recently pressed
                             -- or released; double_press requires this to
                             -- still be `id` (i.e. nothing else happened
                             -- in between) as well as being within the window
  }
end

--- Register a press of `id` at time `now` (seconds, e.g. os.clock()).
--- Returns the classified event: "combo", "double_press", or "press".
function M.press(tracker, id, now)
  for other_id in pairs(tracker.down) do
    if other_id ~= id then
      tracker.down[id] = now
      tracker.last_activity_id = id
      return "combo"
    end
  end

  local event = "press"
  local last = tracker.last_release[id]
  if last and (now - last) <= M.DOUBLE_PRESS_WINDOW and tracker.last_activity_id == id then
    event = "double_press"
  end

  tracker.down[id] = now
  tracker.last_activity_id = id
  return event
end

--- Register a release of `id` at time `now`. Returns true if `id` was
--- actually down (a real release), false otherwise (defensive: ignore
--- a release with no matching press).
function M.release(tracker, id, now)
  if not tracker.down[id] then return false end
  tracker.down[id] = nil
  tracker.last_release[id] = now
  tracker.last_activity_id = id
  return true
end

--- Is `id` currently held down? This is the "hold" state: true from the
--- instant of press until release, regardless of duration.
function M.is_down(tracker, id)
  return tracker.down[id] ~= nil
end

--- How many controls are currently held down.
function M.down_count(tracker)
  local n = 0
  for _ in pairs(tracker.down) do n = n + 1 end
  return n
end

return M
