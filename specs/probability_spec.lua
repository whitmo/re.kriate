-- specs/probability_spec.lua
-- Test trigger probability gating in sequencer

package.path = package.path .. ";./?.lua"

rawset(_G, "clock", {
  sync = function() end,
  run = function(fn) return fn() end,
  cancel = function() end,
})

local sequencer = require("lib/sequencer")
local track_mod = require("lib/track")

local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    scale_notes = {60, 62, 64, 65, 67, 69, 71},
    events = {
      emit = function() end,
    },
    voices = {
      [1] = {
        play_note = function() end,
        set_portamento = function() end,
      },
    },
  }
end

describe("sequencer probability gating", function()
  it("fires when roll <= probability", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.1 end -- 10
    ctx.tracks[1].params.probability.steps[1] = 50
    local fired = false
    ctx.voices[1].play_note = function() fired = true end
    sequencer.step_track(ctx, 1)
    assert.is_true(fired)
  end)

  it("skips when roll > probability", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.9 end -- 90
    ctx.tracks[1].params.probability.steps[1] = 20
    local fired = false
    ctx.voices[1].play_note = function() fired = true end
    sequencer.step_track(ctx, 1)
    assert.is_false(fired)
  end)
end)
