# re.kriate

A kria-inspired polymetric sequencer for norns and seamstress.

Based on [kria](https://monome.org/docs/ansible/kria/) from monome Ansible -- each track has independent loop lengths per parameter, creating evolving polymetric patterns.

## Features

- 4 tracks with independent clocks and per-track clock division
- Per-parameter loop lengths (trigger, note, octave, duration, velocity)
- Scale quantization (14 scales via musicutil)
- Monome grid UI with trigger overview and per-parameter editing
- Musically useful default patterns out of the box
- Sprite visualization layer (seamstress)

### Norns

- [nb](https://github.com/sixolet/nb) voice output (engines, MIDI, crow)

### Seamstress

- Direct MIDI output (one device per track, configurable channel)
- Keyboard controls (no encoders/keys needed)
- Sprite rendering -- visual feedback on the seamstress screen

## Requirements

### Norns

- norns (any hardware revision) or norns shield
- Monome grid (128 recommended, 64 usable)
- [nb](https://github.com/sixolet/nb) library installed
- At least one nb-compatible voice (e.g. nb_mx.synths, midi, crow)

### Seamstress

- [seamstress](https://github.com/ryleelyman/seamstress) v1.4.x (v2 is not yet supported)
- Monome grid (128 recommended)
- A MIDI device on port 1 (configurable via params)

## Install & Run

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

### Seamstress (v1)

Clone the repo anywhere:

```
git clone https://github.com/whit/re.kriate
cd re.kriate
```

Run with the `-s` flag:

```
/opt/homebrew/opt/seamstress@1/bin/seamstress -s re_kriate_seamstress.lua
```

Make sure a MIDI device is connected before launching. The script sends MIDI on channels 1-4 (one per track) by default, configurable in the params menu.

## Controls

### Grid (16x8)

```
Rows 1-7: step data (varies by page)
Row 8:    navigation

Row 8 layout:
  1-4      track select
  6-10     page select (trig / note / oct / dur / vel)
  12       loop edit (hold)
  16       play / stop
```

**Trigger page:** rows 1-4 show all 4 tracks at once. Press to toggle steps.

**Value pages** (note, octave, duration, velocity): rows 1-7 show the active track. Row 1 = highest value (7), row 7 = lowest (1). Press to set a step's value.

**Loop editing:** hold grid key 12 on row 8, then press two step columns to set the loop start and end for the current page/track.

### Norns keys and encoders

| Control | Action |
|---------|--------|
| E1 | Select track (1-4) |
| E2 | Select page |
| K2 | Play / stop |
| K3 | Reset all playheads |

### Seamstress keyboard

| Key | Action |
|-----|--------|
| Space | Play / stop |
| R | Reset all playheads |
| 1-4 | Select track |
| Q / W / E / T / Y | Select page (trig / note / oct / dur / vel) |
| Ctrl+1-9 | Save pattern to slot |
| Shift+1-9 | Load pattern from slot |

### Parameters

- **root note** -- scale root (MIDI note, default 60/C4)
- **scale** -- Major, Natural Minor, Dorian, Mixolydian, Lydian, Phrygian, Locrian, Harmonic Minor, Melodic Minor, Pentatonic Major, Pentatonic Minor, Blues, Whole Tone, Chromatic
- **track N division** -- clock division per track (1/16 through 1/1)
- **track N direction** -- playhead direction per track
- **voice N** -- nb voice assignment per track (norns only)
- **track N channel** -- MIDI channel per track (seamstress only)

## Architecture

```
re_kriate.lua              norns entrypoint (thin global hooks)
re_kriate_seamstress.lua   seamstress entrypoint (MIDI voices, keyboard, sprites)

lib/app.lua                init, params, grid, screen, key/enc
lib/sequencer.lua          clock-driven step advancement
lib/track.lua              data model (steps, loops, defaults)
lib/grid_ui.lua            grid display and input
lib/scale.lua              scale quantization via musicutil
lib/pattern.lua            pattern save/load slots
lib/direction.lua          playhead direction modes

lib/voices/midi.lua        direct MIDI voice output
lib/voices/sprite.lua      visual sprite events
lib/voices/recorder.lua    event recording

lib/norns/nb_voice.lua     nb voice wrapper (norns only)

lib/seamstress/keyboard.lua      keyboard input
lib/seamstress/screen_ui.lua     screen display
lib/seamstress/sprite_render.lua sprite drawing
```

All state flows through a single `ctx` table. No custom globals.

## References

- [monome/ansible](https://github.com/monome/ansible) -- original kria firmware (C)
- [zjb-s/n.kria](https://github.com/zjb-s/n.kria) -- norns kria port
- [Dewb/monome-rack](https://github.com/Dewb/monome-rack) -- VCV Rack port
- [kria docs](https://monome.org/docs/ansible/kria/) -- behavioral reference
