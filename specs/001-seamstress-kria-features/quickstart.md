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
busted specs/
```

All 87+ tests should pass. Every new feature must have a failing test committed before implementation.

## Run the App

```bash
# From the repo root:
/opt/homebrew/opt/seamstress@1/bin/seamstress -s re_kriate_seamstress
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
| 12 | Loop modifier (hold) |
| 16 | Play/Stop |

### Keyboard
| Key | Function |
|-----|----------|
| Space | Play/Stop |
| r | Reset playheads |
| m | Mute toggle |
| 1-4 | Track select |
| q/w/e/t/y | Trigger/Note/Octave/Duration/Velocity |

## Development Workflow

1. **Red**: Write a failing test in `specs/` for the behavior you want
2. **Green**: Write minimum code in `lib/` to make it pass
3. **Refactor**: Clean up while keeping tests green
4. Commit and push to your feature branch
5. Open a PR against `main`

## Project Structure

```
re_kriate.lua                  # norns entrypoint
re_kriate_seamstress.lua       # seamstress entrypoint
lib/
  app.lua                      # App init, params, cleanup
  track.lua                    # Track data model
  sequencer.lua                # Clock-driven sequencer engine
  grid_ui.lua                  # Grid display and input
  scale.lua                    # Scale quantization
  pattern.lua                  # Pattern storage (NEW)
  direction.lua                # Direction mode logic (NEW)
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
