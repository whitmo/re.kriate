# re.kriate Architecture Design Review

**Scope:** `lib/track.lua`, `lib/app.lua`, `lib/grid_ui.lua`, `lib/events.lua`, `lib/pattern.lua`, `lib/voices/`, `lib/remote/`, and supporting modules (`lib/sequencer.lua`, `lib/direction.lua`, `lib/scale.lua`, `lib/grid_provider.lua`, `lib/log.lua`).

**Date:** 2026-03-27

---

## 1. Executive Summary

The architecture is clean, well-factored, and thoughtfully designed for a Lua norns/seamstress sequencer. The context-object pattern (`ctx`) successfully avoids global state, modules have clear responsibilities, and the event bus provides good decoupling. The voice abstraction and grid provider plugin system show mature extensibility thinking. Several concerns exist around coupling patterns, state management edge cases, and preparedness for upcoming features (clock division, direction modes, probability), but none are structural — they're addressable incrementally.

---

## 2. Design Strengths

### 2.1 Context Object Pattern
The single `ctx` table threaded through all calls is the backbone of the architecture. It makes state ownership explicit, eliminates hidden global coupling, and makes testing straightforward. Every module receives and operates on `ctx` — no fishing for upvalues or global lookups.

**Evidence:** `app.init()` constructs `ctx` with all state, passes it to `sequencer.start(ctx)`, `grid_ui.key(ctx, ...)`, etc. Tests can construct a minimal `ctx` and exercise any module in isolation.

### 2.2 Event Bus (lib/events.lua)
Well-implemented pub/sub with:
- Namespace-based event taxonomy (`sequencer:step`, `voice:note`, `grid:key`)
- Wildcard subscriptions (`sequencer:*`)
- Safe iteration (snapshot-based emit, alive-checking during dispatch)
- `once()` for one-shot subscriptions
- Per-handler error isolation (pcall wrapping)
- Shallow-copy of event data per handler (prevents cross-handler mutation)
- Clean unsubscribe via returned closures

This is production-quality event infrastructure for a Lua project.

### 2.3 Voice Abstraction (lib/voices/)
Clean duck-typed voice interface: `play_note(note, vel, dur)`, `all_notes_off()`, `set_portamento(time)`. Four implementations:
- **midi.lua** — hardware MIDI with monophonic note management and clock-based note-off
- **osc.lua** — OSC output for SuperCollider/external synths
- **recorder.lua** — test double that captures events into a buffer
- **sprite.lua** — visual voice for screen animation (additive, alongside audio)

The recorder voice is particularly good — it enables deterministic testing of sequencer output without any audio infrastructure.

### 2.4 Grid Provider Plugin System (lib/grid_provider.lua)
Registry pattern with `register(name, factory)` and `connect(name, opts)`. Five built-in providers (monome, midigrid, virtual, simulated, synthetic) with interface validation on connect. The `synthetic` provider with `dump()`, `simulate_key()`, and `get_state()` is excellent for test assertions against grid LED state.

### 2.5 Remote API (lib/remote/api.lua)
Transport-agnostic command/query dispatch with:
- Clean path-based routing (`/transport/play`, `/step/set`, `/state/snapshot`)
- Input validation helpers (track, param, step, value ranges)
- Separate query and mutation paths
- Full state snapshot for remote UIs
- OSC transport that chains with existing `osc.event` handlers

### 2.6 Separation of Data Model and UI
`lib/track.lua` is a pure data model — step arrays, loop bounds, advance/peek/set operations. It has zero knowledge of grid, screen, or audio. `lib/grid_ui.lua` reads track state for display and delegates mutations back through `track_mod` functions. This boundary is well-maintained.

### 2.7 Per-Parameter Loop Independence
Each parameter (trigger, note, octave, duration, velocity, ratchet, alt_note, glide) has its own `loop_start`, `loop_end`, and `pos`. This is the core kria design — polymetric per-parameter loops — and it's cleanly implemented as independent param tables within each track.

---

## 3. Concerns

### 3.1 Coupling: grid_ui.lua Directly Requires sequencer

**Location:** `lib/grid_ui.lua:222`
```lua
local seq = require("lib/sequencer")
if ctx.playing then seq.stop(ctx) else seq.start(ctx) end
```

The grid UI module directly requires and calls `sequencer.start/stop` for the play/stop button. This creates a circular dependency path: `app -> grid_ui -> sequencer -> track`, while `app -> sequencer` also exists. It works in Lua (require caching), but it means grid_ui is not a pure UI layer — it has control flow responsibility.

**Risk:** If sequencer start/stop gains side effects (e.g., emitting events that trigger grid redraws, which is already partially true), the call chain becomes harder to reason about. The same play/stop logic also exists in `app.key()` (lines 189-196), creating two code paths for the same action.

**Recommendation:** Route play/stop through the event bus or through a callback on `ctx`. The grid UI should emit an intent event (`ui:play_toggle`), and app.lua or a transport controller should handle it. This keeps grid_ui as a pure view+input layer.

### 3.2 State Mutation in Multiple Places

**Location:** `lib/grid_ui.lua:173-176`, `lib/app.lua:189-196`, `lib/remote/api.lua:86-93`

Track selection, play/stop, and mute toggling are implemented independently in:
1. `grid_ui.nav_key()` — grid button handler
2. `app.key()` — norns key handler
3. `remote/api.lua` handlers — remote control

Each duplicates the state mutation logic. When adding a new feature (e.g., clock-synced transport start), you'd need to update three places.

**Recommendation:** Centralize state-mutating operations. The remote API already provides a clean command interface — grid_ui and app.key could route through `api.dispatch()` or through a shared command layer. Alternatively, use the event bus for intent-based dispatch: emit `command:play` and have a single handler that calls `sequencer.start(ctx)`.

### 3.3 Event Bus: Inconsistent Usage

The event bus exists and is well-implemented, but its usage is inconsistent:

- **Emit but don't subscribe:** `grid_ui` emits `track:select`, `track:mute`, `page:select`, `pattern:load`, `grid:key`, but nothing subscribes to these events in the core modules. The events are fire-and-forget, useful only for external observers.
- **Sequencer emits `sequencer:step` and `voice:note`**, but the sprite voice system is driven by direct `play_sprite()` calls, not by subscribing to `voice:note`.
- **No event-driven UI refresh:** Grid dirty flags are set imperatively (`ctx.grid_dirty = true`) scattered across sequencer.lua, app.lua, and grid_ui.lua. An event-driven approach would subscribe to relevant events and set the flag in one place.

**Risk:** As features grow (probability, clock sync), the gap between "events that exist" and "events that drive behavior" will create confusion about which events are load-bearing vs. decorative.

**Recommendation:** Decide on the event bus's role. Either:
- (a) Use it as the primary inter-module communication channel (grid_ui subscribes to `sequencer:step` for playhead updates, sprite voices subscribe to `voice:note`, etc.), or
- (b) Keep it as an observation/extension point and document that core module communication is via direct function calls.

Currently it's a mix of both, which is the worst option for maintainability.

### 3.4 Pattern Load Replaces Track References

**Location:** `lib/pattern.lua:35`
```lua
ctx.tracks = deep_copy(ctx.patterns[slot_num].tracks)
```

Pattern load replaces `ctx.tracks` entirely with a new deep copy. This is simple and correct, but:

- **Clock coroutines hold stale references:** If the sequencer is running, `track_clock()` captured `local track = ctx.tracks[track_num]` at line 103 of sequencer.lua. After pattern load, `ctx.tracks` points to new tables, but the running coroutines still reference the old track objects. Steps will continue advancing on the old pattern data until the clock coroutine re-reads `ctx.tracks[track_num]`.

**Mitigation (partial):** The clock loop does `local track = ctx.tracks[track_num]` at the top, outside the `while` loop — so it captures the track reference once. The `step_track()` function re-reads `ctx.tracks[track_num]` each call, so it would pick up the new track. But `track_clock()` itself uses the stale `track` local for division and swing on line 106-109.

**Recommendation:** Either:
- Re-read `ctx.tracks[track_num]` inside the `while` loop in `track_clock()`, or
- Stop and restart the sequencer on pattern load, or
- Have `pattern.load()` mutate the existing track tables in-place rather than replacing `ctx.tracks`

### 3.5 `track_mod.advance()` vs `direction_mod.advance()` — Redundant Code

**Location:** `lib/track.lua:144-158` and `lib/direction.lua:86-91`

`track_mod.advance()` implements forward-only advancement. `direction_mod.advance()` reimplements the same read-then-advance pattern but with direction support. The sequencer uses `direction_mod.advance()` exclusively (line 123 of sequencer.lua). `track_mod.advance()` appears to be dead code.

**Risk:** Someone might call `track_mod.advance()` expecting direction support and get forward-only behavior silently.

**Recommendation:** Remove `track_mod.advance()` or make it a thin wrapper around `direction_mod.advance(param, "forward")`. One advance function should be canonical.

### 3.6 Params System Coupling

**Location:** `lib/app.lua:39-53`, `lib/app.lua:79-132`

`build_voice()` and division/direction param actions directly reference `params:get()` (norns global) and mutate `ctx` based on param changes. This creates a tight coupling to the norns param system:

- Voice construction requires `params:get("voice_" .. t)` — can't build voices without the params system
- Division and direction are stored both on `ctx.tracks[t]` (the source of truth for the sequencer) and in `params` (the UI/persistence layer), with param actions syncing params -> ctx

This dual-source pattern is necessary for norns but creates a testing challenge: tests must mock the `params` global or bypass it entirely via `config.voices`.

**Current mitigation:** The `config.voices` escape hatch works. This is acceptable complexity for the norns constraint.

### 3.7 No Undo/History for Pattern Edits

Pattern save/load does deep copies, but there's no undo stack. A user who accidentally loads an empty pattern over active work loses their sequence. This becomes more critical with upcoming persistence features (spec 012).

**Recommendation:** Not necessarily needed now, but worth noting as a future concern. The deep_copy pattern in pattern.lua is a natural foundation for an undo ring.

---

## 4. Extensibility Assessment for Upcoming Features

### 4.1 Clock Division (spec 010)
**Status: Already partially implemented.** `ctx.tracks[t].division` exists, `sequencer.DIVISION_MAP` maps values to `clock.sync` arguments, and there's a per-track params entry. The clock coroutine respects it. What's missing is likely MIDI clock slave/master mode, which would require intercepting clock source in the sequencer — clean place to add it.

**Architecture impact:** Low. The per-track clock coroutine model supports this cleanly.

### 4.2 Direction Modes (already implemented)
**Status: Complete.** `lib/direction.lua` has forward, reverse, pendulum, drunk, and random modes. The sequencer uses `direction_mod.advance()`. Per-track direction is a param. Well done.

### 4.3 Trigger Probability (spec 011)
**Status: Not yet implemented.**

**Architecture readiness:** The step_track() function in sequencer.lua is the natural insertion point:
```lua
if vals.trigger == 1 then  -- add: and math.random() < probability
```

However, probability needs to be per-step (like kria's original design), not per-track. This means adding it as a new param in `track_mod.PARAM_NAMES` (like ratchet, alt_note, glide were added). The existing param infrastructure supports this well — add the param, add a grid page, and check probability in step_track().

**Concern:** The grid nav row is getting crowded. Pages are on x=6-10 (5 primary pages with 3 extended toggles). Adding probability as another page or extended page needs thought about UI navigation.

### 4.4 Preset Persistence (spec 012)
**Status: Not yet implemented.**

**Architecture readiness:** `pattern.lua`'s deep_copy approach means patterns are already serializable plain tables (no metatables, closures, or userdata). Persistence would be: serialize `ctx.patterns` + `ctx.tracks` to JSON or Lua table, write to disk.

**Concern:** The `params` system (norns) has its own persistence (`params:write()`/`params:read()`). Preset persistence needs to decide whether it saves params values too (scale, root note, voice assignments, divisions) or only track/pattern data. This is a design decision, not an architecture problem.

---

## 5. Module Dependency Graph

```
app.lua
  ├── track.lua (data model)
  ├── scale.lua (note quantization)
  ├── sequencer.lua
  │   ├── track.lua
  │   ├── scale.lua
  │   ├── direction.lua
  │   └── log.lua
  ├── grid_ui.lua
  │   ├── track.lua
  │   ├── pattern.lua
  │   └── sequencer.lua  ← coupling concern (§3.1)
  ├── pattern.lua
  ├── direction.lua
  ├── grid_provider.lua
  ├── events.lua
  └── log.lua

remote/api.lua
  ├── track.lua
  ├── sequencer.lua
  └── direction.lua

remote/osc.lua
  └── remote/api.lua

remote/grid_api.lua (standalone, no lib deps)

voices/midi.lua → log.lua
voices/osc.lua (standalone, uses global `osc`)
voices/recorder.lua (standalone, uses global `clock`)
voices/sprite.lua (standalone, uses global `clock`)
```

The dependency graph is shallow (max depth 3) and mostly tree-shaped. The one diamond is `track.lua` required by both `sequencer.lua` and `grid_ui.lua`, which is expected and safe.

---

## 6. Recommendations Summary

| Priority | Issue | Recommendation |
|----------|-------|----------------|
| **High** | Pattern load breaks running clock references (§3.4) | Re-read `ctx.tracks[track_num]` inside track_clock's while loop |
| **Medium** | Grid UI couples to sequencer for play/stop (§3.1) | Route through event bus or callback |
| **Medium** | State mutation duplicated across 3 modules (§3.2) | Centralize via command layer or event intents |
| **Medium** | Event bus role is ambiguous (§3.3) | Choose: primary dispatch or observation-only, then be consistent |
| **Low** | Dead code: `track_mod.advance()` (§3.5) | Remove or delegate to direction_mod |
| **Low** | No undo for pattern operations (§3.7) | Note for future; deep_copy is a good foundation |

---

## 7. Overall Assessment

The architecture is **solid and well-suited to its domain**. The ctx-threading pattern, voice duck-typing, grid provider plugins, and remote API dispatch are all good choices that have been executed cleanly. The codebase is small enough (~1200 lines of core lib code) that the coupling concerns in §3.1-3.3 are manageable today, but they should be addressed before adding more features to prevent the complexity from compounding.

The highest-priority fix is §3.4 (stale track references during pattern load while playing) as it's a latent bug, not just a design concern. Everything else is architectural hygiene that can be addressed incrementally.
