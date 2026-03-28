# Quickstart: Complete Seamstress Kria Sequencer

**Branch**: `001-seamstress-kria-features` | **Date**: 2026-03-06

## Prerequisites

- Lua 5.4
- busted (test framework): `luarocks install busted`
- seamstress v1.4.7: `/opt/homebrew/opt/seamstress@1/bin/seamstress`
- Monome grid 128 (optional, keyboard fallback available)
- MIDI output device (optional, recorder voice for testing)

## Run Tests

```bash
./scripts/busted.sh --no-auto-insulate specs/
```

Current headless baseline: 785 passing, 1 pending (`seamstress_load_spec.lua` is opt-in).
Every new feature must have a failing test committed before implementation.

## Run the App

```bash
# From the repo root:
/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua
```

The grid should light up with the default pattern. A desktop window appears with status info.

## Controls

### Grid (row 8 navigation)
| Column | Function |
|--------|----------|
| 1-4 | Track select |
| 5 | Mute toggle |
| 6 | Trigger (double-press: Ratchet) |
| 7 | Note (double-press: Alt Note) |
| 8 | Octave (double-press: Glide) |
| 9 | Duration |
| 10 | Velocity |
| 11 | Probability |
| 12 | Loop modifier (hold) |
| 15 | Alt-track (direction/division/swing/mute) |
| 16 | Play/Stop |

- `x=11` opens the probability page for the active track.
- `x=15` opens the alt-track page: rows map to tracks; direction/division/swing/mute live on that page.
- On the simulated seamstress grid, right-click `x=12` or `x=14` on row 8 to latch loop or pattern hold.

### Keyboard
| Key | Function |
|-----|----------|
| Space | Play/Stop |
| r | Reset playheads |
| 1-4 | Track select |
| q/w/e/t/y | Trigger/Note/Octave/Duration/Velocity |
| Ctrl+P | Probability page |
| Ctrl+B | List saved pattern banks |
| Ctrl+S | Save current pattern bank |
| Ctrl+L | Load current pattern bank |
| Ctrl+Shift+D | Delete current pattern bank |
| Ctrl+1-9 | Save pattern slot |
| Shift+1-9 | Load pattern slot |

## Development Workflow

1. **Red**: Write a failing test in `specs/` for the behavior you want
2. **Green**: Write minimum code in `lib/` to make it pass
3. **Refactor**: Clean up while keeping tests green
4. Commit and push to your feature branch
5. Open a PR against `main`

## Project Structure

```
re_kriate.lua                  # norns entrypoint
seamstress.lua                 # seamstress entrypoint
lib/
  app.lua                      # App init, params, cleanup
  track.lua                    # Track data model
  sequencer.lua                # Clock-driven sequencer engine
  grid_ui.lua                  # Grid display and input
  scale.lua                    # Scale quantization
  pattern.lua                  # Pattern storage (NEW)
  direction.lua                # Direction mode logic (NEW)
  pattern_persistence.lua      # Disk-backed pattern bank persistence
  voices/
    midi.lua                   # MIDI voice backend
    recorder.lua               # Test voice (captures events)
  norns/
    nb_voice.lua               # norns nb voice backend
  seamstress/
    screen_ui.lua              # Seamstress screen display
    keyboard.lua               # Keyboard input
specs/
  *_spec.lua                   # busted test files
```
