# Changelog

All notable changes to re.kriate will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
- Time modifier / clock divider (re-di2)
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
