-- lib/events.lua
-- Lightweight pub/sub event bus for decoupled module communication.
-- No dependencies outside Lua stdlib. No global state.
--
-- Usage:
--   local events = require("lib/events")
--   local bus = events.new()
--   local unsub = bus:on("voice:note", function(data) ... end)
--   bus:emit("voice:note", {track = 1, note = 60})
--   unsub()
--
-- Event taxonomy (colon-separated namespaces):
--   sequencer:start       -- playback started
--   sequencer:stop        -- playback stopped
--   sequencer:reset       -- playheads reset
--   sequencer:step        -- {track, step, vals}      a track advanced one step
--   voice:note            -- {track, note, vel, dur}  a note was played
--   grid:key              -- {x, y, z}                grid key press/release
--   track:select          -- {track}                  active track changed
--   track:mute            -- {track, muted}           track mute toggled
--   page:select           -- {page, prev}             active page changed
--   pattern:load          -- {slot}                   pattern loaded

local M = {}

-- Bus prototype
local Bus = {}
Bus.__index = Bus

--- Create a new, independent event bus instance.
--- @return table bus
function M.new()
  local self = setmetatable({}, Bus)
  -- _exact: event_name -> array of {fn, id}
  self._exact = {}
  -- _wild: prefix -> array of {fn, id}  (for "prefix:*" subscriptions)
  self._wild = {}
  -- monotonically increasing id for safe removal during iteration
  self._next_id = 1
  return self
end

--- Generate a unique subscription id.
local function next_id(self)
  local id = self._next_id
  self._next_id = id + 1
  return id
end

--- Subscribe to an exact event name.
--- @param event string  Event name (e.g. "voice:note")
--- @param fn function   Handler receiving (data)
--- @return function     Call to unsubscribe
function Bus:on(event, fn)
  -- Detect wildcard subscriptions: "something:*"
  if event:sub(-2) == ":*" then
    return self:_on_wild(event:sub(1, -3), fn)
  end

  if not self._exact[event] then
    self._exact[event] = {}
  end
  local id = next_id(self)
  local entry = {fn = fn, id = id}
  table.insert(self._exact[event], entry)

  local removed = false
  return function()
    if removed then return end
    removed = true
    self:_remove_exact(event, id)
  end
end

--- Subscribe to a wildcard: prefix matches any event starting with "prefix:".
--- Handler receives (event_name, data).
--- @param prefix string  The prefix before ":*"
--- @param fn function    Handler receiving (event_name, data)
--- @return function      Call to unsubscribe
function Bus:_on_wild(prefix, fn)
  if not self._wild[prefix] then
    self._wild[prefix] = {}
  end
  local id = next_id(self)
  local entry = {fn = fn, id = id}
  table.insert(self._wild[prefix], entry)

  local removed = false
  return function()
    if removed then return end
    removed = true
    self:_remove_wild(prefix, id)
  end
end

--- One-shot subscription. Auto-unsubscribes after the handler fires once.
--- @param event string  Event name (supports wildcards)
--- @param fn function   Handler
--- @return function     Call to unsubscribe early
function Bus:once(event, fn)
  local unsub
  local is_wild = event:sub(-2) == ":*"

  if is_wild then
    unsub = self:on(event, function(event_name, data)
      unsub()
      fn(event_name, data)
    end)
  else
    unsub = self:on(event, function(data)
      unsub()
      fn(data)
    end)
  end

  return unsub
end

--- Emit an event, calling all matching handlers.
--- Handlers are called in FIFO order. Errors are caught and printed.
--- Safe to call emit() or unsub() from within a handler.
--- @param event string  Event name
--- @param data table|nil  Event payload (shallow-copied per handler)
function Bus:emit(event, data)
  data = data or {}

  -- Exact subscribers: snapshot the list so mutations during iteration are safe
  local exact_list = self._exact[event]
  if exact_list then
    -- Snapshot: copy the array of entries
    local snapshot = {}
    for i = 1, #exact_list do
      snapshot[i] = exact_list[i]
    end
    for i = 1, #snapshot do
      local entry = snapshot[i]
      -- Check the entry is still subscribed (not removed during iteration)
      if self:_entry_alive(self._exact[event], entry.id) then
        local copy = self:_shallow_copy(data)
        local ok, err = pcall(entry.fn, copy)
        if not ok then
          print("[events] handler error on '" .. event .. "': " .. tostring(err))
        end
      end
    end
  end

  -- Wildcard subscribers: match any prefix where event starts with "prefix:"
  -- Extract the prefix from the event name
  local colon_pos = event:find(":", 1, true)
  if colon_pos then
    local prefix = event:sub(1, colon_pos - 1)
    local wild_list = self._wild[prefix]
    if wild_list then
      local snapshot = {}
      for i = 1, #wild_list do
        snapshot[i] = wild_list[i]
      end
      for i = 1, #snapshot do
        local entry = snapshot[i]
        if self:_entry_alive(self._wild[prefix], entry.id) then
          local copy = self:_shallow_copy(data)
          local ok, err = pcall(entry.fn, event, copy)
          if not ok then
            print("[events] wildcard handler error on '" .. event .. "': " .. tostring(err))
          end
        end
      end
    end
  end
end

--- Remove all handlers for a specific event.
--- @param event string  Event name
function Bus:off(event)
  if event:sub(-2) == ":*" then
    local prefix = event:sub(1, -3)
    self._wild[prefix] = nil
  else
    self._exact[event] = nil
  end
end

--- Remove all handlers from the bus.
function Bus:clear()
  self._exact = {}
  self._wild = {}
end

--- Count handlers for a specific event (exact match only).
--- @param event string  Event name
--- @return number
function Bus:count(event)
  if event:sub(-2) == ":*" then
    local prefix = event:sub(1, -3)
    local list = self._wild[prefix]
    return list and #list or 0
  end
  local list = self._exact[event]
  return list and #list or 0
end

-- Internal helpers --

function Bus:_remove_exact(event, id)
  local list = self._exact[event]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].id == id then
      table.remove(list, i)
      break
    end
  end
  if #list == 0 then
    self._exact[event] = nil
  end
end

function Bus:_remove_wild(prefix, id)
  local list = self._wild[prefix]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].id == id then
      table.remove(list, i)
      break
    end
  end
  if #list == 0 then
    self._wild[prefix] = nil
  end
end

function Bus:_entry_alive(list, id)
  if not list then return false end
  for i = 1, #list do
    if list[i].id == id then
      return true
    end
  end
  return false
end

function Bus:_shallow_copy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

return M
