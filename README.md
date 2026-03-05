# re.kriate

A kria-inspired polymetric sequencer for norns (seamstress support planned).

Based on [kria](https://monome.org/docs/ansible/kria/) from monome Ansible -- each track has independent loop lengths per parameter, creating evolving polymetric patterns.

## Features

- 4 tracks with independent clocks and per-track clock division
- Per-parameter loop lengths (trigger, note, octave, duration, velocity)
- Scale quantization (14 scales via musicutil)
- [nb](https://github.com/sixolet/nb) voice output
- Monome grid UI with trigger overview and per-parameter editing
- Musically useful default patterns out of the box

## Requirements

### Norns

- norns (any hardware revision) or norns shield
- Monome grid (128 recommended, 64 usable)
- [nb](https://github.com/sixolet/nb) library installed
- At least one nb-compatible voice (e.g. nb_mx.synths, midi, crow)

### Seamstress (planned)

Seamstress 2.0 is the intended primary dev target but is not yet supported. The current code uses norns-specific APIs (`params`, `metro`, `nb`, `musicutil`, `util`) that don't have seamstress equivalents yet. Contributions welcome.

## Install (norns)

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

### Parameters (norns menu)

- **root note** -- scale root (MIDI note, default 60/C4)
- **scale** -- Major, Natural Minor, Dorian, Mixolydian, Lydian, Phrygian, Locrian, Harmonic Minor, Melodic Minor, Pentatonic Major, Pentatonic Minor, Blues, Whole Tone, Chromatic
- **track N division** -- clock division per track (1/16 through 1/1)
- **voice N** -- nb voice assignment per track

## Architecture

```
re_kriate.lua          main script (thin global hooks)
lib/app.lua            init, params, grid, screen, key/enc
lib/sequencer.lua      clock-driven step advancement, nb output
lib/track.lua          data model (steps, loops, defaults)
lib/grid_ui.lua        grid display and input
lib/scale.lua          scale quantization via musicutil
```

All state flows through a single `ctx` table. No custom globals.

## References

- [monome/ansible](https://github.com/monome/ansible) -- original kria firmware (C)
- [zjb-s/n.kria](https://github.com/zjb-s/n.kria) -- norns kria port
- [Dewb/monome-rack](https://github.com/Dewb/monome-rack) -- VCV Rack port
- [kria docs](https://monome.org/docs/ansible/kria/) -- behavioral reference
