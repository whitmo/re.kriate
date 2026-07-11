-- specs/seamstress_clock_guard_spec.lua
-- Unit coverage for the extracted seamstress clock.resume guard module.
-- Verifies module structure and that install() applies the nil-thread guard
-- without altering behavior for live (non-cancelled) coroutine ids.
--
-- Background: clock.cancel nils the _seamstress.clock.threads table entry,
-- but the C scheduler may still fire a wakeup for that id, causing
-- coroutine.resume(nil) -> crash. This is exacerbated by ratchet's rapid
-- fire-and-cancel pattern. See lib/seamstress/clock_guard.lua.

package.path = package.path .. ";./?.lua"

describe("lib/seamstress/clock_guard", function()
  local UNSET = {}
  local saved_module
  local saved_seamstress

  before_each(function()
    saved_module = package.loaded["lib/seamstress/clock_guard"] == nil and UNSET
      or package.loaded["lib/seamstress/clock_guard"]
    package.loaded["lib/seamstress/clock_guard"] = nil

    saved_seamstress = rawget(_G, "_seamstress") == nil and UNSET or rawget(_G, "_seamstress")
  end)

  after_each(function()
    if saved_module == UNSET then
      package.loaded["lib/seamstress/clock_guard"] = nil
    else
      package.loaded["lib/seamstress/clock_guard"] = saved_module
    end
    if saved_seamstress == UNSET then
      rawset(_G, "_seamstress", nil)
    else
      rawset(_G, "_seamstress", saved_seamstress)
    end
  end)

  it("exposes an install function", function()
    local clock_guard = require("lib/seamstress/clock_guard")
    assert.is_table(clock_guard)
    assert.is_function(clock_guard.install)
  end)

  it("does nothing when _seamstress is absent", function()
    rawset(_G, "_seamstress", nil)
    local clock_guard = require("lib/seamstress/clock_guard")
    assert.has_no.errors(function()
      clock_guard.install()
    end)
  end)

  it("does nothing when _seamstress.clock is absent", function()
    rawset(_G, "_seamstress", {})
    local clock_guard = require("lib/seamstress/clock_guard")
    assert.has_no.errors(function()
      clock_guard.install()
    end)
  end)

  it("passes through resume for a live (non-nil) thread id", function()
    local resumed_with
    rawset(_G, "_seamstress", {
      clock = {
        threads = { [3] = { alive = true } },
        resume = function(id, ...)
          resumed_with = { id, ... }
          return "resumed"
        end,
      },
    })
    local clock_guard = require("lib/seamstress/clock_guard")
    clock_guard.install()

    local result = _seamstress.clock.resume(3, "extra")

    assert.are.equal("resumed", result)
    assert.are.same({ 3, "extra" }, resumed_with)
  end)

  it("swallows resume for a cancelled (nil thread table entry) id without calling original", function()
    local original_called = false
    rawset(_G, "_seamstress", {
      clock = {
        threads = {}, -- id 7 was cancelled: entry nil'd from the threads table
        resume = function()
          original_called = true
          return "should not happen"
        end,
      },
    })
    local clock_guard = require("lib/seamstress/clock_guard")
    clock_guard.install()

    local result = _seamstress.clock.resume(7)

    assert.is_nil(result)
    assert.is_false(original_called)
  end)
end)
