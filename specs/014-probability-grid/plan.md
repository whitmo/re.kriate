# Implementation Plan: Probability & Modifier Holds on Virtual Grid

**Branch**: `whitmo/probability-grid` | **Spec**: `specs/014-probability-grid/spec.md`

## Summary
Add per-step trigger probability, latched modifiers on virtual grid, and an alt-track settings page for direction/division/swing/mute. Use simulated grid for UI/testing; keep ctx pattern and parity with pattern save/load and bank persistence.

## Phases
### Phase 0 — Recon
- Inspect `lib/sequencer.lua` trigger path.
- Inspect `lib/grid_ui.lua`, `lib/seamstress/grid_render.lua`, `lib/seamstress/keyboard.lua`, `lib/seamstress/screen_ui.lua`.
- Check `pattern.lua` and pattern_persistence for fields to extend.

### Phase 1 — Design
- Probability data model: add `params.probability` per track (mirrors trigger, steps[16], loop_start/end, pos, default 100).
- Sequencer change: before triggering, roll RNG vs probability; stub RNG for tests.
- UI: new grid page “probability”; brightness levels reflect %; click cycles values (0/25/50/75/100).
- Alt-track page layout: dedicated page with rows per track, columns for direction/division/swing/mute toggles.
- Modifier latching: keep right-click latch; add visual indicator (LED/state).

### Phase 2 — Tests (write first)
- Add `specs/probability_spec.lua` for sequencer behavior with stub RNG (deterministic).
- Add `specs/grid_ui_probability_spec.lua` for grid rendering/editing of probability.
- Extend `pattern_persistence_spec` for probability/alt-track save/load.
- Extend `keyboard_spec` for probability page keybindings.
- Update `simulated_grid_spec` for latched modifier visual checks if needed.

### Phase 3 — Implementation
- Add probability param to track model and defaults.
- Implement RNG gate in sequencer step dispatch.
- Grid UI probability page (render/edit).
- Alt-track settings page render/edit; hook into ctx fields.
- Screen UI: show probability page label/status.
- Persistence: include probability/alt-track fields in pattern save/load and bank persistence.

### Phase 4 — Verification
- Run targeted specs, then full suite: `./scripts/busted.sh --no-auto-insulate specs`.
- Manual seamstress smoke (probability page, modifier latch).

## Risks / Mitigations
- RNG determinism for tests: inject/stub RNG function.
- UI clutter: keep pages minimal; re-use existing nav to switch.
- Pattern schema change: ensure backward compat defaults when loading older patterns/banks.
