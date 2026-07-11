# Seamstress v1 vs v2 Findings

## Current install
- v2.0.0-alpha: `/opt/homebrew/opt/seamstress@2/bin/seamstress` (symlinked as `seamstress`)
- v1.4.7: `/opt/homebrew/opt/seamstress@1/bin/seamstress` (keg-only, not in PATH)

## v2.0.0-alpha issues
- Our entrypoint fails with `attempt to index a nil value (global 'grid')`
- `seamstress --test --test-dir specs` runs only built-in tests (39), not our specs
- API differences from norns: grid, metro, clock may work differently

## v1.4.7 compatibility (CONFIRMED WORKING)
- All globals present: `midi`, `grid`, `screen`, `clock`, `metro`, `params`, `util`
- `musicutil` available via require (not a global, but in package path)
- `grid.connect()` works and finds the monome grid
- `metro.init()` works
- `clock.run`, `clock.sync`, `clock.cancel`, `clock.get_beats` all present
- `params:add_number`, `params:add_option`, `params:set_action` all present
- `screen.color`, `screen.rect_fill`, `screen.refresh` all present

## Module loading test (v1.4.7)
All pass: lib/track, lib/scale, lib/grid_ui, lib/voices/midi, lib/voices/recorder,
lib/sequencer, lib/seamstress/screen_ui, lib/seamstress/keyboard, lib/app

## Full integration test (v1.4.7)
- `app.init({voices = recorder_voices})` succeeds
- 4 tracks, 57 scale notes, keyboard input toggles play state
- `sequencer.step_track()` fires events into recorder buffer
- `screen_ui.redraw()` succeeds

## Running the entrypoint
- `-s re_kriate_seamstress` works: grid detected, init succeeds, "initialized" printed
- MIDI error `MidiInCore::openPort: error connecting OS-X MIDI input port` when no MIDI device present — may crash
- Process exits when run headless (no SDL window), stays alive when wrapped

## Recommendation
Use seamstress v1.4.7. The v2 alpha API has breaking changes we don't need to fight.
Either:
1. Symlink v1 as the default (`brew link --overwrite seamstress@1`)
2. Use full path: `/opt/homebrew/opt/seamstress@1/bin/seamstress`
