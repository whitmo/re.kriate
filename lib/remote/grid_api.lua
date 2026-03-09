-- lib/remote/grid_api.lua
-- Remote API extensions for grid provider
--
-- Returns a table of handler functions keyed by API path, compatible
-- with calm-hawk's remote API dispatch system (lib/remote/api.lua).
--
-- API paths:
--   /grid/key <x> <y> <z>     -- inject a grid key press/release
--   /grid/state                -- get full LED state (for remote UIs)
--   /grid/led <x> <y>         -- get single LED brightness
--   /grid/info                 -- get grid dimensions and provider info
--
-- Integration with remote API:
--   When lib/remote/api.lua adds register_handler(), call:
--     for path, handler in pairs(grid_api.handlers) do
--       api.register_handler(path, handler)
--     end
--
-- Standalone use (without remote API):
--   local result, err = grid_api.handlers["/grid/key"](ctx, {5, 3, 1})

local M = {}
M.handlers = {}

-- /grid/key: inject a grid key press/release
-- Args: x, y, z (1-indexed, z=1 press, z=0 release)
M.handlers["/grid/key"] = function(ctx, args)
  if not ctx.g or not ctx.g.key then
    return nil, "no grid connected"
  end
  local x = tonumber(args and args[1])
  local y = tonumber(args and args[2])
  local z = tonumber(args and args[3])
  if not x or not y or not z then
    return nil, "requires x, y, z arguments"
  end
  local max_x = ctx.g.cols and ctx.g:cols() or 16
  local max_y = ctx.g.rows and ctx.g:rows() or 8
  if x < 1 or x > max_x or y < 1 or y > max_y then
    return nil, "x must be 1-" .. max_x .. ", y must be 1-" .. max_y
  end
  if z ~= 0 and z ~= 1 then
    return nil, "z must be 0 or 1"
  end
  ctx.g.key(x, y, z)
  return true
end

-- /grid/state: get full LED state for rendering remote grid UIs
M.handlers["/grid/state"] = function(ctx)
  if not ctx.g then
    return nil, "no grid connected"
  end
  if ctx.g.get_state then
    return ctx.g:get_state()
  end
  return nil, "grid provider does not support state reading"
end

-- /grid/led: get single LED brightness
-- Args: x, y
M.handlers["/grid/led"] = function(ctx, args)
  if not ctx.g then
    return nil, "no grid connected"
  end
  if not ctx.g.get_led then
    return nil, "grid provider does not support LED reading"
  end
  local x = tonumber(args and args[1])
  local y = tonumber(args and args[2])
  if not x or not y then
    return nil, "requires x, y arguments"
  end
  return ctx.g:get_led(x, y)
end

-- /grid/info: get grid dimensions and provider capabilities
M.handlers["/grid/info"] = function(ctx)
  if not ctx.g then
    return nil, "no grid connected"
  end
  local cols = ctx.g.cols and ctx.g:cols() or 16
  local rows = ctx.g.rows and ctx.g:rows() or 8
  return {
    cols = cols,
    rows = rows,
    readable = ctx.g.get_led ~= nil,
    has_state = ctx.g.get_state ~= nil,
  }
end

return M
