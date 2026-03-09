# Research: Complete Seamstress Kria Sequencer

**Branch**: `001-seamstress-kria-features` | **Date**: 2026-03-06

## R1: Seamstress v1.4.7 Platform Capabilities

**Decision**: Target seamstress v1.4.7 exclusively (not v2.0.0-alpha)
**Rationale**: v2.0.0-alpha has breaking API changes (grid, metro, screen globals removed). v1.4.7 is the stable release installed at `/opt/homebrew/opt/seamstress@1/bin/seamstress`. Run with `-s` flag.
**Alternatives**: v2.0.0-alpha was tested and rejected due to missing globals.

Key v1.4.7 APIs confirmed working:
- `grid.connect()` -> grid object with `:led()`, `:all()`, `:refresh()`, `.key` callback
- `metro.init()` -> metro object with `.time`, `.event`, `:start()`, `:stop()`
- `screen.color()`, `screen.clear()`, `screen.move()`, `screen.text()`, `screen.update()`
- `screen.key` callback for keyboard input
- `clock.run()`, `clock.sync()`, `clock.cancel()` for coroutine timing
- `midi.connect()` for MIDI output
- `params` global for parameter system
- `require("musicutil")` for scale generation

## R2: Extended Page Toggle Mechanism

**Decision**: Double-press same page nav button to toggle primary/extended view
**Rationale**: This is how original kria works. Three page pairs: trigger/ratchet, note/alt-note, octave/glide. Duration and velocity have no extended pages.
**Alternatives**: Dedicated extended page buttons (rejected: uses grid space). Hold-to-toggle (rejected: inconsistent with kria UX).

Implementation approach:
- Add `extended_page_active` boolean to ctx
- Track `last_page_pressed` in ctx
- On page nav press: if same page pressed again AND page has extension, toggle extended flag
- Extended pages: `{trigger = "ratchet", note = "alt_note", octave = "glide"}`
- Switching to a different page resets extended flag

## R3: Direction Mode Implementation

**Decision**: Per-track direction stored as `track.direction` (string: "forward", "reverse", "pendulum", "random", "drunk")
**Rationale**: Matches original kria's 5 direction modes. Per-track (not per-param) to match original behavior and keep complexity manageable.
**Alternatives**: Per-parameter direction (original kria is per-track on scale page). Enum integers (rejected: strings are more readable in Lua).

Implementation approach:
- Add `direction` field to track (default "forward")
- Modify `track.advance()` to accept direction or use track-level direction
- Pendulum needs extra state: `advancing_forward` boolean per param
- Random uses `math.random(loop_start, loop_end)`
- Drunk: current +/- 1 with wrap at loop boundaries

## R4: Ratchet/Repeat Data Model

**Decision**: Ratchet as a new parameter with values 1-7 (1 = normal, 2-7 = subdivisions)
**Rationale**: Simplifies the original kria's complex sub-trigger grid to a single value per step, which maps cleanly to our existing bar-graph value page UI.
**Alternatives**: Full sub-trigger pattern per step (rejected: over-complex for first implementation, can be added later).

Implementation approach:
- Add "ratchet" to PARAM_NAMES as an extended parameter
- Ratchet value N means N evenly-spaced note-on events within the step duration
- Sequencer fires N notes at duration/N intervals using nested clock.run

## R5: Alt-Note Additive Behavior

**Decision**: Alt-note values are ADDITIVE with primary note values, modulo scale length
**Rationale**: This matches the original kria behavior. Alt-note has its own independent loop, creating polymetric pitch combinations.
**Alternatives**: Probabilistic alternation (rejected: not how original kria works).

Implementation approach:
- Add "alt_note" to extended parameter names
- In sequencer.step_track: `effective_degree = ((note_deg - 1) + (alt_note_deg - 1)) % scale_length + 1`
- Alt-note has independent loop start/end/pos (polymetric)

## R6: Glide/Portamento via MIDI

**Decision**: Glide implemented via MIDI CC 65 (Portamento On/Off) and CC 5 (Portamento Time)
**Rationale**: Standard MIDI portamento controls. Values 1-7 map to portamento times. Value 0 (or no glide) sends CC 65 = 0.
**Alternatives**: Pitch bend glide (rejected: more complex, less standard). CC 84 Portamento Control (rejected: less widely supported).

Implementation approach:
- Add "glide" to extended parameter names
- Voice:play_note checks glide value, sends CC 65 + CC 5 before note-on
- Glide value 1 = 0ms (off), values 2-7 = increasing portamento time

## R7: Pattern Storage Format

**Decision**: Deep-copy all track state (params + division + mute + direction) into a Lua table
**Rationale**: Simple, no serialization needed for in-memory patterns. 16 slots matches original kria.
**Alternatives**: JSON serialization (rejected: no external deps). Shallow copy (rejected: shared references cause bugs).

Implementation approach:
- `pattern.lua` module with `save(tracks)` -> deep copy, `load(pattern, tracks)` -> restore
- 16 pattern slots stored in `ctx.patterns[1..16]`
- Pattern page accessed via grid navigation (need to allocate a nav column)

## R8: Muted Track Behavior

**Decision**: Muted tracks continue advancing playheads silently (match original kria)
**Rationale**: Current implementation returns early in step_track, preventing advancement. Original kria advances muted tracks but suppresses output. This matters because unmuting at the right moment is a performance technique.
**Alternatives**: Keep current behavior (rejected: doesn't match kria UX expectations).

## R9: CI Pipeline

**Decision**: GitHub Actions with luac -p lint + busted tests
**Rationale**: Constitution mandates CI before feature implementation.
**Alternatives**: None (mandated).

Pipeline steps:
1. Install Lua 5.4 + luarocks
2. Install busted via luarocks
3. `luac -p` on all .lua files
4. `busted specs/` to run tests
5. Coverage check: verify every public function in lib/ has a test

## R10: Test Infrastructure

**Decision**: Use busted with mocked platform globals, recorder voice for output verification
**Rationale**: Existing pattern works well. 87 tests already pass. recorder.lua captures events for assertion.
**Alternatives**: seamstress --test (rejected: conflicts with real globals, doesn't pick up our specs).
