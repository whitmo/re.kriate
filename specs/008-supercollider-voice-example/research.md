# Research: SuperCollider Voice Example

**Feature**: 008-supercollider-voice-example
**Date**: 2026-03-25

## Decision 1: SynthDef Architecture

**Decision**: Single SynthDef `\rekriate_sub` with `Saw` oscillator → `RLPF` filter → `EnvGen` amplitude envelope, self-freeing via `doneAction: 2`.

**Rationale**: A `Saw` + RLPF is the canonical subtractive synth — immediately recognizable, easy to understand, and musically useful out of the box. `doneAction: 2` eliminates the need for manual note-off tracking for timed notes, matching re.kriate's `play_note(note, vel, dur)` semantics where duration is known upfront.

**Alternatives considered**:
- `Pulse` oscillator: More harmonically rich but `Saw` is simpler and equally classic
- `MoogFF` filter: Better resonance character but `RLPF` is SC standard and more predictable for beginners
- External envelope gate (no self-free): Would require explicit note-off messages, which re.kriate's OSC voice doesn't send for timed notes

## Decision 2: Portamento Implementation

**Decision**: Per-track portamento time stored in sclang-side state. New synths receive the track's current `porta` arg, applied via `Lag.kr(\freq.kr, \porta.kr)` inside the SynthDef.

**Rationale**: re.kriate sends `/portamento {time}` as a persistent per-track setting (matching `set_portamento` in `lib/voices/osc.lua`). Each new synth node inherits this value. `Lag.kr` provides smooth frequency transitions that feel musical.

**Alternatives considered**:
- Bus-based portamento (shared control bus): More efficient but unnecessarily complex for 4 tracks — direct args are simpler and debuggable
- SynthDef-internal portamento state: Would require a persistent synth per track rather than per-note nodes; conflicts with polyphony requirement (FR-006)

## Decision 3: Node Tracking Strategy

**Decision**: sclang-side `List` per track stores active synth `Node` references. `all_notes_off` iterates and frees them. Nodes are removed from the list via `onFree` callback.

**Rationale**: SuperCollider synths with `doneAction: 2` free themselves after duration, but `all_notes_off` needs to kill currently-playing synths. A sclang-side list is the simplest tracking mechanism — no server-side Group queries needed.

**Alternatives considered**:
- Server-side Group per track + `group.freeAll`: Cleaner server-side but requires Group management boilerplate. Overkill for an example.
- No tracking (rely on `s.freeAll`): Would kill all synths across all tracks, not just one track (violates FR-004)

## Decision 4: Test Script Approach

**Decision**: Lua script using seamstress `osc.send` that sends all 3 message types and prints expected behavior. User visually confirms via SuperCollider post window.

**Rationale**: OSC over UDP is fire-and-forget — there's no acknowledgment protocol. True automated round-trip testing would require SuperCollider to send OSC replies back, adding complexity beyond the scope of an example. The test script exercises the sender side fully; the receiver side is verified by the user checking the SC post window (which prints all received messages per FR-010).

**Alternatives considered**:
- SuperCollider-side OSC reply + Lua listener: Full automation but adds bidirectional OSC complexity beyond the feature scope
- Pure SuperCollider test (no Lua): Wouldn't exercise re.kriate's actual OSC voice module, defeating the "round-trip" purpose
- busted test with mocked OSC: Already covered in feature 004's test suite; this test is specifically for real end-to-end verification

## Decision 5: File Organization

**Decision**: New `examples/supercollider/` directory for SC-specific files. Documentation in `docs/supercollider-setup.md`.

**Rationale**: Keeps example artifacts clearly separated from core `lib/` code. The `examples/` directory signals "optional companion files" rather than "required runtime dependency." SC-005 mandates no changes to existing files, so a new directory is the natural choice.

**Alternatives considered**:
- `lib/supercollider/`: Implies runtime dependency, which this is not
- Root-level `.scd` file: Clutters repo root, unclear purpose
- `docs/supercollider/` for everything: Conflates executable code with documentation
