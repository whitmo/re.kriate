# Feature Queue — re.kriate

Features for ralph to work through, in priority order.
Each line: `- [ ]` pending, `- [~]` in-progress, `- [x]` done.

## Next Up

- [ ] Add OSC voice integration: wire lib/voices/osc.lua into app.lua as an alternative voice backend alongside MIDI, with per-track OSC target params (host/port), so external synths (SuperCollider, Max/MSP) can receive note events
- [ ] Add norns platform entrypoint: create re_kriate.lua (norns main script) that mirrors seamstress.lua but uses norns screen API, norns key/enc callbacks, and nb voice output instead of MIDI. Grid and sequencer modules are shared.
- [ ] Add pattern bank keyboard shortcuts: wire pattern save/load to number keys with modifier (shift+1-8 to save, alt+1-8 to load) on seamstress keyboard, with visual feedback on screen_ui showing which slot is active
- [ ] Add swing/shuffle per track: add a swing parameter (0-100%) per track that offsets every other step's timing, creating groove feel. Wire into sequencer clock logic.
