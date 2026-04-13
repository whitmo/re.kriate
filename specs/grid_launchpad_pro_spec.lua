-- specs/grid_launchpad_pro_spec.lua
-- Tests for lib/grid_launchpad_pro.lua: Novation Launchpad Pro MK3 grid provider

package.path = package.path .. ";./?.lua"

local lp_pro = require("lib/grid_launchpad_pro")

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
    inject = function(self, data)
      if self.event then
        self.event(data)
      end
    end,
  }
  return dev
end

local function find_sysex(sent, header_byte)
  for _, msg in ipairs(sent) do
    if msg[1] == 0xF0 and msg[7] == header_byte then
      return msg
    end
  end
  return nil
end

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

describe("grid_launchpad_pro", function()

  -- ======================================================================
  -- Coordinate mapping (Programmer layout)
  -- ======================================================================

  describe("note mapping", function()

    it("maps top-left pad (1,1) to note 81", function()
      assert.are.equal(81, lp_pro.grid_to_note(1, 1))
    end)

    it("maps top-right pad (8,1) to note 88", function()
      assert.are.equal(88, lp_pro.grid_to_note(8, 1))
    end)

    it("maps bottom-left pad (1,8) to note 11", function()
      assert.are.equal(11, lp_pro.grid_to_note(1, 8))
    end)

    it("maps bottom-right pad (8,8) to note 18", function()
      assert.are.equal(18, lp_pro.grid_to_note(8, 8))
    end)

    it("maps center pad (4,4) to note 54", function()
      -- y=4 from top → LP row 5 → note = 50 + 4 = 54
      assert.are.equal(54, lp_pro.grid_to_note(4, 4))
    end)

    it("round-trips all 64 pad positions", function()
      for py = 1, 8 do
        for px = 1, 8 do
          local note = lp_pro.grid_to_note(px, py)
          local rx, ry = lp_pro.note_to_grid(note)
          assert.are.equal(px, rx, "x mismatch at (" .. px .. "," .. py .. ")")
          assert.are.equal(py, ry, "y mismatch at (" .. px .. "," .. py .. ")")
        end
      end
    end)

    it("rejects notes outside pad range", function()
      local x, y = lp_pro.note_to_grid(10)
      assert.is_nil(x)
      assert.is_nil(y)
      x, y = lp_pro.note_to_grid(89)
      assert.is_nil(x)
      assert.is_nil(y)
    end)

    it("rejects out-of-row notes (col 9/0)", function()
      -- Note 19 would be "row 1, col 9" — not a valid pad position
      local x, y = lp_pro.note_to_grid(19)
      assert.is_nil(x)
      assert.is_nil(y)
      -- Note 20 would be "row 2, col 0"
      x, y = lp_pro.note_to_grid(20)
      assert.is_nil(x)
      assert.is_nil(y)
    end)

  end)

  -- ======================================================================
  -- Sysex builders
  -- ======================================================================

  describe("sysex", function()

    it("builds programmer-mode enter sysex", function()
      local msg = lp_pro.sysex_programmer_mode(true)
      assert.are.equal(0xF0, msg[1])
      assert.are.equal(0x00, msg[2])
      assert.are.equal(0x20, msg[3])
      assert.are.equal(0x29, msg[4])
      assert.are.equal(0x02, msg[5])
      assert.are.equal(0x0E, msg[6])
      assert.are.equal(0x0E, msg[7])
      assert.are.equal(0x01, msg[8])
      assert.are.equal(0xF7, msg[9])
    end)

    it("builds programmer-mode exit sysex", function()
      local msg = lp_pro.sysex_programmer_mode(false)
      assert.are.equal(0x00, msg[8])
    end)

    it("builds single RGB sysex", function()
      local msg = lp_pro.sysex_set_rgb(81, 127, 95, 0)
      assert.are.equal(0xF0, msg[1])
      assert.are.equal(0x03, msg[7])   -- set LED command
      assert.are.equal(0x03, msg[8])   -- RGB spec type
      assert.are.equal(81, msg[9])
      assert.are.equal(127, msg[10])
      assert.are.equal(95, msg[11])
      assert.are.equal(0, msg[12])
      assert.are.equal(0xF7, msg[13])
    end)

    it("clamps RGB values over 127", function()
      local msg = lp_pro.sysex_set_rgb(81, 200, 200, 200)
      assert.are.equal(127, msg[10])
      assert.are.equal(127, msg[11])
      assert.are.equal(127, msg[12])
    end)

    it("builds batched RGB sysex", function()
      local msg = lp_pro.sysex_batch_rgb({
        {81, 10, 20, 30},
        {82, 40, 50, 60},
      })
      assert.are.equal(0xF0, msg[1])
      assert.are.equal(0x03, msg[7])   -- set LED command
      -- First spec
      assert.are.equal(0x03, msg[8])   -- RGB spec type
      assert.are.equal(81, msg[9])
      assert.are.equal(10, msg[10])
      assert.are.equal(20, msg[11])
      assert.are.equal(30, msg[12])
      -- Second spec
      assert.are.equal(0x03, msg[13])
      assert.are.equal(82, msg[14])
      assert.are.equal(40, msg[15])
      assert.are.equal(50, msg[16])
      assert.are.equal(60, msg[17])
      -- EOX
      assert.are.equal(0xF7, msg[18])
    end)

  end)

  -- ======================================================================
  -- Grid provider interface
  -- ======================================================================

  describe("provider interface", function()
    local g

    before_each(function()
      g = lp_pro.new()  -- no MIDI (software-only)
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
    end)

    it("returns full state snapshot", function()
      g:led(1, 1, 5)
      g:led(16, 8, 12)
      local state = g:get_state()
      assert.are.equal(5, state[1][1])
      assert.are.equal(12, state[8][16])
      assert.are.equal(0, state[4][8])
    end)

    it("cleanup clears LED state (no MIDI device)", function()
      g:led(5, 3, 12)
      g:cleanup()
      assert.are.equal(0, g:get_led(5, 3))
    end)

    it("calls on_refresh callback when no MIDI", function()
      local called = false
      g.on_refresh = function() called = true end
      g:refresh()
      assert.is_true(called)
    end)

  end)

  -- ======================================================================
  -- Paging
  -- ======================================================================

  describe("paging", function()

    it("starts on page 0 by default", function()
      local g = lp_pro.new()
      assert.are.equal(0, g:get_page())
    end)

    it("accepts initial page option", function()
      local g = lp_pro.new({ page = 1 })
      assert.are.equal(1, g:get_page())
    end)

    it("switches pages", function()
      local g = lp_pro.new()
      g:set_page(1)
      assert.are.equal(1, g:get_page())
      g:set_page(0)
      assert.are.equal(0, g:get_page())
    end)

    it("rejects invalid page values", function()
      local g = lp_pro.new()
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

    it("sends one batched sysex on refresh", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      dev.sent = {}

      g:led(1, 1, 15)
      g:refresh()

      -- Exactly one sysex message carrying all 64 pads
      assert.are.equal(1, #dev.sent)
      assert.are.equal(0xF0, dev.sent[1][1])
      assert.are.equal(0xF7, dev.sent[1][#dev.sent[1]])
    end)

    it("refresh encodes all 64 pads with page-0 data", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      dev.sent = {}

      g:led(1, 1, 15)  -- page 0, top-left → note 81
      g:refresh()

      local msg = dev.sent[1]
      -- Header (6 bytes) + command (1 byte) + 64 specs*(5 bytes) + EOX = 328
      assert.are.equal(6 + 1 + 64 * 5 + 1, #msg)

      -- Find spec for note 81 (should have brightness-15 RGB, non-zero)
      local found = false
      for i = 8, #msg - 5, 5 do
        if msg[i] == 0x03 and msg[i + 1] == 81 then
          assert.is_true(msg[i + 2] > 0 or msg[i + 3] > 0, "LED 81 should have non-zero RGB at brightness 15")
          found = true
        end
      end
      assert.is_true(found, "expected RGB spec for note 81")
    end)

    it("refresh shows current page only", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      dev.sent = {}

      -- Brightness on col 10 (page 1)
      g:led(10, 1, 15)
      g:refresh()

      -- On page 0, spec for the top-left pad (note 81) should be all zeros
      local msg = dev.sent[1]
      for i = 8, #msg - 5, 5 do
        if msg[i] == 0x03 and msg[i + 1] == 81 then
          assert.are.equal(0, msg[i + 2])
          assert.are.equal(0, msg[i + 3])
          assert.are.equal(0, msg[i + 4])
        end
      end

      -- Switch to page 1: note 82 (pad 2,1) should map from col 10
      dev.sent = {}
      g:set_page(1)
      g:refresh()
      msg = dev.sent[1]
      local found = false
      for i = 8, #msg - 5, 5 do
        if msg[i] == 0x03 and msg[i + 1] == 82 then
          assert.is_true(msg[i + 2] > 0 or msg[i + 3] > 0, "LED 82 should be lit on page 1")
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("clamps brightness to 0-15 in palette lookup", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      g:led(1, 1, 99)  -- over max; should clamp to 15
      dev.sent = {}
      g:refresh()

      local msg = dev.sent[1]
      for i = 8, #msg - 5, 5 do
        if msg[i] == 0x03 and msg[i + 1] == 81 then
          -- Brightness 15 → amber (127, 95, 0)
          assert.are.equal(127, msg[i + 2])
          assert.are.equal(95, msg[i + 3])
          assert.are.equal(0, msg[i + 4])
        end
      end
    end)

    it("cleanup clears pads and exits programmer mode", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      dev.sent = {}

      g:cleanup()

      -- Expect a clear-batch sysex and a programmer-mode-off sysex
      assert.is_true(#dev.sent >= 2, "expected clear + mode-off messages")
      -- Last message should be programmer-mode off (0x0E 0x00)
      local last = dev.sent[#dev.sent]
      assert.are.equal(0x0E, last[7])
      assert.are.equal(0x00, last[8])
    end)

  end)

  -- ======================================================================
  -- MIDI input (pad presses)
  -- ======================================================================

  describe("MIDI input", function()

    it("converts pad press to key callback on page 0", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      -- Press top-left pad: note 81, velocity 100
      dev:inject({0x90, 81, 100})
      assert.are.same({x=1, y=1, z=1}, received)
    end)

    it("converts pad press to key callback on page 1", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev, page = 1 })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      -- Press top-left pad: note 81 → physical (1,1) → grid (9,1) on page 1
      dev:inject({0x90, 81, 100})
      assert.are.same({x=9, y=1, z=1}, received)
    end)

    it("handles Note Off as key release", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      dev:inject({0x80, 81, 0})
      assert.are.same({x=1, y=1, z=0}, received)
    end)

    it("handles Note On velocity 0 as key release", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      dev:inject({0x90, 81, 0})
      assert.are.same({x=1, y=1, z=0}, received)
    end)

    it("bottom-right pad maps correctly", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      local received = {}
      g.key = function(x, y, z) received = {x=x, y=y, z=z} end

      dev:inject({0x90, 18, 64})  -- bottom-right = note 18
      assert.are.same({x=8, y=8, z=1}, received)
    end)

    it("ignores non-pad MIDI notes", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      local called = false
      g.key = function() called = true end

      dev:inject({0x90, 10, 100})  -- below pad range
      assert.is_false(called)
      dev:inject({0x90, 89, 100})  -- above pad range
      assert.is_false(called)
      dev:inject({0x90, 19, 100})  -- gap note (col 9)
      assert.is_false(called)
    end)

    it("page left button switches to page 0", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev, page = 1 })

      dev:inject({0xB0, lp_pro.CC_PAGE_LEFT, 0x7F})
      assert.are.equal(0, g:get_page())
    end)

    it("page right button switches to page 1", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev, page = 0 })

      dev:inject({0xB0, lp_pro.CC_PAGE_RIGHT, 0x7F})
      assert.are.equal(1, g:get_page())
    end)

    it("page left does nothing when already on page 0", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev, page = 0 })

      dev:inject({0xB0, lp_pro.CC_PAGE_LEFT, 0x7F})
      assert.are.equal(0, g:get_page())
    end)

    it("page right does nothing when already on page 1", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev, page = 1 })

      dev:inject({0xB0, lp_pro.CC_PAGE_RIGHT, 0x7F})
      assert.are.equal(1, g:get_page())
    end)

    it("page switch triggers refresh", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev, page = 0 })
      dev.sent = {}

      dev:inject({0xB0, lp_pro.CC_PAGE_RIGHT, 0x7F})
      -- refresh sends one batched sysex
      assert.are.equal(1, #dev.sent)
      assert.are.equal(0xF0, dev.sent[1][1])
    end)

  end)

  -- ======================================================================
  -- Hardware init
  -- ======================================================================

  describe("init_hardware", function()

    it("sends Programmer-mode-enter sysex", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      dev.sent = {}

      g:init_hardware()

      -- First message should be programmer mode enter
      local first = dev.sent[1]
      assert.are.equal(0xF0, first[1])
      assert.are.equal(0x0E, first[7])
      assert.are.equal(0x01, first[8])
    end)

    it("clears all 64 pads after mode set", function()
      local dev = mock_midi()
      local g = lp_pro.new({ midi_dev = dev })
      dev.sent = {}

      g:init_hardware()

      -- 1 mode enter + 1 batched clear sysex = 2
      assert.are.equal(2, #dev.sent)
      local clear_msg = dev.sent[2]
      -- 64 pads, each with RGB (0,0,0): spec type + note + 3 color bytes = 5 bytes per pad
      -- plus header (6) + command (1) + EOX = 6+1+64*5+1 = 328
      assert.are.equal(6 + 1 + 64 * 5 + 1, #clear_msg)
    end)

  end)

  -- ======================================================================
  -- Integration with grid_provider registry
  -- ======================================================================

  describe("grid_provider integration", function()

    it("registers as 'launchpad_pro' provider", function()
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
        if name == "launchpad_pro" then found = true end
      end
      assert.is_true(found, "launchpad_pro should be in registered providers")
    end)

  end)

end)
