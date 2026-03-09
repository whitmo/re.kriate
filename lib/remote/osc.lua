-- lib/remote/osc.lua
-- OSC transport for the remote API
--
-- Listens on a configurable port and translates OSC messages into
-- api.dispatch() calls. Norns has built-in OSC via osc.event.
--
-- OSC address = API path (e.g. /transport/play)
-- OSC args = positional arguments forwarded to the handler
--
-- Usage:
--   local osc_remote = require("lib/remote/osc")
--   -- in app.init:
--   ctx.remote_osc = osc_remote.enable(ctx, { port = 10111 })
--   -- in cleanup:
--   osc_remote.disable(ctx)

local api = require("lib/remote/api")

local M = {}

--- Convert OSC args (typed values) to string args for api.dispatch.
--- OSC sends ints, floats, and strings — we normalize to the flat
--- string/number array that api.dispatch expects.
local function osc_args_to_table(osc_args)
  local args = {}
  for i, v in ipairs(osc_args) do
    args[i] = v
  end
  return args
end

--- Enable OSC remote control on the given context.
--- Installs an osc.event handler that routes messages with known
--- API prefixes to api.dispatch.
--- @param ctx table  Application context
--- @param opts table|nil  Options: { port = number, reply = bool }
--- @return table  Handle for disable()
function M.enable(ctx, opts)
  opts = opts or {}
  local prefix = opts.prefix or "/re_kriate"

  -- Store previous handler so we can chain
  local prev_handler = osc.event

  osc.event = function(path, args, from)
    -- Strip prefix if present
    local api_path = path
    if prefix and path:sub(1, #prefix) == prefix then
      api_path = path:sub(#prefix + 1)
    end

    -- Try dispatch; fall through to previous handler on unknown path
    local result, err = api.dispatch(ctx, api_path, osc_args_to_table(args))
    if err and err:sub(1, 12) == "unknown path" then
      -- Not ours — pass through
      if prev_handler then
        prev_handler(path, args, from)
      end
      return
    end

    -- Send reply if caller provided a return address
    if from and opts.reply ~= false then
      local reply_path = api_path .. "/reply"
      if err then
        osc.send(from, reply_path, {"error", err})
      elseif type(result) == "table" then
        -- Flatten table values for OSC (arrays become positional args)
        local flat = {}
        if result[1] ~= nil then
          -- array-like
          for _, v in ipairs(result) do flat[#flat + 1] = v end
        else
          -- key-value: interleave k, v
          for k, v in pairs(result) do
            flat[#flat + 1] = tostring(k)
            flat[#flat + 1] = v
          end
        end
        osc.send(from, reply_path, flat)
      elseif result == true then
        osc.send(from, reply_path, {"ok"})
      else
        osc.send(from, reply_path, {result})
      end
    end
  end

  local handle = { prev_handler = prev_handler }
  ctx.remote_osc = handle
  return handle
end

--- Disable OSC remote control, restoring the previous handler.
--- @param ctx table  Application context
function M.disable(ctx)
  if ctx.remote_osc then
    osc.event = ctx.remote_osc.prev_handler
    ctx.remote_osc = nil
  end
end

return M
