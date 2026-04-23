-- specs/grid_push2_spec.lua
-- Tests for lib/grid_push2.lua: Push 2 grid provider

package.path = package.path .. ";./?.lua"

local push2 = require("lib/grid_push2")

------------------------------------------------------------------------
-- Mock MIDI device
------------------------------------------------------------------------

local function mock_midi()
  local dev = {
    sent = {},
    event = nil,
    send = function(self, msg)
      self.sent[#self.sent + 1] = msg
    end,
    -- Simulate receiving MIDI data from hardware
    inject = function(self, data)
      if self.event then
        self.event(data)
      end
    end,
  }
  return dev
end

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

describe("grid_push2", function()

  -- ======================================================================
  -- Coordinate mapping
  -- ======================================================================

  describe("note mapping", function()

    it("maps top-left pad (1,1) to note 92", function()
      assert.are.equal(92, push2.grid_to_note(1, 1))
    end)

    it("maps top-right pad (8,1) to note 99", function()
      assert.are.equal(99, push2.grid_to_note(8, 1))
    end)

    it("maps bottom-left pad (1,8) to note 36", function()
      assert.are.equal(36, push2.grid_to_note(1, 8))
    end)

    it("maps bottom-right pad (8,8) to note 43", function()
      assert.are.equal(43, push2.grid_to_note(8, 8))
    end)

    it("maps center pad (4,4) correctly", function()
      -- Row 4, col 4: note = 36 + (8-4)*8 + (4-1) = 36 + 32 + 3 = 71
      assert.are.equal(71, push2.grid_to_note(4, 4))
    end)

    it("round-trips all 64 pad positions", function()
      for py = 1, 8 do
        for px = 1, 8 do
          local note = push2.grid_to_note(px, py)
          local rx, ry = push2.note_to_grid(note)
          assert.are.equal(px, rx, "x mismatch at (" .. px .. "," .. py .. ")")
          assert.are.equal(py, ry, "y mismatch at (" .. px .. "," .. py .. ")")
        end
      end
    end)

    it("returns nil for notes outside pad range", function()
      local x, y = push2.note_to_grid(35)
      assert.is_nil(x)
      assert.is_nil(y)
      x, y = push2.note_to_grid(100)
      assert.is_nil(x)
      assert.is_nil(y)
    end)

  end)

  -- ======================================================================
  -- Sysex builders
  -- ======================================================================

  describe("sysex", function()

    it("builds set-mode sysex for User mode", function()
      local msg = push2.sysex_set_mode(0x01)
      assert.are.equal(0xF0, msg[1])
      assert.are.equal(0x0A, msg[7])  -- command
      assert.are.equal(0x01, msg[8])  -- User mode
      assert.are.equal(0xF7, msg[9])  -- EOX
    end)

    it("builds palette entry sysex", function()
      local msg = push2.sysex_set_palette_entry(15, 255, 191, 0)
      assert.are.equal(0xF0, msg[1])
      assert.are.equal(0x03, msg[7])  -- set palette command
      assert.are.equal(15, msg[8])    -- palette index
      -- R=255: lo=127, hi=1
      assert.are.equal(127, msg[9])
      assert.are.equal(1, msg[10])
      -- G=191: lo=63, hi=1
      assert.are.equal(63, msg[11])
      assert.are.equal(1, msg[12])
      -- B=0: lo=0, hi=0
      assert.are.equal(0, msg[13])
      assert.are.equal(0, msg[14])
      assert.are.equal(0xF7, msg[#msg])
    end)

    it("builds reapply palette sysex", function()
      local msg = push2.sysex_reapply_palette()
      assert.are.equal(0x05, msg[7])
      assert.are.equal(0xF7, msg[8])
    end)

  end)

  -- ======================================================================
  -- Grid provider interface
  -- ======================================================================

  describe("provider interface", function()
    local g

    before_each(function()
      g = push2.new()  -- no MIDI device (software-only)
    end)

    it("reports 16 cols and 8 rows", function()
      assert.are.equal(16, g:cols())
      assert.are.equal(8, g:rows())
    end)

    it("starts with all LEDs off", function()
      assert.are.equal(0, g:get_led(1, 1))
      assert.are.equal(0, g:get_led(16, 8))
    end)

    it("sets single LED", function()
      g:led(5, 3, 12)
      assert.are.equal(12, g:get_led(5, 3))
      assert.are.equal(0, g:get_led(6, 3))
    end)

    it("sets all LEDs", function()
      g:all(10)
      assert.are.equal(10, g:get_led(1, 1))
      assert.are.equal(10, g:get_led(16, 8))
      assert.are.equal(10, g:get_led(8, 4))
    end)

    it("all(0) clears LEDs", function()
      g:led(5, 3, 12)
      g:all(0)
      assert.are.equal(0, g:get_led(5, 3))
    end)

    it("ignores out-of-bounds LED writes", function()
      g:led(0, 1, 5)
      g:led(17, 1, 5)
      g:led(1, 0, 5)
      g:led(1, 9, 5)
      -- Should not error, just ignore
    end)

    it("returns full state snapshot", function()
      g:led(1, 1, 5)
      g:led(16, 8, 12)
      local state = g:get_state()
      assert.are.equal(5, state[1][1])
      assert.are.equal(12, state[8][16])
      assert.are.equal(0, state[4][8])
    end)

    it("cleanup clears LED state", function()
      g:led(5, 3, 12)
      g:cleanup()
      assert.are.equal(0, g:get_led(5, 3))
    end)

    it("calls on_refresh callback", function()
      local called = false
      g.on_refresh = function() called = true end
      g:refresh()
      assert.is_true(called)
    end)

  end)

  -- ======================================================================
  -- Page switching
  -- ======================================================================

  describe("paging", function()

    it("starts on page 0 by default", function()
      local g = push2.new()
      assert.are.equal(0, g:get_page())
    end)

    it("accepts initial page option", function()
      local g = push2.new({ page = 1 })
      assert.are.equal(1, g:get_page())
    end)

    it("switches pages", function()
      local g = push2.new()
      g:set_page(1)
      assert.are.equal(1, g:get_page())
      g:set_page(0)
      assert.are.equal(0, g:get_page())
    end)

    it("rejects invalid page values", function()
      local g = push2.new()
      g:set_page(2)
      assert.are.equal(0, g:get_page())
      g:set_page(-1)
      assert.are.equal(0, g:get_page())
    end)

  end)

  -- ======================================================================
  -- MIDI output (LED refresh)
  -- ======================================================================

  describe("MIDI output", function()

    it("sends Note On for each pad on refresh", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      dev.sent = {}  -- clear init messages if any

      g:led(1, 1, 15)  -- page 0, top-left
      g:refresh()

      -- Should send 64 messages (8x8 grid)
      assert.are.equal(64, #dev.sent)

      -- Find the message for pad (1,1) = note 92
      local found = false
      for _, msg in ipairs(dev.sent) do
        if msg[2] == 92 then
          assert.are.equal(0x90, msg[1])
          assert.are.equal(15, msg[3])
          found = true
        end
      end
      assert.is_true(found, "expected Note On for note 92")
    end)

    it("sends LEDs for current page only", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      dev.sent = {}

      -- Set LED on page 1 (right half)
      g:led(10, 1, 12)  -- col 10 = page 1, col 2
      g:refresh()  -- page 0 active, so col 10 not sent with brightness

      -- All 64 messages should show brightness 0 (page 0 has no LEDs set)
      for _, msg in ipairs(dev.sent) do
        assert.are.equal(0, msg[3], "page 0 should show all off")
      end

      -- Switch to page 1 and refresh
      dev.sent = {}
      g:set_page(1)
      g:refresh()

      -- Note for physical pad (2,1) = note 93, should have brightness 12
      local found = false
      for _, msg in ipairs(dev.sent) do
        if msg[2] == 93 then  -- pad col 2, row 1 = note 93
          assert.are.equal(12, msg[3])
          found = true
        end
      end
      assert.is_true(found, "expected brightness 12 on note 93 (page 1, col 10)")
    end)

    it("clamps brightness to 0-15", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      g:led(1, 1, 20)  -- over max
      dev.sent = {}
      g:refresh()

      -- Find note 92 (pad 1,1)
      for _, msg in ipairs(dev.sent) do
        if msg[2] == 92 then
          assert.are.equal(15, msg[3], "brightness should clamp to 15")
        end
      end
    end)

    it("clears all pads on cleanup", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      dev.sent = {}

      g:cleanup()

      -- Should send Note On with velocity 0 for all 64 pads
      assert.are.equal(64, #dev.sent)
      for _, msg in ipairs(dev.sent) do
        assert.are.equal(0x90, msg[1])
        assert.are.equal(0, msg[3])
      end
    end)

  end)

  -- ======================================================================
  -- MIDI input (pad presses)
  -- ======================================================================

  describe("MIDI input", function()

    it("converts pad press to key callback on page 0", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      -- Press top-left pad: note 92, velocity 100
      dev:inject({0x90, 92, 100})
      assert.are.same({x=1, y=1, z=1}, received)
    end)

    it("converts pad press to key callback on page 1", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev, page = 1 })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      -- Press top-left pad: note 92 → physical (1,1) → grid (9,1) on page 1
      dev:inject({0x90, 92, 100})
      assert.are.same({x=9, y=1, z=1}, received)
    end)

    it("handles Note Off as key release", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      dev:inject({0x80, 92, 0})
      assert.are.same({x=1, y=1, z=0}, received)
    end)

    it("handles Note On velocity 0 as key release", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      dev:inject({0x90, 92, 0})
      assert.are.same({x=1, y=1, z=0}, received)
    end)

    it("bottom-right pad maps correctly", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      -- Bottom-right: note 43 = pad (8,8)
      dev:inject({0x90, 43, 64})
      assert.are.same({x=8, y=8, z=1}, received)
    end)

    it("ignores non-pad MIDI notes", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      local called = false
      g.key = function() called = true end

      dev:inject({0x90, 35, 100})  -- below pad range
      assert.is_false(called)
      dev:inject({0x90, 100, 100})  -- above pad range
      assert.is_false(called)
    end)

    it("page left button switches to page 0", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev, page = 1 })

      dev:inject({0xB0, push2.CC_PAGE_LEFT, 0x7F})
      assert.are.equal(0, g:get_page())
    end)

    it("page right button switches to page 1", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev, page = 0 })

      dev:inject({0xB0, push2.CC_PAGE_RIGHT, 0x7F})
      assert.are.equal(1, g:get_page())
    end)

    it("page left does nothing when already on page 0", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev, page = 0 })

      dev:inject({0xB0, push2.CC_PAGE_LEFT, 0x7F})
      assert.are.equal(0, g:get_page())
    end)

    it("page right does nothing when already on page 1", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev, page = 1 })

      dev:inject({0xB0, push2.CC_PAGE_RIGHT, 0x7F})
      assert.are.equal(1, g:get_page())
    end)

    it("page switch triggers refresh", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev, page = 0 })
      dev.sent = {}

      dev:inject({0xB0, push2.CC_PAGE_RIGHT, 0x7F})
      -- refresh sends 64 messages
      assert.are.equal(64, #dev.sent)
    end)

  end)

  -- ======================================================================
  -- Hardware init
  -- ======================================================================

  describe("init_hardware", function()

    it("sends User mode sysex", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      dev.sent = {}

      g:init_hardware()

      -- First message should be set User mode
      local first = dev.sent[1]
      assert.are.equal(0xF0, first[1])
      assert.are.equal(0x0A, first[7])
      assert.are.equal(0x01, first[8])
    end)

    it("programs 16 palette entries", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      dev.sent = {}

      g:init_hardware()

      -- 1 mode + 16 palette entries + 1 reapply + 64 pad clears = 82
      assert.are.equal(82, #dev.sent)
    end)

    it("clears all pads after palette setup", function()
      local dev = mock_midi()
      local g = push2.new({ midi_dev = dev })
      dev.sent = {}

      g:init_hardware()

      -- Last 64 messages should be pad clears (Note On, velocity 0)
      for i = #dev.sent - 63, #dev.sent do
        local msg = dev.sent[i]
        assert.are.equal(0x90, msg[1])
        assert.are.equal(0, msg[3])
      end
    end)

  end)

  -- ======================================================================
  -- Integration with grid_provider registry
  -- ======================================================================

  describe("grid_provider integration", function()

    it("registers as 'push2' provider", function()
      -- Need to mock grid for the monome provider
      rawset(_G, "grid", {
        connect = function()
          return {
            all = function() end,
            led = function() end,
            refresh = function() end,
          }
        end,
      })

      local grid_provider = require("lib/grid_provider")
      local names = grid_provider.list()
      local found = false
      for _, name in ipairs(names) do
        if name == "push2" then found = true end
      end
      assert.is_true(found, "push2 should be in registered providers")
    end)

  end)

end)
