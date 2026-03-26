# Implementation Plan: OSC Voice Integration

**Branch**: `004-osc-voice-integration` | **Date**: 2026-03-25 | **Spec**: `specs/004-osc-voice-integration/spec.md`
**Input**: Feature specification from `/specs/004-osc-voice-integration/spec.md`

## Summary

Wire the existing `lib/voices/osc.lua` module into seamstress as an alternative voice backend alongside MIDI. Add per-track params for backend selection (midi/osc) and OSC target configuration (host/port). Voice swapping happens via param actions in `seamstress.lua`, with `all_notes_off` on the outgoing backend before swap. No new modules needed — the feature is entirely param wiring in the entrypoint plus tests.

## Technical Context

**Language/Version**: Lua 5.4 (via busted test runner, seamstress v1.4.7 runtime)
**Primary Dependencies**: seamstress v1.4.7, musicutil, busted (test framework)
**Storage**: N/A (in-memory params, no persistence layer)
**Testing**: busted (`busted specs/`)
**Target Platform**: seamstress (macOS/Linux) — OSC is seamstress-only per spec
**Project Type**: Musical sequencer script (norns/seamstress platform)
**Performance Goals**: No additional perf concerns — OSC send is fire-and-forget UDP
**Constraints**: No new dependencies; follow ctx pattern; backward-compatible MIDI default
**Scale/Scope**: 4 tracks × 3 params (backend, host, port) = 12 new params

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-Centric Architecture | PASS | Voice instances live on `ctx.voices[t]`. Param actions swap voices on ctx. No new globals. |
| II. Platform-Parity Behavior | PASS | OSC is seamstress-only adapter (like keyboard.lua). Norns unaffected — uses nb voice system. Sequencing behavior identical regardless of voice backend. |
| III. Test-First Sequencing Correctness | PASS | OSC doesn't affect sequencing logic. Tests will verify voice wiring, param actions, and backend switching. TDD ordering in tasks. |
| IV. Deterministic Timing and Safe Degradation | PASS | No new clock/timing code. OSC send is fire-and-forget UDP — no blocking. `all_notes_off` on swap prevents stuck notes. |
| V. Spec-Driven Delivery | PASS | Full pipeline: spec → plan → tasks → analyze → implement → verify. All artifacts in `specs/004-osc-voice-integration/`. |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/004-osc-voice-integration/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (from /speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── voices/
│   ├── midi.lua          # Existing — unchanged
│   ├── osc.lua           # Existing — unchanged (already has full interface)
│   ├── sprite.lua        # Existing — unchanged
│   └── recorder.lua      # Existing — unchanged
├── app.lua               # Existing — unchanged (cleanup already iterates ctx.voices)
├── sequencer.lua         # Existing — unchanged (already uses ctx.voices[t])
└── seamstress/           # Existing platform-specific modules

seamstress.lua            # MODIFIED — add voice backend params + swap logic
specs/
└── osc_voice_spec.lua    # NEW — tests for OSC voice wiring and param actions
```

**Structure Decision**: No new modules. All wiring happens in `seamstress.lua` (the entrypoint), matching the existing pattern where MIDI channel params are defined there. Tests go in a new spec file.

## Implementation Phases

### Phase 1: Voice Backend Param & Factory (FR-001, FR-008)

Add per-track "voice backend" option param to seamstress.lua with values `{"midi", "osc"}` defaulting to index 1 (midi). No swap logic yet — just the param definition.

**Files**: `seamstress.lua`, `specs/osc_voice_spec.lua`
**Tasks**: ~4 (test param exists, test default is midi, implement param, test backward compat)

### Phase 2: OSC Target Params (FR-003, FR-009)

Add per-track "osc host" (text param, default "127.0.0.1") and "osc port" (number param, range 1-65535, default 57120) to seamstress.lua.

**Files**: `seamstress.lua`, `specs/osc_voice_spec.lua`
**Tasks**: ~4 (test params exist, test defaults, test port range, implement)

### Phase 3: Voice Swap on Backend Change (FR-002, FR-004)

Wire the voice backend param action to:
1. Call `all_notes_off()` on the current voice (`ctx.voices[t]`)
2. Create a new voice instance (MIDI or OSC) based on the new param value
3. Assign it to `ctx.voices[t]`

This is the core feature logic. OSC voices are created via `osc.new(track_num, host, port)` using current param values.

**Files**: `seamstress.lua`, `specs/osc_voice_spec.lua`
**Tasks**: ~6 (test all_notes_off called on swap, test new voice created, test OSC messages sent, test MIDI→OSC switch, test OSC→MIDI switch, implement)

### Phase 4: OSC Target Update on Param Change (FR-005)

Wire osc host and osc port param actions to call `set_target(host, port)` on the active OSC voice (if backend is currently osc). If backend is midi, the param change is stored but no action taken until backend switches to osc.

**Files**: `seamstress.lua`, `specs/osc_voice_spec.lua`
**Tasks**: ~4 (test set_target called, test no-op when midi, test host+port both update, implement)

### Phase 5: Sprite Voice Continuity & Platform Guard (FR-006, FR-007)

Verify that sprite voices remain additive (already the case — they're on `ctx.sprite_voices`, separate from `ctx.voices`). Verify that norns entrypoint (`re_kriate.lua`) has no voice backend params. These are verification tasks, not implementation.

**Files**: `specs/osc_voice_spec.lua`
**Tasks**: ~3 (test sprite voices unaffected, test norns has no osc params, test seamstress has osc params)

### Phase 6: Edge Cases & Integration (SC-001 through SC-005)

- Backend switch while sequencer playing (all_notes_off + swap)
- Shared host/port across multiple tracks (valid, different OSC paths)
- Cleanup with OSC voices active (app.cleanup already calls all_notes_off on all voices)
- Full 4-track mixed MIDI/OSC scenario
- Regression: all 512+ existing tests still pass

**Files**: `specs/osc_voice_spec.lua`
**Tasks**: ~6 (one per edge case + full suite verification)

### Task Count Estimate

- Phase 1: 4 tasks
- Phase 2: 4 tasks
- Phase 3: 6 tasks
- Phase 4: 4 tasks
- Phase 5: 3 tasks
- Phase 6: 6 tasks
- **Total**: ~27 tasks (15+ tests per SC-004)

### Parallel Opportunities

- Phase 1 ∥ Phase 2 (independent param groups, same spec file but different describe blocks)
- Phase 5 verification tasks are independent of Phase 3-4 implementation

## Key Design Decisions

1. **No new modules**: All voice swap logic lives in `seamstress.lua` param actions. This matches the existing pattern (MIDI channel params modify voice state there) and avoids unnecessary abstraction.

2. **Eager voice creation on swap**: When backend changes, create a fresh voice instance. Don't cache both MIDI and OSC voices per track. Simpler, and voice creation is cheap.

3. **Param-driven, not config-driven**: Runtime reconfiguration via params (not app.init config). Users can switch backends during a session without restart.

4. **OSC voice module unchanged**: `lib/voices/osc.lua` already has the full interface. No modifications needed. This feature is purely wiring.

5. **Test via mock/spy on osc.send**: Tests capture outbound OSC messages by stubbing `osc.send` (seamstress global). No network needed.

6. **all_notes_off before swap**: Prevents stuck notes. Both MIDI and OSC voices implement this. Called on the outgoing voice before replacement.
