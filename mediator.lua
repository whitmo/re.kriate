-- Minimal mediator implementation for busted event bus
return function()
  local self = { channels = {} }

  function self:subscribe(channel, fn, options)
    if type(fn) ~= "function" then return nil end
    local subs = self.channels[channel] or {}
    local token = { fn = fn, once = options and options.once }
    table.insert(subs, token)
    self.channels[channel] = subs
    return token
  end

  function self:removeSubscriber(token)
    for ch, subs in pairs(self.channels) do
      for i, sub in ipairs(subs) do
        if sub == token then
          table.remove(subs, i)
          if #subs == 0 then self.channels[ch] = nil end
          return true
        end
      end
    end
    return false
  end

  function self:publish(channel, ...)
    local subs = self.channels[channel]
    if not subs then return end
    local to_remove = {}
    for i, sub in ipairs(subs) do
      sub.fn(...)
      if sub.once then table.insert(to_remove, 1, i) end
    end
    for _, idx in ipairs(to_remove) do
      table.remove(subs, idx)
    end
    if #subs == 0 then self.channels[channel] = nil end
  end

  return self
end
