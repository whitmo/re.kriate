# MIDI Note-Off Timing in Seamstress

## The Problem

A kria sequencer calls `play_note(note, vel, dur)` where `dur` is a gate duration in beats. Raw MIDI has no concept of "play for N beats" -- we must send `note_on`, wait the duration, then send `note_off`. We need a reliable, drift-free mechanism for scheduling note-offs in seamstress.

## Platform State

Seamstress exists in two versions:

- **seamstress v1** (`ryleelyman/seamstress`, now at `robbielyman/seamstress-v1`): stable, has `clock`, `metro`, `lattice`, `midi` modules. API-compatible with norns for these modules.
- **seamstress v2** (`robbielyman/seamstress`, v2.0.0-alpha): complete rewrite in Zig. Has `Timer`, `async/Promise`, `event`, `OSC`, and `monome` (grid/arc). **No `clock` module and no `midi` module yet.** The design doc describes both as planned modules.

Since v2 lacks clock and MIDI, we have two paths: (A) target v1, where the timing primitives mirror norns, or (B) target v2, where we'd build on `seamstress.Timer` and raw OSC-to-MIDI or wait for the clock/MIDI modules to land. The rest of this document covers both.

---

## Approach 1: `clock.run` + `clock.sleep` (v1, recommended for v1 target)

Spawn a one-shot coroutine per note that sleeps for the gate duration, then sends note-off.

```lua
function Voice:play_note(note, vel, dur)
  local ch = self.channel
  self.midi_dev:note_on(note, vel, ch)
  self:_track_note(note, ch)
  clock.run(function()
    clock.sleep(dur * clock.get_beat_sec())
    self.midi_dev:note_off(note, 0, ch)
    self:_untrack_note(note, ch)
  end)
end
```

**Pros:**
- Simplest pattern. One coroutine per note-off, no shared state to manage.
- Used by the official seamstress `hello_midi.lua` example and `awake-seamstress`.
- Coroutines are lightweight in Lua; hundreds of simultaneous note-offs are fine.

**Cons:**
- `clock.sleep` is wall-clock seconds, not beat-relative. If tempo changes mid-note, the gate duration won't track. For a kria sequencer where notes are typically short (sub-beat), this is acceptable.
- No built-in way to cancel a sleeping coroutine from outside (but `clock.cancel(id)` works if you store the coroutine ID).

**Variant: `clock.sync` instead of `clock.sleep`:**

```lua
clock.run(function()
  clock.sync(dur)  -- wait `dur` beats, tempo-relative
  self.midi_dev:note_off(note, 0, ch)
end)
```

`clock.sync` waits for a beat boundary, making the note-off tempo-tracking. If tempo changes during the note, the gate duration adjusts proportionally. This is better for musical timing but may feel unexpected for very short gates -- a 1/16 gate at 120bpm is ~125ms, and if the tempo jumps to 60bpm mid-gate, it doubles to ~250ms. For a kria sequencer this is arguably correct behavior.

**Recommendation:** Use `clock.sync(dur)` for beat-relative note-offs. It matches how the step sequencer thinks about time (in beats, not seconds).

---

## Approach 2: `metro` One-Shot Timer (v1)

Use a metro with `count = 1` to fire a single note-off callback after a delay.

```lua
function Voice:play_note(note, vel, dur)
  local ch = self.channel
  self.midi_dev:note_on(note, vel, ch)
  local m = metro.init()
  m.event = function()
    self.midi_dev:note_off(note, 0, ch)
  end
  m:start(dur * clock.get_beat_sec(), 1)  -- fire once after dur beats
end
```

**Pros:**
- Metro callbacks don't run as coroutines, so there's no coroutine overhead.
- One-shot behavior is clean with `count = 1`.

**Cons:**
- Seamstress v1 has a hard limit of 36 metros. A 4-track kria sequencer with polyphonic voices could easily exhaust this. If two tracks fire simultaneously and each has a note with a different gate, that's 2 metros consumed. With fast sequences and overlapping gates, you'd hit the ceiling.
- Metro time is in wall-clock seconds, not beats. No tempo tracking.
- Must manage metro lifecycle: free slots after use or pool and reuse them.
- Not used by any existing seamstress scripts for this purpose.

**Verdict:** Not recommended. The 36-metro limit is a hard constraint that makes this unreliable for polyphonic sequencing.

---

## Approach 3: Lattice Sprocket (v1)

Use the lattice library's sprocket system to schedule note-offs at beat-grid positions.

The lattice pulses at high PPQN (default 96) and triggers sprocket actions at their division. You could create a sprocket per pending note-off that fires at the right beat position.

```lua
-- Hypothetical: create a one-shot sprocket for note-off
local sprocket = my_lattice:new_sprocket{
  division = dur,  -- fire after `dur` beats
  action = function()
    midi_dev:note_off(note, 0, ch)
    sprocket.enabled = false  -- disable after firing
  end
}
```

**Pros:**
- Beat-relative timing with drift correction (lattice uses `clock.sync` internally).
- Swing-aware if you want gate durations to follow the lattice's swing setting.

**Cons:**
- Sprockets are designed for repeating patterns, not one-shot events. Disabling after one fire is a hack.
- A sprocket's division is fixed relative to the lattice's pulse rate. Arbitrary gate durations (e.g., 0.37 beats) don't map cleanly to sprocket divisions.
- Creating and destroying sprockets per-note is heavyweight compared to a coroutine.
- The lattice is better suited as the *step clock* (advancing the sequencer), not as a note-off scheduler.

**Verdict:** Not recommended for note-offs. Use lattice for the sequencer step clock, use `clock.run`/`clock.sync` for note-offs. This hybrid is exactly what the crow-timeline research concluded.

---

## Approach 4: `seamstress.Timer` (v2)

In seamstress v2, the `Timer` is the primary timing primitive. It fires a callback at intervals measured in seconds.

```lua
local seamstress = require "seamstress"

-- One-shot timer for note-off
seamstress.Timer(
  function(self, dt)
    midi_dev:note_off(note, 0, ch)
  end,
  dur_seconds,  -- delta in seconds
  1             -- stage_end = 1 means fire once
)
```

**Pros:**
- No coroutine overhead. Timer callbacks are not coroutines (cannot yield).
- No slot limit mentioned in the v2 design (unlike v1's 36-metro cap). Timers are event-loop-backed.
- Clean one-shot semantics with `stage_end = 1`.

**Cons:**
- Time is in wall-clock seconds, not beats. You'd compute `dur_seconds = dur * (60 / tempo)` at note-on time. Tempo changes during the note won't be tracked.
- v2 has no `clock` module yet, so there's no `clock.sync` or beat-relative timing available.
- v2 has no `midi` module yet. MIDI would need to be implemented via OSC-to-MIDI bridge or wait for the module.
- Timer action functions cannot yield, so you can't do multi-step sequences inside a timer callback.

**Verdict:** This is the correct approach for v2 *when clock and MIDI modules land*. For now, v2 lacks the necessary infrastructure. If we target v2 today, we'd need to build a beat-aware wrapper around `Timer` that recomputes timing on tempo changes.

---

## Existing Patterns from Seamstress Scripts

### `hello_midi.lua` (official example, v1)

Uses `clock.run` + `clock.sleep` for note-off. Computes duration from tempo manually:

```lua
clock.run(function()
  clock.sleep((60 / params:get("clock_tempo") / 4) * 2 * 0.25)
  all_notes_off()
end)
```

Calls `all_notes_off()` which iterates an `active_notes` table and sends note-off for each. Simple but effective. The duration calculation is hardcoded rather than parameterized.

### `awake-seamstress` (robbielyman, v1)

Uses a **metro** for note-off when note length < 100%, and lets notes ring until next step at 100%:

```lua
notes_off_metro:start(
  (60 / clock_tempo / step_div) * note_length * 0.25, 1)
```

A single metro is reused (not allocated per note), with `count = 1` for one-shot. This works because awake is monophonic per voice -- only one note is active at a time.

### `faeng-seamstress` (robbielyman, v1)

Uses `clock.run` + `clock.sync` for note-off. This is the most relevant pattern for a polyphonic sequencer:

```lua
local function note_on(note, velocity, duration, id)
  table.insert(Notes[id], note)
  clock.sync(duration / 16)        -- slight delay before note-on (humanize?)
  Midi:note_on(note, velocity, id)
  clock.sync(duration, duration)   -- wait for gate duration
  Midi:note_off(note, 0, id)
  clock.sleep(0.5)                 -- brief pause before cleanup
  local key = tab.key(Notes[id], note)
  if key then table.remove(Notes[id], key) end
end

function Manage_Polyphony(note, velocity, duration, id)
  clock.run(note_on, note, velocity, duration, id)
end
```

Each note gets its own coroutine. Active notes are tracked per track in `Notes[id]`. Cleanup sends CC 123 (All Notes Off) per channel on script exit.

### `flora_seamstress` (jaseknighter, v1)

Uses `clock.run` + `clock.sleep` for note-off, with envelope-length-based duration:

```lua
pse.midi_note_off = function(delay, note_num, channel, plant_id, note_location)
  clock.sleep(note_off_delay)
  active_midi_notes[note_num] = nil
  midi_out_device:note_off(note_num, nil, channel)
end

-- Scheduled from note_on:
clock.run(pse.midi_note_off, envelope_length, note_to_play, ...)
```

Tracks active notes in a table keyed by note number. This allows deduplication -- if the same note is re-triggered before its note-off, the tracking table prevents double-off.

---

## Edge Cases and Solutions

### Overlapping notes on the same pitch and channel

If track 1 plays C4 with a 2-beat gate, and step 3 (1 beat later) also triggers C4, we have overlapping note-ons for the same pitch. MIDI spec says a second note-on for an already-sounding note is implementation-defined (some synths retrigger, some ignore).

**Solution:** Track active notes per channel. Before sending note-on, check if the note is already active. If so, send note-off first (retrigger), or skip the note-on (legato). The choice depends on the voice mode.

```lua
function Voice:play_note(note, vel, dur)
  local ch = self.channel
  local key = ch * 128 + note
  -- Cancel existing note-off coroutine if re-triggering same note
  if self.active_notes[key] then
    clock.cancel(self.active_notes[key])
    self.midi_dev:note_off(note, 0, ch)
  end
  self.midi_dev:note_on(note, vel, ch)
  local coro_id = clock.run(function()
    clock.sync(dur)
    self.midi_dev:note_off(note, 0, ch)
    self.active_notes[key] = nil
  end)
  self.active_notes[key] = coro_id
end
```

### Note-off when sequencer stops

When the user stops the sequencer, all pending note-off coroutines should fire immediately. If they don't, notes hang.

**Solution:** Track all active note-off coroutine IDs. On stop, cancel them all and send note-off for every tracked note. Also send CC 123 (All Notes Off) as a safety net.

```lua
function Voice:all_notes_off()
  for key, coro_id in pairs(self.active_notes) do
    clock.cancel(coro_id)
    local ch = math.floor(key / 128)
    local note = key % 128
    self.midi_dev:note_off(note, 0, ch)
  end
  self.active_notes = {}
  -- Safety: send All Notes Off CC on all used channels
  for _, ch in ipairs(self.channels_used) do
    self.midi_dev:cc(123, 0, ch)
  end
end
```

### Cleanup on script exit

The norns/seamstress `cleanup` callback must silence all notes. This is the last line of defense against hanging notes.

```lua
function cleanup()
  for _, voice in ipairs(ctx.voices) do
    voice:all_notes_off()
  end
end
```

### Tempo changes mid-note

With `clock.sync(dur)`, tempo changes during the note affect the remaining gate time proportionally (the gate is specified in beats, so it naturally tracks tempo). With `clock.sleep(seconds)`, the gate is fixed in wall-clock time regardless of tempo.

**Recommendation:** Use `clock.sync` for the primary note-off path. It's musically correct -- a quarter-note gate should last one beat regardless of tempo changes.

---

## Recommended Design

### For seamstress v1 (our immediate target)

Use `clock.run` + `clock.sync` for note-off scheduling. This matches the pattern used by `faeng-seamstress` (the most feature-complete seamstress sequencer found) and aligns with the crow-timeline research conclusion.

```lua
local Voice = {}
Voice.__index = Voice

function Voice.new(midi_dev, channel)
  return setmetatable({
    midi_dev = midi_dev,
    channel = channel,
    active_notes = {},  -- key -> coroutine_id
  }, Voice)
end

function Voice:play_note(note, vel, dur)
  local ch = self.channel
  local key = ch * 128 + note
  -- Retrigger: cancel pending note-off for same pitch
  if self.active_notes[key] then
    clock.cancel(self.active_notes[key])
    self.midi_dev:note_off(note, 0, ch)
  end
  -- Note on
  self.midi_dev:note_on(note, vel, ch)
  -- Schedule note-off
  local coro_id = clock.run(function()
    clock.sync(dur)
    self.midi_dev:note_off(note, 0, ch)
    self.active_notes[key] = nil
  end)
  self.active_notes[key] = coro_id
end

function Voice:all_notes_off()
  for key, coro_id in pairs(self.active_notes) do
    clock.cancel(coro_id)
    local ch = math.floor(key / 128)
    local note = key % 128
    self.midi_dev:note_off(note, 0, ch)
  end
  self.active_notes = {}
  self.midi_dev:cc(123, 0, self.channel)
end
```

### For seamstress v2 (future)

When v2's `clock` module lands (the design doc confirms it's planned with `clock.run`, `clock.sleep`, `clock.sync`), the same pattern will work. Until then, a `Timer`-based fallback with `stage_end = 1` provides one-shot note-offs in wall-clock seconds. The voice abstraction can swap implementations based on available modules:

```lua
-- v2 fallback until clock module exists
function Voice:play_note(note, vel, dur)
  local dur_sec = dur * (60 / tempo)
  self.midi_dev:note_on(note, vel, self.channel)
  seamstress.Timer(
    function() self.midi_dev:note_off(note, 0, self.channel) end,
    dur_sec,
    1  -- one-shot
  )
end
```

### Hybrid architecture (lattice for steps, clock.run for note-offs)

The sequencer step clock should use lattice sprockets (or a `clock.run` loop with drift-corrected `clock.sync`). Note-off scheduling is a separate concern handled by the voice layer. The sequencer calls `voice:play_note(note, vel, dur)` and the voice handles the rest.

```
Lattice sprocket (step clock)
  -> sequencer.step() computes note/vel/dur from parameter sequences
    -> voice:play_note(note, vel, dur)
      -> MIDI note_on immediately
      -> clock.run: clock.sync(dur), then MIDI note_off
```

This separation means the voice layer is testable in isolation and the sequencer doesn't need to know about MIDI timing at all.

## Summary

| Approach | Beat-relative | Polyphonic | Slot limit | Complexity | Verdict |
|---|---|---|---|---|---|
| `clock.run` + `clock.sync` | Yes | Yes | None | Low | **Recommended** |
| `clock.run` + `clock.sleep` | No | Yes | None | Low | Acceptable fallback |
| `metro` one-shot | No | Limited | 36 max | Medium | Not recommended |
| Lattice sprocket | Yes | Awkward | None | High | Wrong tool for this job |
| `Timer` (v2) | No | Yes | None | Low | Future, when v2 has clock+MIDI |

Use `clock.run` + `clock.sync` with per-note coroutine tracking, retrigger handling, and CC 123 safety on stop/cleanup.
