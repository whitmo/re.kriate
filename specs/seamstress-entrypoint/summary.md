# Summary: Seamstress Entrypoint for re.kriate

## Artifacts

| File | Description |
|------|-------------|
| `specs/seamstress-entrypoint/rough-idea.md` | Original idea from PROMPT.md |
| `specs/seamstress-entrypoint/requirements.md` | 10 Q&A pairs refining scope and decisions |
| `specs/seamstress-entrypoint/research/` | 6 research documents |
| `specs/seamstress-entrypoint/research/midi-timing.md` | MIDI note-off timing strategies |
| `specs/seamstress-entrypoint/research/crow-timeline.md` | Timeline library as event model |
| `specs/seamstress-entrypoint/research/dual-platform.md` | Norns/seamstress compatibility patterns |
| `specs/seamstress-entrypoint/research/test-voices.md` | Recorder voice and test strategies |
| `specs/seamstress-entrypoint/research/drum-tracks-and-recording.md` | Drum UI, live recording, unusual voices |
| `specs/seamstress-entrypoint/research/seamstress-v2-api.md` | Verified seamstress 2.0 API availability |
| `specs/seamstress-entrypoint/design.md` | Full design: architecture, interfaces, data models, acceptance criteria |
| `specs/seamstress-entrypoint/plan.md` | 8-step incremental implementation plan |
| `specs/seamstress-entrypoint/summary.md` | This file |

## Overview

The project adds seamstress as a first-class platform for re.kriate by:

1. Creating a **voice abstraction layer** (`play_note` interface) with MIDI and recorder backends, injected into ctx
2. **Refactoring shared modules** (sequencer, app) to be platform-agnostic — no nb dependency in the core
3. Building a **seamstress entrypoint** with minimal screen UI and keyboard fallback
4. Wrapping **nb into the voice interface** so the norns entrypoint continues working unchanged
5. A **5-layer test strategy** from unit tests to manual end-to-end verification

Current seamstress interaction notes:
- Grid nav `x=11` opens the probability page.
- Grid nav `x=15` opens the alt-track page for direction/division/swing/mute edits.
- `Ctrl+P` jumps to probability from the keyboard.
- Right-click on simulated-grid nav `x=12` / `x=14` latches loop/pattern holds.

**Success:** `seamstress -s seamstress.lua` opens, grid lights up, sequencer plays MIDI notes, keyboard controls work, clean stop.

## Key Decisions

- Separate entrypoints (not runtime detection) — proven community pattern
- Voice objects on ctx (not nb, not direct MIDI calls) — testable, platform-agnostic
- MIDI note-off via `clock.run` + `clock.sync` — beat-relative, no slot limits
- Recorder voice powers both automated tests and future piano roll visualization
- Shared code refactorable freely — both entrypoints adapt
- Grid code shared as-is (identical API on both platforms)
- Screen code separate per platform (APIs too different to abstract)

## Next Steps

- Implement the 8-step plan
- Or use Ralph for autonomous implementation via the PROMPT.md below
