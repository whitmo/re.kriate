-- specs/grid_mixer_spec.lua
package.path = package.path .. ";./?.lua"
local grid_ui = require("lib/grid_ui")
local Mixer = require("lib/mixer")
local match = require("luassert.match")

describe("Grid Mixer UI", function()
  local mixer
  local ctx
  local g

  before_each(function()
    mixer = Mixer.new()
    g = { led = spy.new(function() end) }
    ctx = {
      g = g,
      mixer = mixer,
      active_track = 1,
      active_page = "mixer"
    }
    _G.params = {
      set = spy.new(function() end),
      get = function(self, id) return 1 end
    }
  end)

  after_each(function()
    _G.params = nil
  end)

  it("draws level faders with correct brightness (T007)", function()
    mixer.tracks[1].level = 1.0 -- All 6 rows should be lit
    grid_ui.draw_mixer_page(ctx, g)
    
    -- col 1, row 1-6 should be lit
    assert.spy(g.led).was_called_with(g, 1, 1, 10) -- fill
    assert.spy(g.led).was_called_with(g, 1, 6, 10) -- fill
  end)

  it("dims fader for muted channel (T007)", function()
    mixer.tracks[1].mute = 1
    mixer.tracks[1].level = 1.0
    grid_ui.draw_mixer_page(ctx, g)
    
    -- brightness should be 4 for muted fill
    assert.spy(g.led).was_called_with(g, 1, 1, 4)
  end)

  it("adds meter overlay brightness (T007)", function()
    mixer.tracks[1].level = 0.5 -- lvl 3 (rows 4,5,6 lit with 10)
    mixer.meters.tracks[1] = {0.8, 0.8} -- peak 0.8 -> lvl 5 (rows 2,3,4,5,6 overlay)
    
    grid_ui.draw_mixer_page(ctx, g)
    
    -- row 4 should have 10 (fill) + 5 (meter) = 15
    assert.spy(g.led).was_called_with(g, 1, 4, 15)
  end)

  it("sets mixer level via params (T007)", function()
    -- Press col 1, row 1 (lvl 6/max)
    grid_ui.mixer_key(ctx, 1, 1, 1)
    assert.spy(_G.params.set).was_called_with(_G.params, "mixer_level_1", 1.0)
  end)

  it("toggles mute via params (T007)", function()
    -- Press col 1, row 7 (mute toggle)
    grid_ui.mixer_key(ctx, 1, 7, 1)
    assert.spy(_G.params.set).was_called_with(_G.params, "mixer_mute_1", 2) -- 2 = on
  end)
end)
