package.path = package.path .. ";./?.lua"
-- specs/mixer_persistence_spec.lua
local pattern_persistence = require("lib/pattern_persistence")
local Mixer = require("lib/mixer")
local track_mod = require("lib/track")
local pattern = require("lib/pattern")

describe("Mixer Persistence Integration", function()
  local ctx
  local test_dir = "/Users/whit/src/re.kriate/specs/tmp/mixer_persistence_test"

  before_each(function()
    -- Create test dir
    os.execute("mkdir -p " .. test_dir)
    pattern_persistence._test_set_data_dir(test_dir)
    
    -- Mock params
    _G.params = {
      set = spy.new(function() end),
      get = function() return 1 end
    }
    _G.osc = {
      send = spy.new(function() end)
    }
    
    -- Setup ctx
    ctx = {
      tracks = track_mod.new_tracks(),
      patterns = pattern.new_slots(),
      mixer = Mixer.new()
    }
  end)

  after_each(function()
    _G.params = nil
    _G.osc = nil
    -- Cleanup test dir
    os.execute("rm -rf " .. test_dir)
  end)

  it("saves mixer state in pattern bank (T009/T031)", function()
    -- Clear params to use fallback merge in mixer:deserialize
    local old_params = _G.params
    _G.params = nil
    
    ctx.mixer.tracks[1].level = 0.42
    local ok, path = pattern_persistence.save(ctx, "test-mix")
    assert.is_true(ok)
    
    -- Verify "mixer" key in payload (simulated load)
    ctx.mixer.tracks[1].level = 0.7 -- reset
    ok = pattern_persistence.load(ctx, "test-mix")
    assert.is_true(ok)
    assert.equal(0.42, ctx.mixer.tracks[1].level)
    
    _G.params = old_params
  end)

  it("loads legacy pattern banks without mixer data gracefully (T009/T031)", function()
    assert.has_no.errors(function()
      ctx.mixer:deserialize(nil)
    end)
  end)

  it("roundtrip preserves all params (T009)", function()
    local old_params = _G.params
    _G.params = nil
    
    ctx.mixer.tracks[2].pan = 0.5
    ctx.mixer.aux.reverb_mix = 0.8
    ctx.mixer.master.level = 0.9
    
    local data = ctx.mixer:serialize()
    local new_mixer = Mixer.new()
    new_mixer:deserialize(data)
    
    assert.equal(0.5, new_mixer.tracks[2].pan)
    assert.equal(0.8, new_mixer.aux.reverb_mix)
    assert.equal(0.9, new_mixer.master.level)
    
    _G.params = old_params
  end)

  it("deserialize() with partial data preserves defaults (T009)", function()
    local data = ctx.mixer:serialize()
    data.aux = nil
    
    local new_mixer = Mixer.new()
    new_mixer.aux.level = 0.5 -- non-default
    new_mixer:deserialize(data)
    -- Since aux was missing from data, it should stay 0.5 if it preserves current state
    -- or if we are talking about "fresh" mixer, it stays at default.
    -- The requirement says "preserves defaults for missing fields".
    assert.equal(0.5, new_mixer.aux.level)
  end)
end)
