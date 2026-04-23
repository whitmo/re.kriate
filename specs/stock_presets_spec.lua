-- specs/stock_presets_spec.lua
-- Tests for lib/stock_presets.lua: seeding behavior + round-trip load via
-- lib/preset.lua.

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Minimal params mock so preset.save/load can snapshot/apply values.
local param_store = {}
local param_lookup = {}
rawset(_G, "params", {
  lookup = param_lookup,
  get = function(self, id) return param_store[id] end,
  set = function(self, id, val) param_store[id] = val end,
})

rawset(_G, "clock", {
  run = function() end,
  sync = function() end,
  cancel = function() end,
  get_beats = function() return 0 end,
})

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local meta_pattern = require("lib/meta_pattern")
local preset = require("lib/preset")
local stock_presets = require("lib/stock_presets")

local tmp_root = "specs/tmp/stock_presets"

local function reset_tmp()
  os.execute("rm -rf " .. tmp_root)
  os.execute("mkdir -p " .. tmp_root)
  preset._test_set_data_dir(tmp_root)
  preset._test_set_fs(nil)
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_lookup) do param_lookup[k] = nil end
end

local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
    meta = meta_pattern.new(),
    pattern_slot = 1,
    active_track = 1,
    active_page = "trigger",
  }
end

describe("stock_presets", function()

  before_each(reset_tmp)

  describe("names", function()
    it("exposes the full ordered list of stock preset names", function()
      local names = stock_presets.names()
      assert.is_true(#names >= 3)
      assert.are.equal("stock-defaults", names[1])
      assert.are.equal("stock-four-on-floor", names[2])
      assert.are.equal("stock-arp-up", names[3])
    end)
  end)

  describe("seed_if_empty", function()
    it("writes all stock presets when the dir is empty", function()
      local count, errs = stock_presets.seed_if_empty(preset)
      assert.is_nil(errs)
      assert.are.equal(#stock_presets.presets, count)

      local listed = preset.list()
      -- preset.list returns sorted names, so compare via set-membership
      local set = {}
      for _, n in ipairs(listed) do set[n] = true end
      for _, s in ipairs(stock_presets.presets) do
        assert.is_true(set[s.name], "missing " .. s.name)
      end
    end)

    it("does not overwrite existing user presets", function()
      local ctx = make_ctx()
      ctx.tracks[1].division = 7
      assert.is_true(preset.save(ctx, "user-tweak"))

      local count = stock_presets.seed_if_empty(preset)
      assert.are.equal(0, count)

      -- User preset untouched; no stock files written
      assert.is_true(preset.exists("user-tweak"))
      for _, s in ipairs(stock_presets.presets) do
        assert.is_false(preset.exists(s.name))
      end
    end)

    it("is idempotent: second call writes nothing after seeding", function()
      local first = stock_presets.seed_if_empty(preset)
      assert.is_true(first > 0)

      local second = stock_presets.seed_if_empty(preset)
      assert.are.equal(0, second)
    end)

    it("returns 0 when preset_mod is nil", function()
      local count, errs = stock_presets.seed_if_empty(nil)
      assert.are.equal(0, count)
      assert.is_not_nil(errs)
    end)
  end)

  describe("round-trip through preset.load", function()
    it("stock-defaults loads into a ctx with populated slot 1", function()
      assert.is_true(stock_presets.seed_if_empty(preset) > 0)

      local ctx = make_ctx()
      assert.is_true(preset.load(ctx, "stock-defaults"))
      assert.is_true(pattern.is_populated(ctx.patterns, 1))
      -- Track defaults carry the musical starting pattern from new_track.
      assert.are.equal("forward", ctx.tracks[1].direction)
    end)

    it("stock-four-on-floor places a kick on steps 1/5/9/13", function()
      assert.is_true(stock_presets.seed_if_empty(preset) > 0)

      local ctx = make_ctx()
      assert.is_true(preset.load(ctx, "stock-four-on-floor"))

      local kick = ctx.tracks[1].params.trigger.steps
      assert.are.equal(1, kick[1])
      assert.are.equal(1, kick[5])
      assert.are.equal(1, kick[9])
      assert.are.equal(1, kick[13])
      assert.are.equal(0, kick[2])
      assert.are.equal(0, kick[4])

      -- Track 4 should be muted as a background track
      assert.is_true(ctx.tracks[4].muted)
    end)

    it("stock-arp-up sets an 8-step ascending scale on track 1", function()
      assert.is_true(stock_presets.seed_if_empty(preset) > 0)

      local ctx = make_ctx()
      assert.is_true(preset.load(ctx, "stock-arp-up"))

      local notes = ctx.tracks[1].params.note.steps
      for i = 1, 7 do
        assert.are.equal(i, notes[i])
      end
      -- All triggers on for an arp
      for i = 1, 8 do
        assert.are.equal(1, ctx.tracks[1].params.trigger.steps[i])
      end
      -- Loop is capped to the 8-note run
      assert.are.equal(8, ctx.tracks[1].params.note.loop_end)
      -- Remaining tracks muted
      assert.is_true(ctx.tracks[2].muted)
      assert.is_true(ctx.tracks[3].muted)
      assert.is_true(ctx.tracks[4].muted)
    end)
  end)

  describe("payload shape", function()
    it("each build() returns a preset-compatible payload", function()
      for _, s in ipairs(stock_presets.presets) do
        local payload = s.build()
        assert.is_table(payload.tracks)
        assert.are.equal(track_mod.NUM_TRACKS, #payload.tracks)
        assert.is_table(payload.patterns)
        assert.is_table(payload.meta)
        assert.is_not_nil(payload.active_track)
        assert.is_not_nil(payload.active_page)
      end
    end)
  end)

  describe("FR-007a compliance in seeded payloads", function()
    it("stock-four-on-floor slot 1 is populated but does not clobber live tracks", function()
      assert.is_true(stock_presets.seed_if_empty(preset) > 0)

      local ctx = make_ctx()
      assert.is_true(preset.load(ctx, "stock-four-on-floor"))
      -- slot 1 holds the four-on-floor snapshot identical to live tracks on load
      assert.is_true(pattern.is_populated(ctx.patterns, 1))
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[1])
      assert.are.equal(1, ctx.patterns[1].tracks[1].params.trigger.steps[5])
    end)
  end)
end)
