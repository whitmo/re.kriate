# Requirements: Seamstress Entrypoint

Q&A record from requirements clarification.

**Success criterion (stated upfront):** Load the script in seamstress and see kria come up working.

---

## Q1: What does the plugin system replacing NB need to do?

nb on norns provides a unified voice abstraction: you call `player:play_note(note, vel, dur)` and nb routes it to whatever backend is registered (MIDI, engine, crow, etc.). Seamstress has no audio engine, so the available backends are MIDI and OSC.

When you say "a plugin system to replace NB," do you mean:

(a) A voice abstraction layer that works like nb but is native to seamstress (MIDI + OSC backends), so scripts call the same `play_note` interface without caring about the output method?

(b) Something broader -- a general plugin/extension system where voices are just one type of plugin, and other plugins could add behaviors (e.g., pattern recorders, scale managers, external sync)?

(c) A literal nb compatibility shim that makes nb's API work in seamstress by implementing the expected interfaces on top of MIDI/OSC?

**A1:** (a) — A voice abstraction layer native to seamstress (MIDI + OSC backends) with a unified `play_note` interface. Leave room for (b) general plugin system and (c) nb compat shim later, but don't build those now.

---

## Q2: What does the compatibility layer look like?

The current codebase uses several norns-specific APIs that seamstress also has (grid, clock, metro, params, musicutil) and one big one it doesn't (nb). With the voice abstraction from Q1 handling the nb gap, the remaining compat questions are:

- **params** — seamstress has params but with slightly different syntax (no `:add_taper`, no `:add_file`, and `params:lookup_param()` may behave differently). The current code uses `params:add_number`, `params:add_option`, `params:add_separator`, `params:set_action`, and `params:lookup_param("voice_N"):get_player()`.
- **screen** — seamstress has a color SDL screen (256x128) vs norns' monochrome OLED (128x64). The current screen code is minimal (just text display).
- **util** — `util.clamp` is used. Seamstress has `util` but the API may differ slightly.

Do you want:

(a) A single entrypoint script for seamstress (`re_kriate_seamstress.lua`) that replaces platform-specific bits, while keeping the shared `lib/` modules untouched?

(b) A platform detection approach — one entrypoint that detects norns vs seamstress at runtime and adapts?

(c) Something else?

**A2:** (a) — Separate seamstress entrypoint script. Shared `lib/` modules stay untouched where possible. Platform-specific code lives in platform-specific libraries (e.g. `lib/seamstress/` and `lib/norns/`) when needed. The entrypoint wires up the right platform libs.

---

## Q3: Voice abstraction — what backends matter for seamstress?

Since seamstress has no audio engine, voice output is MIDI or OSC. For the initial voice abstraction layer:

Which backends do you need working for "kria comes up working"?

(a) MIDI only — seamstress `midi.connect()` sends note_on/note_off/cc. This is the simplest path and covers hardware synths, DAWs, and software synths listening on virtual MIDI ports.

(b) MIDI + OSC — add OSC voice backend for sending to SuperCollider, Max/MSP, or other OSC-speaking software.

(c) MIDI + OSC + something specific (e.g. a particular SuperCollider setup, a specific soft synth)?

**A3:** Both MIDI and OSC backends, but MIDI is the priority for "comes up working." OSC backend can follow shortly after.

---

## Q4: The seamstress UI — what should it show?

Seamstress gives you a full-color 256x128 SDL window with mouse/keyboard input. The rough idea lists three UI goals:

1. **Configuring voices (osc, midi)** — selecting output device/channel per track
2. **Visualizing time and sequencer function** — showing playheads, loop positions, step values, clock state
3. **Aiding in sequencer usage** — helping the user understand/operate kria without memorizing grid gestures

For "kria comes up working," how much UI do you need?

(a) Minimal info display (like current norns screen but in color) — track name, page, play state, maybe active step values. Grid remains the primary interface.

(b) A richer visualization — show all 4 tracks' step data, playhead positions, and loop boundaries on screen. Still grid-driven, but the screen gives you an overview you can't get from the grid alone.

(c) Full interactive UI — screen shows everything in (b) plus you can click to edit steps, select tracks/pages, configure voices, etc. Grid optional.

**A4:** (a) — Minimal info display for now. Grid is primary. Record plans for (b) richer visualization and (c) full interactive UI as future work in the design.

---

## Q5: How should the sequencer play without nb?

Right now `lib/sequencer.lua:play_note` does this:

```lua
local player = params:lookup_param("voice_" .. track_num):get_player()
if player then
  player:play_note(note, velocity, duration)
end
```

This is the only place nb is called. The voice abstraction needs to replace this call path. Two approaches:

(a) **Swap at the sequencer level** — `sequencer.play_note` calls into the voice abstraction directly. The sequencer imports the voice module instead of going through params/nb. Clean break, sequencer doesn't know or care about nb.

(b) **Swap at the init level** — the seamstress entrypoint injects a voice object into `ctx` that has the same `play_note(note, vel, dur)` interface. The sequencer calls `ctx.voice[track_num]:play_note(...)`. The norns entrypoint injects nb players instead. Sequencer code stays the same either way.

Which feels right?

**A5:** (b) — Inject voice objects into ctx at init time. Sequencer calls `ctx.voices[track_num]:play_note(note, vel, dur)`. Entrypoint is responsible for creating the right voice objects per platform.

Tradeoffs discussed:
- Pro: sequencer stays platform-agnostic, testable, follows ctx pattern
- Pro: easy to mock in tests
- Con: MIDI voice backend must handle note-off timing internally (raw MIDI has no "play for N beats")
- Con: small indirection, but that's what ctx is for
- Decision: voice config (MIDI port/channel, OSC address) lives in params, wired up by the entrypoint

---

## Q6: What does "tests to validate it works" mean concretely?

The existing test suite (`specs/track_spec.lua`) covers the data model. For the seamstress entrypoint, what level of testing do you need?

(a) Unit tests for the new voice abstraction (MIDI backend sends correct note_on/note_off, timing works, OSC backend sends correct messages) — run via `seamstress --test`

(b) Unit tests (a) plus integration test that loads the full script in seamstress without errors and verifies ctx is initialized correctly

(c) Something else — e.g., you want to manually load it and hear sound, and "tests" means the code doesn't crash on startup?

**A6:** All of the above, layered:
- (a) Unit tests for voice abstraction via `seamstress --test`
- (b) Integration test that loads full script and verifies ctx init
- Research: investigate integration tests that run with a real/virtual grid. Explore a "test voice" backend that produces visuals or data structures instead of notes — lets you verify sequencer behavior by inspecting output rather than listening. This is a research topic for the research phase.

---

## Q7: Does the seamstress entrypoint need to work without a grid?

On norns, grid is the primary UI and keys/encoders provide basic fallback controls. On seamstress there are no keys/encoders, but you do have keyboard and mouse via screen callbacks.

For "kria comes up working," does a grid need to be connected?

(a) Yes, grid required — seamstress is a grid companion app. No grid = no interaction. The screen just shows status.

(b) Grid preferred but keyboard fallback — map basic operations (play/stop, track select, page select) to keyboard shortcuts so you can at least demo it without hardware.

(c) Grid optional — full keyboard/mouse interaction as an alternative. (This is really future UI work from Q4c.)

**A7:** (b) — Grid preferred, but add keyboard shortcuts for basic ops (play/stop, track select, page select) so it's demoable without hardware. Plan for (c) full keyboard/mouse alternative as future work alongside the interactive UI.

---

## Q8: How should MIDI voice configuration work?

For the MIDI voice backend, each of the 4 tracks needs to know where to send notes. The config options are:

(a) **One MIDI device, channel-per-track** — params for "MIDI device" (global) and "track N channel" (1-16). Simplest, covers the common case of one synth/DAW with multi-timbral setup.

(b) **Device-per-track** — each track gets its own MIDI device + channel param. More flexible (track 1 to hardware synth, track 2 to DAW, etc.) but more params to configure.

(c) **Start with (a), design for (b)** — ship the simple version but structure the voice abstraction so per-track device assignment is a config change, not a rewrite.

**A8:** (c) — One MIDI device + channel-per-track initially. Voice abstraction designed so swapping to per-track devices is a config change later.

---

## Q9: What changes to the shared lib/ modules are acceptable?

The current `lib/sequencer.lua` hardcodes the nb call path. To support ctx-injected voices (A5), it needs a small change — replace `params:lookup_param("voice_N"):get_player()` with `ctx.voices[track_num]`. This is the only required change to shared code.

(a) **That one change is fine** — modify `sequencer.play_note` to use `ctx.voices`. Both entrypoints (norns and seamstress) inject the appropriate voice objects. The norns entrypoint wraps nb players to match the interface.

(b) **Don't touch shared code at all** — the seamstress entrypoint provides its own sequencer module or monkey-patches the play_note function.

(c) **Refactor shared code freely** — if something is cleaner with a different structure, change it. Both entrypoints adapt.

**A9:** (c) — Refactor shared code as needed for cleanliness. Both entrypoints adapt. No need to preserve the current structure if a better one serves both platforms.

---

I think we've covered the core shape of the project. Let me check if there are gaps before we move on.

## Summary of requirements so far:

1. **Voice abstraction** — `play_note` interface over MIDI (priority) + OSC backends, injected into ctx. Room for general plugin system and nb compat later.
2. **Separate entrypoint** — `re_kriate_seamstress.lua` alongside the norns one. Platform-specific libs in `lib/seamstress/` and `lib/norns/` as needed.
3. **Shared code refactorable** — lib/ modules can be restructured to serve both platforms cleanly.
4. **MIDI config** — one device + channel-per-track initially, designed for per-track devices later.
5. **Minimal screen UI** — status display, plans recorded for richer visualization and interactive UI.
6. **Keyboard fallback** — basic ops without grid, plan for full keyboard/mouse alternative.
7. **Tests** — unit tests for voice abstraction, integration test for script load, research into test voices and grid integration tests.
8. **Success** — load in seamstress, kria comes up working.

## Q10: Are we missing anything, or is requirements clarification complete?

Anything else on your mind before we move to research? Topics I'd suggest researching:
- seamstress note-off timing strategies (clock-based vs metro-based for MIDI duration)
- test voice / visual verification pattern
- existing norns/seamstress dual-platform scripts as reference

**A10:** Requirements clarification complete. Moving to research with expanded topics:
- Seamstress note-off timing strategies (MIDI duration handling)
- Test voice / visual verification patterns
- Existing norns/seamstress dual-platform scripts as reference
- Crow `timeline` library as a model for managing musical events
- Drum track UI — how it might differ from a melodic kria track
- Live recording — capturing a sequence by playing it in real time
- Unusual voice backends — sample player, sampler, other non-note voices

**Research complete. Proceeding to design.**
