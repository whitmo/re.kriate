# Implementation Plan: SuperCollider Voice Example

**Branch**: `008-supercollider-voice-example` | **Date**: 2026-03-25 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-supercollider-voice-example/spec.md`

## Summary

Create a companion SuperCollider example that receives OSC messages from re.kriate's existing OSC voice backend (`lib/voices/osc.lua`) and plays them through a subtractive synth. Deliverables: SynthDef + sclang listener script, setup documentation, and a Lua round-trip test script. **No changes to existing re.kriate source files** (SC-005).

## Technical Context

**Language/Version**: SuperCollider (sclang) for synth/listener, Lua 5.4 for test script
**Primary Dependencies**: SuperCollider 3.x (user-installed), seamstress v1.4.7 (for test script OSC), lib/voices/osc.lua (existing, not modified)
**Storage**: N/A (no persistence)
**Testing**: Manual verification via SuperCollider + Lua test script using `osc.send`; no busted tests (no Lua library code to unit-test)
**Target Platform**: macOS / Linux with SuperCollider installed
**Project Type**: Example / documentation (additive-only)
**Performance Goals**: Real-time audio synthesis — synth nodes must start within 10ms of OSC receipt
**Constraints**: Must work with SuperCollider default config (port 57120). No changes to existing `lib/`, `specs/`, or entrypoint files.
**Scale/Scope**: 4 tracks, 3 message types, 1 SynthDef, 12 OSC responders

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Check

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Context-Centric Architecture** | PASS | No changes to ctx or core modules. Example files are standalone. |
| **II. Platform-Parity Behavior** | PASS | This is an example/addon, not core sequencing behavior. Does not affect norns/seamstress parity. |
| **III. Test-First Sequencing Correctness** | N/A | No sequencing logic changes. The round-trip test script (FR-008) verifies OSC integration, not sequencer correctness. |
| **IV. Deterministic Timing and Safe Degradation** | PASS | No clock/scheduling changes. SuperCollider handles its own timing. |
| **V. Spec-Driven Delivery** | PASS | Following full speckit pipeline (specify → plan → tasks → analyze → implement → verify). |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/008-supercollider-voice-example/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
examples/
└── supercollider/
    ├── rekriate_sub.scd       # SynthDef + sclang listener (FR-001, FR-002)
    └── test_osc_roundtrip.lua # Lua round-trip test script (FR-008, US4)

docs/
└── supercollider-setup.md     # Setup documentation (FR-007, US3)
```

**Structure Decision**: New `examples/supercollider/` directory for SC artifacts. Documentation goes in `docs/`. No existing files are modified (SC-005). The test script is Lua (not busted) because it needs a live SuperCollider instance — it's an integration verification tool, not a unit test.

## Implementation Phases

### Phase 1: SynthDef + Listener Script (US1, US2)

Create `examples/supercollider/rekriate_sub.scd` containing:

1. **SynthDef `\rekriate_sub`** (FR-001, FR-009):
   - Args: `freq` (Hz), `amp` (0-1), `dur` (seconds), `cutoff` (Hz), `porta` (portamento lag time), `gate` (for all_notes_off)
   - Oscillator: `Saw` or `Pulse` (classic subtractive source)
   - Filter: `MoogFF` or `RLPF` with envelope controlling cutoff — velocity maps to both amplitude and filter cutoff (FR-009)
   - Amplitude envelope: `EnvGen.kr(Env.perc(0.01, dur), doneAction: 2)` — self-freeing after duration (US1-AS3)
   - Frequency with lag: `Lag.kr(freq, porta)` for portamento (FR-005)
   - Minimum release time of 0.01s to prevent clicks on very short durations (edge case EC5)

2. **Track voice state** (FR-004, FR-005, FR-006):
   - Array of 4 track dictionaries, each tracking: active synth nodes (`List`), portamento time (`Float`)
   - `all_notes_off` frees all nodes in the track's list (FR-004)
   - Polyphonic: each `/note` creates a new node, added to track list (FR-006)

3. **OSC responders** (FR-002, FR-010):
   - 12 responders total: 4 tracks × 3 message types
   - `/rekriate/track/{1-4}/note` → create synth, add to track list, print to post window
   - `/rekriate/track/{1-4}/all_notes_off` → free all track nodes, clear list
   - `/rekriate/track/{1-4}/portamento` → update per-track portamento time
   - All responders print received messages (FR-010)

**Design decisions:**
- Use `doneAction: 2` on the amplitude envelope so synths self-free — no manual cleanup needed for timed notes
- Portamento is per-track state (not per-synth) — new synths inherit the track's current portamento time
- Node tracking via sclang-side `List` enables `all_notes_off` without server-side group queries

### Phase 2: Setup Documentation (US3)

Create `docs/supercollider-setup.md` covering (FR-007):

1. **Prerequisites**: SuperCollider 3.x installed, re.kriate running with OSC voice backend
2. **Quick start**: Open `rekriate_sub.scd` in SuperCollider IDE → Boot server → Evaluate script
3. **Configure re.kriate**: Set voice backend to OSC targeting `127.0.0.1:57120`
4. **Verify connection**: Start sequencer, hear sound
5. **Troubleshooting**: SC not listening (NetAddr check), wrong port, no sound (server not booted), latency

### Phase 3: Round-Trip Test Script (US4)

Create `examples/supercollider/test_osc_roundtrip.lua`:

1. Uses seamstress `osc.send` to send test messages to `127.0.0.1:57120`
2. Exercises all 3 message types across all 4 tracks (FR-008, SC-004):
   - Send `/note` with known MIDI note, velocity, duration
   - Send `/portamento` with known time
   - Send `/all_notes_off`
3. Prints summary of sent messages and expected behavior (SC-004)
4. Detects if SuperCollider is not responding (US4-AS2) — since OSC is UDP, the script can note that verification requires checking SC post window
5. Reports which message types were exercised (US4-AS3)

**Note**: True round-trip verification requires checking SuperCollider's post window output. The Lua script sends and reports; the user visually confirms SC received them. This matches the UDP fire-and-forget nature of OSC.

### Phase 4: Polish & Verify

1. Follow setup docs from scratch to validate SC-001 (5-minute setup)
2. Verify all 11 FRs are addressed
3. Confirm no existing files modified (SC-005)

## Complexity Tracking

No constitution violations. No complexity justifications needed.
