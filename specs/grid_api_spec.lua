-- specs/grid_api_spec.lua
-- Tests for lib/remote/grid_api.lua: remote API grid extensions

package.path = package.path .. ";./?.lua"

-- Mock norns grid (needed by grid_provider "monome" registration)
rawset(_G, "grid", {
  connect = function()
    return {
      all = function(self, val) end,
      led = function(self, x, y, b) end,
      refresh = function(self) end,
    }
  end,
})

-- Mock clock (needed by grid_ui -> sequencer indirect require)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local grid_provider = require("lib/grid_provider")
local grid_api = require("lib/remote/grid_api")
local grid_ui = require("lib/grid_ui")
local track_mod = require("lib/track")

-- Helper: create a ctx with a virtual grid and grid_ui wired up
local function make_ctx()
  local g = grid_provider.connect("virtual")
  local ctx = {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    loop_first_press = nil,
    grid_dirty = true,
    g = g,
  }
  -- Wire up key callback like app.lua does
  g.key = function(x, y, z)
    grid_ui.key(ctx, x, y, z)
    ctx.grid_dirty = true
  end
  return ctx
end

describe("grid_api", function()

  -- ========================================================================
  -- /grid/key: inject key events
  -- ========================================================================

  describe("/grid/key", function()

    it("injects a key press that reaches grid_ui", function()
      local ctx = make_ctx()
      local before = ctx.tracks[1].params.trigger.steps[5]
      -- Toggle trigger step 5 on track 1 via API
      local result, err = grid_api.handlers["/grid/key"](ctx, {5, 1, 1})
      assert.is_nil(err)
      assert.is_true(result)
      -- The grid_ui should have toggled the trigger (flipped from default)
      local expected = before == 0 and 1 or 0
      assert.are.equal(expected, ctx.tracks[1].params.trigger.steps[5])
    end)

    it("handles key release (z=0)", function()
      local ctx = make_ctx()
      local result, err = grid_api.handlers["/grid/key"](ctx, {5, 1, 0})
      assert.is_nil(err)
      assert.is_true(result)
    end)

    it("selects track via nav row press", function()
      local ctx = make_ctx()
      -- Press track 3 button (x=3, y=8, z=1)
      grid_api.handlers["/grid/key"](ctx, {3, 8, 1})
      assert.are.equal(3, ctx.active_track)
    end)

    it("errors on missing args", function()
      local ctx = make_ctx()
      local result, err = grid_api.handlers["/grid/key"](ctx, {})
      assert.is_nil(result)
      assert.is_string(err)
    end)

    it("errors on out-of-range x", function()
      local ctx = make_ctx()
      local _, err = grid_api.handlers["/grid/key"](ctx, {17, 1, 1})
      assert.is_string(err)
    end)

    it("errors on out-of-range y", function()
      local ctx = make_ctx()
      local _, err = grid_api.handlers["/grid/key"](ctx, {1, 9, 1})
      assert.is_string(err)
    end)

    it("errors on invalid z", function()
      local ctx = make_ctx()
      local _, err = grid_api.handlers["/grid/key"](ctx, {1, 1, 2})
      assert.is_string(err)
    end)

    it("errors when no grid connected", function()
      local ctx = make_ctx()
      ctx.g = nil
      local _, err = grid_api.handlers["/grid/key"](ctx, {1, 1, 1})
      assert.is_string(err)
    end)

  end)

  -- ========================================================================
  -- /grid/state: read full LED state
  -- ========================================================================

  describe("/grid/state", function()

    it("returns LED state after redraw", function()
      local ctx = make_ctx()
      -- Set some triggers and redraw
      ctx.tracks[1].params.trigger.steps[1] = 1
      grid_ui.redraw(ctx)

      local state, err = grid_api.handlers["/grid/state"](ctx)
      assert.is_nil(err)
      assert.is_table(state)
      -- Should have 8 rows
      assert.are.equal(8, #state)
      -- Each row should have 16 columns
      assert.are.equal(16, #state[1])
      -- Step 1 trigger on track 1 should be lit (brightness 8)
      assert.are.equal(8, state[1][1])
    end)

    it("reflects nav row state", function()
      local ctx = make_ctx()
      grid_ui.redraw(ctx)

      local state = grid_api.handlers["/grid/state"](ctx)
      -- Active track 1 at nav row (y=8, x=1) should be bright
      assert.are.equal(12, state[8][1])
      -- Inactive track 2 should be dim
      assert.are.equal(3, state[8][2])
    end)

    it("errors when no grid connected", function()
      local ctx = make_ctx()
      ctx.g = nil
      local _, err = grid_api.handlers["/grid/state"](ctx)
      assert.is_string(err)
    end)

    it("errors when grid lacks get_state", function()
      local ctx = make_ctx()
      ctx.g.get_state = nil
      local _, err = grid_api.handlers["/grid/state"](ctx)
      assert.is_string(err)
    end)

  end)

  -- ========================================================================
  -- /grid/led: read single LED
  -- ========================================================================

  describe("/grid/led", function()

    it("reads LED brightness at position", function()
      local ctx = make_ctx()
      ctx.tracks[1].params.trigger.steps[3] = 1
      grid_ui.redraw(ctx)

      local val, err = grid_api.handlers["/grid/led"](ctx, {3, 1})
      assert.is_nil(err)
      assert.are.equal(8, val)
    end)

    it("reads LED for step without trigger", function()
      local ctx = make_ctx()
      -- Step 2 on track 1 has trigger=0 in default pattern
      grid_ui.redraw(ctx)

      local val = grid_api.handlers["/grid/led"](ctx, {2, 1})
      -- No trigger, but in loop region = brightness 2
      assert.are.equal(2, val)
    end)

    it("errors on missing args", function()
      local ctx = make_ctx()
      local _, err = grid_api.handlers["/grid/led"](ctx, {})
      assert.is_string(err)
    end)

    it("errors when grid lacks get_led", function()
      local ctx = make_ctx()
      ctx.g.get_led = nil
      local _, err = grid_api.handlers["/grid/led"](ctx, {1, 1})
      assert.is_string(err)
    end)

  end)

  -- ========================================================================
  -- /grid/info: grid metadata
  -- ========================================================================

  describe("/grid/info", function()

    it("returns grid dimensions and capabilities", function()
      local ctx = make_ctx()
      local info, err = grid_api.handlers["/grid/info"](ctx)
      assert.is_nil(err)
      assert.are.equal(16, info.cols)
      assert.are.equal(8, info.rows)
      assert.is_true(info.readable)
      assert.is_true(info.has_state)
    end)

    it("reports non-readable grid correctly", function()
      local ctx = make_ctx()
      ctx.g.get_led = nil
      ctx.g.get_state = nil
      local info = grid_api.handlers["/grid/info"](ctx)
      assert.is_false(info.readable)
      assert.is_false(info.has_state)
    end)

    it("errors when no grid connected", function()
      local ctx = make_ctx()
      ctx.g = nil
      local _, err = grid_api.handlers["/grid/info"](ctx)
      assert.is_string(err)
    end)

  end)

  -- ========================================================================
  -- End-to-end: remote UI round-trip
  -- ========================================================================

  describe("round-trip: key inject -> redraw -> state read", function()

    it("toggle trigger via API, see result in LED state", function()
      local ctx = make_ctx()

      -- Step 2 on track 1 defaults to trigger=0, toggling makes it 1
      local before = ctx.tracks[1].params.trigger.steps[2]
      assert.are.equal(0, before)

      grid_api.handlers["/grid/key"](ctx, {2, 1, 1})
      assert.are.equal(1, ctx.tracks[1].params.trigger.steps[2])

      -- Redraw grid
      grid_ui.redraw(ctx)

      -- Read back LED state — trigger on = brightness 8
      local state = grid_api.handlers["/grid/state"](ctx)
      assert.are.equal(8, state[1][2])
    end)

    it("switch page via API nav press, see updated display", function()
      local ctx = make_ctx()

      -- Press note page button (x=7, y=8)
      grid_api.handlers["/grid/key"](ctx, {7, 8, 1})
      assert.are.equal("note", ctx.active_page)

      -- Redraw and verify nav reflects new page
      grid_ui.redraw(ctx)
      local state = grid_api.handlers["/grid/state"](ctx)
      -- Note page button (x=7) should be bright
      assert.are.equal(12, state[8][7])
      -- Trigger button (x=6) should be dim
      assert.are.equal(3, state[8][6])
    end)

  end)

end)
