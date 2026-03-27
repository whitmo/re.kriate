# Tasks: Probability & Modifier Holds (test-first)
**Branch**: `whitmo/probability-grid`

## Phase A — Tests
- [ ] Add sequencer probability spec (`specs/probability_spec.lua`): stub RNG; assert skip vs fire based on probability.
- [ ] Add grid UI probability spec: render brightness by %; click cycles 0/25/50/75/100; updates ctx.
- [ ] Add persistence spec coverage: probability and alt-track fields round-trip via pattern save/load and bank persistence.
- [ ] Add keyboard spec: probability page keybinding + step adjust, latched modifier visualization.

## Phase B — Implementation
- [ ] Extend track model with `params.probability` (steps, loop bounds, pos) default 100.
- [ ] Gate sequencer trigger emission by probability.
- [ ] Add grid probability page: nav entry, render, edit handler; show latched modifier indicator.
- [ ] Add alt-track page: direction/division/swing/mute edit grid.
- [ ] Update screen_ui labels/status for probability page.
- [ ] Update pattern save/load + pattern_persistence for new fields and defaults.

## Phase C — Verification
- [ ] Run `./scripts/busted.sh --no-auto-insulate specs`.
- [ ] Manual seamstress check (probability page, modifier latch, alt-track page).
