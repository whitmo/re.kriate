# Screen UI, Info Panel, and Navigation Audit

**Date:** 2026-04-11
**Scope:** `lib/seamstress/screen_ui.lua`, `lib/seamstress/keyboard.lua`, `lib/seamstress/grid_render.lua`, `lib/grid_ui.lua`, `lib/seamstress/help_overlay.lua`, `seamstress.lua`

---

## 1. What does the screen tray currently show? Is it useful?

The screen tray (`screen_ui.draw_tray`) is rendered at the bottom of the seamstress window, below the virtual grid. It shows:

- **Page indicator labels** (9 groups): TR/RA, NO/AN, OC/GL, DU, VE, PR, AT, MP, SC. The active page's label is highlighted bright (200,200,255); inactive groups are dim (60,60,80). When on an extended page (e.g. ratchet), the label switches to the extended abbreviation (RA instead of TR).
- **Pattern slot indicators** (9 slots): Small rectangles showing which of 9 pattern slots are populated (medium brightness) vs empty (dim), with the active slot shown bright.
- **Transient pattern message**: Text like "saved 3" or "loaded bank" that auto-expires after 1.5 seconds.

**Assessment:** The tray is useful as a minimal status bar. However:
- Only 9 pattern slots are drawn even though the system supports 16 slots (rows 1-2 x cols 1-8 in pattern mode). This is a **discrepancy** -- `draw_pattern_slots` in `screen_ui.lua` iterates `1..9` while the grid UI and pattern module support 16 slots.
- It does not show track number, play state, direction, or clock division. The full `M.redraw()` method in `screen_ui.lua` does draw these (title, track+page, play state, step positions), but `seamstress.lua` only calls `draw_tray()`, **not** the full `redraw()`. The seamstress entrypoint draws the grid + sprites + tray, skipping the detailed text info that `redraw()` provides.
- The tray occupies 20px (`TRAY_HEIGHT`) which is compact. The page abbreviations are somewhat cryptic without documentation (solved by the help overlay).

**Gap:** The full `screen_ui.redraw()` (which shows track, page, play state, step positions) is dead code in seamstress mode -- only `draw_tray()` is called.

---

## 2. Has a dynamic info side panel been implemented?

**No.** There is no side panel implementation. The seamstress window is sized to exactly `grid_width x (grid_height + tray_height)`. There is no context-sensitive panel that shows different information based on the active page.

The `screen_ui.redraw()` function has a fixed layout (title, track+page, play/stop, step positions for 4 tracks, then tray) but it is **not called** from seamstress mode. It appears to be a leftover from an earlier norns-style screen layout or an unused prototype.

**Recommendation:** A side panel showing page-specific context (e.g. current param values, loop bounds, direction/division on alt-track, scale info on scale page) would improve usability significantly.

---

## 3. What keyboard shortcuts exist? Are they documented/discoverable?

### Implemented shortcuts (from `keyboard.lua`):

| Key | Action |
|-----|--------|
| Space | Play/Stop |
| R | Reset playheads |
| 1-4 | Select track |
| Q | Trigger page (toggle to ratchet on repeat press) |
| W | Note page (toggle to alt_note on repeat press) |
| E | Octave page (toggle to glide on repeat press) |
| T | Duration page |
| Y | Velocity page |
| D | Cycle direction mode |
| L | Toggle loop edit mode |
| F1 | Toggle time modifier (KEY 1) |
| F2 | Config/alt-track page (KEY 2) |
| Ctrl+P | Toggle probability modifier |
| Ctrl+A | Alt-track page |
| Ctrl+S | Save pattern bank to disk |
| Ctrl+L | Load pattern bank from disk |
| Ctrl+B | List pattern banks |
| Ctrl+Shift+D | Delete pattern bank |
| Ctrl+1-9 | Save to pattern slot |
| Shift+1-9 | Load from pattern slot |

### Additional shortcuts in `seamstress.lua`:

| Key | Action |
|-----|--------|
| ? | Toggle help overlay |
| Escape | Dismiss help overlay / release locked grid keys |
| Ctrl+Shift+T | Cycle grid visual theme |

### Discoverability:
**Yes** -- the `?` key help overlay documents all keyboard shortcuts and grid nav row functions. The overlay is comprehensive (4 two-column sections covering keyboard, control row, patterns, pages, loop editing, meta-sequencer, voices, and alt-track).

**Gaps:**
- The `?` shortcut itself is not documented anywhere visible until you discover it. There's no on-screen hint.
- The `Ctrl+Shift+T` theme cycling shortcut is not listed in the help overlay.
- Scale page has no keyboard shortcut (only reachable via grid nav x=15).
- Meta-pattern page has no keyboard shortcut (only reachable via grid nav x=16 double-press).

---

## 4. How does page navigation work on the grid? Is the nav row clear?

### Grid nav row layout (row 8, x=1-16):

| x | Function | Brightness |
|---|----------|-----------|
| 1-4 | Track select | Active=12, others=3 |
| 5 | KEY 1: Time modifier (hold) | Held=12, else=0 (dark) |
| 6 | Trigger page (press again for ratchet) | Active=12, extended=8, else=3 |
| 7 | Note page (press again for alt_note) | Active=12, extended=8, else=3 |
| 8 | Octave page (press again for glide) | Active=12, extended=8, else=3 |
| 9 | Cycle: Duration > Velocity > Probability | Active=12, else=3 |
| 10 | KEY 2: Config/Alt-track (press) | Active=12, else=0 (dark) |
| 11 | Loop modifier (hold) | Held=12, else=3 |
| 12 | Pattern mode (hold) | Held=12, else=3 |
| 13 | Mute toggle | Muted=12, else=3 |
| 14 | Probability modifier (hold) | Held=12, else=3 |
| 15 | Scale page | Active=12, else=3 |
| 16 | Meta / Alt-track toggle | Active=12, else=3 |

### Assessment:
- **Functional and mostly clear.** The brightness differentiation (12 for active, 3 for inactive, 0 for KEY buttons when not held) makes the active page identifiable.
- **Extended page toggle** is well-designed: pressing the same page button a second time enters the extended page (ratchet, alt_note, glide), shown at reduced brightness (8).
- **x=9 cycle group** (duration/velocity/probability) is a good space-saving design but may confuse users expecting direct page access.
- **Keys 5 and 10** (KEY 1, KEY 2) are dark (brightness 0) when inactive, making them invisible on the grid. This matches Ansible hardware conventions but could be disorienting for new users.

### Bug/confusion in code comments:
- Line 458 has comment `-- x=15: blank (no LED)` but it actually draws `NAV_META` (x=16). The comment references x=15 when it should reference x=16. Cosmetic; code behavior is correct via the constant.
- Line 559 has comment `-- scale (x=14)` but the actual constant `NAV_SCALE` is 15. Another cosmetic comment error.

---

## 5. Has a help overlay (? key) been implemented?

**Yes.** Fully implemented in `lib/seamstress/help_overlay.lua` and wired into `seamstress.lua`.

### Details:
- **Toggle:** `?` key press toggles `ctx.help_visible`. Escape also dismisses it.
- **Window resize:** When the overlay is shown, the window resizes to 400x380 pixels (larger than the default grid view). On dismiss, it resizes back to grid dimensions.
- **Content:** 4 sections in two-column layout:
  1. Keyboard shortcuts | Control row (grid row 8)
  2. Patterns | Pages
  3. Loop editing | Meta-sequencer
  4. Voices | Alt-track
- **Rendering:** Full-screen dark background with color-coded headers (yellow/orange) and body text. Footer reads "? or Esc to close".
- **Testing support:** `M.get_sections()` exposes content for testing.

**Assessment:** The help overlay is comprehensive and well-structured. The only gap is that the help overlay itself has no on-screen indicator telling users it exists (no "Press ? for help" hint in the tray or elsewhere).

---

## 6. What's the state of meta_pattern and scale pages -- functional or stubs?

### meta_pattern (`lib/meta_pattern.lua` + grid_ui)

**Fully functional.** The module implements:
- `M.new()` creates state with 16 meta-steps, each with slot + loop count
- `M.set_step()` / `M.clear_step()` for editing meta-steps
- `M.start()` / `M.stop()` / `M.toggle()` for playback control
- `M.on_loop_complete()` handles advancing through meta-sequence with loop counting and cue support
- `M.cue()` / `M.cancel_cue()` for cueing patterns at loop boundaries
- Playhead reset on pattern transitions

Grid UI support (`grid_ui.draw_meta_pattern_page` / `grid_ui.meta_pattern_key`):
- Rows 1-2: Pattern slot assignment for selected meta-step
- Row 3: Loop count selector (1-7)
- Row 5: Meta-sequence overview with playback/selection indicators
- Row 6: Cued pattern indicator
- Row 7 x=1: Toggle active

**Assessment:** Complete implementation with cueing, loop counting, event emission, and full grid interaction. Not a stub.

### scale (`lib/scale.lua` + grid_ui)

**Functional but minimal.** The module provides:
- `M.build_scale(root, scale_type)` generates 8 octaves of a scale via musicutil
- `M.to_midi(degree, octave, scale_notes)` converts step values to MIDI notes

Grid UI support (`grid_ui.draw_scale_page` / `grid_ui.scale_key`):
- Row 1: Chromatic root note selection (12 pitch classes)
- Row 2: Octave selection (0-9)
- Row 3-4: Scale type selection (14 scale types across 2 rows)
- Row 5: Scale note visualization (which chromatic pitches are in the selected scale)
- Event emission for `scale:root` and `scale:type` changes

**Assessment:** Functional with a working grid UI. The module delegates scale generation to musicutil (an external dependency). The scale page has no keyboard shortcut (only reachable via grid x=15). Scale type names are not shown anywhere -- the user must know which of the 14 types corresponds to which position.

---

## Summary of Findings

### What works well
- Help overlay is comprehensive and well-wired
- Nav row is functional with good brightness differentiation
- Extended page toggle (press-again) is elegant
- Meta-pattern sequencer is fully functional with cueing
- Scale page has working grid UI with root/octave/type selection

### Gaps and issues
1. **No dynamic info panel** -- no context-sensitive side panel exists
2. **`screen_ui.redraw()` is dead code** in seamstress mode -- only `draw_tray()` is called
3. **Pattern slot count mismatch** -- tray shows 9 slots, system supports 16
4. **No "Press ? for help" hint** visible to new users
5. **Ctrl+Shift+T** (theme cycle) not documented in help overlay
6. **Scale page has no keyboard shortcut** -- grid-only access
7. **Meta-pattern page has no keyboard shortcut** -- grid-only access
8. **Comment errors** in grid_ui.lua nav section (wrong x positions in comments)
9. **Scale type names not displayed** -- positions 1-14 are unlabeled on screen
