-- specs/lib/host_stubs.lua
-- Shared save/restore helpers for host-runtime globals (params, clock, grid,
-- screen, midi, ...) that spec files fake out.
--
-- Why this exists: under this project's `--no-auto-insulate` busted flag
-- (see scripts/busted.sh), every spec file runs in the SAME Lua process, in
-- file order. A spec that does `rawset(_G, "params", {...})` at module load
-- time (i.e. outside any before_each) installs that fake once, when busted
-- requires the file, and it stays in `_G` for every spec that runs after it
-- -- there is no per-file insulation to reset it. Whichever such file loads
-- last "wins" for the rest of the process, and any file that assumes
-- `_G.params` is absent (or a specific shape) can silently break depending
-- on file execution order.
--
-- The fix is mechanical: snapshot the globals you're about to fake in a
-- before_each, and restore them in the matching after_each. This module
-- factors out that snapshot/restore bookkeeping so specs don't hand-roll it
-- (see specs/platform_spec.lua and specs/seamstress_entrypoint_spec.lua for
-- the hand-rolled versions this generalizes, and specs/ui_spec_spec.lua's
-- mixer describe block for the single-global version this was modeled on).
--
-- Usage (single global):
--   local host_stubs = require("specs/lib/host_stubs")
--   local saved_params
--   before_each(function()
--     saved_params = host_stubs.save_and_clear("params")
--     rawset(_G, "params", my_fake_params)
--   end)
--   after_each(function()
--     host_stubs.restore("params", saved_params)
--   end)
--
-- Usage (multiple globals):
--   local HOST_GLOBALS = {"params", "clock", "grid"}
--   local saved
--   before_each(function()
--     saved = host_stubs.snapshot(HOST_GLOBALS)
--     rawset(_G, "params", my_fake_params)
--     rawset(_G, "clock", my_fake_clock)
--     rawset(_G, "grid", my_fake_grid)
--   end)
--   after_each(function()
--     host_stubs.restore_all(saved)
--   end)

local M = {}

-- Sentinel distinguishing "this global was genuinely absent" from "this
-- global's saved value happens to be nil" inside a snapshot table (a plain
-- Lua table can't hold a `nil` value at a key, so pairs() would silently
-- skip it on restore without this).
local UNSET = setmetatable({}, {__tostring = function() return "<host_stubs.UNSET>" end})
M.UNSET = UNSET

--- Save the current value of a single global and clear it.
--- @param name string  Global name (e.g. "params")
--- @return any  The value that was there before (nil if it was absent)
function M.save_and_clear(name)
  local saved = rawget(_G, name)
  rawset(_G, name, nil)
  return saved
end

--- Restore a single global to a previously-saved value.
--- @param name string  Global name
--- @param value any     Value returned by save_and_clear
function M.restore(name, value)
  rawset(_G, name, value)
end

--- Snapshot several globals at once, without clearing them.
--- @param names table  Array of global names
--- @return table  Opaque snapshot to pass to restore_all
function M.snapshot(names)
  local saved = {}
  for _, name in ipairs(names) do
    local v = rawget(_G, name)
    saved[name] = (v == nil) and UNSET or v
  end
  return saved
end

--- Restore every global captured in a snapshot back to its saved value,
--- setting it to nil if it was absent when snapshotted.
--- @param saved table  Snapshot from M.snapshot
function M.restore_all(saved)
  for name, v in pairs(saved) do
    if v == UNSET then
      rawset(_G, name, nil)
    else
      rawset(_G, name, v)
    end
  end
end

--- Convenience wrapper: snapshot `names`, run `install()` to set up fakes,
--- and return a closure that restores the snapshot. Lets a before_each do
--- the snapshot+install in one call, paired with an after_each that just
--- calls the returned function.
--- @param names table  Array of global names
--- @param install function|nil  Called immediately after snapshotting
--- @return function  Call with no args to restore the snapshot
function M.stub(names, install)
  local saved = M.snapshot(names)
  if install then install() end
  return function() M.restore_all(saved) end
end

return M
