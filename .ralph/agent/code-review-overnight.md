# Overnight Feature Review (002-006)

Reviewed 2026-03-25. Branch: 007-swing-shuffle (contains all prior features).

---

## 002-quality-hardening

**Files**: specs/track_spec.lua, specs/sequencer_spec.lua, specs/direction_spec.lua, specs/pattern_spec.lua, specs/integration_spec.lua

**Verdict: PASS -- well done**

### Convention compliance
- All tests use the ctx pattern correctly. No custom globals.
- Tests exercise real module code (track_mod, direction, sequencer, pattern) with minimal mocking -- only platform APIs (clock, params, grid, screen) are mocked, which is correct.

### Test quality
- Loop boundary edge cases (T002-T007) are thorough: single-step loop, full-range loop, mid-playback loop change, polymetric independence across all 8 params x 100 steps.
- Retrigger safety (T008-T011): properly validates the note-off-before-note-on contract on the MIDI voice, including a 16-step rapid retrigger stress test. These test real MIDI voice behavior, not mocks.
- Clock idempotency (T012-T015): double-start, double-stop, rapid 50x toggle, and stop-then-start playhead preservation. Good use of clock.run/cancel spies to verify coroutine lifecycle.
- Pattern roundtrip (T016-T020): extended params, direction modes, comprehensive all-params-all-tracks roundtrip, slot overwrite independence. Tests deep_copy correctness thoroughly.
- Direction transitions (T021-T024): forward-to-reverse mid-sequence, pendulum-to-forward, single-step loop across all modes, drunk boundary after mode change. Meaningful behavioral tests.
- Mute timing (T025-T028): mute-advance-unmute position tracking, double-mute safety, all-4-tracks-muted, muted playhead count verification.
- Scale change (T029, T031): verifies next note uses new scale, and already-sounding notes are not retroactively re-pitched.

### Issues: None found.

---

## 003-simulated-grid

**Files**: lib/grid_provider.lua (simulated provider), lib/seamstress/grid_render.lua, specs/simulated_grid_spec.lua, specs/grid_render_spec.lua

**Verdict: HAS BUGS -- needs fixes**

### Convention compliance
- Grid provider uses module-returns-table pattern correctly.
- Grid render is a clean stateless module.
- No custom globals.

### Test quality
- Provider tests (T016-T022): interface compliance, LED roundtrip, key callback, dimensions. Good.
- Mouse click tests (T028-T031): coordinate mapping, non-left-click filtering, out-of-bounds, boundary pixel. Good.
- Behavioral parity (T037-T038): verifies simulated and virtual providers produce identical LED state under grid_ui.redraw. Excellent test.
- Performance test (T040): 100 draws under 500ms. Reasonable.
- Edge cases (T043-T046): drag, out-of-bounds LED, end-to-end flow. Good.

### BUG 1 (Critical): grid_render.lua uses wrong calling convention for seamstress screen API

`grid_render.draw()` calls `scr:color(r, g, b)` and `scr:rect_fill(px, py, CELL_SIZE, CELL_SIZE)` using **colon (method) syntax**. When `seamstress.lua` passes the global `screen` table, the colon syntax inserts `screen` as the first argument:

- `scr:color(r, g, b)` becomes `screen.color(screen, r, g, b)` -- wrong. Seamstress expects `screen.color(r, g, b, a)`.
- `scr:rect_fill(px, py, w, h)` becomes `screen.rect_fill(screen, px, py, w, h)` -- wrong. Seamstress expects `screen.move(x,y)` then `screen.rect_fill(w, h)`.

The tests pass because mock screens are defined as objects with `self`-accepting methods. But at runtime on real seamstress, the grid will not render correctly.

**Fix**: Either:
(a) Change grid_render to use dot syntax and call `screen.move(px, py)` then `screen.rect_fill(w, h)` and `screen.color(r, g, b, 255)` -- matching screen_ui.lua's pattern, OR
(b) Change grid_render to not accept a screen param and just use the global `screen` directly.

Option (a) is cleaner and maintains testability.

### BUG 2 (Minor): grid_render uses 4-arg rect_fill, but seamstress rect_fill takes 2 args

Even ignoring the colon/dot issue, `rect_fill(px, py, CELL_SIZE, CELL_SIZE)` passes position as arguments, but seamstress's `screen.rect_fill(w, h)` expects only width and height (position set via `screen.move()`). The grid_render module needs to call `screen.move(px, py)` before `screen.rect_fill(CELL_SIZE, CELL_SIZE)`.

### Note: simulated vs virtual provider duplication

The `simulated` and `virtual` providers in grid_provider.lua are nearly identical. The only difference is that `simulated.led()` has bounds checking (`if x < 1 or x > cols...`). Consider extracting a shared factory to reduce duplication. Low priority.

---

## 004-osc-voice-integration

**Files**: lib/voices/osc.lua, seamstress.lua (OSC params integration), specs/osc_voice_spec.lua

**Verdict: PASS -- clean implementation**

### Convention compliance
- OSC voice follows the voice interface (play_note, all_notes_off, set_portamento, set_target).
- Module returns table. No globals.
- Voice backend params live in seamstress.lua entrypoint (not in app.lua), correctly keeping platform-specific config out of shared code.
- ctx pattern used properly throughout.

### Code quality
- OSC voice is minimal (33 lines). Clean factory function.
- OSC path convention `/rekriate/track/{n}/note` is well-structured for multi-track routing.
- Voice backend switching in seamstress.lua calls `all_notes_off()` on the outgoing voice before replacing -- correct.
- OSC target params (host/port per track) properly update the active voice when changed mid-session.
- Default values (127.0.0.1:57120) target SuperCollider's default port -- sensible.

### Test quality
- Tests replicate the seamstress.lua init flow in a `seamstress_init()` helper, which tests the actual wiring rather than just the module in isolation. This catches integration bugs.
- T003-T005: param registration and defaults.
- T011-T016: voice swap mechanics including all_notes_off on outgoing voice, mixed backends.
- T018-T021: OSC target update via param change, including guard against calling set_target on MIDI voice.
- T023-T030: sprite voice continuity, platform guard (norns has no OSC params), mixed 4-track scenario, cleanup with OSC voices.
- T025: reads re_kriate.lua file content to verify it does NOT contain OSC param IDs. Smart structural test.

### Issues: None found.

---

## 005-norns-entrypoint

**Files**: re_kriate.lua, lib/norns/nb_voice.lua, specs/norns_entrypoint_spec.lua

**Verdict: PASS -- clean and minimal**

### Convention compliance
- re_kriate.lua defines exactly 5 globals (init, redraw, key, enc, cleanup) -- verified by test T021.
- Thin wrappers delegating to app module, matching CLAUDE.md's prescribed pattern.
- `ctx` is a module-level local (not global), passed to app functions.
- nb_voice wraps nb player lookups correctly.
- No seamstress-only features leak into norns entrypoint (verified by test T022).

### Code quality
- re_kriate.lua is 72 lines. Very clean.
- nb_voice.lua is 37 lines. Each method does a nil-safe `params:lookup_param():get_player()` lookup.
- Cleanup guards against nil ctx (`if not ctx then return end`).
- Screen metro at 15fps (vs seamstress 30fps) -- appropriate for norns 128x64 OLED.
- `log.session_start()` / `log.close()` bookend the lifecycle.

### Test quality
- norns_init() helper mirrors the actual re_kriate.lua init flow.
- T003-T005: voice creation, grid provider, screen metro.
- T007-T009: key/enc/redraw delegation.
- T010-T012: portamento through nb voice (with/without set_slew support, nil player).
- T014-T016: cleanup stops metro, cleanup with nil ctx.
- T021-T022: structural verification of globals-only and no seamstress features.
- T024: rapid init/cleanup/init cycle.

### Minor note
- T016 (cleanup with nil ctx) is a bit of a tautology -- it guards with `if nil then app.cleanup(nil) end` which is always false. The real test should verify that calling the actual `cleanup()` function when ctx is nil does not error. However, since re_kriate.lua line 65 has `if not ctx then return end`, the behavior is correct in practice.
- T018-T019 (logging) test mock functions rather than the actual wiring. They verify `mock_log.session_start()` is callable, not that `init()` calls it. Low severity since the wiring is trivially visible in re_kriate.lua.

---

## 006-pattern-bank-ui

**Files**: lib/seamstress/keyboard.lua (ctrl+N/shift+N), lib/seamstress/screen_ui.lua (slot indicators + transient messages), specs/pattern_bank_ui_spec.lua

**Verdict: PASS -- well-scoped**

### Convention compliance
- Pattern UI is entirely in seamstress modules (keyboard.lua, screen_ui.lua). Not in app.lua or re_kriate.lua.
- Test T023-T024 structurally verify re_kriate.lua and app.lua contain no pattern indicator code.
- ctx.active_pattern and ctx.pattern_message are seamstress-only UI state -- not persisted, not in the shared model.

### Code quality
- Keyboard shortcuts: ctrl+1-9 = save, shift+1-9 = load. Load only fires if slot is populated. Clean.
- Screen UI renders 9 slot indicators with 3 brightness levels (dim/medium/bright). Simple and readable.
- Transient message auto-expires after 1.5 seconds (checked during redraw). No timer/metro needed.
- Pattern save/load delegates to the existing pattern module -- no duplication.

### Test quality
- T003-T007: active pattern tracking (save, load, empty-slot guard, startup nil, subsequent save).
- T009-T013: slot indicator rendering with mock screen capture. Tests color brightness thresholds.
- T015-T020: transient messages (save/load text, empty-slot no-message, render, expiry, replacement).
- T023-T025: scope verification and slot-9 boundary.

### Minor note
- `screen_ui.lua` line 28: `screen.rect_fill(10, 5)` follows the correct seamstress convention (`screen.move` then `screen.rect_fill(w, h)`). Consistent with the rest of screen_ui but **inconsistent with grid_render.lua** (see Bug 1 above).
- Keyboard handles `char >= "1" and char <= "9"` with modifier checks ordered ctrl-first, shift-second, bare-last. This is correct -- bare "1"-"4" falls through for track select, and "5"-"9" without modifiers are no-ops (no track 5+).

---

## Cross-Feature Issues

### 1. grid_render.lua screen API mismatch (Critical)
As detailed under 003 above, `grid_render.lua` will not work correctly on the real seamstress runtime. The grid will be invisible or corrupted. This needs to be fixed before merging.

### 2. Test mock inconsistency for screen API
Different test files mock `screen.rect_fill` with different signatures:
- pattern_bank_ui_spec.lua: `rect_fill = function(w, h)` (correct for seamstress)
- grid_render_spec.lua: `rect_fill = function(self, x, y, w, h)` (matches grid_render's buggy API)
- norns_entrypoint_spec.lua: `rect_fill = function(w, h)` (correct)

When the grid_render bug is fixed, grid_render_spec.lua mocks will need updating too.

### 3. seamstress.lua redraw vs screen_ui.redraw
`seamstress.lua` defines a global `redraw()` that does its own screen.clear/rect_fill/grid_render.draw/sprite_render.draw, but the `screen_ui.redraw(ctx)` module also does `screen.clear()` and draws its own background. Currently `seamstress.lua:redraw()` does NOT call `screen_ui.redraw()`. This means the screen_ui (track info, pattern indicators, play state) is not displayed during normal operation. It's wired via the screen_metro event but the metro calls `redraw()` which only renders the grid+sprites.

This is likely intentional (seamstress shows grid, not info panel), but it means the pattern bank UI indicators (feature 006) and the track/page/play status (screen_ui) are never displayed. The pattern_bank_ui tests verify rendering in isolation but the UI is unreachable at runtime.

**Recommendation**: Either wire screen_ui.redraw into the seamstress redraw path (below or beside the grid), or document that screen_ui is only for a future dual-pane layout.

### 4. No swing param in seamstress.lua
Feature 007 (current branch) adds swing support in the sequencer and app.lua (swing params). The seamstress.lua entrypoint imports app.lua which registers swing params, so this should work. But the keyboard.lua does not have any shortcut for adjusting swing -- it's param-only. This is fine but worth noting.

---

## Summary

| Feature | Status | Issues |
|---------|--------|--------|
| 002-quality-hardening | PASS | None |
| 003-simulated-grid | NEEDS FIX | grid_render screen API mismatch (Critical) |
| 004-osc-voice-integration | PASS | None |
| 005-norns-entrypoint | PASS | None |
| 006-pattern-bank-ui | PASS | screen_ui not wired into seamstress redraw (see cross-feature #3) |

**Action items before merge**:
1. Fix grid_render.lua to use `screen.move(px, py)` + `screen.color(r, g, b, 255)` + `screen.rect_fill(CELL_SIZE, CELL_SIZE)` (dot syntax, not colon). Update grid_render_spec.lua mocks accordingly.
2. Decide whether screen_ui.redraw should be called from seamstress.lua's redraw function. If yes, wire it in. If no, add a comment explaining the intentional omission.
