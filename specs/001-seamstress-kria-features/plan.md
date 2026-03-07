# Implementation Plan: Complete Seamstress Kria Sequencer

**Branch**: `001-seamstress-kria-features` | **Date**: 2026-03-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/001-seamstress-kria-features/spec.md`

## Summary

Complete the re.kriate seamstress kria sequencer by implementing all missing features identified in the spec: extended page toggle (ratchet, alt-note, glide), direction modes, pattern storage, and ensuring 100% test coverage of lib/ modules. All work follows TDD red-green-refactor, uses dependency injection, and lands via PRs.

## Technical Context

**Language/Version**: Lua 5.4 (seamstress v1.4.7 runtime)
**Primary Dependencies**: seamstress v1.4.7 platform (grid, metro, clock, midi, screen, params, musicutil)
**Storage**: In-memory Lua tables (pattern storage); no disk persistence in this phase
**Testing**: busted (87 existing tests pass; target 100% public function coverage)
**Target Platform**: seamstress v1.4.7 on macOS (`/opt/homebrew/opt/seamstress@1/bin/seamstress -s`)
**Project Type**: Desktop music application (monome grid + screen + MIDI)
**Performance Goals**: Grid redraws at 30fps, sequencer timing via clock.sync (jitter-free)
**Constraints**: No external dependencies beyond seamstress runtime. All state in ctx table.
**Scale/Scope**: 10 lib/ modules, 4 tracks x 8 params x 16 steps, 16 pattern slots

## Constitution Check

*GATE: All gates pass.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. No Custom Globals | PASS | Entrypoints define only platform hooks; all logic in modules |
| II. State via ctx + DI | PASS | Single ctx table, voices injected via config |
| III. Red Tests First | PASS | Mandated by spec FR-014 and SC-007; every PR must include tests |
| IV. Dual-Platform | PASS | Shared lib/, platform-specific entrypoints + seamstress/ + norns/ |
| V. Simplicity & YAGNI | PASS | Extended features are SHOULD, not MUST; implement incrementally |
| VI. Visual Aids | PASS | Screen UI displays state; HTML grid layout diagram exists |
| VII. Docs as Acceptance | PASS | Spec acceptance scenarios define done; kria-features.md has 50+ tests |
| VIII. Multiplexed Dev | PASS | Plan structured for multiclaude parallel workers with ralph loops |

## Project Structure

### Documentation (this feature)

```text
specs/001-seamstress-kria-features/
  plan.md              # This file
  spec.md              # Feature specification
  research.md          # Phase 0 research decisions
  data-model.md        # Phase 1 data model
  quickstart.md        # Phase 1 quickstart guide
  contracts/
    module-interfaces.md  # Module API contracts
  checklists/
    requirements.md    # Spec quality checklist
```

### Source Code (repository root)

```text
lib/
  app.lua              # App init, params, cleanup
  track.lua            # Track data model (add extended params, direction)
  sequencer.lua        # Clock engine (add ratchet, alt-note, glide, direction)
  grid_ui.lua          # Grid UI (add extended page toggle, extended page displays)
  scale.lua            # Scale quantization (unchanged)
  pattern.lua          # NEW: Pattern storage and recall
  direction.lua        # NEW: Direction mode advance logic
  voices/
    midi.lua           # MIDI voice (add portamento CC support)
    recorder.lua       # Test voice (add portamento event capture)
  norns/
    nb_voice.lua       # norns voice (unchanged this phase)
  seamstress/
    screen_ui.lua      # Screen display (enhance with more state info)
    keyboard.lua       # Keyboard input (add extended page toggle keys)

specs/
  track_spec.lua           # Track model tests (add direction, extended params)
  sequencer_spec.lua       # Sequencer tests (add ratchet, direction, mute behavior)
  grid_ui_spec.lua         # Grid UI tests (add extended toggle, extended pages)
  scale_spec.lua           # Scale tests (unchanged)
  pattern_spec.lua         # NEW: Pattern storage tests
  direction_spec.lua       # NEW: Direction mode tests
  midi_voice_spec.lua      # MIDI voice tests (add portamento)
  recorder_voice_spec.lua  # Recorder voice tests
  screen_ui_spec.lua       # Screen UI tests
  keyboard_spec.lua        # Keyboard input tests
  app_spec.lua             # Integration tests
```

**Structure Decision**: Flat lib/ with voices/ and platform/ subdirectories. No new directories needed -- just new files `pattern.lua` and `direction.lua`.

## Implementation Strategy

### Orchestration: Ralph + MultiClaude

Work is broken into independent, PR-sized tasks. Each task can be assigned to a multiclaude worker running ralph internally for the full hat loop (Researcher -> Musician -> Lua Wizard -> Tester -> Musician -> Refactorer).

**Phase 0 (Sequential)**: CI setup -- must land first as all subsequent PRs depend on it.

**Phase 1 (Parallel Wave 1)**: Independent module-level features that don't touch the same files:
- direction.lua (new file)
- pattern.lua (new file)
- track.lua extended params
- midi voice portamento

**Phase 2 (Parallel Wave 2)**: Features that integrate Phase 1 work:
- Extended page toggle in grid_ui.lua
- Sequencer integration (ratchet, alt-note, glide, direction)
- Muted track behavior fix

**Phase 3 (Parallel Wave 3)**: UI and polish:
- Extended page grid displays (ratchet, alt-note, glide pages)
- Screen UI enhancements
- Keyboard extended page support

**Phase 4 (Sequential)**: Integration testing and final PR.

### Task Breakdown

Each task below is a standalone PR with its own branch, tests, and implementation.

---

#### Task 0: CI Pipeline Setup
**Priority**: BLOCKER (all other tasks depend on this)
**Branch**: `ci-pipeline`
**Files**: `.github/workflows/test.yml`
**Scope**: Set up GitHub Actions with:
1. Install Lua 5.4 + luarocks
2. Install busted
3. `luac -p` lint on all .lua files
4. `busted specs/` test run
5. Report coverage (list untested public functions)

**Acceptance**: Push to any branch triggers CI; all 87 existing tests pass in CI.

---

#### Task 1: Direction Mode Module
**Priority**: P3 (FR-016)
**Branch**: `add-direction-modes`
**Files**: `lib/direction.lua` (new), `specs/direction_spec.lua` (new)
**Scope**:
- Create `direction.lua` with `advance(param, direction)` function
- 5 modes: forward, reverse, pendulum, drunk, random
- Pendulum needs `advancing_forward` state on param
- All modes respect loop_start/loop_end boundaries
- Tests: one per direction mode, edge cases (single-step loop, wrap behavior)

**Dependencies**: None (new files only)
**Parallelizable**: Yes (Wave 1)

---

#### Task 2: Pattern Storage Module
**Priority**: P3 (FR-017)
**Branch**: `add-pattern-storage`
**Files**: `lib/pattern.lua` (new), `specs/pattern_spec.lua` (new)
**Scope**:
- Create `pattern.lua` with `new_slots()`, `save(ctx, slot)`, `load(ctx, slot)`, `is_populated(patterns, slot)`
- Deep-copy all track state (params, division, muted, direction)
- 16 slots
- Tests: save/load roundtrip, verify independence (modifying after save doesn't affect saved data)

**Dependencies**: None (new files only)
**Parallelizable**: Yes (Wave 1)

---

#### Task 3: Extended Params in Track Model
**Priority**: P2-P3 (FR-015, FR-018-020)
**Branch**: `add-extended-track-params`
**Files**: `lib/track.lua`, `specs/track_spec.lua`
**Scope**:
- Add "ratchet", "alt_note", "glide" to PARAM_NAMES
- Add CORE_PARAMS and EXTENDED_PARAMS lists
- Default values: ratchet=1, alt_note=1, glide=1
- Update `new_track()` to initialize extended params
- Update `new_tracks()` accordingly
- Add `direction` field to track (default "forward")
- Tests: verify extended params exist, default values correct

**Dependencies**: None
**Parallelizable**: Yes (Wave 1)

---

#### Task 4: MIDI Voice Portamento
**Priority**: P3 (FR-018)
**Branch**: `add-voice-portamento`
**Files**: `lib/voices/midi.lua`, `lib/voices/recorder.lua`, `specs/midi_voice_spec.lua`, `specs/recorder_voice_spec.lua`
**Scope**:
- Add `set_portamento(time)` to MIDI voice (sends CC 5 + CC 65)
- Add `set_portamento(time)` to recorder voice (captures event)
- time=0 sends CC 65 off; time>0 sends CC 65 on + CC 5 = mapped value
- Tests: verify CC messages sent, recorder captures portamento events

**Dependencies**: None
**Parallelizable**: Yes (Wave 1)

---

#### Task 5: Extended Page Toggle in Grid UI
**Priority**: P2 (FR-015) -- root cause of "secondary pages don't work"
**Branch**: `add-extended-page-toggle`
**Files**: `lib/grid_ui.lua`, `specs/grid_ui_spec.lua`
**Scope**:
- Add `EXTENDED_PAGES = {trigger = "ratchet", note = "alt_note", octave = "glide"}`
- Add `extended_page` boolean to ctx initialization (in app.lua)
- Modify `nav_key`: if same page button pressed AND page has extension, toggle `ctx.extended_page`
- Switching to a different page clears `ctx.extended_page`
- `ctx.active_page` reflects the actual page name (e.g., "ratchet" when extended)
- Tests: press trigger twice -> ratchet, press again -> trigger, press note -> note (clears extended)

**Dependencies**: Task 3 (extended params must exist in track model)
**Parallelizable**: Yes (Wave 2)

---

#### Task 6: Sequencer Integration -- Direction + Ratchet + Alt-Note + Glide
**Priority**: P2-P3 (FR-016, FR-018-020)
**Branch**: `integrate-sequencer-features`
**Files**: `lib/sequencer.lua`, `specs/sequencer_spec.lua`
**Scope**:
- Use `direction.advance()` instead of `track_mod.advance()` when track has non-forward direction
- Alt-note: advance alt_note param, compute `effective_degree = ((note - 1) + (alt_note - 1)) % #scale + 1`
- Ratchet: if ratchet > 1, fire N evenly-spaced notes within step duration via nested `clock.run`
- Glide: call `voice:set_portamento(glide_value)` before `play_note`
- Tests: direction changes step sequence, ratchet produces multiple events, alt-note shifts pitch, glide sends portamento

**Dependencies**: Tasks 1, 3, 4
**Parallelizable**: Yes (Wave 2)

---

#### Task 7: Fix Muted Track Behavior
**Priority**: P2 (matches original kria)
**Branch**: `fix-mute-advance`
**Files**: `lib/sequencer.lua`, `specs/sequencer_spec.lua`
**Scope**:
- Muted tracks advance all param playheads but suppress note output
- Currently `step_track` returns early on mute -- change to advance without firing
- Tests: mute track, step N times, verify playhead positions advanced

**Dependencies**: None (can be done against current codebase)
**Parallelizable**: Yes (Wave 2, but touches sequencer.lua -- coordinate with Task 6)

---

#### Task 8: Extended Page Grid Displays
**Priority**: P2-P3
**Branch**: `add-extended-page-displays`
**Files**: `lib/grid_ui.lua`, `specs/grid_ui_spec.lua`
**Scope**:
- Add `draw_ratchet_page(ctx, g)` -- same bar-graph layout as value pages, values 1-7
- Add `draw_alt_note_page(ctx, g)` -- same bar-graph layout, values 1-7
- Add `draw_glide_page(ctx, g)` -- same bar-graph layout, values 1-7
- Update `redraw()` to dispatch to extended page draw functions when `ctx.active_page` is an extended page name
- Update `grid_key` to handle value editing on extended pages
- Tests: verify LED output for each extended page, verify editing sets correct param values

**Dependencies**: Tasks 3, 5
**Parallelizable**: Yes (Wave 3)

---

#### Task 9: Screen UI Enhancements
**Priority**: P2 (FR-009)
**Branch**: `enhance-screen-ui`
**Files**: `lib/seamstress/screen_ui.lua`, `specs/screen_ui_spec.lua`
**Scope**:
- Show per-track step positions (step N/loop_end) for all 4 tracks
- Show extended page indicator when active
- Show pattern slot number if patterns are in use
- Use color coding for track/page state
- Tests: verify screen_ui.redraw produces correct calls for various ctx states

**Dependencies**: None (reads ctx, doesn't modify it)
**Parallelizable**: Yes (Wave 3)

---

#### Task 10: Keyboard Extended Page Support
**Priority**: P2
**Branch**: `keyboard-extended-pages`
**Files**: `lib/seamstress/keyboard.lua`, `specs/keyboard_spec.lua`
**Scope**:
- Pressing the same page key twice toggles extended page (same logic as grid nav)
- Track last pressed key to detect double-press
- Tests: press 'q' twice -> ratchet, press 'w' -> note (clears extended)

**Dependencies**: Task 5 (extended page toggle logic)
**Parallelizable**: Yes (Wave 3)

---

#### Task 11: Integration Testing
**Priority**: P1
**Branch**: `integration-tests`
**Files**: `specs/integration_spec.lua`
**Scope**:
- End-to-end test: init app, start sequencer, step through pattern, verify MIDI output
- Test extended page toggle -> edit ratchet -> play -> verify ratcheted output
- Test pattern save/load roundtrip during playback
- Test direction modes produce expected step sequences during playback
- Verify 100% public function coverage across all lib/ modules

**Dependencies**: All previous tasks
**Parallelizable**: No (final task)

---

### Execution Schedule

```
Wave 0 (Sequential):  Task 0 (CI)
                         |
Wave 1 (Parallel):    Task 1  Task 2  Task 3  Task 4
                       dir     pat    track    voice
                         \       \      |      /
Wave 2 (Parallel):    Task 5  Task 6  Task 7
                       toggle  seq     mute
                         \      |      /
Wave 3 (Parallel):    Task 8  Task 9  Task 10
                       grids  screen  keyboard
                         \      |      /
Wave 4 (Sequential):  Task 11 (Integration)
```

### MultiClaude Dispatch Plan

```bash
# Wave 0: CI (single worker)
/mc work "Set up GitHub Actions CI: Lua 5.4, busted, luac lint. See plan Task 0."

# Wave 1: Independent modules (4 parallel workers)
/mc swarm \
  "Create lib/direction.lua with 5 direction modes + tests. See plan Task 1." \
  "Create lib/pattern.lua with save/load/16 slots + tests. See plan Task 2." \
  "Add extended params (ratchet, alt_note, glide) + direction to track.lua + tests. See plan Task 3." \
  "Add portamento CC support to midi + recorder voices + tests. See plan Task 4."

# Wave 2: Integration features (3 parallel workers, Task 7 may need sequencing with Task 6)
/mc swarm \
  "Add extended page toggle to grid_ui.lua (double-press nav). See plan Task 5." \
  "Integrate direction, ratchet, alt-note, glide into sequencer.lua. See plan Task 6." \
  "Fix muted tracks to advance playheads silently. See plan Task 7."

# Wave 3: UI polish (3 parallel workers)
/mc swarm \
  "Add ratchet/alt-note/glide page displays to grid_ui.lua. See plan Task 8." \
  "Enhance screen_ui.lua with per-track positions + colors. See plan Task 9." \
  "Add keyboard extended page toggle support. See plan Task 10."

# Wave 4: Final integration
/mc work "Full integration tests + coverage verification. See plan Task 11."
```

Each worker runs ralph internally for the full hat loop on its task.

## Complexity Tracking

No constitution violations. All work follows established patterns (ctx, DI, TDD, busted).

| Decision | Rationale |
|----------|-----------|
| Simplified ratchet (value 1-7 vs sub-trigger grid) | YAGNI: bar-graph UI is simpler, matches existing pages. Full sub-trigger grid can be added later. |
| Per-track direction (not per-param) | Matches original kria. Per-param direction adds complexity without clear musical benefit. |
| No scale page on grid this phase | Scale editing via params works. Grid scale editor is complex (interval editing) and lower priority. |
| No pattern page on grid this phase | Pattern save/load API exists for integration testing. Grid UI for patterns is separate scope. |
| No probability modifier this phase | Not in spec. Can be added as a future feature. |
