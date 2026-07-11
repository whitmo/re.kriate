-- specs/button_events_spec.lua
-- Layer 1 of the declarative UI spec framework: classifies raw press/
-- release timing into semantic button events (press, double_press, combo)
-- independent of what those events MEAN in any given page or mode — that
-- resolution is layer 2 (see specs/ui_spec_spec.lua and ui_spec.lua's
-- BODY table for "context events": a button event interpreted within a
-- particular page/modifier context).
--
-- "hold" is deliberately not a discrete event fired by this module — every
-- current hold-modifier in this codebase (loop/pattern/time/prob) needs to
-- know it's held from the instant of press, not after some threshold
-- elapses, so "hold" is simply the ongoing is_down() state between a
-- control's press and release, of any duration.

package.path = package.path .. ";./?.lua"

local button_events = require("lib/button_events")

describe("button_events", function()

  describe("press classification", function()

    it("classifies a fresh press as 'press'", function()
      local t = button_events.new()
      assert.are.equal("press", button_events.press(t, "a", 0.0))
    end)

    it("classifies a second press of the same id shortly after release as 'double_press'", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      button_events.release(t, "a", 0.05)
      assert.are.equal("double_press", button_events.press(t, "a", 0.1))
    end)

    it("classifies a press after the double-press window has elapsed as 'press'", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      button_events.release(t, "a", 0.05)
      assert.are.equal("press",
        button_events.press(t, "a", 0.05 + button_events.DOUBLE_PRESS_WINDOW + 0.01))
    end)

    it("classifies a press of a different id while another id is held as 'combo'", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      assert.are.equal("combo", button_events.press(t, "b", 0.1))
    end)

    it("combo takes priority over double_press when both conditions hold", function()
      local t = button_events.new()
      -- "a" is pressed and released quickly, then held down as a modifier
      button_events.press(t, "a", 0.0)
      button_events.release(t, "a", 0.05)
      button_events.press(t, "a", 0.1) -- this would be a double_press on its own
      -- while "a" is down, "b" is pressed -- combo, not affected by a's history
      assert.are.equal("combo", button_events.press(t, "b", 0.15))
    end)

    it("does not classify as double_press if a different id was pressed in between", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      button_events.release(t, "a", 0.05)
      button_events.press(t, "b", 0.06)
      button_events.release(t, "b", 0.07)
      assert.are.equal("press", button_events.press(t, "a", 0.1))
    end)

  end)

  describe("release", function()

    it("returns true and clears down state for a real release", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      assert.is_true(button_events.is_down(t, "a"))
      assert.is_true(button_events.release(t, "a", 0.1))
      assert.is_false(button_events.is_down(t, "a"))
    end)

    it("returns false for a release with no matching press", function()
      local t = button_events.new()
      assert.is_false(button_events.release(t, "a", 0.1))
    end)

  end)

  describe("is_down (the 'hold' state)", function()

    it("is false before any press", function()
      local t = button_events.new()
      assert.is_false(button_events.is_down(t, "a"))
    end)

    it("is true between press and release, regardless of duration", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      assert.is_true(button_events.is_down(t, "a"))
      button_events.release(t, "a", 5.0) -- held a long time
      assert.is_false(button_events.is_down(t, "a"))
    end)

    it("tracks multiple ids independently", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      button_events.press(t, "b", 0.1)
      assert.is_true(button_events.is_down(t, "a"))
      assert.is_true(button_events.is_down(t, "b"))
      button_events.release(t, "a", 0.2)
      assert.is_false(button_events.is_down(t, "a"))
      assert.is_true(button_events.is_down(t, "b"))
    end)

  end)

  describe("down_count", function()

    it("counts zero when nothing is held", function()
      local t = button_events.new()
      assert.are.equal(0, button_events.down_count(t))
    end)

    it("counts concurrently held ids", function()
      local t = button_events.new()
      button_events.press(t, "a", 0.0)
      button_events.press(t, "b", 0.1)
      assert.are.equal(2, button_events.down_count(t))
      button_events.release(t, "a", 0.2)
      assert.are.equal(1, button_events.down_count(t))
    end)

  end)

end)
