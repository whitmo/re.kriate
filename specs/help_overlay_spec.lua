-- specs/help_overlay_spec.lua
-- Tests for lib/seamstress/help_overlay.lua

package.path = package.path .. ";./?.lua"

local help_overlay = require("lib/seamstress/help_overlay")

-- Mock screen that records calls
local function mock_screen()
  local calls = {}
  return {
    calls = calls,
    color = function(r, g, b, a)
      calls[#calls + 1] = {type = "color", r = r, g = g, b = b, a = a}
    end,
    move = function(x, y)
      calls[#calls + 1] = {type = "move", x = x, y = y}
    end,
    text = function(str)
      calls[#calls + 1] = {type = "text", str = str}
    end,
    rect_fill = function(w, h)
      calls[#calls + 1] = {type = "rect_fill", w = w, h = h}
    end,
    font_size = function(size)
      calls[#calls + 1] = {type = "font_size", size = size}
    end,
  }
end

-- Extract all text calls from screen mock
local function text_calls(scr)
  local texts = {}
  for _, call in ipairs(scr.calls) do
    if call.type == "text" then
      texts[#texts + 1] = call.str
    end
  end
  return texts
end

describe("help_overlay", function()

  describe("dimensions", function()

    it("exports WIDTH and HEIGHT", function()
      assert.is_number(help_overlay.WIDTH)
      assert.is_number(help_overlay.HEIGHT)
      assert.is_true(help_overlay.WIDTH > 0)
      assert.is_true(help_overlay.HEIGHT > 0)
    end)

  end)

  describe("content", function()

    it("has sections with paired columns", function()
      local sections = help_overlay.get_sections()
      assert.is_true(#sections > 0)
      for _, section in ipairs(sections) do
        assert.is_string(section.left_title)
        assert.is_string(section.right_title)
        assert.is_table(section.left)
        assert.is_table(section.right)
      end
    end)

    it("documents keyboard shortcuts", function()
      local sections = help_overlay.get_sections()
      local keyboard_section = sections[1]
      assert.are.equal("KEYBOARD", keyboard_section.left_title)
      local joined = table.concat(keyboard_section.left, " ")
      assert.is_truthy(joined:find("Play"))
      assert.is_truthy(joined:find("Reset"))
      assert.is_truthy(joined:find("F1"))
      assert.is_truthy(joined:find("F2"))
    end)

    it("documents control row", function()
      local sections = help_overlay.get_sections()
      local nav_section = sections[1]
      assert.is_truthy(nav_section.right_title:find("CONTROL ROW"))
      local joined = table.concat(nav_section.right, " ")
      assert.is_truthy(joined:find("Track"))
      assert.is_truthy(joined:find("KEY 1"))
      assert.is_truthy(joined:find("KEY 2"))
      assert.is_truthy(joined:find("Loop"))
      assert.is_truthy(joined:find("Pattern"))
      assert.is_truthy(joined:find("Mute"))
      assert.is_truthy(joined:find("Scale"))
    end)

    it("documents pages", function()
      local sections = help_overlay.get_sections()
      local page_section = sections[2]
      assert.are.equal("PAGES", page_section.right_title)
      local joined = table.concat(page_section.right, " ")
      assert.is_truthy(joined:find("Trigger"))
      assert.is_truthy(joined:find("Note"))
      assert.is_truthy(joined:find("Velocity"))
      assert.is_truthy(joined:find("Ratchet"))
    end)

    it("documents patterns", function()
      local sections = help_overlay.get_sections()
      local pattern_section = sections[2]
      assert.are.equal("PATTERNS", pattern_section.left_title)
      local joined = table.concat(pattern_section.left, " ")
      assert.is_truthy(joined:find("Save"))
      assert.is_truthy(joined:find("Load"))
    end)

    it("documents loop editing", function()
      local sections = help_overlay.get_sections()
      local found = false
      for _, s in ipairs(sections) do
        if s.left_title:find("LOOP") then found = true end
      end
      assert.is_true(found)
    end)

    it("documents meta-sequencer", function()
      local sections = help_overlay.get_sections()
      local found = false
      for _, s in ipairs(sections) do
        if s.right_title:find("META") then found = true end
      end
      assert.is_true(found)
    end)

    it("documents voices", function()
      local sections = help_overlay.get_sections()
      local found = false
      for _, s in ipairs(sections) do
        if s.left_title:find("VOICES") then
          found = true
          local joined = table.concat(s.left, " ")
          assert.is_truthy(joined:find("midi"))
          assert.is_truthy(joined:find("softcut"))
        end
      end
      assert.is_true(found)
    end)

  end)

  describe("draw", function()

    it("draws background, header, sections, and footer", function()
      local scr = mock_screen()
      help_overlay.draw(scr, help_overlay.WIDTH, help_overlay.HEIGHT)
      local texts = text_calls(scr)
      -- Header
      assert.is_truthy(texts[1]:find("re.kriate"))
      -- Footer
      assert.is_truthy(texts[#texts]:find("close"))
      -- Should have many text calls (section titles + content)
      assert.is_true(#texts > 20)
    end)

    it("draws a background rectangle covering the full area", function()
      local scr = mock_screen()
      help_overlay.draw(scr, 400, 380)
      -- First drawing operations: color + move + rect_fill
      local first_rect = nil
      for _, call in ipairs(scr.calls) do
        if call.type == "rect_fill" then
          first_rect = call
          break
        end
      end
      assert.is_not_nil(first_rect)
      assert.are.equal(400, first_rect.w)
      assert.are.equal(380, first_rect.h)
    end)

    it("uses font_size when available", function()
      local scr = mock_screen()
      help_overlay.draw(scr, 400, 380)
      local found_small = false
      local found_restore = false
      for _, call in ipairs(scr.calls) do
        if call.type == "font_size" and call.size == 8 then found_small = true end
        if call.type == "font_size" and call.size == 12 then found_restore = true end
      end
      assert.is_true(found_small)
      assert.is_true(found_restore)
    end)

    it("works without font_size on screen", function()
      local scr = mock_screen()
      scr.font_size = nil
      assert.has_no.errors(function()
        help_overlay.draw(scr, 400, 380)
      end)
    end)

  end)

end)
