# Research: OSC Voice Integration

**Feature**: 004-osc-voice-integration
**Date**: 2026-03-25

## Research Summary

No NEEDS CLARIFICATION items in the technical context — the existing codebase already has all required infrastructure. This research documents the 6 key architectural decisions validated during planning.

## Decision 1: Voice Swap Location

**Decision**: Voice swap logic lives in `seamstress.lua` param actions, not a new module.
**Rationale**: The existing pattern puts voice-related param actions in the entrypoint (see MIDI channel params at `seamstress.lua:43-49`). Adding a `voice_manager.lua` abstraction for simple param→swap wiring would violate the "don't over-architect" principle.
**Alternatives considered**:
- `lib/voice_manager.lua` — rejected: adds indirection for 4 param actions. Would be warranted if norns also needed voice switching, but norns uses nb (a completely different system).
- Logic in `lib/app.lua` — rejected: app.lua is platform-agnostic. Voice backend selection is seamstress-specific.

## Decision 2: Testing Strategy for OSC Messages

**Decision**: Stub `osc.send` (seamstress global) in tests to capture outbound messages.
**Rationale**: `osc.send` is the seamstress API for sending OSC. The existing `lib/voices/osc.lua` calls it directly. Tests can replace `osc.send` with a spy function that records calls, then assert on the captured messages.
**Alternatives considered**:
- Listen on a real UDP socket — rejected: adds network dependency to tests, introduces flakiness. The osc.lua module is already tested implicitly by the voice interface contract.
- Test only at the param/wiring level, not message content — rejected: SC-001 requires verifying "correct MIDI note number, velocity, and duration" reach the OSC target.

## Decision 3: Voice Instance Lifecycle

**Decision**: Create a fresh voice instance on each backend swap. Don't cache both MIDI and OSC voices.
**Rationale**: Voice creation is trivial (table construction, no I/O). Caching adds state management complexity (which cached voice is "current"?) for no performance benefit.
**Alternatives considered**:
- Pre-create both MIDI and OSC voices per track, swap pointer — rejected: doubles voice objects. Requires tracking "active" flag. More state, same behavior.
- Lazy creation with memoization — rejected: over-engineering for 4 tracks × 2 backends.

## Decision 4: Param Type for OSC Host

**Decision**: Use `params:add_text` for osc host (string param, default "127.0.0.1").
**Rationale**: Host is a free-form string (IP address or hostname). Seamstress params support text type. No validation needed beyond what the user types — UDP send to invalid host simply doesn't arrive (fire-and-forget per spec edge case).
**Alternatives considered**:
- `params:add_option` with preset hosts — rejected: too restrictive for real studio setups.
- No host param, hardcode localhost — rejected: spec FR-003 requires per-track configurable host.

## Decision 5: Param Visibility When Backend is MIDI

**Decision**: OSC host/port params are always present for each track regardless of backend selection. They are not hidden when backend is MIDI.
**Rationale**: Seamstress params don't support conditional visibility (hide/show). The spec says "hidden or clearly marked as inactive" (US3 scenario 4). Since hiding isn't feasible, the params simply have no effect when backend is MIDI — the param action checks `backend == "osc"` before calling `set_target`. This is the standard pattern for norns/seamstress params.
**Alternatives considered**:
- Dynamic param visibility — rejected: not supported by seamstress param system.
- Add "(inactive)" suffix to param name when MIDI — rejected: param names are static after creation in seamstress.

## Decision 6: MIDI Device Reference for Voice Recreation

**Decision**: Store `midi_dev` reference in a local variable in `seamstress.lua` init scope. When swapping back to MIDI, create `midi_voice.new(midi_dev, channel)` using the stored reference.
**Rationale**: The MIDI device (`midi.connect(1)`) is connected once at init. Voice swap actions need access to it to create new MIDI voice instances. Storing it as a local in the init closure is the simplest approach, matching the existing code pattern.
**Alternatives considered**:
- Store `midi_dev` on ctx — rejected: ctx doesn't currently hold platform-specific resources directly. Adding it would blur the platform abstraction boundary.
- Reconnect MIDI on each swap — rejected: wasteful and potentially causes device reset.
