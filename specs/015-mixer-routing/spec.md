# Feature Specification: Mixer Page + Audio Routing Layer

**Branch**: `015-mixer-routing`
**Bead**: re-kev
**Created**: 2026-04-13
**Status**: Implemented
**Input**: "Add a mixer/controller grid page and voice-level mixing controls to re.kriate."

## User Stories

### US1 — Per-Track Level on the Grid (P1)

As a performer, I want to set per-track output level on the grid without
leaving performance context so I can mix live while the sequencer runs.

- Independent test: Switch to the mixer page, tap column 1 on row 1, play back
  — track 1 notes are silenced. Tap column 7 — track 1 returns to full level.
- Acceptance:
  1. Mixer page is a first-class grid page listed in `grid_ui.PAGES`.
  2. Row 1..4 maps to tracks 1..4. Columns 1..7 are a level bar (col 1 = 0.0,
     col 7 = 1.0).
  3. Tapping a level column immediately updates `ctx.mixer.level[t]` and is
     reflected in the corresponding `level_<t>` param.
  4. Level is applied as a velocity multiplier in `sequencer.play_note` before
     the voice receives the note.

### US2 — Per-Track Pan (P1)

As a performer, I want to pan each track independently so the mix has spatial
separation.

- Independent test: Set track 2 pan to col 9 (hard left). Route to a stereo
  backend (MIDI CC10 or SC synth). Confirm signal lands only on the left bus.
- Acceptance:
  1. Columns 9..15 on the mixer page form a pan strip (col 9 = hard left,
     col 12 = center, col 15 = hard right).
  2. Pan edits update `ctx.mixer.pan[t]` and the `pan_<t>` param.
  3. Pan is pushed to the active voice via `voice:set_pan` whenever it
     changes or when the voice is rebuilt (backend swap, reload).

### US3 — Per-Track Mute in the Mix Context (P1)

As a performer, I want a dedicated mute cell on the mixer page.

- Acceptance:
  1. Column 16 on each track row toggles `ctx.tracks[t].muted`.
  2. Mute state is the single authoritative flag — the existing `NAV_MUTE`
     button and alt-track page continue to drive the same field.

### US4 — External Routing Compatibility (P2)

As a performer using seamstress on macOS, I want to route the mixer outputs
through SuperCollider (with BlackHole as an aggregate device) so I can mix
SC synths, softcut samples, and external MIDI gear into one stereo bus.

- Acceptance:
  1. `docs/routing.md` documents the recommended setup: MIDI CC7/CC10 for
     hardware; SC mixer OSC paths for SC synth and drum voices; softcut level/
     pan primitives for sample playback; BlackHole/aggregate device for
     monitoring.
  2. OSC paths are stable and namespaced per backend.

### US5 — Remote OSC Control (P2)

As a developer building an external controller (touchscreen, tablet, DAW),
I want an OSC surface for the mixer so I can drive levels, pans, and mutes
without going through grid_ui.

- Acceptance:
  1. `/mixer/level <track> [<value>]`, `/mixer/pan <track> [<value>]`,
     `/mixer/mute <track> [<0|1>]` — set or query. Values use float units
     (level in `[0, 1]`, pan in `[-1, 1]`).
  2. `/mixer/get` returns a full mixer snapshot (`{level, pan, mute}`).
  3. `/state/snapshot` includes the mixer snapshot so a cold-booted remote UI
     can render the initial mix.

## Requirements

### Functional

- **FR-001**: Each voice backend (midi, osc, sc_synth, sc_drums, softcut) must
  implement `voice:set_level(val)` and `voice:set_pan(val)` with the following
  transport mappings:
  - MIDI → CC 7 (level) and CC 10 (pan), scaled to 0..127 on the voice channel.
  - OSC → `/rekriate/track/{n}/level`, `/rekriate/track/{n}/pan`.
  - SC synth → `/rekriate/synth/{n}/level`, `/rekriate/synth/{n}/pan`.
  - SC drums → `/rekriate/track/{n}/drum_level`, `/rekriate/track/{n}/drum_pan`.
  - Softcut → `softcut.level(voice, v)` and `softcut.pan(voice, v)` via the
    injected runtime.
- **FR-002**: Each backend must clamp inputs (`level` to `[0, 1]`, `pan` to
  `[-1, 1]`) before transmission.
- **FR-003**: `lib/mixer.lua` owns mixer state; `ctx.mixer = {level, pan}` is
  the float-unit source of truth. Mute remains on `ctx.tracks[t].muted`.
- **FR-004**: Params `level_<t>` (0–100), `pan_<t>` (-100..100), and
  `mute_<t>` (off/on) exist per track in the "mixer" group, and their actions
  delegate to `mixer.set_level / set_pan / set_mute`.
- **FR-005**: Rebuilding a voice (voice type change, MIDI channel change,
  softcut sample change) must re-apply current mixer level/pan to the new
  voice object via `mixer.apply_to_voice`.
- **FR-006**: `sequencer.play_note` scales the step velocity by
  `ctx.mixer.level[t]` and clamps the result to `[0, 1]` before dispatching to
  the voice.
- **FR-007**: `grid_ui` adds a `mixer` page. The page lists in `grid_ui.PAGES`
  and sits in the `x=9` nav cycle alongside duration/velocity/probability.
- **FR-008**: Mixer page layout:
  - rows 1..4 = tracks 1..4
  - cols 1..7 = level bar
  - cols 9..15 = pan bar
  - col 16 = mute
- **FR-009**: Remote API (`lib/remote/api.lua`) exposes `/mixer/level`,
  `/mixer/pan`, `/mixer/mute`, and `/mixer/get`. `/state/snapshot` includes a
  `mixer` key with the full snapshot.
- **FR-010**: Mixer state round-trips through preset persistence — because the
  params system already snapshots `level_<t>`, `pan_<t>`, and `mute_<t>`, the
  existing `apply_params` path restores the mixer without preset schema
  changes.

### Non-Functional

- Preset format remains backward compatible: old presets without mixer params
  load with default mixer state (level=1.0, pan=0.0, mute=false).
- Runtime cost: two extra multiplies per note in the sequencer hot path;
  mixer edits trigger one OSC/MIDI send per tweak.

## Out of Scope

- Per-voice EQ, compression, or sends.
- Mixer automation (LFOs / envelope modulation of level/pan).
- Master bus level on the Lua side — SC-side master is covered by the separate
  `re-4qz` mixer engine landing upstream.
