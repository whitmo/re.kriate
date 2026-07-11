-- specs/nav_spec_spec.lua
-- Validates lib/nav_spec.lua: internal consistency, and that every declared
-- nav-row (row 8) control matches what lib/grid_ui.lua's dispatch actually
-- does. This is the "declarative UI spec, tested in code" layer — it exists
-- so nav behavior can never silently drift from its description the way
-- README/help_overlay drifted from the code earlier (see feature-queue.md
-- "Known Issues", 2026-07-11).

package.path = package.path .. ";./?.lua"

rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function() return 1 end,
  cancel = function() end,
  sync = function() end,
})

local nav_spec = require("lib/nav_spec")
local grid_ui = require("lib/grid_ui")
local track_mod = require("lib/track")

local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    active_track = 1,
    active_page = "trigger",
    playing = false,
    loop_held = false,
    loop_first_press = nil,
    loop_first_y = nil,
    pattern_held = false,
    time_held = false,
    prob_held = false,
    grid_dirty = true,
  }
end

describe("nav_spec", function()

  describe("internal consistency", function()

    it("declares all 16 nav-row positions", function()
      for x = 1, 16 do
        assert.is_not_nil(nav_spec.NAV[x], "missing nav entry for x=" .. x)
      end
    end)

    it("uses only known control kinds", function()
      local valid_kinds = {}
      for _, k in ipairs(nav_spec.KINDS) do valid_kinds[k] = true end
      for x, entry in pairs(nav_spec.NAV) do
        assert.is_true(valid_kinds[entry.kind] == true,
          "x=" .. x .. " has unknown kind " .. tostring(entry.kind))
      end
    end)

    it("every referenced page name exists in grid_ui.PAGES", function()
      local valid_pages = {}
      for _, p in ipairs(grid_ui.PAGES) do valid_pages[p] = true end
      for x, entry in pairs(nav_spec.NAV) do
        for _, field in ipairs({"target", "extended", "alt_target"}) do
          if entry[field] then
            assert.is_true(valid_pages[entry[field]] == true,
              "x=" .. x .. " references unknown page " .. tostring(entry[field]))
          end
        end
        if entry.cycle then
          for _, p in ipairs(entry.cycle) do
            assert.is_true(valid_pages[p] == true,
              "x=" .. x .. " cycle references unknown page " .. tostring(p))
          end
        end
      end
    end)

    it("MODIFIER_PRECEDENCE only lists held_fields declared as modifiers in NAV", function()
      local modifier_fields = {}
      for _, entry in pairs(nav_spec.NAV) do
        if entry.kind == "modifier" then
          modifier_fields[entry.held_field] = true
        end
      end
      for _, field in ipairs(nav_spec.MODIFIER_PRECEDENCE) do
        assert.is_true(modifier_fields[field] == true,
          field .. " is in MODIFIER_PRECEDENCE but not declared as a modifier in NAV")
      end
    end)

  end)

  -- lib/grid_ui.lua's grid_key() checks pattern_held, then time_held, then
  -- prob_held (return-early chain) — loop_held is handled separately and
  -- inconsistently by redraw() (see feature-queue.md "Known Issues"), so it
  -- is deliberately excluded from this precedence declaration for now.
  describe("modifier precedence (matches grid_key's return-early chain)", function()

    it("declares pattern_held > time_held > prob_held", function()
      assert.are.same({"pattern_held", "time_held", "prob_held"}, nav_spec.MODIFIER_PRECEDENCE)
    end)

    it("pattern_held wins over time_held in grid_key", function()
      local ctx = make_ctx()
      ctx.patterns = require("lib/pattern").new_slots()
      ctx.pattern_held = true
      ctx.time_held = true
      grid_ui.grid_key(ctx, 1, 1, 1)
      assert.are.equal(1, ctx.pattern_slot)
    end)

    it("time_held wins over prob_held in grid_key", function()
      local ctx = make_ctx()
      ctx.active_page = "note"
      ctx.time_held = true
      ctx.prob_held = true
      local prob_before = ctx.tracks[ctx.active_track].params.probability.steps[1]
      grid_ui.grid_key(ctx, 1, 1, 1)
      assert.are.equal(1, ctx.tracks[1].params.note.clock_div)
      assert.are.equal(prob_before, ctx.tracks[ctx.active_track].params.probability.steps[1])
    end)

  end)

  describe("runtime cross-check: track_select", function()
    for x = 1, 4 do
      it("x=" .. x .. " sets active_track to " .. x, function()
        local ctx = make_ctx()
        grid_ui.nav_key(ctx, x, 1)
        assert.are.equal(x, ctx.active_track)
      end)
    end
  end)

  describe("runtime cross-check: modifier", function()
    for x, entry in pairs(nav_spec.NAV) do
      if entry.kind == "modifier" then
        it("x=" .. x .. " sets ctx." .. entry.held_field .. " on hold, clears on release", function()
          local ctx = make_ctx()
          grid_ui.nav_key(ctx, x, 1)
          assert.is_true(ctx[entry.held_field])
          grid_ui.nav_key(ctx, x, 0)
          assert.is_false(ctx[entry.held_field])
        end)

        if entry.extra_reset_fields then
          it("x=" .. x .. " clears " .. table.concat(entry.extra_reset_fields, ", ") .. " on release", function()
            local ctx = make_ctx()
            grid_ui.nav_key(ctx, x, 1)
            for _, field in ipairs(entry.extra_reset_fields) do
              ctx[field] = "sentinel"
            end
            grid_ui.nav_key(ctx, x, 0)
            for _, field in ipairs(entry.extra_reset_fields) do
              assert.is_nil(ctx[field])
            end
          end)
        end
      end
    end
  end)

  describe("runtime cross-check: page (oneshot select)", function()
    for x, entry in pairs(nav_spec.NAV) do
      if entry.kind == "page" then
        it("x=" .. x .. " sets active_page to " .. entry.target, function()
          local ctx = make_ctx()
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.target, ctx.active_page)
        end)
      end
    end
  end)

  describe("runtime cross-check: page_extended", function()
    for x, entry in pairs(nav_spec.NAV) do
      if entry.kind == "page_extended" then
        it("x=" .. x .. " toggles " .. entry.target .. " <-> " .. entry.extended, function()
          local ctx = make_ctx()
          -- Start from a neutral page: make_ctx()'s default ("trigger") is
          -- itself one nav button's target, which would make the first
          -- press below toggle straight to `extended` instead of arriving
          -- at `target` for the first time.
          ctx.active_page = "__neutral__"
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.target, ctx.active_page)
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.extended, ctx.active_page)
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.target, ctx.active_page)
        end)
      end
    end
  end)

  describe("runtime cross-check: page_cycle", function()
    for x, entry in pairs(nav_spec.NAV) do
      if entry.kind == "page_cycle" then
        it("x=" .. x .. " cycles through " .. table.concat(entry.cycle, " -> ") .. " and wraps", function()
          local ctx = make_ctx()
          for _, expected_page in ipairs(entry.cycle) do
            grid_ui.nav_key(ctx, x, 1)
            assert.are.equal(expected_page, ctx.active_page)
          end
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.cycle[1], ctx.active_page)
        end)
      end
    end
  end)

  describe("runtime cross-check: page_toggle2", function()
    for x, entry in pairs(nav_spec.NAV) do
      if entry.kind == "page_toggle2" then
        it("x=" .. x .. " toggles " .. entry.target .. " <-> " .. entry.alt_target, function()
          local ctx = make_ctx()
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.target, ctx.active_page)
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.alt_target, ctx.active_page)
          grid_ui.nav_key(ctx, x, 1)
          assert.are.equal(entry.target, ctx.active_page)
        end)
      end
    end
  end)

  describe("runtime cross-check: track_toggle", function()
    for x, entry in pairs(nav_spec.NAV) do
      if entry.kind == "track_toggle" then
        it("x=" .. x .. " flips ctx.tracks[active_track]." .. entry.field, function()
          local ctx = make_ctx()
          local track = ctx.tracks[ctx.active_track]
          local before = track[entry.field]
          grid_ui.nav_key(ctx, x, 1)
          assert.are_not.equal(before, track[entry.field])
        end)
      end
    end
  end)

end)
