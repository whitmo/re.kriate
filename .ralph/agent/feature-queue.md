# Feature Queue — re.kriate

Features for ralph to work through, in priority order.
Each line: `- [ ]` pending, `- [~]` in-progress, `- [x]` done.

## Quality Arc

Ensure fundamental features work correctly end-to-end and have thorough test coverage. Fix bugs, harden edge cases, verify musical correctness before adding new features.

- [x] Quality hardening: audit all 442 existing tests for gaps — verify loop boundary edge cases (loop_start == loop_end, loop wrapping at step 16→1), note retrigger safety (note-on before previous note-off), clock stop/start idempotency, pattern save/load roundtrip fidelity, direction mode transitions (changing mode mid-sequence), mute/unmute timing, and scale change mid-playback. Write failing tests for any uncovered edge case, then fix. Run seamstress load test to verify the script initializes and cleans up without errors or resource leaks.

## Known Issues (flagged during live manual testing, 2026-07-11)

- [ ] Remove redundant "probability" page from the nav x=9 cycle (`NAV_PAGE_CYCLE_9` in lib/grid_ui.lua): probability already works correctly as a hold-modifier (nav x=14, `ctx.prob_held`, overlays rows 1-7 on whatever page is active) — this is the original kria design and it's implemented right. The *page* version (3rd stop of the x=9 cycle, `draw_value_page(ctx, g, "probability")`) is leftover duplication from before the modifier existed (see CHANGELOG re-2d4) and should go, along with `mixer` shifting to 3rd stop.
- [ ] `connect_grid()` in lib/app.lua (used by the `grid_provider` param's `set_action`) tears down the current grid (`ctx.g:cleanup()`) *before* confirming the new provider connects. If the new provider's `connect()` throws (e.g. selecting "midigrid" without it installed — reproduced live, see `~/.re_kriate.log` "grid reconnect failed (midigrid)"), the old grid has already been wiped. The simulated provider's `cleanup()` only blanks LEDs (self-heals next redraw frame), but this ordering is unsafe in general — reorder to connect the new provider first, and only tear down the old one after success.
- [ ] Consider a "reset to defaults" action (params entry or grid gesture) to recover from a degraded UI/session state without restarting the process — came up after the params-menu grid-provider issue above left things feeling stuck.
- [ ] Clarify further: reporter says "everything seems to destabilize at some point in the UI and options" — the grid-provider reconnect issue above is a strong candidate but unconfirmed as *the* cause; needs a repro if it recurs after that fix.
- [ ] **Stronger candidate for "destabilizes":** `lib/grid_ui.lua`'s `redraw()` and `grid_key()` disagree on hold-modifier precedence. `redraw()` draws `pattern_held > time_held > prob_held` as mutually exclusive (if/elseif), then draws the `loop_held` overlay *unconditionally on top* whenever `active_page ~= "alt_track"` — regardless of whether another modifier is also held. `grid_key()` instead checks `pattern_held > time_held > prob_held` and returns early for any of them, only reaching `loop_held` after — so holding e.g. `prob_held` + `loop_held` together shows a loop-anchor highlight drawn over the probability-edit view, but key presses actually edit probability, not the loop. Reproduced by static analysis (grid_ui.lua:54-99 vs 656-716), not yet live-confirmed. n.kria avoids this class of bug entirely with a single resolved `mod` value (leftmost-wins) instead of 4 independent booleans checked in two places — worth the same approach here.
- [ ] `NAV_PAGE[9] = "duration"` (lib/grid_ui.lua) is dead data — x=9's actual behavior comes entirely from `NAV_PAGE_CYCLE_9`, `NAV_PAGE[9]` is never read. Minor cleanup, but exactly the kind of drift the declarative nav spec (see below) is meant to catch.
- [ ] Simulated grid visuals called "lame and unhelpful": `lib/seamstress/grid_render.lua` `M.draw()` only paints a brightness→RGB rect per cell plus a dark border and an optional lock-dot — no labels, no per-page semantic distinction beyond raw brightness, nothing to help someone who hasn't memorized the nav layout. Needs design input on what "helpful" looks like before building (candidates: nav-row button labels/tooltips, distinct color coding for hold-modifiers vs page-select vs value cells, a hover/last-press highlight).
- [ ] Side info panel (`lib/seamstress/screen_ui.lua` `draw_side_panel`) is acknowledged as improving but is pure readout — nothing in it is clickable. `seamstress.lua`'s `screen.click` handler only ever routes to `grid_render.handle_click` (the grid region); no click handling exists for the panel's pixel range at all. Requested: make it navigable — e.g. click a track row to select that track, click the page name to page-select, click a pattern slot indicator to load/save — turning it into a second control surface, not just a readout.

## Event-layer migration (from the 2026-07-11 inventory; see docs/event-layers.md once PR #145 lands)

- [ ] Migrate interface surfaces to emit cmd:* behavioral events instead of calling modules directly, one surface per PR — keyboard first (simplest adapter), then remote/api.lua transport handlers, then grid_ui pattern/transport paths. Each migration collapses one of the divergent-path families below.
- [ ] Mute has 5 writers with inconsistent events: grid NAV_MUTE flips `track.muted` directly (emits `track:mute`); alt_track page x=16 and `/track/mute` flip it silently; the mixer path (`mute_N` param, `/mixer/mute`, grid mixer x=16) goes through `mixer.set_mute` (emits `mixer:mute`). Consolidate all five on `cmd:track:set_mute` → `mixer.set_mute`, and pick ONE fact name (`mixer:mute`) — `track:mute` becomes an alias to deprecate.
- [ ] Track/page select facts are grid-only: keyboard 1-4/q-w-e-t-y, `/track/select`, `/page/select`, and norns encoders all write `ctx.active_track`/`ctx.active_page` silently — remote UIs listening for `track:select`/`page:select` see only grid-originated changes. Migrating those surfaces to cmd:* fixes the fact gap for free.
- [ ] Direction/division/swing have 4 writers (keyboard `d`, alt_track page, remote api, params) with zero events and no params sync-back — the params menu shows stale values after grid/keyboard edits. Needs cmd:option:change wiring plus the same bidirectional sync pattern scale:root/scale:type already use.
- [ ] MIDI clock Start resets playheads before starting; every other transport-start path (space, K2, /transport/play, params, help console) does not — a musician switching between local and slaved operation gets different downbeat behavior. Decide the canonical semantic and make all paths converge on cmd:transport:play (+ explicit cmd:transport:reset where reset-on-start is wanted).
- [ ] `voice:note` fires once per step even when ratchet produces N sub-notes (lib/sequencer.lua:267 vs the ratchet loop's N play_note calls) — the fact stream under-reports what actually sounded. If facts are to be a faithful behavioral record (macro recording, visualization), emit per sounding.
- [ ] `/mixer/level` and `/mixer/pan` (remote api) bypass the params system while the grid mixer page routes through `params:set` — params menu shows stale mixer values after remote changes. Converge on one path (params:set when available, like grid does).

## Next Up

- [ ] Probability & modifiers on virtual grid: add per-step trigger probability UI, alt-track modifier holds (keyboard + virtual grid), and tests using simulated grid.

## 2026-04-12 Review Dispatch (see docs/projects/2026-04-12-review-of-main/plan.md)

Interleaved across grid-UX / voices / params / startup so parallel polecats hit disjoint files.

- [ ] re-lz0 Loop modifier: modifier-not-page (kria form) — `lib/grid_ui.lua`, `lib/track.lua` → specs/018-loop-modifier-overlay
- [ ] re-mgm SC voice: seamstress↔SC handshake and easier launch — `lib/voices/sc_synth.lua`, `sc/*.scd` → specs/024-sc-voice-handshake
- [ ] re-rr0 Param reorganization: voice-scoped params, swing/voice under track, clock-sync clarity — `lib/app.lua` → specs/026-param-reorganization
- [ ] re-4fs Startup banner: git hash, branch, release, SC/softcut connection status — `lib/seamstress/*` → specs/028-startup-banner
- [ ] re-7xm Alt-param visuals + octave row-0 setter + glissando graphic — `lib/grid_ui.lua` → specs/019-alt-param-visuals
- [ ] re-l8p Softcut + recorder integration (grab samples live) — `lib/voices/softcut_*.lua`, `lib/voices/recorder.lua` → specs/025-softcut-recorder
- [ ] re-2yn Preset/pattern unification + stock banks (depends on re-rr0) — `lib/preset.lua`, `lib/pattern_persistence.lua` → specs/027-preset-pattern-unify
- [ ] re-107 Seamstress console help() callable exposing ctx/transport/debug — `lib/seamstress/console.lua` (new) → specs/029-console-help
- [ ] re-sc1 Per-parameter probability semantics (depends on re-rr0) — `lib/track.lua`, `lib/sequencer.lua`, `lib/grid_ui.lua` → specs/022-param-probability
- [ ] re-cv2 SC mixer Lua wrapper + tests — `lib/voices/sc_mixer.lua` (new), `specs/sc_mixer_spec.lua` (new) → specs/030-sc-mixer-wrapper
- [ ] re-1mo Virtual grid aesthetics: colors, spacing, borders — `lib/seamstress/grid_render.lua`, `lib/seamstress/screen_ui.lua` → specs/016-virtual-grid-aesthetics
- [ ] re-trn Dynamic info panel + `?` help overlay on right side — `lib/seamstress/screen_ui.lua`, `lib/seamstress/help_overlay.lua` → specs/017-info-panel-help
- [ ] re-44c Control row audit: row 7 buttons x=4 and x=13 purpose — `lib/grid_ui.lua` → specs/020-control-row-audit
- [ ] re-563 Clock divider modifier key repair — `lib/grid_ui.lua`, `lib/sequencer.lua` → specs/021-clock-divider-modifier
- [ ] re-lub Scale / meta-sequence page integration (row 8 x=16) — `lib/grid_ui.lua`, `lib/meta_pattern.lua` → specs/023-meta-scale-pages
- [x] Pattern persistence: save/load patterns to disk (norns + seamstress) with round-trip tests and checksum guard.
- [x] Add simulated grid: render an interactive 16x8 grid in the seamstress window using screen drawing primitives (rect_fill for buttons, brightness-mapped colors). Mirror the real grid state — LED brightness maps to button color intensity. Mouse clicks on grid cells generate the same key events as a physical grid (x, y, z=1 on press, z=0 on release). Enables full kria interaction without hardware.
- [x] Add OSC voice integration: wire lib/voices/osc.lua into app.lua as an alternative voice backend alongside MIDI, with per-track OSC target params (host/port), so external synths (SuperCollider, Max/MSP) can receive note events
- [x] Add norns platform entrypoint: create re_kriate.lua (norns main script) that mirrors seamstress.lua but uses norns screen API, norns key/enc callbacks, and nb voice output instead of MIDI. Grid and sequencer modules are shared.
- [x] Add pattern bank keyboard shortcuts: wire pattern save/load to number keys with modifier (shift+1-8 to save, alt+1-8 to load) on seamstress keyboard, with visual feedback on screen_ui showing which slot is active
- [x] Add swing/shuffle per track: add a swing parameter (0-100%) per track that offsets every other step's timing, creating groove feel. Wire into sequencer clock logic.
- [x] Add example SuperCollider voice: create a SuperCollider SynthDef and companion sclang script that listens for OSC messages from re.kriate's OSC voice backend (/rekriate/track/{n}/note). Include a simple subtractive synth with filter envelope, a docs/supercollider-setup.md explaining how to run it, and a test script that verifies OSC round-trip. Depends on OSC voice integration being complete.
