-- specs/synthetic_grid_behavior_spec.lua
-- Demonstrates how the synthetic grid simulates, tests, and visualizes
-- sequencer behavior without any hardware.
--
-- This spec is a walkthrough: each describe block showcases a different
-- capability of the synthetic grid as a behavioral testing tool.

package.path = package.path .. ";./?.lua"

-- Mock clock (needed by sequencer, which grid_ui requires for play/stop)
rawset(_G, "clock", {
  get_beats = function() return 0 end,
  run = function(fn) return 1 end,
  cancel = function(id) end,
  sync = function() end,
})

local track_mod = require("lib/track")
local grid_provider = require("lib/grid_provider")
local grid_ui = require("lib/grid_ui")
local pattern = require("lib/pattern")
local events_mod = require("lib/events")
local synth_grid = require("specs/lib/synthetic_grid")

-- ============================================================================
-- 1. SIMULATE: Replay user interactions without hardware
-- ============================================================================

describe("simulate: replay user interactions", function()

  it("programs a 4-on-the-floor kick pattern via grid taps", function()
    -- Scenario: user taps steps 1, 5, 9, 13 on track 1 (the classic kick)
    -- Track 1 defaults already have triggers at odd steps; clear them first
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Clear all default triggers on track 1
    local trig = ctx.tracks[1].params.trigger
    for i = 1, 16 do trig.steps[i] = 0 end

    -- Now tap the four-on-the-floor pattern
    synth_grid.tap_sequence(g, {
      {1, 1}, {5, 1}, {9, 1}, {13, 1}
    })

    -- Verify the pattern was programmed correctly
    assert.are.equal(1, trig.steps[1])
    assert.are.equal(0, trig.steps[2])
    assert.are.equal(0, trig.steps[3])
    assert.are.equal(0, trig.steps[4])
    assert.are.equal(1, trig.steps[5])
    assert.are.equal(1, trig.steps[9])
    assert.are.equal(1, trig.steps[13])
  end)

  it("programs a melody across multiple pages", function()
    -- Scenario: user sets triggers on track 2, then switches to note page
    -- and enters a melodic contour
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Clear track 2 triggers
    local trig = ctx.tracks[2].params.trigger
    for i = 1, 16 do trig.steps[i] = 0 end

    -- Tap triggers on track 2 row (row 2 in trigger page)
    synth_grid.tap_sequence(g, {
      {1, 2}, {3, 2}, {5, 2}, {7, 2}
    })
    assert.are.equal(1, trig.steps[1])
    assert.are.equal(1, trig.steps[3])

    -- Switch to note page (nav x=7, y=8)
    synth_grid.tap(g, 7, 8)
    assert.are.equal("note", ctx.active_page)

    -- Switch active track to 2 (nav x=2, y=8)
    synth_grid.tap(g, 2, 8)
    assert.are.equal(2, ctx.active_track)

    -- Set ascending melody: C D E G (scale degrees 1,2,3,5)
    -- Value pages: row 1=7, row 2=6, row 3=5, row 4=4, row 5=3, row 6=2, row 7=1
    synth_grid.tap(g, 1, 7)  -- step 1, row 7 = degree 1
    synth_grid.tap(g, 3, 6)  -- step 3, row 6 = degree 2
    synth_grid.tap(g, 5, 5)  -- step 5, row 5 = degree 3
    synth_grid.tap(g, 7, 3)  -- step 7, row 3 = degree 5

    local note = ctx.tracks[2].params.note
    assert.are.equal(1, note.steps[1])
    assert.are.equal(2, note.steps[3])
    assert.are.equal(3, note.steps[5])
    assert.are.equal(5, note.steps[7])
  end)

  it("edits loop boundaries with hold gesture", function()
    -- Scenario: user holds loop button, then presses start and end steps
    local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })

    -- Default loop is 1-6
    local trig = ctx.tracks[1].params.trigger
    assert.are.equal(1, trig.loop_start)
    assert.are.equal(6, trig.loop_end)

    -- Hold loop button (x=11, y=8)
    synth_grid.press(g, 11, 8)
    assert.is_true(ctx.loop_held)

    -- Tap start and end of new loop
    synth_grid.tap(g, 5, 1)   -- first press = start
    synth_grid.tap(g, 12, 1)  -- second press = end

    -- Release loop button
    synth_grid.release(g, 11, 8)

    assert.are.equal(5, trig.loop_start)
    assert.are.equal(12, trig.loop_end)
  end)

end)

-- ============================================================================
-- 2. VISUALIZE: Use dump() to see grid state as text
-- ============================================================================

describe("visualize: inspect grid state via dump", function()

  it("shows the default trigger page layout", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })
    synth_grid.render(ctx)
    local dump = synth_grid.dump(g)

    -- The dump is a human-readable snapshot of the grid:
    -- . = off, 1-9/A-F = brightness levels
    -- Useful for visual debugging and documentation
    assert.is_string(dump)
    -- Track rows should show trigger pattern (8 = active trigger)
    assert.truthy(dump:match("8"), "should show brightness 8 for active triggers")
    -- Nav row should show selected items (C = brightness 12)
    assert.truthy(dump:match("C"), "should show brightness 12 for selected nav items")
  end)

  it("captures before/after state for a user action", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Capture "before" snapshot
    synth_grid.render(ctx)
    local before = synth_grid.dump(g)

    -- User toggles step 2 on track 1
    synth_grid.tap(g, 2, 1)
    synth_grid.render(ctx)
    local after = synth_grid.dump(g)

    -- The snapshots differ — we can see exactly what changed
    assert.are_not.equal(before, after)
  end)

  it("shows loop region vs active triggers at different brightnesses", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Set a tight loop: steps 1-4
    local trig = ctx.tracks[1].params.trigger
    track_mod.set_loop(trig, 1, 4)
    -- Clear all triggers, set just step 1
    for i = 1, 16 do trig.steps[i] = 0 end
    trig.steps[1] = 1

    synth_grid.render(ctx)

    -- Step 1: trigger active (brightness 8)
    synth_grid.assert_led(g, 1, 1, 8)
    -- Step 2: in loop, no trigger (brightness 2 = dim loop indicator)
    synth_grid.assert_led(g, 2, 1, 2)
    -- Step 5: outside loop (brightness 0)
    synth_grid.assert_led(g, 5, 1, 0)
  end)

  it("shows playhead at maximum brightness", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger", playing = true })

    -- Playhead at step 1 (default pos)
    synth_grid.render(ctx)
    synth_grid.assert_led(g, 1, 1, 15, "playhead should be brightness 15")

    -- Non-playhead trigger steps remain at 8
    synth_grid.assert_led(g, 3, 1, 8, "non-playhead trigger should be 8")
  end)

  it("value page shows vertical bar for note values", function()
    local ctx, g = synth_grid.setup({ active_page = "note", active_track = 1 })

    -- Set step 1 to note value 5
    ctx.tracks[1].params.note.steps[1] = 5

    synth_grid.render(ctx)

    -- Row that corresponds to value 5: row = 8 - 5 = 3
    -- Should be the value marker (brightness 10 for in-loop)
    synth_grid.assert_led(g, 1, 3, 10, "value marker at row 3 for note=5")
    -- Rows below value (rows 4-7) show fill (brightness 3 for in-loop)
    synth_grid.assert_led(g, 1, 4, 3, "fill below value marker")
    -- Row above value (row 2) should be off
    synth_grid.assert_led(g, 1, 2, 0, "above value should be off")
  end)

end)

-- ============================================================================
-- 3. TEST: Verify behavioral contracts via assertions
-- ============================================================================

describe("test: verify behavioral contracts", function()

  it("nav row reflects track/page/mode state exactly", function()
    local ctx, g = synth_grid.setup({
      active_page = "trigger",
      active_track = 3,
    })
    synth_grid.render(ctx)

    -- Track buttons: only track 3 is selected (bright=12), others dim (3)
    synth_grid.assert_led(g, 1, 8, 3)
    synth_grid.assert_led(g, 2, 8, 3)
    synth_grid.assert_led(g, 3, 8, 12, "track 3 should be selected")
    synth_grid.assert_led(g, 4, 8, 3)

    -- Page buttons: trigger=12, rest=3
    synth_grid.assert_led(g, 6, 8, 12, "trigger page selected")
    synth_grid.assert_led(g, 7, 8, 3)
    synth_grid.assert_led(g, 8, 8, 3)
    synth_grid.assert_led(g, 9, 8, 3)  -- cycle group (duration/velocity/probability)
  end)

  it("mute toggle changes nav indicator", function()
    local ctx, g = synth_grid.setup({ active_track = 1 })

    -- Initially unmuted
    synth_grid.render(ctx)
    synth_grid.assert_led(g, 13, 8, 3, "mute button dim when unmuted")

    -- Tap mute (x=13, y=8)
    synth_grid.tap(g, 13, 8)
    assert.is_true(ctx.tracks[1].muted)

    synth_grid.render(ctx)
    synth_grid.assert_led(g, 13, 8, 12, "mute button bright when muted")

    -- Tap again to unmute
    synth_grid.tap(g, 13, 8)
    assert.is_false(ctx.tracks[1].muted)
  end)

  it("extended page toggle: double-tap trigger goes to ratchet", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Tap trigger page button again (x=6, y=8) — should toggle to ratchet
    synth_grid.tap(g, 6, 8)
    assert.are.equal("ratchet", ctx.active_page)

    -- Tap again — should toggle back to trigger
    synth_grid.tap(g, 6, 8)
    assert.are.equal("trigger", ctx.active_page)
  end)

  it("trigger toggle is idempotent: on-off-on cycle", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })
    local trig = ctx.tracks[1].params.trigger

    -- Clear step 4
    trig.steps[4] = 0
    assert.are.equal(0, trig.steps[4])

    -- Toggle on
    synth_grid.tap(g, 4, 1)
    assert.are.equal(1, trig.steps[4])

    -- Toggle off
    synth_grid.tap(g, 4, 1)
    assert.are.equal(0, trig.steps[4])

    -- Toggle on again
    synth_grid.tap(g, 4, 1)
    assert.are.equal(1, trig.steps[4])
  end)

  it("loop edit clamps playhead into new loop", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })
    local trig = ctx.tracks[1].params.trigger

    -- Move playhead to step 10 (outside new loop)
    trig.pos = 10

    -- Set loop to 3-6
    synth_grid.press(g, 11, 8)  -- hold loop
    synth_grid.tap(g, 3, 1)     -- start
    synth_grid.tap(g, 6, 1)     -- end
    synth_grid.release(g, 11, 8)

    -- Playhead should be clamped into new loop
    assert.is_true(trig.pos >= 3 and trig.pos <= 6,
      "playhead should be clamped into loop 3-6, got " .. trig.pos)
  end)

end)

-- ============================================================================
-- 4. EVENT TRACING: Use the event bus to verify behavioral side-effects
-- ============================================================================

describe("event tracing: capture side-effects of grid actions", function()

  local function setup_with_events(opts)
    local ctx, g = synth_grid.setup(opts)
    ctx.events = events_mod.new()
    -- Re-wire key callback to include event-aware grid_ui
    g.key = function(x, y, z)
      grid_ui.key(ctx, x, y, z)
      ctx.grid_dirty = true
    end
    return ctx, g
  end

  it("track selection emits track:select event", function()
    local ctx, g = setup_with_events()
    local captured = {}
    ctx.events:on("track:select", function(data)
      captured[#captured + 1] = data.track
    end)

    synth_grid.tap(g, 3, 8)  -- select track 3
    synth_grid.tap(g, 1, 8)  -- select track 1

    assert.are.equal(2, #captured)
    assert.are.equal(3, captured[1])
    assert.are.equal(1, captured[2])
  end)

  it("page selection emits page:select event", function()
    local ctx, g = setup_with_events()
    local captured = {}
    ctx.events:on("page:select", function(data)
      captured[#captured + 1] = { page = data.page, prev = data.prev }
    end)

    synth_grid.tap(g, 7, 8)  -- switch to note page

    assert.are.equal(1, #captured)
    assert.are.equal("note", captured[1].page)
    assert.are.equal("trigger", captured[1].prev)
  end)

  it("grid:key event fires for every key press", function()
    local ctx, g = setup_with_events()
    local key_events = {}
    ctx.events:on("grid:key", function(data)
      key_events[#key_events + 1] = { x = data.x, y = data.y, z = data.z }
    end)

    synth_grid.tap(g, 5, 3)  -- press + release = 2 events

    assert.are.equal(2, #key_events)
    assert.are.equal(5, key_events[1].x)
    assert.are.equal(3, key_events[1].y)
    assert.are.equal(1, key_events[1].z)  -- press
    assert.are.equal(0, key_events[2].z)  -- release
  end)

  it("mute toggle emits track:mute event", function()
    local ctx, g = setup_with_events({ active_track = 2 })
    local captured = {}
    ctx.events:on("track:mute", function(data)
      captured[#captured + 1] = { track = data.track, muted = data.muted }
    end)

    synth_grid.tap(g, 13, 8)  -- mute toggle

    assert.are.equal(1, #captured)
    assert.are.equal(2, captured[1].track)
    assert.is_true(captured[1].muted)
  end)

end)

-- ============================================================================
-- 5. PATTERN MANAGEMENT: Save/load via grid simulation
-- ============================================================================

describe("pattern management: save/load through grid", function()

  local function setup_with_patterns(opts)
    local ctx, g = synth_grid.setup(opts)
    ctx.patterns = pattern.new_slots()
    ctx.pattern_slot = nil
    ctx.events = events_mod.new()
    g.key = function(x, y, z)
      grid_ui.key(ctx, x, y, z)
      ctx.grid_dirty = true
    end
    return ctx, g
  end

  it("pattern mode shows slot grid when held", function()
    local ctx, g = setup_with_patterns()

    -- Hold pattern button (x=12, y=8)
    synth_grid.press(g, 12, 8)
    assert.is_true(ctx.pattern_held)

    -- Render in pattern mode
    synth_grid.render(ctx)

    -- All 16 slots should show as unpopulated (brightness 2)
    for row = 1, 2 do
      for col = 1, 8 do
        synth_grid.assert_led(g, col, row, 2,
          string.format("empty slot (%d,%d) should be dim", col, row))
      end
    end

    synth_grid.release(g, 12, 8)
  end)

  it("populated slots appear brighter than empty ones", function()
    local ctx, g = setup_with_patterns()

    -- Save current state to slot 1
    pattern.save(ctx, 1)

    -- Hold pattern and render
    synth_grid.press(g, 12, 8)
    synth_grid.render(ctx)

    -- Slot 1 (row 1, col 1) should be brighter than empty slots
    synth_grid.assert_led_gte(g, 1, 1, 10, "populated slot should be bright")
    -- Slot 2 (row 1, col 2) still empty
    synth_grid.assert_led(g, 2, 1, 2, "empty slot should be dim")

    synth_grid.release(g, 12, 8)
  end)

  it("loading a pattern restores track state", function()
    local ctx, g = setup_with_patterns()

    -- Modify track 1: set a distinctive trigger pattern
    local trig = ctx.tracks[1].params.trigger
    for i = 1, 16 do trig.steps[i] = 0 end
    trig.steps[1] = 1
    trig.steps[2] = 1
    trig.steps[3] = 1

    -- Save to slot 3
    pattern.save(ctx, 3)

    -- Now modify track 1 differently
    trig.steps[1] = 0
    trig.steps[2] = 0
    trig.steps[3] = 0
    trig.steps[4] = 1
    assert.are.equal(0, trig.steps[1])
    assert.are.equal(1, trig.steps[4])

    -- Hold pattern, tap slot 3 (row 1, col 3) to load
    synth_grid.press(g, 12, 8)
    synth_grid.tap(g, 3, 1)
    synth_grid.release(g, 12, 8)

    -- Track state should be restored to the saved version
    local restored = ctx.tracks[1].params.trigger
    assert.are.equal(1, restored.steps[1])
    assert.are.equal(1, restored.steps[2])
    assert.are.equal(1, restored.steps[3])
    assert.are.equal(0, restored.steps[4])
  end)

end)

-- ============================================================================
-- 6. ROW-LEVEL INSPECTION: Analyze grid regions programmatically
-- ============================================================================

describe("row-level inspection: analyze grid regions", function()

  it("count_lit reveals how many triggers are active per track", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })
    synth_grid.render(ctx)

    -- Count triggers visible at brightness >= 8 for each track row
    local counts = {}
    for t = 1, 4 do
      counts[t] = synth_grid.count_lit(g, t, 8)
    end

    -- Track 1 default: triggers at odd steps 1,3,5,7,9,11,13,15 -> 8 triggers
    -- But only steps 1-6 are in default loop, so within-loop triggers = 1,3,5 = 3 at brightness 8
    -- Steps outside loop with trigger get brightness 0 (not in loop = no brightness)
    -- Actually: trigger page shows ALL 16 steps, loop indicator is brightness 2,
    -- trigger value is 8 regardless of loop. Let me check...
    -- From grid_ui: brightness = 0, then if in loop -> 2, then if trigger=1 -> 8
    -- So triggers OUTSIDE loop still show brightness 8 if trigger=1
    assert.is_true(counts[1] > 0, "track 1 should have visible triggers")
  end)

  it("get_row captures exact LED state for a track", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Set a known pattern on track 3
    local trig = ctx.tracks[3].params.trigger
    for i = 1, 16 do trig.steps[i] = 0 end
    trig.steps[1] = 1
    trig.steps[5] = 1
    trig.steps[9] = 1
    trig.steps[13] = 1

    synth_grid.render(ctx)
    local row = synth_grid.get_row(g, 3)

    -- Steps with triggers in loop (1-6) -> brightness 8
    assert.are.equal(8, row[1])
    assert.are.equal(8, row[5])
    -- Steps with triggers outside loop -> dimmed brightness 4
    assert.are.equal(4, row[9])
    assert.are.equal(4, row[13])

    -- Steps 2-4 are in default loop (1-6) but no trigger -> brightness 2
    assert.are.equal(2, row[2])
    assert.are.equal(2, row[3])
    assert.are.equal(2, row[4])

    -- Steps outside loop with no trigger -> brightness 0
    assert.are.equal(0, row[7])
    assert.are.equal(0, row[8])
  end)

  it("get_state captures the full 8x16 matrix for snapshot comparison", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })
    synth_grid.render(ctx)

    local state = g:get_state()
    assert.are.equal(8, #state, "8 rows")
    assert.are.equal(16, #state[1], "16 columns")

    -- Nav row (row 8) should have some non-zero values
    local nav_sum = 0
    for x = 1, 16 do nav_sum = nav_sum + state[8][x] end
    assert.is_true(nav_sum > 0, "nav row should have lit LEDs")
  end)

end)

-- ============================================================================
-- 7. POLYMETRIC BEHAVIOR: Different loop lengths per parameter
-- ============================================================================

describe("polymetric behavior: independent parameter loops", function()

  it("trigger and note can have different loop lengths", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })

    -- Set trigger loop to 4 steps
    local trig = ctx.tracks[1].params.trigger
    track_mod.set_loop(trig, 1, 4)

    -- Set note loop to 6 steps (via direct manipulation — would normally
    -- use loop-hold on note page, but we can verify the model directly)
    local note = ctx.tracks[1].params.note
    track_mod.set_loop(note, 1, 6)

    -- Advance trigger 4 times -> should wrap
    for _ = 1, 4 do track_mod.advance(trig) end
    assert.are.equal(1, trig.pos, "trigger wraps after 4 steps")

    -- Advance note 6 times -> should wrap
    for _ = 1, 6 do track_mod.advance(note) end
    assert.are.equal(1, note.pos, "note wraps after 6 steps")

    -- After 12 steps both align again (LCM of 4 and 6)
    trig.pos = 1
    note.pos = 1
    for _ = 1, 12 do
      track_mod.advance(trig)
      track_mod.advance(note)
    end
    assert.are.equal(1, trig.pos, "trigger realigns at step 12")
    assert.are.equal(1, note.pos, "note realigns at step 12")
  end)

  it("grid shows trigger loop region on trigger page", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })

    -- Set a 4-step loop
    local trig = ctx.tracks[1].params.trigger
    track_mod.set_loop(trig, 1, 4)
    for i = 1, 16 do trig.steps[i] = 0 end
    trig.steps[1] = 1

    synth_grid.render(ctx)

    -- Steps 1-4 should be visible (in loop)
    synth_grid.assert_led(g, 1, 1, 8, "step 1 trigger in loop")
    synth_grid.assert_led(g, 2, 1, 2, "step 2 in loop, no trigger")
    synth_grid.assert_led(g, 4, 1, 2, "step 4 in loop, no trigger")

    -- Steps 5+ should be invisible (outside loop)
    synth_grid.assert_led(g, 5, 1, 0, "step 5 outside loop")
    synth_grid.assert_led(g, 8, 1, 0, "step 8 outside loop")
  end)

  it("switching to note page shows note loop independently", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })

    -- Set trigger loop = 4, note loop = 8
    local trig = ctx.tracks[1].params.trigger
    local note = ctx.tracks[1].params.note
    track_mod.set_loop(trig, 1, 4)
    track_mod.set_loop(note, 1, 8)
    -- Clear trigger at step 5 so it's fully invisible outside loop
    trig.steps[5] = 0

    -- On trigger page, we see trigger's loop (4 steps)
    synth_grid.render(ctx)
    synth_grid.assert_led(g, 5, 1, 0, "trigger page: step 5 outside trigger loop")

    -- Switch to note page
    synth_grid.tap(g, 7, 8)
    assert.are.equal("note", ctx.active_page)
    synth_grid.render(ctx)

    -- On note page, step 5 IS in note loop -> should show value marker
    -- Note page shows value bar, step 5 in loop -> value marker at brightness 10
    local note_val = note.steps[5]
    local val_row = 8 - note_val
    synth_grid.assert_led_gte(g, 5, val_row, 4,
      "note page: step 5 should show value (in note loop)")
  end)

end)

-- ============================================================================
-- 8. MULTI-TRACK INTERACTION: Cross-track behavior on trigger page
-- ============================================================================

describe("multi-track interaction on trigger page", function()

  it("all 4 tracks display simultaneously", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })
    synth_grid.render(ctx)

    -- Each track row should have at least one lit LED
    for t = 1, 4 do
      local lit = synth_grid.count_lit(g, t, 1)
      assert.is_true(lit > 0, "track " .. t .. " should have visible LEDs")
    end
  end)

  it("tapping different rows edits different tracks", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger" })

    -- Clear step 16 on all tracks
    for t = 1, 4 do
      ctx.tracks[t].params.trigger.steps[16] = 0
    end

    -- Tap step 16 on track 2 (row 2) and track 4 (row 4)
    synth_grid.tap(g, 16, 2)
    synth_grid.tap(g, 16, 4)

    -- Only tracks 2 and 4 should have step 16 toggled
    assert.are.equal(0, ctx.tracks[1].params.trigger.steps[16])
    assert.are.equal(1, ctx.tracks[2].params.trigger.steps[16])
    assert.are.equal(0, ctx.tracks[3].params.trigger.steps[16])
    assert.are.equal(1, ctx.tracks[4].params.trigger.steps[16])
  end)

  it("track selection only affects nav highlight, not trigger editing", function()
    local ctx, g = synth_grid.setup({ active_page = "trigger", active_track = 1 })

    -- Select track 3 via nav
    synth_grid.tap(g, 3, 8)
    assert.are.equal(3, ctx.active_track)

    -- Tap step 10 on row 1 — should edit track 1, NOT track 3
    -- (trigger page always maps row to track number)
    ctx.tracks[1].params.trigger.steps[10] = 0
    ctx.tracks[3].params.trigger.steps[10] = 0

    synth_grid.tap(g, 10, 1)
    assert.are.equal(1, ctx.tracks[1].params.trigger.steps[10],
      "row 1 always edits track 1")
    assert.are.equal(0, ctx.tracks[3].params.trigger.steps[10],
      "track 3 should be unchanged")
  end)

end)
