# Feature Specification: Probability & Modifier Holds on Virtual Grid

**Branch**: `014-probability-grid`  
**Created**: 2026-03-27  
**Status**: Draft  
**Input**: “Use the virtual grid for per-step trigger probability, alt track settings, and latched modifiers (VCV monome grid style).”

## User Stories

### US1 — Per-Step Trigger Probability (P1)
As a performer, I want to set a trigger probability for each step on the virtual grid so patterns evolve subtly without editing notes.
- Independent test: Set step 5 probability to 30%, run sequencer, observe ~30% hit rate over many bars.
- Acceptance:
  1. Grid shows probability values (0–100%) per step for active track when on “probability” page.
  2. Clicking a step cycles/adjusts probability in sensible increments that include both 0% and 100%.
  3. Probability affects playback: trigger is skipped when random roll > probability.
  4. Probability state saves/loads with pattern slots and pattern banks.

### US2 — Modifier Holds (P1)
As a performer without hardware, I want to latch modifier keys (loop, pattern, alt) via the virtual grid so I can do multi-gesture edits with a mouse.
- Independent test: Right-click loop button to latch; left-click steps to set loop without holding; right-click again to unlatch.
- Acceptance:
  1. Loop and pattern modifiers can be latched via right-click on nav buttons (x=12,14,y=8); latched state reflected visually.
  2. Latched modifiers persist until toggled off; regular press still works momentarily.
  3. Works with simulated grid and keyboard coexisting.

### US3 — Alt Track Settings Page (P2)
As a performer, I want quick access to per-track meta settings (direction, swing %, division, mute) via a grid page.
- Independent test: Switch to “alt-track” page; click cells to toggle direction or adjust swing; playback reflects new settings.
- Acceptance:
  1. New grid page or overlay lets user adjust direction, division, swing %, mute per track.
  2. Existing persisted direction modes remain representable on the page; unsupported modes must not render as "nothing selected" or get silently discarded.
  3. Swing UI must represent the full supported range used by playback/persistence, including 100%.
  4. Changes are visible (LEDs/text), stored in ctx, and kept consistent with existing params/actions.
  5. State saves/loads with pattern slots and pattern banks.

### US4 — Probability Page Keyboard Access (P2)
As a keyboard user on seamstress, I want to edit probability without grid hardware.
- Acceptance:
  1. Keybinding to enter probability page (e.g., Ctrl+P or dedicated key).
  2. While on probability page, 1–16 keys adjust probability for current step/track; visual feedback on screen_ui.

## Requirements

### Functional
- Add `probability` param per step on each track (0–100%) integrated into sequencer trigger decision.
- Extend `grid_ui` to render and edit probability: brightness or height reflects percentage; click cycles predefined values.
- Probability editing must allow users to reach 0% directly from the grid UI.
- Add virtual-grid modifier latches (already partial) with visual indication when latched.
- Add an “alt track” grid view for direction/division/swing/mute.
- Alt-track editing must remain in sync with existing params so menu and grid changes do not diverge.
- Update `pattern.lua` save/load and pattern persistence to include probability data and alt-track settings.
- Add seamstress keyboard binding(s) for probability page and adjustments.

### Non-Functional
- Keep ctx state pattern; no globals.
- Tests must cover probability rendering/editing, playback effect (stubbed RNG), save/load roundtrip, modifier latch behavior.
- Maintain norns parity where applicable; norns UI may stay minimal but state must roundtrip.

## Open Questions
- Probability resolution: 0/25/50/75/100 or finer (0–100 in 5% steps)? Default to coarse cycle; hold modifier to fine-adjust?
- UI for swing/division/direction on grid: row/column mapping TBD, but it must preserve existing engine ranges and modes.
- Visual indication for latched modifiers on virtual grid: invert LED brightness? Add status message?

## Success Criteria
- SC-001: Probability page editable on virtual grid and keyboard; values persist across pattern save/load and bank save/load.
- SC-002: Sequencer skips triggers in proportion to probability in tests (deterministic RNG stub for specs).
- SC-003: Latched loop/pattern/alt modifiers usable via mouse-only workflow on virtual grid.
- SC-004: Alt track settings page adjusts direction/division/swing/mute and is saved/loaded correctly.
