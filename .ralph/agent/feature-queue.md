# Feature Queue — re.kriate

Features for ralph to work through, in priority order.
Each line: `- [ ]` pending, `- [~]` in-progress, `- [x]` done.

## Quality Arc

Ensure fundamental features work correctly end-to-end and have thorough test coverage. Fix bugs, harden edge cases, verify musical correctness before adding new features.

- [x] Quality hardening: audit all 442 existing tests for gaps — verify loop boundary edge cases (loop_start == loop_end, loop wrapping at step 16→1), note retrigger safety (note-on before previous note-off), clock stop/start idempotency, pattern save/load roundtrip fidelity, direction mode transitions (changing mode mid-sequence), mute/unmute timing, and scale change mid-playback. Write failing tests for any uncovered edge case, then fix. Run seamstress load test to verify the script initializes and cleans up without errors or resource leaks.

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
