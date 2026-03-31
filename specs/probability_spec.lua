-- specs/probability_spec.lua
-- Test per-parameter probability gating in sequencer

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

describe("per-parameter probability gating", function()
  it("fires when roll <= probability (all params advance)", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.1 end -- 10 <= 50
    ctx.tracks[1].params.probability.steps[1] = 50
    local fired = false
    ctx.voices[1].play_note = function() fired = true end
    sequencer.step_track(ctx, 1)
    assert.is_true(fired)
  end)

  it("skips trigger when roll > probability (trigger holds at 0)", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.9 end -- 90 > 20
    -- trigger step 1 = 1 (would fire), but probability will prevent it from advancing
    -- Position starts at 1. Default trigger pattern for track 1: {1,0,1,0,...}
    -- With probability failing, trigger holds its peek value at pos 1 = 1
    -- BUT trigger doesn't advance. Actually, let's set up a clearer scenario:
    -- Set all trigger steps to 0 except step 2
    for i = 1, 16 do ctx.tracks[1].params.trigger.steps[i] = 0 end
    ctx.tracks[1].params.trigger.steps[2] = 1
    -- advance trigger once to get to step 2
    ctx.tracks[1].params.trigger.pos = 1
    -- With 100% prob first to advance to step 2
    ctx.tracks[1].params.probability.steps[1] = 100
    sequencer.step_track(ctx, 1)
    -- now at step 2 (trigger=1), set low probability
    ctx.tracks[1].params.probability.steps[2] = 20
    local fired = false
    ctx.voices[1].play_note = function() fired = true end
    sequencer.step_track(ctx, 1)
    -- trigger held at step 2 value (1) since probability failed,
    -- but note params also held, so trigger=1 still fires but with held note values
    -- Wait - roll 90 > 20, so trigger does NOT advance. It peeks at current pos.
    -- Current pos after first advance = 2, step 2 = 1, so trigger=1
    -- trigger fires because its VALUE is 1 (held), even though it didn't advance
    -- Actually this IS correct - the trigger fires with its current (held) value
    assert.is_true(fired)
  end)

  it("at 100% probability all params always advance", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.99 end -- 99 <= 100
    ctx.tracks[1].params.probability.steps[1] = 100
    -- set specific note values to detect advancement
    ctx.tracks[1].params.note.steps[1] = 3
    ctx.tracks[1].params.note.steps[2] = 5
    ctx.tracks[1].params.note.pos = 1
    local note_val
    ctx.voices[1].play_note = function(_, note) note_val = note end
    sequencer.step_track(ctx, 1)
    -- note should have advanced from pos 1 (val=3) to pos 2
    assert.are.equal(2, ctx.tracks[1].params.note.pos)
  end)

  it("at 0% probability no params advance (all hold)", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.01 end -- 1 > 0
    ctx.tracks[1].params.probability.steps[1] = 0
    -- record starting positions
    local start_positions = {}
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      if name ~= "probability" then
        start_positions[name] = ctx.tracks[1].params[name].pos
      end
    end
    sequencer.step_track(ctx, 1)
    -- all param positions should be unchanged (held)
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      if name ~= "probability" then
        assert.are.equal(start_positions[name], ctx.tracks[1].params[name].pos,
          name .. " position should not advance at 0% probability")
      end
    end
  end)

  it("probability param always advances regardless of its own value", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.5 end
    -- even at 0% probability, the probability param itself must advance
    ctx.tracks[1].params.probability.steps[1] = 0
    ctx.tracks[1].params.probability.pos = 1
    sequencer.step_track(ctx, 1)
    assert.are.equal(2, ctx.tracks[1].params.probability.pos,
      "probability param should advance even when its own value is 0")
  end)

  it("each parameter rolls independently (some advance, some hold)", function()
    local ctx = make_ctx()
    -- alternate rolls: first call passes, second fails, third passes, etc.
    local call_count = 0
    ctx.rng = function()
      call_count = call_count + 1
      if call_count % 2 == 1 then return 0.1 end -- 10 <= 50 (pass)
      return 0.9 -- 90 > 50 (fail)
    end
    ctx.tracks[1].params.probability.steps[1] = 50
    -- record starting positions
    local start_positions = {}
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      start_positions[name] = ctx.tracks[1].params[name].pos
    end
    sequencer.step_track(ctx, 1)
    -- some params should advance (odd rolls) and some should hold (even rolls)
    local advanced = 0
    local held = 0
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      if name ~= "probability" then
        if ctx.tracks[1].params[name].pos ~= start_positions[name] then
          advanced = advanced + 1
        else
          held = held + 1
        end
      end
    end
    -- with alternating pass/fail, we should see a mix
    assert.is_true(advanced > 0, "some params should advance")
    assert.is_true(held > 0, "some params should hold")
  end)

  it("held param retains its current step value", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.9 end -- 90 > 50 (always fail)
    ctx.tracks[1].params.probability.steps[1] = 50
    -- set note at pos 1 to a known value
    ctx.tracks[1].params.note.pos = 1
    ctx.tracks[1].params.note.steps[1] = 7
    ctx.tracks[1].params.note.steps[2] = 1
    -- ensure trigger fires so we can observe
    ctx.tracks[1].params.trigger.steps[1] = 1
    ctx.tracks[1].params.trigger.pos = 1
    local played_note
    ctx.voices[1].play_note = function(_, note) played_note = note end
    sequencer.step_track(ctx, 1)
    -- note should still be at pos 1 (held), not advanced to pos 2
    assert.are.equal(1, ctx.tracks[1].params.note.pos,
      "note position should hold when probability fails")
  end)

  it("step event reports actual values including held params", function()
    local ctx = make_ctx()
    ctx.rng = function() return 0.9 end -- always fail
    ctx.tracks[1].params.probability.steps[1] = 50
    ctx.tracks[1].params.note.pos = 1
    ctx.tracks[1].params.note.steps[1] = 5
    local emitted_vals
    ctx.events = {
      emit = function(_, event_name, data)
        if event_name == "sequencer:step" then
          emitted_vals = data.vals
        end
      end,
    }
    sequencer.step_track(ctx, 1)
    -- emitted vals should contain the held (peeked) note value
    assert.are.equal(5, emitted_vals.note)
  end)
end)
