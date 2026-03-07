-- specs/screen_ui_spec.lua
-- Tests for lib/seamstress/screen_ui.lua

package.path = package.path .. ";./?.lua"

-- Mock seamstress screen API
local screen_buffer = {}
local current_pos = {x = 0, y = 0}
local current_color = {0, 0, 0, 255}

local function reset_screen()
  screen_buffer = { texts = {} }
  current_pos = {x = 0, y = 0}
  current_color = {0, 0, 0, 255}
end

rawset(_G, "screen", {
  clear = function() reset_screen() end,
  color = function(r, g, b, a) current_color = {r, g, b, a} end,
  move = function(x, y) current_pos = {x = x, y = y} end,
  rect_fill = function() end,
  text = function(str)
    table.insert(screen_buffer.texts, {
      str = str,
      x = current_pos.x,
      y = current_pos.y,
      color = {current_color[1], current_color[2], current_color[3], current_color[4]},
    })
  end,
  refresh = function() end,
})

local track_mod = require("lib/track")
local screen_ui = require("lib/seamstress/screen_ui")

-- Helper: find text matching a Lua pattern in screen buffer
local function find_text(pat)
  for _, entry in ipairs(screen_buffer.texts) do
    if entry.str:find(pat) then
      return entry
    end
  end
  return nil
end

-- Helper: create minimal ctx
local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
  }
end

describe("screen_ui", function()

  before_each(function()
    reset_screen()
  end)

  describe("basic display", function()

    it("shows title", function()
      local ctx = make_ctx()
      screen_ui.redraw(ctx)
      assert.truthy(find_text("re%.kriate"))
    end)

    it("shows active track number", function()
      local ctx = make_ctx()
      ctx.active_track = 3
      screen_ui.redraw(ctx)
      assert.truthy(find_text("3"))
    end)

    it("shows active page name", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      screen_ui.redraw(ctx)
      assert.truthy(find_text("note"))
    end)

    it("shows stopped state", function()
      local ctx = make_ctx()
      ctx.playing = false
      screen_ui.redraw(ctx)
      assert.truthy(find_text("stopped"))
    end)

    it("shows playing state", function()
      local ctx = make_ctx()
      ctx.playing = true
      screen_ui.redraw(ctx)
      assert.truthy(find_text("playing"))
    end)

  end)

  describe("per-track step positions (T029)", function()

    it("shows step position for all 4 tracks", function()
      local ctx = make_ctx()
      screen_ui.redraw(ctx)
      assert.truthy(find_text("T1"))
      assert.truthy(find_text("T2"))
      assert.truthy(find_text("T3"))
      assert.truthy(find_text("T4"))
    end)

    it("shows current pos and loop_end for a track", function()
      local ctx = make_ctx()
      ctx.tracks[1].params.trigger.pos = 5
      ctx.tracks[1].params.trigger.loop_end = 12
      screen_ui.redraw(ctx)
      assert.truthy(find_text("5/12"))
    end)

    it("shows muted indicator for muted tracks", function()
      local ctx = make_ctx()
      ctx.tracks[2].muted = true
      screen_ui.redraw(ctx)
      -- muted tracks should show a mute indicator
      local entry = find_text("T2.*mute")
      assert.truthy(entry, "expected mute indicator for track 2")
    end)

  end)

  describe("extended page indicator (T030)", function()

    it("shows parent and extended page for ratchet", function()
      local ctx = make_ctx()
      ctx.active_page = "ratchet"
      screen_ui.redraw(ctx)
      -- should show it's an extended page of trigger
      assert.truthy(find_text("trigger"), "expected parent page 'trigger' shown")
      assert.truthy(find_text("ratchet"), "expected extended page 'ratchet' shown")
    end)

    it("shows parent and extended page for alt_note", function()
      local ctx = make_ctx()
      ctx.active_page = "alt_note"
      screen_ui.redraw(ctx)
      assert.truthy(find_text("note"), "expected parent page 'note' shown")
      assert.truthy(find_text("alt_note"), "expected extended page 'alt_note' shown")
    end)

    it("shows parent and extended page for glide", function()
      local ctx = make_ctx()
      ctx.active_page = "glide"
      screen_ui.redraw(ctx)
      assert.truthy(find_text("octave"), "expected parent page 'octave' shown")
      assert.truthy(find_text("glide"), "expected extended page 'glide' shown")
    end)

    it("does not show extended indicator for primary pages", function()
      local ctx = make_ctx()
      ctx.active_page = "trigger"
      screen_ui.redraw(ctx)
      -- should show "trigger" but NOT show an extended indicator arrow
      assert.truthy(find_text("trigger"))
      assert.falsy(find_text(">"))
    end)

  end)

end)
