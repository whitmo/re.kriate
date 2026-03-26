# Feature Queue — re.kriate

Features for ralph to work through, in priority order.
Each line: `- [ ]` pending, `- [~]` in-progress, `- [x]` done.

## Quality Arc

Ensure fundamental features work correctly end-to-end and have thorough test coverage. Fix bugs, harden edge cases, verify musical correctness before adding new features.

- [ ] Quality hardening: audit all 442 existing tests for gaps — verify loop boundary edge cases (loop_start == loop_end, loop wrapping at step 16→1), note retrigger safety (note-on before previous note-off), clock stop/start idempotency, pattern save/load roundtrip fidelity, direction mode transitions (changing mode mid-sequence), mute/unmute timing, and scale change mid-playback. Write failing tests for any uncovered edge case, then fix. Run seamstress load test to verify the script initializes and cleans up without errors or resource leaks.

## Next Up

- [ ] Add simulated grid: render an interactive 16x8 grid in the seamstress window using screen drawing primitives (rect_fill for buttons, brightness-mapped colors). Mirror the real grid state — LED brightness maps to button color intensity. Mouse clicks on grid cells generate the same key events as a physical grid (x, y, z=1 on press, z=0 on release). Enables full kria interaction without hardware.
- [ ] Add OSC voice integration: wire lib/voices/osc.lua into app.lua as an alternative voice backend alongside MIDI, with per-track OSC target params (host/port), so external synths (SuperCollider, Max/MSP) can receive note events
- [ ] Add norns platform entrypoint: create re_kriate.lua (norns main script) that mirrors seamstress.lua but uses norns screen API, norns key/enc callbacks, and nb voice output instead of MIDI. Grid and sequencer modules are shared.
- [ ] Add pattern bank keyboard shortcuts: wire pattern save/load to number keys with modifier (shift+1-8 to save, alt+1-8 to load) on seamstress keyboard, with visual feedback on screen_ui showing which slot is active
- [ ] Add swing/shuffle per track: add a swing parameter (0-100%) per track that offsets every other step's timing, creating groove feel. Wire into sequencer clock logic.
