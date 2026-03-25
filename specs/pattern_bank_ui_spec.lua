-- specs/pattern_bank_ui_spec.lua
-- Tests for pattern bank visual feedback (006-pattern-bank-ui)

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer -> recorder)
local beat_counter = 0
rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

-- Mock seamstress screen API
local screen_buffer = {}
local current_pos = {x = 0, y = 0}
local current_color = {0, 0, 0, 255}

local function reset_screen()
  screen_buffer = { texts = {}, rects = {} }
  current_pos = {x = 0, y = 0}
  current_color = {0, 0, 0, 255}
end

rawset(_G, "screen", {
  clear = function() reset_screen() end,
  color = function(r, g, b, a) current_color = {r, g, b, a} end,
  move = function(x, y) current_pos = {x = x, y = y} end,
  rect_fill = function(w, h)
    table.insert(screen_buffer.rects, {
      x = current_pos.x,
      y = current_pos.y,
      w = w,
      h = h,
      color = {current_color[1], current_color[2], current_color[3], current_color[4]},
    })
  end,
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
local pattern = require("lib/pattern")
local keyboard = require("lib/seamstress/keyboard")
local screen_ui = require("lib/seamstress/screen_ui")

-- Helper: create minimal ctx for keyboard tests
local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    grid_dirty = false,
    voices = {},
    clock_ids = nil,
  }
end

-- Helper: find text matching a Lua pattern in screen buffer
local function find_text(pat)
  for _, entry in ipairs(screen_buffer.texts) do
    if entry.str:find(pat) then
      return entry
    end
  end
  return nil
end

-- Helper: count rect_fill calls excluding the background rect (256x128)
local function count_slot_rects()
  local count = 0
  for _, r in ipairs(screen_buffer.rects) do
    if r.w ~= 256 or r.h ~= 128 then
      count = count + 1
    end
  end
  return count
end

-- Helper: get slot indicator rects (excluding background)
local function get_slot_rects()
  local slots = {}
  for _, r in ipairs(screen_buffer.rects) do
    if r.w ~= 256 or r.h ~= 128 then
      table.insert(slots, r)
    end
  end
  return slots
end

-- ============================================================
-- US1: Active Pattern Indicator
-- ============================================================

describe("pattern bank UI", function()

  before_each(function()
    reset_screen()
  end)

  describe("US1: active pattern tracking", function()

    it("T003: save pattern sets ctx.active_pattern", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "3", {ctrl = true}, false, 1)
      assert.are.equal(3, ctx.active_pattern)
    end)

    it("T004: load populated slot sets ctx.active_pattern", function()
      local ctx = make_ctx()
      -- save to slot 5 first to populate it
      pattern.save(ctx, 5)
      keyboard.key(ctx, "5", {shift = true}, false, 1)
      assert.are.equal(5, ctx.active_pattern)
    end)

    it("T005: load empty slot does NOT change ctx.active_pattern", function()
      local ctx = make_ctx()
      -- save to slot 3 to set active_pattern
      keyboard.key(ctx, "3", {ctrl = true}, false, 1)
      assert.are.equal(3, ctx.active_pattern)
      -- load empty slot 7
      keyboard.key(ctx, "7", {shift = true}, false, 1)
      assert.are.equal(3, ctx.active_pattern)
    end)

    it("T006: no active pattern on startup", function()
      local ctx = make_ctx()
      assert.is_nil(ctx.active_pattern)
    end)

    it("T007: active pattern moves on subsequent save", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "3", {ctrl = true}, false, 1)
      assert.are.equal(3, ctx.active_pattern)
      keyboard.key(ctx, "7", {ctrl = true}, false, 1)
      assert.are.equal(7, ctx.active_pattern)
    end)
  end)

  -- ============================================================
  -- US2: Populated Slot Indicators
  -- ============================================================

  describe("US2: slot indicators", function()

    it("T009: 9 slot indicators rendered", function()
      local ctx = make_ctx()
      screen_ui.redraw(ctx)
      assert.are.equal(9, count_slot_rects())
    end)

    it("T010: empty slots render dim color", function()
      local ctx = make_ctx()
      screen_ui.redraw(ctx)
      local slots = get_slot_rects()
      assert.are.equal(9, #slots)
      for _, s in ipairs(slots) do
        -- dim color: low brightness
        assert.is_true(s.color[1] <= 60, "expected dim red channel <= 60, got " .. s.color[1])
      end
    end)

    it("T011: populated slots render medium color", function()
      local ctx = make_ctx()
      pattern.save(ctx, 1)
      pattern.save(ctx, 3)
      pattern.save(ctx, 5)
      screen_ui.redraw(ctx)
      local slots = get_slot_rects()
      assert.are.equal(9, #slots)
      -- populated slots (1, 3, 5) should have higher brightness than dim
      for _, idx in ipairs({1, 3, 5}) do
        local s = slots[idx]
        assert.is_true(s.color[1] > 60, "slot " .. idx .. " expected medium brightness, got " .. s.color[1])
      end
      -- empty slots (2, 4, 6, 7, 8, 9) should be dim
      for _, idx in ipairs({2, 4, 6, 7, 8, 9}) do
        local s = slots[idx]
        assert.is_true(s.color[1] <= 60, "slot " .. idx .. " expected dim, got " .. s.color[1])
      end
    end)

    it("T012: active slot renders bright color", function()
      local ctx = make_ctx()
      pattern.save(ctx, 3)
      ctx.active_pattern = 3
      screen_ui.redraw(ctx)
      local slots = get_slot_rects()
      -- slot 3 should be brightest
      local active = slots[3]
      assert.is_true(active.color[1] >= 180, "expected bright for active slot, got " .. active.color[1])
    end)

    it("T013: nil ctx.patterns renders all-empty without error", function()
      local ctx = make_ctx()
      ctx.patterns = nil
      screen_ui.redraw(ctx)
      local slots = get_slot_rects()
      assert.are.equal(9, #slots)
      for _, s in ipairs(slots) do
        assert.is_true(s.color[1] <= 60, "expected dim for nil patterns, got " .. s.color[1])
      end
    end)
  end)

  -- ============================================================
  -- US3: Transient Save/Load Feedback
  -- ============================================================

  describe("US3: transient messages", function()

    it("T015: save sets ctx.pattern_message", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "3", {ctrl = true}, false, 1)
      assert.is_not_nil(ctx.pattern_message)
      assert.are.equal("saved 3", ctx.pattern_message.text)
      assert.is_number(ctx.pattern_message.time)
    end)

    it("T016: load populated slot sets ctx.pattern_message", function()
      local ctx = make_ctx()
      pattern.save(ctx, 5)
      keyboard.key(ctx, "5", {shift = true}, false, 1)
      assert.is_not_nil(ctx.pattern_message)
      assert.are.equal("loaded 5", ctx.pattern_message.text)
    end)

    it("T017: load empty slot does NOT set message", function()
      local ctx = make_ctx()
      -- set an initial state
      keyboard.key(ctx, "3", {ctrl = true}, false, 1)
      local original_msg = ctx.pattern_message
      -- load empty slot 7
      keyboard.key(ctx, "7", {shift = true}, false, 1)
      -- message should still be the save message, not changed to a load message
      assert.are.equal("saved 3", ctx.pattern_message.text)
    end)

    it("T018: transient message rendered on screen", function()
      local ctx = make_ctx()
      ctx.pattern_message = {text = "saved 3", time = os.clock()}
      screen_ui.redraw(ctx)
      assert.truthy(find_text("saved 3"))
    end)

    it("T019: expired message cleared during redraw", function()
      local ctx = make_ctx()
      -- set message with time 2 seconds in the past
      ctx.pattern_message = {text = "saved 3", time = os.clock() - 2}
      screen_ui.redraw(ctx)
      assert.falsy(find_text("saved 3"))
      assert.is_nil(ctx.pattern_message)
    end)

    it("T020: new action replaces message and resets timer", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "3", {ctrl = true}, false, 1)
      assert.are.equal("saved 3", ctx.pattern_message.text)
      -- populate slot 1 then load it
      pattern.save(ctx, 1)
      keyboard.key(ctx, "1", {shift = true}, false, 1)
      assert.are.equal("loaded 1", ctx.pattern_message.text)
    end)
  end)

  -- ============================================================
  -- US4: Verification
  -- ============================================================

  describe("US4: seamstress-only scope", function()

    it("T023: re_kriate.lua contains no pattern indicator code", function()
      local f = io.open("re_kriate.lua", "r")
      assert.truthy(f, "re_kriate.lua must exist")
      local content = f:read("*a")
      f:close()
      assert.falsy(content:find("active_pattern"), "re_kriate.lua must not contain active_pattern")
      assert.falsy(content:find("pattern_message"), "re_kriate.lua must not contain pattern_message")
    end)

    it("T024: lib/app.lua contains no pattern UI logic", function()
      local f = io.open("lib/app.lua", "r")
      assert.truthy(f, "lib/app.lua must exist")
      local content = f:read("*a")
      f:close()
      assert.falsy(content:find("draw_pattern"), "lib/app.lua must not contain draw_pattern")
      assert.falsy(content:find("pattern_message"), "lib/app.lua must not contain pattern_message")
    end)

    it("T025: slot 9 boundary works identically", function()
      local ctx = make_ctx()
      keyboard.key(ctx, "9", {ctrl = true}, false, 1)
      assert.are.equal(9, ctx.active_pattern)
      assert.are.equal("saved 9", ctx.pattern_message.text)
    end)
  end)
end)
