# Tasks: Probability & Modifier Holds (test-first)
**Branch**: `whitmo/probability-grid`

## Phase A — Tests
- [ ] Add sequencer probability spec (`specs/probability_spec.lua`): stub RNG; assert skip vs fire based on probability.
- [ ] Add grid UI probability spec: render brightness by %; click cycles include both 0 and 100; updates ctx.
- [ ] Add persistence spec coverage: probability and alt-track fields round-trip via pattern save/load and bank persistence.
- [ ] Add keyboard spec: probability page keybinding + step adjust, latched modifier visualization.
- [ ] Add alt-track spec coverage for full supported state: existing direction modes remain visible, swing 100 is representable, and grid edits keep params in sync.
- [ ] Add pattern bank failure-path spec: failed bank saves do not mutate any in-memory pattern slot.

## Phase B — Implementation
- [ ] Extend track model with `params.probability` (steps, loop bounds, pos) default 100.
- [ ] Gate sequencer trigger emission by probability.
- [ ] Add grid probability page: nav entry, render, edit handler; show latched modifier indicator.
- [ ] Add alt-track page: direction/division/swing/mute edit grid.
- [ ] Ensure alt-track page preserves existing engine-supported direction modes and full swing range instead of truncating them.
- [ ] Route alt-track edits through shared setters/params so grid and menu state stay synchronized.
- [ ] Update screen_ui labels/status for probability page.
- [ ] Update pattern save/load + pattern_persistence for new fields and defaults.
- [ ] Keep bank-save metadata separate from user-facing slots so slot 1 is never repurposed as scratch state.

## Phase C — Verification
- [ ] Run `./scripts/busted.sh --no-auto-insulate specs`.
- [ ] Manual seamstress check (probability page, modifier latch, alt-track page).
