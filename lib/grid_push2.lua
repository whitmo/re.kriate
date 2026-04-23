-- lib/grid_push2.lua
-- Push 2 grid provider: Ableton Push 2 as 16x8 monome-style grid
--
-- Uses Push 2's 8x8 pad grid (MIDI notes 36-99) with page switching
-- for full 16x8 monome grid emulation. Page Left/Right buttons (CC 62/63)
-- switch between the left half (cols 1-8) and right half (cols 9-16).
--
-- Brightness 0-15 maps to Push 2 color palette entries 0-15, programmed
-- on init as an amber gradient to match monome aesthetic.
--
-- Reference: github.com/Ableton/push-interface

local M = {}

------------------------------------------------------------------------
-- Portable bit helpers (Lua 5.1/5.2/5.3 compatible)
------------------------------------------------------------------------

local floor = math.floor

local function band(a, b) return a % (b + 1) end
local function rshift(a, n) return floor(a / (2 ^ n)) end
local function idiv(a, b) return floor(a / b) end

-- Split an 8-bit color value into lo (bits 0-6) and hi (bit 7)
local function split_byte(v)
  return v % 128, floor(v / 128)
end

-- Extract high nibble from a byte (status & 0xF0)
local function high_nibble(byte)
  return byte - (byte % 16)
end

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

M.PAD_NOTE_MIN = 36
M.PAD_NOTE_MAX = 99
M.CC_PAGE_LEFT = 62
M.CC_PAGE_RIGHT = 63

-- Push 2 sysex header: 0x00 0x21 0x1D = Ableton, 0x01 0x01 = Push 2
local SYSEX_HEADER = {0xF0, 0x00, 0x21, 0x1D, 0x01, 0x01}

------------------------------------------------------------------------
-- Sysex builders
------------------------------------------------------------------------

local function build_sysex(command_bytes)
  local msg = {}
  for i, b in ipairs(SYSEX_HEADER) do msg[i] = b end
  for _, b in ipairs(command_bytes) do msg[#msg + 1] = b end
  msg[#msg + 1] = 0xF7
  return msg
end

--- Set MIDI mode: 0x00=Live, 0x01=User
function M.sysex_set_mode(mode)
  return build_sysex({0x0A, mode})
end

--- Set a color palette entry (index 0-127, RGB 0-255 each)
function M.sysex_set_palette_entry(index, r, g, b, w)
  w = w or 0
  local r_lo, r_hi = split_byte(r)
  local g_lo, g_hi = split_byte(g)
  local b_lo, b_hi = split_byte(b)
  local w_lo, w_hi = split_byte(w)
  return build_sysex({
    0x03, index,
    r_lo, r_hi, g_lo, g_hi, b_lo, b_hi, w_lo, w_hi,
  })
end

--- Reapply palette after setting entries
function M.sysex_reapply_palette()
  return build_sysex({0x05})
end

------------------------------------------------------------------------
-- Pad <-> grid coordinate mapping
------------------------------------------------------------------------

--- Convert physical pad position (1-8, 1-8) to MIDI note.
--- px: pad column 1-8 (left to right)
--- py: pad row 1-8 (1=top, 8=bottom)
function M.grid_to_note(px, py)
  return M.PAD_NOTE_MIN + (8 - py) * 8 + (px - 1)
end

--- Convert MIDI note to physical pad position.
--- Returns px (1-8), py (1-8, 1=top) or nil,nil if not a pad note.
function M.note_to_grid(note)
  if note < M.PAD_NOTE_MIN or note > M.PAD_NOTE_MAX then return nil, nil end
  local idx = note - M.PAD_NOTE_MIN
  local pad_col = idx % 8
  local pad_row = idiv(idx, 8)  -- 0=bottom row, 7=top row
  return pad_col + 1, 8 - pad_row
end

------------------------------------------------------------------------
-- Default amber palette (monome-style, 16 brightness levels)
------------------------------------------------------------------------

M.DEFAULT_PALETTE = {
  [0]  = {  0,   0,   0},
  [1]  = { 17,  13,   0},
  [2]  = { 34,  25,   0},
  [3]  = { 51,  38,   0},
  [4]  = { 68,  51,   0},
  [5]  = { 85,  64,   0},
  [6]  = {102,  76,   0},
  [7]  = {119,  89,   0},
  [8]  = {136, 102,   0},
  [9]  = {153, 115,   0},
  [10] = {170, 127,   0},
  [11] = {187, 140,   0},
  [12] = {204, 153,   0},
  [13] = {221, 166,   0},
  [14] = {238, 178,   0},
  [15] = {255, 191,   0},
}

------------------------------------------------------------------------
-- Provider factory
------------------------------------------------------------------------

--- Create a Push 2 grid provider.
--- @param opts table  Options:
---   midi_dev   - connected MIDI device (midi.connect result)
---   device     - MIDI port number (used if midi_dev not provided, requires global midi)
---   page       - initial page: 0=left (cols 1-8), 1=right (cols 9-16)
---   palette    - custom palette table [0-15] = {r, g, b} (optional)
--- @return table  Grid object implementing the grid_provider interface
function M.new(opts)
  opts = opts or {}
  local total_cols = 16
  local total_rows = 8
  local page = opts.page or 0
  local palette = opts.palette or M.DEFAULT_PALETTE

  -- Resolve MIDI device
  local midi_dev = opts.midi_dev
  if not midi_dev and midi then
    midi_dev = midi.connect(opts.device or 1)
  end

  -- LED state buffer (full 16x8 logical grid)
  local leds = {}

  local g = {
    key = nil,  -- callback: assigned by app.lua

    all = function(self, brightness)
      leds = {}
      if brightness and brightness > 0 then
        for y = 1, total_rows do
          for x = 1, total_cols do
            leds[y * total_cols + x] = brightness
          end
        end
      end
    end,

    led = function(self, x, y, brightness)
      if x < 1 or x > total_cols or y < 1 or y > total_rows then return end
      leds[y * total_cols + x] = brightness
    end,

    --- Push buffered LED state to Push 2 pads.
    --- Only sends the 8x8 region for the current page.
    refresh = function(self)
      if not midi_dev then
        if self.on_refresh then self:on_refresh() end
        return
      end
      local x_offset = page * 8
      for py = 1, 8 do
        for px = 1, 8 do
          local grid_x = px + x_offset
          local b = leds[py * total_cols + grid_x] or 0
          if b < 0 then b = 0 elseif b > 15 then b = 15 end
          local note = M.grid_to_note(px, py)
          midi_dev:send({0x90, note, b})
        end
      end
      if self.on_refresh then self:on_refresh() end
    end,

    cols = function() return total_cols end,
    rows = function() return total_rows end,

    get_led = function(self, x, y)
      return leds[y * total_cols + x] or 0
    end,

    get_state = function(self)
      local state = {}
      for y = 1, total_rows do
        state[y] = {}
        for x = 1, total_cols do
          state[y][x] = leds[y * total_cols + x] or 0
        end
      end
      return state
    end,

    get_page = function(self) return page end,

    set_page = function(self, p)
      if p ~= 0 and p ~= 1 then return end
      page = p
    end,

    --- Send Push 2 init sysex: User mode, amber palette, clear pads.
    init_hardware = function(self)
      if not midi_dev then return end
      midi_dev:send(M.sysex_set_mode(0x01))
      for i = 0, 15 do
        local c = palette[i]
        if c then
          midi_dev:send(M.sysex_set_palette_entry(i, c[1], c[2], c[3]))
        end
      end
      midi_dev:send(M.sysex_reapply_palette())
      for note = M.PAD_NOTE_MIN, M.PAD_NOTE_MAX do
        midi_dev:send({0x90, note, 0})
      end
    end,

    cleanup = function(self)
      leds = {}
      if midi_dev then
        for note = M.PAD_NOTE_MIN, M.PAD_NOTE_MAX do
          midi_dev:send({0x90, note, 0})
        end
      end
    end,
  }

  -- Wire up MIDI input from Push 2
  if midi_dev then
    midi_dev.event = function(data)
      if not data or #data < 3 then return end
      local status = high_nibble(data[1])
      local byte2 = data[2]
      local byte3 = data[3]

      if status == 0x90 and byte2 >= M.PAD_NOTE_MIN and byte2 <= M.PAD_NOTE_MAX then
        -- Note On: pad press (velocity > 0) or release (velocity == 0)
        local px, py = M.note_to_grid(byte2)
        if px then
          local grid_x = px + page * 8
          local z = byte3 > 0 and 1 or 0
          if g.key then g.key(grid_x, py, z) end
        end
      elseif status == 0x80 and byte2 >= M.PAD_NOTE_MIN and byte2 <= M.PAD_NOTE_MAX then
        -- Note Off: pad release
        local px, py = M.note_to_grid(byte2)
        if px then
          local grid_x = px + page * 8
          if g.key then g.key(grid_x, py, 0) end
        end
      elseif status == 0xB0 and byte3 == 0x7F then
        -- CC button press: page switching
        if byte2 == M.CC_PAGE_LEFT and page > 0 then
          page = 0
          g:refresh()
        elseif byte2 == M.CC_PAGE_RIGHT and page < 1 then
          page = 1
          g:refresh()
        end
      end
    end
  end

  return g
end

return M
