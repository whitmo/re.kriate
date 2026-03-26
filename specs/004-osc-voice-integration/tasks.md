# Tasks: OSC Voice Integration (004)

**Input**: Design documents from `specs/004-osc-voice-integration/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: TDD is NON-NEGOTIABLE per constitution principle III. Every implementation task MUST be preceded by a test task that writes failing tests first. Tests live in `specs/osc_voice_spec.lua`. Run with: `busted --no-auto-insulate specs/`

**Organization**: Tasks are grouped by phase/user story. Phase 1 ∥ Phase 2 (independent param groups). Phase 5 verification tasks are independent of Phase 3-4 implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different describe blocks, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify baseline and create new spec file

- [x] T001 Verify baseline: run `busted --no-auto-insulate specs/` — all 512 tests pass, 0 failures
- [x] T002 Create empty `specs/osc_voice_spec.lua` test file with package.path setup, mock `clock`, mock `params` (matching `specs/integration_spec.lua` pattern), mock `osc.send`, and require `lib/voices/osc`, `lib/voices/midi`

**Checkpoint**: Baseline green, new spec file exists, `busted` still passes

---

## Phase 2: Voice Backend Param (FR-001, FR-008)

**Purpose**: Add per-track "voice backend" option param to `seamstress.lua`, defaulting to MIDI

**Independent Test**: After `app.init`, verify `params:get("voice_backend_1")` returns 1 (midi index)

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T003 [P] [US2] Test that after seamstress init, `params:get("voice_backend_1")` exists and defaults to 1 (midi) in `specs/osc_voice_spec.lua`
- [x] T004 [P] [US2] Test that all 4 tracks have `voice_backend_{t}` params (t=1..4), all defaulting to 1 in `specs/osc_voice_spec.lua`
- [x] T005 [P] [US2] Test backward compatibility: with default params (all midi), `ctx.voices[1]` through `ctx.voices[4]` are MIDI voices (have `midi_dev` field) in `specs/osc_voice_spec.lua`

### Implementation

- [x] T006 [US2] Add `params:add_option("voice_backend_" .. t, "track " .. t .. " voice", {"midi", "osc"}, 1)` for t=1..4 in `seamstress.lua` after MIDI separator, inside a new "Voice" separator. Tests T003-T005 must pass.

**Checkpoint**: Voice backend params exist for all 4 tracks, default to midi. Backward compat preserved.

---

## Phase 3: OSC Target Params (FR-003, FR-009)

**Purpose**: Add per-track "osc host" and "osc port" params to `seamstress.lua`

**Independent Test**: After init, `params:get("osc_host_1")` returns "127.0.0.1" and `params:get("osc_port_1")` returns 57120

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T007 [P] [US3] Test that after init, `params:get("osc_host_1")` returns "127.0.0.1" and `params:get("osc_port_1")` returns 57120 in `specs/osc_voice_spec.lua`
- [x] T008 [P] [US3] Test that all 4 tracks have `osc_host_{t}` and `osc_port_{t}` params with correct defaults in `specs/osc_voice_spec.lua`
- [x] T009 [P] [US3] Test that `osc_port_{t}` param is constrained to range 1-65535 (verify param definition min/max) in `specs/osc_voice_spec.lua`

### Implementation

- [x] T010 [US3] Add per-track `osc_host_{t}` (text param, default "127.0.0.1") and `osc_port_{t}` (number param, range 1-65535, default 57120) in `seamstress.lua`. Tests T007-T009 must pass.

**Checkpoint**: OSC target params exist for all 4 tracks with correct defaults and constraints.

---

## Phase 4: Voice Swap on Backend Change (FR-002, FR-004) — Core Feature

**Purpose**: Wire voice backend param action to swap voice instance on `ctx.voices[t]`, with `all_notes_off` on the outgoing backend

**Independent Test**: Set `voice_backend_1` to 2 (osc), verify `ctx.voices[1]` is an OSC voice and `all_notes_off` was called on the outgoing MIDI voice

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T011 [US4] Test that changing `voice_backend_1` from midi to osc calls `all_notes_off()` on the outgoing MIDI voice in `specs/osc_voice_spec.lua`
- [x] T012 [US4] Test that after changing `voice_backend_1` to osc, `ctx.voices[1]` is an OSC voice (has `track_num` field, responds to `play_note`) in `specs/osc_voice_spec.lua`
- [x] T013 [US1] Test that after switching to osc, calling `ctx.voices[1]:play_note(60, 0.8, 1)` triggers `osc.send` with path `/rekriate/track/1/note` and args `{60, 0.8, 1}` in `specs/osc_voice_spec.lua`
- [x] T014 [US4] Test that changing `voice_backend_1` from osc back to midi calls `all_notes_off()` on the outgoing OSC voice, and `ctx.voices[1]` is a MIDI voice again in `specs/osc_voice_spec.lua`
- [x] T015 [US2] Test that track 1 on midi and track 2 on osc can coexist — `ctx.voices[1]` is MIDI, `ctx.voices[2]` is OSC in `specs/osc_voice_spec.lua`
- [x] T016 [US1] Test that OSC voice uses current host/port params: set `osc_host_1` to "10.0.0.1" and `osc_port_1` to 7400 before switching to osc, verify `osc.send` target is `{"10.0.0.1", 7400}` in `specs/osc_voice_spec.lua`

### Implementation

- [x] T017 [US4] Add voice backend param action in `seamstress.lua`: on change, call `all_notes_off()` on current `ctx.voices[t]`, create new voice instance (MIDI via `midi_voice.new(midi_dev, channel)` or OSC via `osc.new(t, host, port)` using current param values), assign to `ctx.voices[t]`. Store `midi_dev` as local in init scope per research decision 6. Require `lib/voices/osc` at top of file. Tests T011-T016 must pass.

**Checkpoint**: Voice swap works in both directions (midi→osc, osc→midi), all_notes_off fires on outgoing, new voice receives notes. Mixed backends across tracks work.

---

## Phase 5: OSC Target Update on Param Change (FR-005)

**Purpose**: Wire osc host/port param actions to call `set_target` on the active OSC voice, no-op when backend is MIDI

**Independent Test**: With backend=osc, change `osc_port_1` to 7400, verify `set_target` called with new values

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation**

- [x] T018 [US3] Test that changing `osc_port_1` while backend is osc calls `set_target("127.0.0.1", new_port)` on `ctx.voices[1]` in `specs/osc_voice_spec.lua`
- [x] T019 [US3] Test that changing `osc_host_1` while backend is osc calls `set_target(new_host, 57120)` on `ctx.voices[1]` in `specs/osc_voice_spec.lua`
- [x] T020 [US3] Test that changing `osc_port_1` while backend is midi does NOT call `set_target` (no-op) in `specs/osc_voice_spec.lua`
- [x] T021 [US3] Test that after changing host/port and then calling `play_note`, the OSC message goes to the updated target in `specs/osc_voice_spec.lua`

### Implementation

- [x] T022 [US3] Add param actions for `osc_host_{t}` and `osc_port_{t}` in `seamstress.lua`: if `params:get("voice_backend_" .. t) == 2` (osc), call `ctx.voices[t]:set_target(host, port)` using current param values. Otherwise no-op. Tests T018-T021 must pass.

**Checkpoint**: OSC target updates live when backend is osc. No-op when backend is midi.

---

## Phase 6: Sprite Voice Continuity & Platform Guard (FR-006, FR-007)

**Purpose**: Verify sprite voices remain additive alongside any audio backend, and OSC params are seamstress-only

### Tests

> **Write these tests FIRST, ensure they FAIL before implementation (verification tests that confirm existing behavior)**

- [x] T023 [P] [US5] Test that after switching track 1 to osc, `ctx.sprite_voices[1]` is unchanged and still functional in `specs/osc_voice_spec.lua`
- [x] T024 [P] [US5] Test that `seamstress.lua` creates `voice_backend_{t}` params (already verified in T003, but verify here that seamstress specifically creates them)
- [x] T025 [P] [US5] Test that the norns entrypoint (`re_kriate.lua`) does NOT create `voice_backend_{t}` or `osc_host_{t}` or `osc_port_{t}` params — verify by reading the file for those param IDs, or by loading and checking `params:get` returns nil in `specs/osc_voice_spec.lua`

**Checkpoint**: Sprite voices are never affected by backend swap. OSC params are seamstress-only.

---

## Phase 7: Edge Cases & Integration (SC-001 through SC-005)

**Purpose**: Verify edge case handling and full integration across all user stories

### Tests

> **Write these tests FIRST — these are integration/edge-case verification tests**

- [x] T026 [US4] Test backend switch mid-play: with sequencer running (mocked), switch backend — verify `all_notes_off` on outgoing, next note fires on new backend in `specs/osc_voice_spec.lua`
- [x] T027 [US3] Test shared host/port across tracks: set tracks 1 and 2 both to osc with same host/port — verify both send correctly with different OSC paths (`/rekriate/track/1/...` vs `/rekriate/track/2/...`) in `specs/osc_voice_spec.lua`
- [x] T028 [US4] Test cleanup with OSC voices active: set track 1 to osc, call `app.cleanup(ctx)` — verify `all_notes_off` is called on the OSC voice in `specs/osc_voice_spec.lua`
- [x] T029 [US1] [US2] Test full 4-track mixed scenario: tracks 1,3 on midi, tracks 2,4 on osc — fire notes on all 4 tracks, verify MIDI voices get `note_on` and OSC voices get `osc.send` in `specs/osc_voice_spec.lua`
- [x] T030 [US1] Test OSC portamento: set track to osc, call `set_portamento(3)` — verify `osc.send` with path `/rekriate/track/{t}/portamento` and args `{3}` in `specs/osc_voice_spec.lua`
- [x] T031 Verify full regression: run `busted --no-auto-insulate specs/` — all 512+ existing tests pass plus 15+ new tests, 0 failures

**Checkpoint**: All edge cases pass. All existing tests still green. SC-001 through SC-005 met.

---

## Summary

| Phase | Tasks | Test Tasks | Impl Tasks | Setup Tasks |
|-------|-------|------------|------------|-------------|
| 1: Setup | T001-T002 | 0 | 0 | 2 |
| 2: Backend Param | T003-T006 | 3 | 1 | 0 |
| 3: OSC Target Params | T007-T010 | 3 | 1 | 0 |
| 4: Voice Swap | T011-T017 | 6 | 1 | 0 |
| 5: Target Update | T018-T022 | 4 | 1 | 0 |
| 6: Platform Guard | T023-T025 | 3 | 0 | 0 |
| 7: Edge Cases | T026-T031 | 6 | 0 | 0 |
| **Total** | **31** | **25** | **4** | **2** |

### Parallel Opportunities

- Phase 2 ∥ Phase 3 (independent param groups, different describe blocks in same spec file)
- Phase 6 verification tasks (T023-T025) are all [P] and independent of Phase 4-5
- Edge case tests T026-T030 are all independent [P]

### TDD Compliance

- Every implementation task (T006, T010, T017, T022) preceded by test tasks
- 25 test tasks, 4 implementation tasks, 2 setup tasks
- Tests written in `specs/osc_voice_spec.lua`
- SC-004 requires 15+ new tests — 25 test tasks exceeds this

### FR Coverage

| FR | Tasks |
|----|-------|
| FR-001 (backend param) | T003-T006 |
| FR-002 (OSC note output) | T011-T017 |
| FR-003 (target params) | T007-T010 |
| FR-004 (all_notes_off on swap) | T011, T014, T017 |
| FR-005 (target update on change) | T018-T022 |
| FR-006 (seamstress-only) | T024-T025 |
| FR-007 (sprite continuity) | T023 |
| FR-008 (MIDI default) | T005, T006 |
| FR-009 (port range) | T009, T010 |

### SC Coverage

| SC | Verification |
|----|-------------|
| SC-001 (4-track OSC output) | T029 |
| SC-002 (no stuck notes on switch) | T011, T014, T026 |
| SC-003 (MIDI default preserved) | T005, T006 |
| SC-004 (15+ new tests) | 25 test tasks |
| SC-005 (512+ existing pass) | T031 |

### Edge Case Coverage

| Edge Case | Task |
|-----------|------|
| Unreachable host (fire-and-forget) | Inherent in OSC/UDP — no test needed |
| Mid-play backend switch | T026 |
| Shared host/port across tracks | T027 |
| Cleanup with OSC active | T028 |
| Invalid port | T009 (param range constraint) |
