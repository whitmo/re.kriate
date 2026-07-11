# Research: Test Voice / Visual Verification Patterns

## 1. How Music Software Projects Test Sequencer Output

### The norns community problem

The norns ecosystem has essentially no established unit testing culture. Scripts rely on manual "load and listen" verification. The norns core provides `CroneTester` for SuperCollider engine testing, but there is no standard pattern for testing Lua sequencer logic against expected note output. The existing `specs/track_spec.lua` in this project is ahead of the curve -- most norns scripts have zero tests.

The root cause: norns scripts are tightly coupled to the runtime (clock, params, grid, engine/nb). Without a way to mock these, testing requires the full norns environment.

### MIDI capture approaches

MIDI testing in the broader music software world follows a "capture and compare" pattern:

- **Linux**: `aseqdump` captures MIDI events from ALSA sequencer ports as human-readable text. Tests can pipe this output and compare against expected sequences.
- **macOS**: MIDI Monitor / MIDIView capture bi-directional MIDI traffic.
- **Programmatic**: The Java Sound API's `Sequencer` class has `Transmitter` objects that send `MidiMessage` to `Receiver` objects -- a natural seam for test interception.

The core insight: **controllability and observability**. You need the ability to apply a stimulus (trigger the sequencer) and measure the response (capture note events). Our voice abstraction (`ctx.voices[track_num]:play_note(note, vel, dur)`) already provides the observability seam -- we just need a voice implementation that records instead of playing.

### Strudel/Tidal Cycles visual verification

Strudel (the JavaScript TidalCycles port) has the most developed visual verification system in the live-coding world:

- **Pianoroll**: `all(pianoroll)` renders a scrolling visualization with pitch on the Y axis and time on the X axis. Configurable cycles displayed, playhead position, note coloring, MIDI range boundaries, and labels.
- **Punchcard**: Similar to pianoroll but shows the *final* transformed pattern (post-effects), using the same data as mini-notation highlighting. Less resource intensive.
- **Scope/Spectrum**: Real-time waveform and frequency visualizers.
- **Inline visualizations**: `._pianoroll()`, `._punchcard()` can be embedded in code.

Strudel's pianoroll works because patterns are pure data structures that can be rendered without audio. This is exactly what we want: sequencer output as data, renderable visually or assertable programmatically.

### Minetest/Luanti mock recording pattern

The Luanti (Minetest) modding community documents a clean Lua mock recording pattern that maps directly to our needs:

```lua
-- Setup: create a table to capture calls
local play_note_calls = {}
function mock_voice:play_note(note, vel, dur)
    table.insert(play_note_calls, { note = note, vel = vel, dur = dur })
end

-- Reset between tests
play_note_calls = {}

-- Verify: count
assert.equals(2, #play_note_calls)

-- Verify: specific args
assert.equals(60, play_note_calls[1].note)

-- Verify: full structure
assert.same(expected_sequence, play_note_calls)
```

This is the foundation of the recorder voice.


## 2. Visual Verification on the Seamstress Screen

### Available drawing primitives

Based on meadowphysics-seamstress and seamstress examples, the screen API provides:

| Function | Description |
|---|---|
| `screen.clear()` | Clear display |
| `screen.color(r, g, b [, a])` | Set RGBA draw color |
| `screen.level(v)` | Set brightness (norns compat, 0-15) |
| `screen.move(x, y)` | Set cursor position |
| `screen.rect_fill(w, h)` | Filled rectangle at cursor |
| `screen.pixel(x, y)` | Single pixel |
| `screen.line(x, y)` | Line to coordinates |
| `screen.text(str)` | Text at cursor |
| `screen.text_right(str)` | Right-aligned text |
| `screen.refresh()` / `screen.update()` | Flush to display |
| `screen.set_size(w, h)` | Resize window |

The full-color SDL screen (default ~256x128, resizable) is vastly more capable than norns' 128x64 monochrome OLED.

### What a test voice could render

**Piano roll view**: Time on X axis, pitch on Y. Each `play_note` call renders as a colored rectangle whose:
- X position = time of event (beat or wall clock)
- Y position = MIDI note number (scaled to screen height)
- Width = duration in beats
- Color = track (4 tracks, 4 colors)
- Brightness/opacity = velocity

This gives immediate visual feedback: "is the sequencer producing the right pattern?" You can see polymetric relationships, loop lengths, and timing at a glance.

**Event log view**: Scrolling text list of recent events:
```
T1 step 3: note=64 vel=0.75 dur=0.25
T1 step 5: note=67 vel=0.60 dur=0.25
T3 step 1: note=72 vel=0.45 dur=0.50
```

**Step state view**: For each track, show the current state of all parameter lanes as colored bars -- playhead positions, loop boundaries, step values. Similar to what the grid shows but with labels and colors.

### Implementation sketch

The test voice would implement the same `play_note(note, vel, dur)` interface but push events into a ring buffer that the screen reads during `redraw`:

```lua
-- lib/voices/test_voice.lua
local M = {}

function M.new(track_num, event_buffer)
    return {
        play_note = function(self, note, vel, dur)
            table.insert(event_buffer, {
                track = track_num,
                note = note,
                vel = vel,
                dur = dur,
                time = clock.get_beats(),
            })
        end
    }
end

return M
```

The screen module reads `event_buffer` and renders the piano roll. The same buffer is available to tests for assertions.


## 3. Recorder Voice Design

### Interface

The recorder voice implements the same contract as MIDI and OSC voices:

```lua
voice:play_note(note, velocity, duration)
```

It captures every call into an ordered list with timestamps. The recorder is both a **test double** (for automated tests) and a **diagnostic tool** (for visual verification).

### Data structure

```lua
{
    events = {
        { track = 1, note = 64, vel = 0.75, dur = 0.25, beat = 0.0 },
        { track = 1, note = 67, vel = 0.60, dur = 0.25, beat = 0.25 },
        { track = 3, note = 72, vel = 0.45, dur = 0.50, beat = 0.25 },
        ...
    },
    start_beat = 0.0,    -- when recording started
    event_count = 3,     -- running count
}
```

### Operations tests need

- `recorder:get_events()` -- return the full event list
- `recorder:get_events_for_track(n)` -- filter by track
- `recorder:clear()` -- reset for next test
- `recorder:get_notes()` -- just the note numbers in order (for quick assertions)
- `recorder:get_last(n)` -- last N events (for incremental checks)

### Assertion helpers

Build thin wrappers for common assertions:

```lua
-- Did track 1 play exactly these notes over one loop?
assert.same({64, 67, 69, 72}, recorder:get_notes_for_track(1))

-- Did all 4 tracks fire on beat 0?
local beat_0 = recorder:get_events_at_beat(0.0, 0.01)  -- tolerance
assert.equals(4, #beat_0)

-- Did polymetric loops produce expected pattern after N steps?
local t1_notes = recorder:get_notes_for_track(1)
local t2_notes = recorder:get_notes_for_track(2)
assert.equals(8, #t1_notes)  -- 8-step loop
assert.equals(4, #t2_notes)  -- 4-step loop cycled twice = 4 notes in same time
```

### Dual use: test and visual

The same recorder powers both automated tests and the visual display. In test mode, you advance the clock deterministically and inspect the buffer. In visual mode, the seamstress screen renders it as a piano roll in real time.


## 4. Seamstress Screen as Test Output Display

### Real-time manual verification

Yes, seamstress's screen is well-suited as a test output display. The pattern:

1. Load re.kriate in seamstress with test voices instead of MIDI voices
2. Connect a grid (or use keyboard fallback) and start the sequencer
3. The screen renders a piano roll of what the sequencer is producing
4. Visually confirm: correct notes, correct timing, polymetric patterns look right, loop boundaries respected

This is valuable for:
- **Development**: See what the sequencer does as you build it
- **Debugging**: "Why does track 3 sound wrong?" becomes "Why does track 3's visual pattern look wrong?"
- **Demo**: Show sequencer behavior without audio setup

### Dirty flag pattern (from meadowphysics-seamstress)

Seamstress uses a 60fps metro for screen refresh with dirty flagging:

```lua
-- only redraw when something changed
if screen_dirty then
    screen.clear()
    -- render piano roll from event_buffer
    screen.refresh()
    screen_dirty = false
end
```

New `play_note` events set `screen_dirty = true`. This is efficient and already the established seamstress pattern.

### Multiple display modes

The screen could offer switchable views (cycle with a key):

1. **Status** -- minimal info (current: track, page, play state)
2. **Piano roll** -- scrolling note visualization
3. **Event log** -- text list of recent events
4. **Step state** -- all parameter lanes for current track

For testing purposes, piano roll and event log are most useful. For performance, status is sufficient.


## 5. Testing Async/Timed Behavior with Busted

### Seamstress `--test` capabilities

Seamstress v2 (2.0.0-alpha, January 2025) added:

- `seamstress --test` -- runs Lua test files using busted conventions
- `--test-dir <path>` -- load additional test directories
- `--log-level <level>` -- control log verbosity during tests

The seamstress test suite itself (`lua/test/`) includes `timer_spec.lua` and `async_spec.lua` that demonstrate the test runner works. The timer test uses `coroutine.yield()` polling to wait for async completion within busted's test harness.

### The clock mocking problem

The sequencer uses `clock.run()` and `clock.sync()` for timing. In tests, we need deterministic control over time. Two approaches:

**Approach A: Mock clock (recommended for unit tests)**

Replace `clock` with a mock that gives manual control over time advancement:

```lua
-- test_helpers/mock_clock.lua
local M = {}
local coroutines = {}
local current_beat = 0

function M.run(fn)
    local co = coroutine.create(fn)
    table.insert(coroutines, { co = co, wake_at = 0 })
    return #coroutines
end

function M.sync(beats)
    -- record that this coroutine wants to wake after `beats`
    -- yield back to the test runner
    coroutine.yield(beats)
end

function M.get_beats()
    return current_beat
end

function M.advance(beats)
    -- advance time and resume any coroutines whose wake time has passed
    current_beat = current_beat + beats
    for _, entry in ipairs(coroutines) do
        if entry.wake_at <= current_beat and coroutine.status(entry.co) == "suspended" then
            local ok, next_sync = coroutine.resume(entry.co)
            if ok and next_sync then
                entry.wake_at = current_beat + next_sync
            end
        end
    end
end

function M.cancel(id)
    coroutines[id] = nil
end

function M.reset()
    coroutines = {}
    current_beat = 0
end

return M
```

Usage in tests:

```lua
local mock_clock = require("test_helpers/mock_clock")

-- inject mock clock before requiring sequencer
_G.clock = mock_clock

describe("sequencer", function()
    before_each(function()
        mock_clock.reset()
    end)

    it("advances track steps on clock tick", function()
        local ctx = create_test_ctx()  -- with recorder voices
        sequencer.start(ctx)

        -- advance one sixteenth note
        mock_clock.advance(0.25)

        local events = ctx.recorder:get_events()
        assert.equals(1, #events)  -- one note fired
    end)
end)
```

**Approach B: Real clock with short waits (for integration tests)**

Use seamstress's actual clock but with a fast tempo and `coroutine.yield()` polling:

```lua
it("plays a full loop", function()
    params:set("clock_tempo", 300)  -- fast tempo
    sequencer.start(ctx)

    -- wait for events to accumulate
    local timeout = 100
    while #ctx.recorder:get_events() < 16 and timeout > 0 do
        coroutine.yield()
        timeout = timeout - 1
    end

    assert.is_true(#ctx.recorder:get_events() >= 16)
    sequencer.stop(ctx)
end)
```

This is less deterministic but tests the real clock integration.

### Recommended layering

| Layer | Clock | Voice | Runs via | Tests |
|---|---|---|---|---|
| Unit | Mock clock | Recorder | `busted` standalone | Step logic, loop wrapping, polymetric math |
| Component | Mock clock | Recorder | `busted` standalone | Sequencer start/stop, track stepping, note generation |
| Integration | Real clock | Recorder | `seamstress --test` | Full script init, clock-driven playback, grid interaction |
| Visual | Real clock | Recorder + screen render | `seamstress` (manual) | Piano roll verification, live debugging |
| End-to-end | Real clock | MIDI voice | `seamstress` (manual) | Actual MIDI output to hardware/DAW |


## 6. Practical Recommendations

### Recorder/mock voice interface

Build `lib/voices/recorder.lua`:

```lua
local M = {}

function M.new(track_num, shared_buffer)
    local voice = {
        track_num = track_num,
        events = shared_buffer or {},
    }

    function voice:play_note(note, vel, dur)
        table.insert(self.events, {
            track = self.track_num,
            note = note,
            vel = vel,
            dur = dur,
            beat = clock.get_beats(),
        })
    end

    function voice:get_events()
        local result = {}
        for _, e in ipairs(self.events) do
            if e.track == self.track_num then
                table.insert(result, e)
            end
        end
        return result
    end

    function voice:get_notes()
        local notes = {}
        for _, e in ipairs(self:get_events()) do
            table.insert(notes, e.note)
        end
        return notes
    end

    function voice:clear()
        -- remove events for this track
        local i = 1
        while i <= #self.events do
            if self.events[i].track == self.track_num then
                table.remove(self.events, i)
            else
                i = i + 1
            end
        end
    end

    return voice
end

function M.clear_all(buffer)
    for i = #buffer, 1, -1 do
        table.remove(buffer, i)
    end
end

return M
```

This module works in three contexts:
1. **Busted unit tests** -- inject into ctx, advance mock clock, assert on events
2. **Seamstress integration tests** -- inject into ctx via `seamstress --test`, real clock
3. **Seamstress visual mode** -- inject into ctx in the entrypoint, render events on screen

### Visual verification approach

Build `lib/seamstress/piano_roll.lua` that reads the shared event buffer and draws to screen:

- X axis: time in beats, scrolling left as playback advances
- Y axis: MIDI note range (auto-scale to notes present, or fixed range like 36-96)
- Colored rectangles per track (e.g. track 1 = red, track 2 = blue, track 3 = green, track 4 = yellow)
- Opacity/brightness mapped to velocity
- Vertical playhead line at current beat
- Width of each rectangle proportional to duration

This uses only the confirmed seamstress APIs: `screen.color()`, `screen.move()`, `screen.rect_fill()`, `screen.text()`, `screen.refresh()`.

### Integration test patterns for clock-driven code

**Pattern 1: Mock clock for deterministic unit tests**

```lua
-- specs/sequencer_spec.lua
describe("sequencer.step_track", function()
    it("fires note on trigger step", function()
        local ctx = test_helpers.make_ctx()  -- includes recorder voices, mock clock
        ctx.tracks[1].params.trigger.steps[1] = 1
        ctx.tracks[1].params.note.steps[1] = 3

        sequencer.step_track(ctx, 1)

        local events = ctx.voices[1]:get_events()
        assert.equals(1, #events)
        assert.equals(3, events[1].note)  -- scale degree -> midi note via scale_mod
    end)

    it("does not fire note on rest step", function()
        local ctx = test_helpers.make_ctx()
        ctx.tracks[1].params.trigger.steps[1] = 0

        sequencer.step_track(ctx, 1)

        assert.equals(0, #ctx.voices[1]:get_events())
    end)
end)
```

Note: `step_track` can be tested without a clock at all -- it is a pure function of ctx state. The clock only drives *when* it gets called.

**Pattern 2: Mock clock for multi-step sequencing**

```lua
describe("sequencer multi-step", function()
    it("produces polymetric pattern", function()
        local ctx = test_helpers.make_ctx()
        -- track 1: 4-step trigger loop
        track_mod.set_loop(ctx.tracks[1].params.trigger, 1, 4)
        -- track 2: 3-step trigger loop
        track_mod.set_loop(ctx.tracks[2].params.trigger, 1, 3)

        -- step both tracks 12 times (LCM of 4 and 3)
        for _ = 1, 12 do
            sequencer.step_track(ctx, 1)
            sequencer.step_track(ctx, 2)
        end

        -- verify loop counts
        local t1 = ctx.voices[1]:get_events()
        local t2 = ctx.voices[2]:get_events()
        -- assert expected note counts and patterns
    end)
end)
```

**Pattern 3: Seamstress integration test with real clock**

```lua
-- specs/integration_spec.lua (run via seamstress --test)
describe("full sequencer integration", function()
    it("initializes without error", function()
        local app = require("lib/app")
        local ctx = app.init()  -- seamstress entrypoint init
        assert.is_not_nil(ctx)
        assert.is_not_nil(ctx.tracks)
        assert.is_not_nil(ctx.voices)
        app.cleanup(ctx)
    end)

    it("plays notes when started", function()
        local ctx = test_helpers.make_seamstress_ctx()
        sequencer.start(ctx)

        -- yield to let clock coroutines run
        local attempts = 0
        while #ctx.event_buffer < 1 and attempts < 200 do
            coroutine.yield()
            attempts = attempts + 1
        end

        assert.is_true(#ctx.event_buffer > 0, "expected at least one note event")
        sequencer.stop(ctx)
    end)
end)
```


## 7. Open Questions

- **`seamstress --test` maturity**: The feature shipped in January 2025 as alpha. The built-in tests (`timer_spec`, `async_spec`, `monome_spec`, `osc_spec`) use `coroutine.yield()` for async waiting. It likely does not offer anything beyond standard busted plus seamstress runtime access. Worth testing with a simple spec to confirm behavior.

- **Clock mock fidelity**: The mock clock sketch above handles `clock.run`, `clock.sync`, `clock.cancel`, and `clock.get_beats`. It does not handle `clock.sleep` (wall-clock time) or `clock.tempo` changes mid-sequence. These can be added incrementally.

- **Event buffer size**: For long-running visual verification, the event buffer needs a cap (ring buffer) to avoid unbounded memory growth. For tests, the buffer is small and short-lived.

- **Busted standalone vs seamstress --test**: Pure unit tests (track, scale, recorder) can run via standalone `busted` with no seamstress dependency. Integration tests that need `clock`, `screen`, `grid`, or `params` must run via `seamstress --test`. Keep the test layers separate.


## Sources

- [Busted testing framework documentation](https://lunarmodules.github.io/busted/)
- [Busted async_spec.lua](https://github.com/Olivine-Labs/busted/blob/master/spec/async_spec.lua)
- [Seamstress v2 releases (--test flag)](https://github.com/robbielyman/seamstress/releases)
- [Seamstress grid studies](https://monome.org/docs/grid/studies/seamstress/)
- [Seamstress and norns comparison](https://monome.org/docs/grid/studies/seamstress/seamstress-and-norns/)
- [Seamstress v2 test directory](https://github.com/robbielyman/seamstress/tree/main/lua/test)
- [Seamstress v1 examples (plasma.lua screen API)](https://github.com/robbielyman/seamstress-v1/blob/main/examples/plasma.lua)
- [Meadowphysics-seamstress (screen drawing patterns)](https://github.com/monome/meadowphysics-seamstress)
- [Strudel visual feedback (pianoroll, punchcard)](https://strudel.cc/learn/visual-feedback/)
- [Luanti/Minetest mock recording pattern](https://rubenwardy.com/minetest_modding_book/en/quality/unit_testing.html)
- [Norns clock API](https://monome.org/docs/norns/clocks/)
- [Norns screen API](https://monome.org/docs/norns/api/modules/screen.html)
- [Kotlin coroutines TestDispatcher (mock clock reference)](https://kotlin.github.io/kotlinx.coroutines/kotlinx-coroutines-test/kotlinx.coroutines.test/-delay-controller/advance-time-by.html)
- [clock-mock (JS mock clock reference)](https://isaacs.github.io/clock-mock/)
