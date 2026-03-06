# Crow Timeline as a Model for Musical Event Scheduling

## What Timeline Is

`timeline` is a Lua library in [monome/crow](https://github.com/monome/crow/blob/main/lua/timeline.lua) that provides declarative, table-driven event sequencing on top of crow's `clock` coroutine system. Instead of writing imperative `clock.run` / `clock.sync` loops, you describe a sequence as alternating duration-action pairs in a flat table:

```lua
timeline.loop{ 1, kick, 0.5, hat, 0.5, snare }
```

The library handles coroutine lifecycle, launch quantization, drift correction, and repetition control.

## Three Scheduling Modes

### `loop` -- repeating beat-relative durations

Durations are *intervals* in beats. The sequence repeats until stopped or a predicate fires.

```lua
tl = timeline.loop{ 1, kick, 0.5, hat, 0.5, snare }
tl:stop()
```

Internally: `clock.sync(lq)` for launch quantization, then a `repeat/until` that iterates the table in pairs, calling `doact(action)` then `dowait(duration, zero_ref)`. The zero-reference (`self.z`) is set once after quantization and accumulated forward, preventing drift from accumulating across iterations.

### `score` -- absolute beat timestamps

Durations are *absolute beat positions* relative to a beat-zero calculated at launch. Good for song-form structures.

```lua
timeline.score{ 0, intro, 32, verse, 64, chorus }
```

Uses `doalign(beat, zero)` which computes elapsed beats since zero and sleeps the remaining difference. Supports a `'reset'` return value from action functions to restart the score from a new beat-zero.

### `real` -- wall-clock seconds

Same structure as score but times are in seconds, independent of tempo. Uses `clock.sleep` instead of `clock.sync`.

```lua
timeline.real{ 0, strum_1, 0.05, strum_2, 0.05, strum_3 }
```

## Key Mechanisms

### Built on clock coroutines

Timeline is a thin layer over `clock.run` / `clock.sync` / `clock.sleep` / `clock.cancel`. Each timeline instance holds one coroutine ID (`self.coro`). Starting a timeline calls `clock.run(self.fn)`. Stopping calls `clock.cancel(self.coro)`. There is no custom scheduler -- it piggybacks entirely on the existing clock infrastructure.

### Launch quantization

Every timeline quantizes its start to a beat boundary via `clock.sync(self.lq)`. Default is 1 beat (`TL.launch_default = 1`). Configurable per-instance with `:launch(q)` or globally by setting `timeline.launch_default`.

### Drift correction

In loop mode, `self.z` (the zero-reference beat) is set once after launch quantization to `math.floor(clock.get_beats())` and then accumulated by the realized duration at each step: `z = z + realize(d); clock.sync(z)`. By syncing to an absolute beat target rather than a relative offset, rounding errors do not compound across iterations.

### Sequins integration

Both durations and actions can be `sequins` objects. The `realize()` helper calls `q()` on any sequins value before using it. This means a single timeline definition can produce varied rhythms and melodies:

```lua
timeline.loop{ sequins{0.55, 0.45}, hat }  -- swing
timeline.loop{ 1, {note, sequins{0,2,4,7}, 2} }  -- arpeggio
```

### Predicate-based stopping

`:unless(pred)` attaches a predicate evaluated after each full loop iteration. `:times(n)` is syntactic sugar that sets a decrementing predicate. The predicate is checked in the `repeat/until` of loop mode.

### Hotswap

`TL.hotswap(old, new)` recursively replaces data inside a running timeline without restarting it. If the old data contains sequins, it uses `sequins:settable()`. This enables live-coding: redefine the table and hotswap it into the running coroutine.

### Play / stop / replay

`:stop()` cancels the coroutine. `:play()` stops any existing coroutine, resets `:times()` predicates, and starts fresh via `clock.run`. The timeline object persists across stop/play cycles.

## What Seamstress Already Has

Seamstress (checked against [ryleelyman/seamstress](https://github.com/ryleelyman/seamstress) `main` branch) provides these scheduling primitives:

| Module | Location | What it does |
|---|---|---|
| **clock** | `lua/core/clock.lua` | Coroutine-based timing. Has `clock.run`, `clock.cancel`, `clock.sleep`, `clock.sync`, `clock.get_beats`, `clock.get_beat_sec`. API-compatible with norns and crow's clock. Supports internal, MIDI, and Link sources. |
| **metro** | `lua/core/metro.lua` | Fixed-interval timer callbacks (up to 36 slots). Not coroutine-based -- fires a callback at a fixed period. |
| **lattice** | `lua/lib/lattice.lua` | A "superclock" that pulses at high PPQN (default 96) and dispatches to "sprockets" -- division-based callbacks with swing and ordering. Each sprocket has a division (e.g. 1/4), an action callback, and optional swing/delay. The lattice ticks all sprockets from a single `clock.run` coroutine. |
| **sequins** | `lua/lib/sequins.lua` | Ported from crow. Iterable sequences with flow control (`every`, `times`, `count`, `step`) and nesting. |
| **pattern_time** | `lua/lib/pattern_time.lua` | Event recorder/player. Records timestamped events and replays them via metro. Designed for gesture recording, not programmatic sequencing. |

**No timeline module exists in seamstress.** There is no equivalent declarative event sequencer.

## Applicability to a Polymetric Kria Sequencer

### What timeline solves well

1. **Declarative rhythm description.** A kria track's step sequence maps naturally to a duration-action table. Instead of writing a `clock.run` loop with index management, clock division math, and sync calls, you describe what happens and when.

2. **Drift-free absolute sync.** The zero-reference accumulation pattern (`z = z + duration; clock.sync(z)`) is exactly what a step sequencer needs. Each track maintains its own `z` and drifts are impossible regardless of how many steps have elapsed.

3. **Per-instance lifecycle.** Each timeline is an independent object with play/stop/coroutine management. For kria's 4 tracks, you'd have 4 timeline instances, each independently stoppable/restartable.

4. **Sequins for parameter variation.** Kria's per-parameter sequences (note, octave, velocity, duration, trigger) could be expressed as sequins feeding into timeline actions. The library already handles realizing sequins values at each step.

### What needs adaptation for our use case

1. **Flat table structure is too rigid for kria.** Kria doesn't have a static duration-action table. Each parameter (note, octave, trigger, duration, velocity) has its own independent loop length and position. The "action" at each step is computed dynamically from the current state of multiple parameter sequences. A direct `timeline.loop{...}` with a pre-built table wouldn't work -- you'd need to rebuild the table every time a loop length changes.

2. **We need dynamic step computation, not static tables.** The better pattern for kria is a single-step-at-a-time approach: compute the current step's duration from the duration parameter sequence, compute the action from the other parameter sequences, execute, advance all parameter indices independently. This is closer to a `clock.run` loop with internal state than a timeline table.

3. **Note-off scheduling is orthogonal to step sequencing.** Timeline handles "do X, wait, do Y" but doesn't model overlapping events. A kria voice needs to schedule note-on at the step boundary and note-off after the gate duration -- these are concurrent timers. Timeline would need a secondary mechanism (another timeline, a `clock.run`, or a metro) for note-offs.

4. **Lattice might be the better foundation.** Lattice's sprocket model -- a division-based callback with swing -- maps more directly to kria's clock-divided tracks. Each track is a sprocket with its division set to the track's clock division. The callback computes the current step from the track's parameter sequences.

### Design insights for our voice/event system

**Steal the drift-correction pattern.** Whether we use timeline, lattice, or raw clock, the `z = z + step_duration; clock.sync(z)` pattern from timeline's `dowait` is the right way to handle timing. Never use relative sleep.

**Steal the lifecycle model.** Timeline's play/stop/replay pattern (coroutine ID stored on the object, stop = cancel + nil, play = stop + run) is clean and should be adopted for voice objects.

**Use lattice for the master pulse, timeline-style coroutines for note-offs.** A hybrid:
- Each kria track is a lattice sprocket at its clock division. The sprocket callback reads the current step from all parameter sequences, computes the note event, and fires note-on.
- Note-off is scheduled via `clock.run(function() clock.sleep(gate_duration); midi_note_off(...) end)` -- a lightweight one-shot coroutine per note. This is simpler than a full timeline for what is essentially a single delayed callback.

**The timeline table structure is useful for meta-sequences.** Pattern chains, song-form arrangement, or preset recall sequences map well to `score` mode. Consider timeline (or a minimal port of it) for higher-level sequencing above the step level.

**Sequins as the parameter iterator.** Kria's per-parameter sequences with independent lengths are a natural fit for sequins with `step(1)` -- each parameter is a sequins object that advances independently. The main question is whether to use sequins directly or a simpler circular-index approach. Sequins adds value if we want flow modifiers (every, times, count) for parameter-level variation.

## Summary

Timeline is a well-designed declarative wrapper over clock coroutines. Its key contributions are: (1) a clean object lifecycle for coroutine-managed sequences, (2) drift-free timing via absolute beat references, (3) deep sequins integration for dynamic variation, and (4) launch quantization for rhythmic alignment. For a kria sequencer, the step-by-step computation model means we can't use timeline's flat table structure directly, but we should adopt its timing and lifecycle patterns. Lattice sprockets are a better fit for the per-track pulse, with timeline-style one-shot coroutines for note-off scheduling. Timeline's `score` mode could serve higher-level sequencing (pattern chains, song form).
