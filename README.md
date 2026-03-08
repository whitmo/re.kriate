# re.kriate

A kria-inspired polymetric sequencer for [norns](https://monome.org/docs/norns/) and [seamstress](https://github.com/ryleelyman/seamstress).

Based on [kria](https://monome.org/docs/ansible/kria/) from monome Ansible — each track has independent loop lengths per parameter, creating evolving polymetric patterns.

For an interactive visual guide to the grid interface, see [`docs/grid-interface.html`](docs/grid-interface.html).

## Features

- 4 tracks with independent clocks and per-track clock division
- Per-parameter loop lengths (trigger, note, octave, duration, velocity)
- Extended parameters: ratchet, alt note, glide
- 5 direction modes: forward, reverse, pendulum, drunk, random
- Per-track mute
- Scale quantization (14 scales via musicutil)
- Voice abstraction: [nb](https://github.com/sixolet/nb) on norns, MIDI on seamstress
- Monome grid UI with trigger overview, per-parameter editing, and extended page toggle
- Keyboard fallback controls (seamstress)
- Musically useful default patterns out of the box

## Requirements

### Norns

- norns (any hardware revision) or norns shield
- Monome grid (128 recommended, 64 usable)
- [nb](https://github.com/sixolet/nb) library installed
- At least one nb-compatible voice (e.g. nb_mx.synths, midi, crow)

### Seamstress

- [Seamstress 2.0](https://github.com/ryleelyman/seamstress) (alpha or later)
- Monome grid (128 recommended)
- MIDI output device

## Install

### Norns

From maiden (norns web REPL):

```
;install https://github.com/whit/re.kriate
```

Or manually clone into `~/dust/code/`:

```
cd ~/dust/code
git clone https://github.com/whit/re.kriate re_kriate
```

Then select **re.kriate** from the norns script menu.

### Seamstress

Clone and run:

```
git clone https://github.com/whit/re.kriate
cd re.kriate
seamstress re_kriate_seamstress.lua
```

## Controls

### Grid (16x8)

```
Rows 1-7: step data (varies by page)
Row 8:    navigation

Row 8 layout:
  1-4      track select
  6        trigger page (double-tap: ratchet)
  7        note page (double-tap: alt note)
  8        octave page (double-tap: glide)
  9        duration page
  10       velocity page
  12       loop edit (hold)
  16       play / stop
```

**Trigger page:** rows 1-4 show all 4 tracks at once. Press to toggle steps.

**Value pages** (note, octave, duration, velocity, ratchet, alt note, glide): rows 1-7 show the active track. Row 1 = highest value (7), row 7 = lowest (1). Press to set a step's value.

**Extended pages:** double-tap a page button to toggle its extended parameter:
- trigger → **ratchet** (number of note repeats within a step, 1-7)
- note → **alt note** (secondary note offset combined with note degree)
- octave → **glide** (portamento amount, 1 = none, 7 = max)

**Loop editing:** hold grid key 12 on row 8, then press two step columns to set the loop start and end for the current page/track.

### Norns keys and encoders

| Control | Action |
|---------|--------|
| E1 | Select track (1-4) |
| E2 | Select page (cycles all 8 pages) |
| K2 | Play / stop |
| K3 | Reset all playheads |

### Seamstress keyboard

| Key | Action |
|-----|--------|
| Space | Play / stop |
| R | Reset all playheads |
| 1-4 | Select track |
| Q | Trigger page |
| W | Note page |
| E | Octave page |
| T | Duration page |
| Y | Velocity page |

### Parameters

- **root note** — scale root (MIDI note, default 60/C4)
- **scale** — Major, Natural Minor, Dorian, Mixolydian, Lydian, Phrygian, Locrian, Harmonic Minor, Melodic Minor, Pentatonic Major, Pentatonic Minor, Blues, Whole Tone, Chromatic
- **track N division** — clock division per track (1/16, 1/12, 1/8, 1/6, 1/4, 1/2, 1/1)
- **voice N** — nb voice assignment per track (norns only)
- **track N channel** — MIDI channel per track (seamstress only)

### Value ranges

| Parameter | Range | Meaning |
|-----------|-------|---------|
| trigger | 0-1 | on/off |
| note | 1-7 | scale degree |
| octave | 1-7 | octave offset (4 = center) |
| duration | 1-7 | 1/16 beat → 4 beats |
| velocity | 1-7 | 0.15 → 1.0 |
| ratchet | 1-7 | note repeats per step (1 = normal) |
| alt note | 1-7 | degree offset added to note (1 = none) |
| glide | 1-7 | portamento amount (1 = none) |

### Direction modes

Each track has a direction mode that controls how all its parameters step through the loop:

- **forward** — left to right, wrap at end
- **reverse** — right to left, wrap at start
- **pendulum** — bounce back and forth
- **drunk** — random walk (±1 or stay)
- **random** — jump to any position in loop

## Architecture

```
re_kriate.lua                 norns entrypoint (thin global hooks)
re_kriate_seamstress.lua      seamstress entrypoint (MIDI voices, keyboard)
lib/
  app.lua                     init, params, grid, screen, key/enc
  sequencer.lua               clock-driven step advancement, voice output
  track.lua                   data model (steps, loops, defaults)
  grid_ui.lua                 grid display and input
  scale.lua                   scale quantization via musicutil
  direction.lua               direction modes (forward, reverse, pendulum, drunk, random)
  norns/
    nb_voice.lua              nb voice wrapper for norns
  seamstress/
    screen_ui.lua             seamstress screen display
    keyboard.lua              keyboard input handler
  voices/
    midi.lua                  MIDI voice backend
    recorder.lua              test voice (captures events)
docs/
  grid-interface.html         interactive visual guide to the grid UI
```

All state flows through a single `ctx` table. No custom globals.

## Development Automation

Repository orchestration is configured in `ralph.yml`.

- Treat `ralph.yml` as the source of truth for Ralph event loop behavior.
- If hats are used, each hat MUST define clear `triggers` and `publishes`.
- Hat names and event contracts in `ralph.yml` MUST match the feature spec and tasks for
  the same change.

## References

- [monome/ansible](https://github.com/monome/ansible) — original kria firmware (C)
- [zjb-s/n.kria](https://github.com/zjb-s/n.kria) — norns kria port
- [Dewb/monome-rack](https://github.com/Dewb/monome-rack) — VCV Rack port
- [kria docs](https://monome.org/docs/ansible/kria/) — behavioral reference
