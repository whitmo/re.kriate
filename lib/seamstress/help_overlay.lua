-- lib/seamstress/help_overlay.lua
-- Help overlay for seamstress: quick-reference drawn over the grid
-- Toggled with ? key, dismissed with ? or Escape
-- Window resizes to fit the overlay content

local M = {}

-- Overlay window dimensions (used by seamstress.lua for screen.set_size)
M.WIDTH = 400
M.HEIGHT = 380

-- Layout constants
local MARGIN_X = 8
local MARGIN_Y = 6
local LINE_H = 10
local COL_GAP = 12
local SECTION_GAP = 6
local TITLE_COLOR = {255, 210, 75, 255}
local TEXT_COLOR = {200, 200, 220, 255}
local HEADER_COLOR = {255, 250, 142, 255}
local FOOTER_COLOR = {150, 150, 170, 255}
local BG_COLOR = {10, 10, 20, 255}

-- Help content: paired columns per section
local SECTIONS = {
  {
    left_title = "KEYBOARD",
    left = {
      "Space  Play / Stop",
      "R      Reset playheads",
      "1-4    Select track",
      "Q W E  Trig / Note / Octave",
      "T Y    Duration / Velocity",
      "D      Cycle direction",
      "L      Toggle loop edit",
      "F1     Time view (KEY 1)",
      "F2     Config page (KEY 2)",
      "Ctrl+P Probability page",
      "Ctrl+A Alt-track page",
    },
    right_title = "CONTROL ROW (grid row 8)",
    right = {
      "1-4   Track select",
      "5     KEY 1: Time (hold)",
      "6     Trigger page",
      "7     Note page",
      "8     Octave page",
      "9     Dur > Vel > Prob cycle",
      "10    KEY 2: Config (press)",
      "11    Loop modifier (hold)",
      "12    Pattern mode (hold)",
      "13    Mute toggle",
      "14    Scale page",
      "15    Meta / Alt-track",
    },
  },
  {
    left_title = "PATTERNS",
    left = {
      "Ctrl+S     Save bank to disk",
      "Ctrl+L     Load bank from disk",
      "Ctrl+B     List saved banks",
      "Ctrl+Sh+D  Delete bank",
      "Ctrl+1-9   Save to slot",
      "Shift+1-9  Load from slot",
    },
    right_title = "PAGES",
    right = {
      "Trigger      4-track step on/off",
      "Note         Per-step pitch (1-7)",
      "Octave       Octave offset per step",
      "Duration     Note length per step",
      "Velocity     Note velocity per step",
      "Probability  Trigger gate chance",
      "2x page key = extended page:",
      "  Ratchet / Alt-Note / Glide",
    },
  },
  {
    left_title = "LOOP EDITING",
    left = {
      "Hold L (or grid 11), then tap",
      "start position, tap end position.",
      "Each param has independent loops",
      "(polymetric sequencing).",
    },
    right_title = "META-SEQUENCER",
    right = {
      "Press grid 15 twice to enter.",
      "Rows 1-2: assign pattern slot",
      "Row 3: set loop count (1-7)",
      "Row 5: select meta-step",
      "Row 7 x=1: toggle active",
    },
  },
  {
    left_title = "VOICES (via Params menu)",
    left = {
      "Types: midi, osc, sc_drums,",
      "       softcut, none",
      "Per-track: voice type + midi ch",
    },
    right_title = "ALT-TRACK (F2 / grid 10)",
    right = {
      "Row per track: dir/div/swing/mute",
      "Row 5 x1-4: trigger clocking",
      "Time (F1 / grid 5): per-param",
      "  clock division overlay",
    },
  },
}

--- Draw the help overlay on the given screen.
--- @param scr table  Screen object (screen module)
--- @param width number  Screen width in pixels
--- @param height number  Screen height in pixels
function M.draw(scr, width, height)
  -- Solid dark background
  scr.color(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4])
  scr.move(0, 0)
  scr.rect_fill(width, height)

  -- Use smaller font if available
  if scr.font_size then scr.font_size(8) end

  local col_w = math.floor((width - MARGIN_X * 2 - COL_GAP) / 2)
  local y = MARGIN_Y + LINE_H

  -- Header
  scr.color(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3], HEADER_COLOR[4])
  scr.move(MARGIN_X, y)
  scr.text("re.kriate — quick reference")
  y = y + LINE_H + 4

  -- Sections
  for _, section in ipairs(SECTIONS) do
    local left_x = MARGIN_X
    local right_x = MARGIN_X + col_w + COL_GAP

    -- Section titles
    scr.color(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], TITLE_COLOR[4])
    scr.move(left_x, y)
    scr.text(section.left_title)
    scr.move(right_x, y)
    scr.text(section.right_title)
    y = y + LINE_H

    -- Content lines (side by side)
    local max_lines = math.max(#section.left, #section.right)
    for i = 1, max_lines do
      scr.color(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3], TEXT_COLOR[4])
      if section.left[i] then
        scr.move(left_x + 2, y)
        scr.text(section.left[i])
      end
      if section.right[i] then
        scr.move(right_x + 2, y)
        scr.text(section.right[i])
      end
      y = y + LINE_H
    end

    y = y + SECTION_GAP
  end

  -- Footer
  scr.color(FOOTER_COLOR[1], FOOTER_COLOR[2], FOOTER_COLOR[3], FOOTER_COLOR[4])
  scr.move(MARGIN_X, height - MARGIN_Y)
  scr.text("? or Esc to close")

  -- Restore default font if we changed it
  if scr.font_size then scr.font_size(12) end
end

--- Get the help content sections (for testing).
function M.get_sections()
  return SECTIONS
end

return M
