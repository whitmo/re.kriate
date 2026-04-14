# Changelog

All notable changes to re.kriate will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed
- Simulated grid aesthetics (`lib/seamstress/grid_render.lua`,
  `lib/seamstress/screen_ui.lua`, `seamstress.lua`): tighter cell spacing
  (1px gaps at sizes 128/256, 2px at 64) for richer LED presence. The
  bottom page-label tray moves to a vertical info panel on the right of
  the grid with full page names ("trigger", "probability", etc.) rather
  than two-letter abbreviations, transport state, per-track step counters
  with an active-track marker, a dynamic "last press" readout fed by
  mouse clicks, pattern slot indicators, and save/load messages. Legacy
  `screen_ui.redraw` is preserved for the existing test surface. (re-1mo)

### Added
- Seamstress console `help()` object (`lib/seamstress/help_console.lua`):
  installed into the Lua console at init as a callable namespace exposing
  `help.ctx` (live application context), `help.transport` (sequencer play /
  stop / reset plus a state snapshot) and `help.debug` (log path, `tail(n)`,
  `ctx_dump`, voice + params + remote-API introspection). Calling `help()`,
  `help.transport()` or `help.debug()` prints a per-topic reference so the
  surface is discoverable from inside seamstress with no external docs.
  (re-107)
- Startup banner (`lib/startup_info.lua`): prints `=== re.kriate ===` with git
  commit / branch / release and per-platform connection status at init. Reads
  git metadata directly from `.git` (worktree-aware: follows `gitdir:` pointers
  and falls back to `packed-refs`); reads release marker from the first
  `## [...]` heading in `CHANGELOG.md`, pairing `Unreleased` with the last
  shipped date when present. Wired into both entrypoints: `seamstress.lua`
  surfaces the configured SC target (host/port from `osc_host` / `osc_port`)
  plus softcut mode; `re_kriate.lua` shows softcut mode only (SC status on
  norns is per-voice). (re-4fs)
- SC ↔ seamstress bidirectional OSC handshake (`lib/sc_bridge.lua`): ping/pong
  protocol on `/rekriate/ping` → `/rekriate/pong {version, features...}`. Each
  companion .scd (voice, synths, drums, sub) replies with its own feature list;
  the Lua bridge merges them under a single handshake nonce so `is_connected()`
  and `status_string()` surface a canonical view. State machine
  `disconnected → pinging → connected` with timeout fallback. Demo in
  `scripts/demo_sc_handshake.lua`. (re-mgm)
- Launch scripts `bin/start-sc` and `bin/start-rekriate`: one-shot sclang
  bootstrap that loads the full companion stack (voice + mixer + sc_synth +
  sc_drums) via `sc/rekriate-bootstrap.scd`; `start-rekriate` also backgrounds
  SC and launches seamstress together. Prefers
  `/Applications/SuperCollider.app/Contents/MacOS/sclang`, falls back to
  `$PATH`. (re-mgm)
- Softcut platform-mode helper (`softcut_runtime.detect_mode` /
  `status_string` / `announce`): explicit `norns` vs `dry` mode distinction
  announced at init so seamstress users aren't misled into thinking softcut
  tracks are producing audio. (re-mgm)
- SC mixer engine (`sc/rekriate-mixer.scd`): standalone mixer layered on
  top of the voice engine. Allocates 4 mono channel buses + stereo aux
  send/return; groups execute voices → channels → aux → master.
  SynthDefs: `\rekriate_channel_strip` (filter HP/LP, insert reverb,
  insert delay, compressor, level, pan, mute, aux send) per channel;
  `\rekriate_aux` (global reverb + delay); `\rekriate_mixer_master`
  (aux-return sum + tanh soft-clip limiter via `ReplaceOut`). OSC
  responders on `/rekriate/mixer/channel/{1-4}/…`, `/rekriate/mixer/aux/…`,
  `/rekriate/mixer/master/…` for every strip parameter. Per-channel/aux/
  master peak metering at 30 Hz via `SendReply`, forwarded to a
  configurable NetAddr (`/rekriate/mixer/meter/target host port`). When
  the voice engine is loaded, the mixer patches `~rekriate[\playNote]` to
  spawn voices into the mixer's voices group with `\out` set to the
  channel bus, and tears down the simple trackstrip/master synths + their
  `/rekriate/mixer/track/...` responders so the new chain is
  authoritative. (re-4qz)
- SC engine mixer bus architecture: voices in `sc/rekriate-voice.scd` now
  route through per-track mono buses into persistent mixer-strip synths
  (level/pan/mute) and a master strip (master level), instead of applying
  pan/amp on ephemeral voice synths. Adds OSC responders
  `/rekriate/mixer/track/{1-4}/{level,pan,mute}` and
  `/rekriate/mixer/master/level`. Mixing state persists regardless of voice
  lifecycle. (re-u9w)
- Novation Launchpad Pro MK3 grid provider (`lib/grid_launchpad_pro.lua`):
  presents the 8x8 RGB pad grid as a 16x8 monome-style grid via page switching
  on the top-row Left/Right arrows. Enters Programmer mode on init, sends a
  single batched RGB sysex per refresh, and restores Live mode on cleanup.
  Registered as the `launchpad_pro` provider alongside `monome`, `push2`,
  `midigrid`, `virtual`, `simulated`, and `synthetic`. (re-yp0)
- Grid selection params ("grid" group): pick the grid backend at runtime via
  the params menu; provider swap cleans up the old grid and reconnects. MIDI
  port for push2 / launchpad_pro / midigrid is configurable via
  `grid_midi_device`. (re-yp0)
- MIDI clock sync (spec 010): external clock source, clock output at 24 PPQ, Start/Stop/Continue transport messages, clock status display (re-ot4)
- Hardware kria parity: pattern cueing with quantized transitions. During
  playback, pressing a pattern slot (pattern-held) queues the transition for
  the next track-1 loop boundary instead of jumping mid-loop. Pressing the
  current or already-cued slot cancels the cue; pressing a different slot
  overwrites the pending cue. Cued slot renders at brightness 13 on the grid.
  When stopped, pattern loads remain immediate. Meta-pattern, when active,
  still owns transitions. (re-f9i)

### Fixed
- Time modifier on value pages (note/octave/duration/velocity/etc.) now edits
  the param actually displayed on each row. Previously every press set the
  active param's `clock_div` regardless of which row was pressed, so the
  non-active params shown on rows 2-7 looked interactive but weren't — the
  button you pressed didn't move the cursor on that row. Row 1 still edits
  the active param; rows 2-7 edit the same other-param list the overlay
  draws. (re-0sy)
- Time modifier (F1) keyboard shortcut had no effect: seamstress delivers
  function keys as tables (`{name = "F1"}`), but the keyboard handler
  early-returned on non-string chars before reaching the F1/F2 branches.
  F1 now toggles `time_held` and F2 switches to alt_track as intended. (re-di2)

## [2026-04-03]

### Added
- Loop boundary indicators on simulated grid (light grey markers at loop start/end) (#95)
- Page indicator tray on screen UI with abbreviated labels (#93, #91)
- Cell edge borders for sharper grid visuals (#90)
- Dim notes outside active loop range on hardware grid (#92)
- Secondary page control row dimming (#94)
- KEY 1/KEY 2 nav buttons default to off in normal page mode (#89)
- Help overlay toggled with `?` key showing keyboard shortcuts
- Grid theme cycling with Ctrl+Shift+T (yellow, red, orange, white)
- Ctrl+click hold keys, Ctrl+Shift+click lock/toggle keys on simulated grid
- Page Up/Down navigation in params menu

### Fixed
- Clock resume crash from cancelled coroutine race condition (#88)
- Flaky CI grid_render perf test threshold increased to 1000ms (#87)

### In Progress
- Params menu back-navigation (re-35u)
- Probability modifier (re-2d4)
- Ratchet page UX improvements (re-sfk)
- screen_ui.redraw wiring into seamstress.lua render loop (re-5nt)

## [2026-04-01]

### Added
- Probability map (1-7) with ratchet all-or-nothing gating (#67)
- Probability x ratchet interaction (#59)
- Trigger clocking mode for hardware kria parity (#66)
- Per-parameter clock division via Time modifier key
- Feature inventory and interactive feature map (docs)
