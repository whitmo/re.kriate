# Changelog

All notable changes to re.kriate will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- MIDI clock sync (spec 010): external clock source, clock output at 24 PPQ, Start/Stop/Continue transport messages, clock status display (re-ot4)
- Hardware kria parity: pattern cueing with quantized transitions. During
  playback, pressing a pattern slot (pattern-held) queues the transition for
  the next track-1 loop boundary instead of jumping mid-loop. Pressing the
  current or already-cued slot cancels the cue; pressing a different slot
  overwrites the pending cue. Cued slot renders at brightness 13 on the grid.
  When stopped, pattern loads remain immediate. Meta-pattern, when active,
  still owns transitions. (re-f9i)

### Fixed
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
