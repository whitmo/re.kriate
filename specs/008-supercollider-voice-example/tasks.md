# Tasks: SuperCollider Voice Example

**Input**: Design documents from `/specs/008-supercollider-voice-example/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: No busted tests — Constitution Principle III is N/A (no sequencing logic changes). The round-trip test script (US4) is itself a deliverable, not a preceding test task.

**Organization**: Tasks grouped by user story. Only 3 new files created — no existing files modified (SC-005).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create directory structure for SuperCollider example files

- [x] T001 Create `examples/supercollider/` directory for SC deliverables

---

## Phase 2: User Story 1 — Play Notes from re.kriate in SuperCollider (Priority: P1) — MVP

**Goal**: A companion SuperCollider script receives OSC messages from re.kriate and plays notes through a subtractive synth — correct pitch, velocity, duration, with polyphony and all_notes_off support.

**Independent Test**: Start the SC script, send `/rekriate/track/1/note 60 100 0.5` via OSC — hear middle C at high velocity for 0.5s. Send notes on tracks 1-4 simultaneously — hear 4 independent voices. Send `/all_notes_off` — silence.

### Implementation for User Story 1

- [x] T002 [US1] Create SynthDef `\rekriate_sub` in `examples/supercollider/rekriate_sub.scd` — `Saw` oscillator → `RLPF` filter → `EnvGen(Env.perc)` amplitude envelope with `doneAction: 2` (self-freeing). Args: `freq` (440 Hz default), `amp` (0.5), `dur` (0.5s), `cutoff` (2000 Hz), `porta` (0.0s), `gate` (1). Velocity maps to both `amp` (vel/127) and `cutoff` (vel.linlin 0-127 → 400-8000 Hz) per FR-009. Frequency uses `Lag.kr(\freq.kr, \porta.kr)` for portamento support. Minimum envelope release of 0.01s to prevent clicks on short durations (EC5).
- [x] T003 [US1] Add track voice state and OSC responders to `examples/supercollider/rekriate_sub.scd` — Initialize array of 4 track dictionaries each with `nodes` (List) and `portaTime` (0.0). Register 8 OSC responders (4 tracks × 2 types): `/rekriate/track/{1-4}/note` creates synth with `freq: midi.midicps`, `amp: vel/127`, `dur: dur`, `cutoff: vel.linlin(0,127,400,8000)`, `porta: track.portaTime`, adds node to track's list with `onFree` cleanup callback; `/rekriate/track/{1-4}/all_notes_off` iterates track's node list calling `.free`, then clears list. All responders print received messages to post window (FR-010). Add startup banner: `"re.kriate listener ready on port 57120"`.

**Checkpoint**: rekriate_sub.scd plays notes from all 4 tracks with correct pitch/velocity/duration, supports polyphony (FR-006), and handles all_notes_off (FR-004).

---

## Phase 3: User Story 2 — Portamento/Glide Between Notes (Priority: P2)

**Goal**: The `/portamento` OSC message sets a per-track glide time so subsequent notes slide smoothly to the target pitch.

**Independent Test**: Send `/portamento 0.2` then two notes in quick succession on track 1 — hear frequency glide over 0.2s. Set portamento to 0 — no glide.

### Implementation for User Story 2

- [x] T004 [US2] Add `/portamento` OSC responders to `examples/supercollider/rekriate_sub.scd` — Register 4 responders for `/rekriate/track/{1-4}/portamento` that update the track's `portaTime` field. Subsequent `/note` responders already pass `porta: track.portaTime` to new synths (from T003). Print portamento changes to post window. Verify default portaTime 0.0 produces instantaneous pitch changes and non-zero values produce audible glide via `Lag.kr`.

**Checkpoint**: rekriate_sub.scd fully implements all 12 OSC responders (4 tracks × 3 message types). US1 + US2 complete.

---

## Phase 4: User Story 3 — Setup and Run the Example (Priority: P1)

**Goal**: A user who has never used SuperCollider with re.kriate reads the setup documentation and hears sound within 5 minutes (SC-001).

**Independent Test**: Follow the documentation from scratch on a machine with SuperCollider installed — verify all steps lead to working audio output.

### Implementation for User Story 3

- [x] T005 [P] [US3] Create `docs/supercollider-setup.md` — Cover: (1) Prerequisites: SuperCollider 3.x installed, re.kriate running with OSC voice backend; (2) Quick Start: open `rekriate_sub.scd` in SC IDE → boot server (Cmd+B) → evaluate (Cmd+Enter) → see "re.kriate listener ready" message; (3) Configure re.kriate: set voice backend to OSC targeting 127.0.0.1:57120; (4) Verify: start sequencer, hear sound; (5) Troubleshooting: SC not listening (check `NetAddr.langPort`), wrong port, no sound (server not booted/script not evaluated), re.kriate not using OSC voice. Reference exact file paths: `examples/supercollider/rekriate_sub.scd` and `examples/supercollider/test_osc_roundtrip.lua`.

**Checkpoint**: A new user can follow docs to hear re.kriate-driven sound from SuperCollider.

---

## Phase 5: User Story 4 — Verify OSC Round-Trip (Priority: P2)

**Goal**: A test script exercises the full OSC signal chain — sends all 3 message types across all 4 tracks and reports results.

**Independent Test**: Run the test script with SuperCollider listener active — see sent messages in terminal and received messages in SC post window.

### Implementation for User Story 4

- [x] T006 [P] [US4] Create `examples/supercollider/test_osc_roundtrip.lua` — Lua script for seamstress runtime. Uses `osc.send` to send to `{"127.0.0.1", 57120}`. Test sequence per track (1-4): (1) send `/rekriate/track/{n}/portamento` with time=0.3; (2) send `/rekriate/track/{n}/note` with midi=60+(n*4), vel=100, dur=0.5; (3) short delay; (4) send `/rekriate/track/{n}/note` with midi=64+(n*4) (to exercise portamento); (5) send `/rekriate/track/{n}/all_notes_off`. Print each sent message to stdout. After all tracks: print summary listing message types exercised (note, portamento, all_notes_off) and total messages sent. Note in output that user should check SC post window for received message confirmation (UDP is fire-and-forget). Run via: `seamstress -s examples/supercollider/test_osc_roundtrip.lua`

**Checkpoint**: Test script exercises all 3 OSC message types (SC-004) across all 4 tracks (SC-002).

---

## Phase 6: Polish & Verify

**Purpose**: End-to-end validation of all deliverables

- [x] T007 Validate `docs/supercollider-setup.md` by following quickstart steps end-to-end — confirm SC-001 (5-minute setup with SC already installed)
- [x] T008 Final verification: confirm all 11 FRs addressed, all 5 SCs met, SC-005 holds (no changes to existing `lib/`, `specs/`, or entrypoint files), and all 3 deliverable files are syntactically valid

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — creates directory
- **US1 (Phase 2)**: Depends on Phase 1 — creates rekriate_sub.scd with SynthDef + note/all_notes_off responders
- **US2 (Phase 3)**: Depends on Phase 2 — adds portamento responders to existing rekriate_sub.scd
- **US3 (Phase 4)**: Depends on Phase 1 only — docs reference file paths from spec, not file contents
- **US4 (Phase 5)**: Depends on Phase 1 only — test script sends OSC messages per data-model protocol
- **Polish (Phase 6)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Foundational — must complete before US2 (same file, sequential additions)
- **US2 (P2)**: Depends on US1 (extends rekriate_sub.scd)
- **US3 (P1)**: Independent — can run in parallel with US1/US2 (different file)
- **US4 (P2)**: Independent — can run in parallel with US1/US2 (different file)

### Parallel Opportunities

**Swarm Block 1** (after T001 completes): T002+T003 sequence (US1, rekriate_sub.scd) can run in parallel with T005 (US3, docs) and T006 (US4, test script):

```
Worker A: T002 → T003 → T004  (examples/supercollider/rekriate_sub.scd)
Worker B: T005                 (docs/supercollider-setup.md)
Worker C: T006                 (examples/supercollider/test_osc_roundtrip.lua)
```

All 3 workers touch different files with no data dependencies. Each worker draws implementation details from spec.md and data-model.md.

**Swarm Block 2** (after all stories complete): T007 + T008 (sequential — validation requires all files).

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (create directory)
2. Complete Phase 2: US1 (SynthDef + note/all_notes_off responders)
3. **STOP and VALIDATE**: Send OSC note messages manually — hear sound from SuperCollider
4. This alone demonstrates the core value: re.kriate driving SuperCollider audio

### Incremental Delivery

1. Setup + US1 → Hear notes from SuperCollider (MVP)
2. Add US2 → Portamento glide between notes
3. Add US3 → Users can set up the example from docs
4. Add US4 → Automated verification of the signal chain
5. Polish → End-to-end validation of all deliverables

### Parallel Dispatch (3 workers)

With multiclaude/worktree isolation:
1. All workers start after T001 (Setup)
2. Worker A: US1 → US2 (same file, sequential) — `rekriate_sub.scd`
3. Worker B: US3 — `supercollider-setup.md`
4. Worker C: US4 — `test_osc_roundtrip.lua`
5. Merge all 3 workers, then Phase 6 (Polish)

---

## Requirement Traceability

| Requirement | Task(s) | Deliverable |
|-------------|---------|-------------|
| FR-001 (SynthDef) | T002 | rekriate_sub.scd |
| FR-002 (OSC responders) | T003, T004 | rekriate_sub.scd |
| FR-003 (/note handler) | T003 | rekriate_sub.scd |
| FR-004 (all_notes_off) | T003 | rekriate_sub.scd |
| FR-005 (portamento) | T004 | rekriate_sub.scd |
| FR-006 (polyphony) | T003 | rekriate_sub.scd |
| FR-007 (setup docs) | T005 | supercollider-setup.md |
| FR-008 (test script) | T006 | test_osc_roundtrip.lua |
| FR-009 (velocity→amp+cutoff) | T002 | rekriate_sub.scd |
| FR-010 (post window logging) | T003, T004 | rekriate_sub.scd |
| FR-011 (default port 57120) | T002, T003, T004, T006 | rekriate_sub.scd, test_osc_roundtrip.lua |
| SC-001 (5-min setup) | T005, T007 | supercollider-setup.md |
| SC-002 (4-track verify) | T006 | test_osc_roundtrip.lua |
| SC-003 (portamento verify) | T006 | test_osc_roundtrip.lua |
| SC-004 (3 message types) | T006 | test_osc_roundtrip.lua |
| SC-005 (no existing files) | T008 | (verification only) |

---

## Notes

- No busted tests — this is an example/documentation feature, not core library code
- All 3 deliverable files can be written from spec + data-model alone (OSC protocol is well-defined)
- [P] tasks touch different files with no data dependencies
- SuperCollider syntax should be idiomatic sclang (parentheses for blocks, dot notation for methods)
- The test script runs under seamstress, not busted — it uses `osc.send` for real UDP messaging
