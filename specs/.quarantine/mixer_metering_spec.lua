-- specs/mixer_metering_spec.lua
package.path = package.path .. ";./?.lua"
local Mixer = require("lib/mixer")
local grid_ui = require("lib/grid_ui")
local match = require("luassert.match")

describe("Mixer Metering", function()
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
  end)

  it("handles meterId 0-3 for tracks (T011)", function()
    -- Format: {nodeID, meterId, peakL, peakR}
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 0, 0.5, 0.6})
    assert.equal(0.5, mixer.meters.tracks[1][1])
    assert.equal(0.6, mixer.meters.tracks[1][2])
    
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 3, 0.1, 0.2})
    assert.equal(0.1, mixer.meters.tracks[4][1])
    assert.equal(0.2, mixer.meters.tracks[4][2])
  end)

  it("handles meterId 10 for aux (T011)", function()
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 10, 0.7, 0.8})
    assert.equal(0.7, mixer.meters.aux[1])
    assert.equal(0.8, mixer.meters.aux[2])
  end)

  it("handles meterId 20 for master (T011)", function()
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 20, 0.9, 1.0})
    assert.equal(0.9, mixer.meters.master[1])
    assert.equal(1.0, mixer.meters.master[2])
  end)

  it("is no-op for invalid meterId (T011)", function()
    -- Should not error
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 5, 0.5, 0.6})
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 99, 0.5, 0.6})
  end)

  it("is no-op for missing/short args (T011)", function()
    mixer:handle_meter("/rekriate/mixer/meter", {1001, 0})
    assert.equal(0, mixer.meters.tracks[1][1])
  end)

  it("reflects meter values in LED brightness (T011)", function()
    mixer.tracks[1].level = 0
    mixer.meters.tracks[1] = {1.0, 1.0} -- Full peak
    
    grid_ui.draw_mixer_page(ctx, g)
    
    -- row 1 (y=1) should be lit due to meter overlay (base 2 or 3 + 5 = 7... wait)
    -- Actually in draw_mixer_page:
    -- if row_val <= math.floor(peak * 6 + 0.5) then brightness = math.min(15, brightness + 5)
    -- If peak=1.0, math.floor(1.0 * 6 + 0.5) = 6.
    -- So all 6 rows (y=1..6) should have +5 brightness.
    assert.spy(g.led).was_called_with(g, 1, 1, match.is_number())
    
    -- Find the call for x=1, y=1 and check brightness
    local found = false
    for _, call in ipairs(g.led.calls) do
      if call.vals[2] == 1 and call.vals[3] == 1 then
        assert.is_true(call.vals[4] >= 5)
        found = true
      end
    end
    assert.is_true(found)
  end)
end)
