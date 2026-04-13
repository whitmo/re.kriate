-- lib/grid_launchpad_pro.lua
-- Novation Launchpad Pro MK3 grid provider: 8x8 RGB grid as 16x8 monome-style grid
--
-- Uses the Launchpad Pro MK3's 8x8 velocity-sensitive pad grid with page
-- switching to present a full 16x8 monome grid. The Left/Right navigation
-- arrows on the top row (CCs 93/94) switch between the left half (cols 1-8)
-- and right half (cols 9-16).
--
-- Pads are addressed in Programmer layout: note = y*10 + x, where (1,1) is
-- bottom-left (note 11) and (8,8) is top-right (note 88). The provider maps
-- these to norns conventions where (1,1) is top-left.
--
-- Brightness 0-15 is mapped to a 16-entry amber palette sent via Programmer-mode
-- RGB sysex — matching monome aesthetic.
--
-- Reference: https://fael-downloads-prod.focusrite.com/customer/prod/s3fs-public/downloads/Launchpad%20Pro%20-%20Programmers%20Reference%20Manual.pdf

local M = {}

------------------------------------------------------------------------
-- Portable math helpers
------------------------------------------------------------------------

local floor = math.floor

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

-- Programmer-mode pad range (y*10 + x for y,x in 1..8)
M.PAD_NOTE_MIN = 11
M.PAD_NOTE_MAX = 88

-- Top-row navigation arrow CCs (Programmer mode, LP Pro MK3)
M.CC_PAGE_LEFT = 93
M.CC_PAGE_RIGHT = 94

-- Novation SysEx header: 00 20 29 = Novation, 02 0E = Launchpad Pro MK3
local SYSEX_HEADER = {0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E}

------------------------------------------------------------------------
-- Default 16-step amber palette (RGB 0-127 each — Launchpad Pro scale)
-- Matches the Push 2 monome-style amber gradient, scaled to 0-127.
------------------------------------------------------------------------

M.DEFAULT_PALETTE = {
  [0]  = {  0,   0,   0},
  [1]  = {  8,   6,   0},
  [2]  = { 17,  12,   0},
  [3]  = { 25,  19,   0},
  [4]  = { 34,  25,   0},
  [5]  = { 42,  32,   0},
  [6]  = { 51,  38,   0},
  [7]  = { 59,  44,   0},
  [8]  = { 68,  51,   0},
  [9]  = { 76,  57,   0},
  [10] = { 85,  63,   0},
  [11] = { 93,  70,   0},
  [12] = {102,  76,   0},
  [13] = {110,  83,   0},
  [14] = {119,  89,   0},
  [15] = {127,  95,   0},
}

------------------------------------------------------------------------
-- Sysex builders
------------------------------------------------------------------------

local function build_sysex(payload)
  local msg = {}
  for i, b in ipairs(SYSEX_HEADER) do msg[i] = b end
  for _, b in ipairs(payload) do msg[#msg + 1] = b end
  msg[#msg + 1] = 0xF7
  return msg
end

--- Enter Programmer layout (0x00=Live, 0x01=Programmer)
function M.sysex_programmer_mode(enable)
  return build_sysex({0x0E, enable and 0x01 or 0x00})
end

--- Set a single pad LED to an RGB color (values clamped to 0-127).
function M.sysex_set_rgb(note, r, g, b)
  if r < 0 then r = 0 elseif r > 127 then r = 127 end
  if g < 0 then g = 0 elseif g > 127 then g = 127 end
  if b < 0 then b = 0 elseif b > 127 then b = 127 end
  -- Command 0x03 = set LED; spec type 0x03 = RGB
  return build_sysex({0x03, 0x03, note, r, g, b})
end

--- Batch multiple RGB LED updates into a single sysex message.
--- specs: array of {note, r, g, b}
function M.sysex_batch_rgb(specs)
  local payload = {0x03}
  for _, s in ipairs(specs) do
    local r, g, b = s[2], s[3], s[4]
    if r < 0 then r = 0 elseif r > 127 then r = 127 end
    if g < 0 then g = 0 elseif g > 127 then g = 127 end
    if b < 0 then b = 0 elseif b > 127 then b = 127 end
    payload[#payload + 1] = 0x03
    payload[#payload + 1] = s[1]
    payload[#payload + 1] = r
    payload[#payload + 1] = g
    payload[#payload + 1] = b
  end
  return build_sysex(payload)
end

------------------------------------------------------------------------
-- Pad <-> grid coordinate mapping
------------------------------------------------------------------------

--- Convert physical pad position (1-8 cols, 1-8 rows where py=1 is TOP)
--- to the Launchpad Pro Programmer-layout MIDI note.
function M.grid_to_note(px, py)
  -- Programmer layout: note = y*10 + x, with y=1 at BOTTOM
  -- norns convention: py=1 is TOP, so LP y = 9 - py
  return (9 - py) * 10 + px
end

--- Convert MIDI note (Programmer layout) to physical pad position.
--- Returns px (1-8), py (1-8, 1=top) or nil,nil if out of range.
function M.note_to_grid(note)
  if note < M.PAD_NOTE_MIN or note > M.PAD_NOTE_MAX then return nil, nil end
  local lp_y = floor(note / 10)
  local lp_x = note % 10
  if lp_x < 1 or lp_x > 8 or lp_y < 1 or lp_y > 8 then return nil, nil end
  return lp_x, 9 - lp_y
end

------------------------------------------------------------------------
-- Provider factory
------------------------------------------------------------------------

--- Create a Launchpad Pro grid provider.
--- @param opts table  Options:
---   midi_dev   - connected MIDI device (midi.connect result)
---   device     - MIDI port number (used if midi_dev not provided)
---   page       - initial page: 0=left (cols 1-8), 1=right (cols 9-16)
---   palette    - custom palette table [0-15] = {r, g, b} (0-127 each)
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

    --- Push buffered LED state to the Launchpad Pro.
    --- Batches all 64 pads into a single RGB sysex message.
    refresh = function(self)
      if not midi_dev then
        if self.on_refresh then self:on_refresh() end
        return
      end
      local x_offset = page * 8
      local specs = {}
      for py = 1, 8 do
        for px = 1, 8 do
          local grid_x = px + x_offset
          local b = leds[py * total_cols + grid_x] or 0
          if b < 0 then b = 0 elseif b > 15 then b = 15 end
          local c = palette[b] or palette[0]
          local note = M.grid_to_note(px, py)
          specs[#specs + 1] = {note, c[1], c[2], c[3]}
        end
      end
      midi_dev:send(M.sysex_batch_rgb(specs))
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

    --- Enter Programmer mode and clear all pads.
    init_hardware = function(self)
      if not midi_dev then return end
      midi_dev:send(M.sysex_programmer_mode(true))
      -- Clear all 64 pads to black
      local specs = {}
      for note = M.PAD_NOTE_MIN, M.PAD_NOTE_MAX do
        -- Skip the "gap" notes (x=9 or x=0) — only real pads are 1-8
        local lp_x = note % 10
        if lp_x >= 1 and lp_x <= 8 then
          specs[#specs + 1] = {note, 0, 0, 0}
        end
      end
      midi_dev:send(M.sysex_batch_rgb(specs))
    end,

    cleanup = function(self)
      leds = {}
      if midi_dev then
        local specs = {}
        for note = M.PAD_NOTE_MIN, M.PAD_NOTE_MAX do
          local lp_x = note % 10
          if lp_x >= 1 and lp_x <= 8 then
            specs[#specs + 1] = {note, 0, 0, 0}
          end
        end
        midi_dev:send(M.sysex_batch_rgb(specs))
        -- Return to Live mode on cleanup
        midi_dev:send(M.sysex_programmer_mode(false))
      end
    end,
  }

  -- Wire up MIDI input from Launchpad Pro
  if midi_dev then
    midi_dev.event = function(data)
      if not data or #data < 3 then return end
      local status = data[1] - (data[1] % 16)  -- high nibble
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
        -- CC button press (only act on "down" edge)
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
