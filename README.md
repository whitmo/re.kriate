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
- Multiple voice backends: MIDI, OSC, SuperCollider drums, softcut sampler
- [nb](https://github.com/sixolet/nb) voice output on norns
- Per-track swing and trigger clocking
- Per-parameter clock division
- Monome grid UI with trigger overview, per-parameter editing, and extended page toggle
- Push 2 grid support (Ableton Push 2 as 16x8 monome grid)
- Dedicated probability and alt-track grid pages for performance controls
- Remote control API (OSC transport)
- Keyboard fallback controls (seamstress)
- Musically useful default patterns out of the box
- Pattern bank disk persistence API with checksum validation
- Sprite visualization layer (seamstress)

### Norns

- [nb](https://github.com/sixolet/nb) voice output (engines, MIDI, crow)

### Seamstress

- Configurable voice per track (MIDI, OSC, SuperCollider drums, softcut sampler)
- Keyboard controls (no encoders/keys needed)
- Simulated grid display with mouse interaction
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
/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua
```

Make sure a MIDI device is connected before launching. The script sends MIDI on channels 1-4 (one per track) by default, configurable in the params menu.

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
  9        cycle: duration → velocity → probability
  11       loop edit (hold)
  12       pattern mode (hold)
  13       mute toggle
  14       scale page
  15       alt-track page
```

**Trigger page:** rows 1-4 show all 4 tracks at once. Press to toggle steps.

**Value pages** (note, octave, duration, velocity, ratchet, alt note, glide): rows 1-7 show the active track. Row 1 = highest value (7), row 7 = lowest (1). Press to set a step's value.

**Probability page:** nav `x=11` opens trigger probability editing for the active track. Rows 1-7 act like a value page, mapping top-to-bottom from high to low probability.

**Alt-track page:** nav `x=15` opens a per-track performance page. Each row is a track; columns `1-4` set direction, `5-11` set division, `12-15` set coarse swing, and `16` toggles mute.

**Extended pages:** double-tap a page button to toggle its extended parameter:
- trigger → **ratchet** (number of note repeats within a step, 1-7)
- note → **alt note** (secondary note offset combined with note degree)
- octave → **glide** (portamento amount, 1 = none, 7 = max)

**Loop editing:** hold grid key 12 on row 8, then press two step columns to set the loop start and end for the current page/track.

**Right-click latch (seamstress simulated grid):** right-click nav `x=12` to latch/unlatch loop hold, or nav `x=14` to latch/unlatch pattern hold without keeping the mouse button down.

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
| Q / W / E / T / Y | Select page (trig / note / oct / dur / vel) |
| Ctrl+P | Jump to probability page |
| Ctrl+B | List saved pattern banks |
| Ctrl+S | Save current pattern bank by name |
| Ctrl+L | Load current pattern bank by name |
| Ctrl+Shift+D | Delete current pattern bank by name |
| Ctrl+1-9 | Save pattern to slot |
| Shift+1-9 | Load pattern from slot |

### Pattern bank persistence

Pattern slots now have a disk persistence module in `lib/pattern_persistence.lua`.
It saves the full 16-slot bank with a checksum guard so corrupted files are rejected
before `ctx` is mutated.

```lua
local pp = require("lib/pattern_persistence")

local ok, path_or_err = pp.save(ctx, "my-set")
assert(ok, path_or_err)

local loaded, err = pp.load(ctx, "my-set")
assert(loaded, err)

local banks = pp.list()
assert.are.same({"my-set"}, banks)
```

For a quick manual smoke test, use `lua scripts/pattern_persistence_demo.lua save demo`
and `lua scripts/pattern_persistence_demo.lua load demo`, or run tests with
`./scripts/busted.sh --no-auto-insulate specs/pattern_persistence_spec.lua`.
On seamstress, the params menu exposes the same save/load/list/delete actions under
the `pattern persistence` group, and keyboard shortcuts surface status messages on
the screen.

### Parameters

- **root note** -- scale root (MIDI note, default 60/C4)
- **scale** -- Major, Natural Minor, Dorian, Mixolydian, Lydian, Phrygian, Locrian, Harmonic Minor, Melodic Minor, Pentatonic Major, Pentatonic Minor, Blues, Whole Tone, Chromatic
- **track N division** -- clock division per track (1/16 through 1/1)
- **track N direction** -- playhead direction per track
- **voice N** -- nb voice assignment per track (norns only)
- **track N channel** -- MIDI channel per track (seamstress only)

### Value ranges

| Parameter | Range | Meaning |
|-----------|-------|---------|
| trigger | 0-1 | on/off |
| note | 1-7 | scale degree |
| octave | 1-7 | octave offset (4 = center) |
| duration | 1-7 | 1/16 beat to 4 beats |
| velocity | 1-7 | 0.15 to 1.0 |
| ratchet | 1-7 | note repeats per step (1 = normal) |
| alt note | 1-7 | degree offset added to note (1 = none) |
| glide | 1-7 | portamento amount (1 = none) |
| probability | 1-7 | trigger probability (1 = 0%, 7 = 100%) |

### Direction modes

Each track has a direction mode that controls how all its parameters step through the loop:

- **forward** -- left to right, wrap at end
- **reverse** -- right to left, wrap at start
- **pendulum** -- bounce back and forth
- **drunk** -- random walk (+/-1 or stay)
- **random** -- jump to any position in loop

## Architecture

```
re_kriate.lua                    norns entrypoint (thin global hooks)
seamstress.lua                   seamstress entrypoint (MIDI voices, keyboard, sprites)

lib/app.lua                      init, params, grid, screen, key/enc
lib/sequencer.lua                clock-driven step advancement, voice output
lib/track.lua                    data model (steps, loops, defaults)
lib/grid_ui.lua                  grid display and input
lib/scale.lua                    scale quantization via musicutil
lib/pattern.lua                  pattern save/load slots
lib/pattern_persistence.lua      pattern bank save/load/list/delete on disk
lib/direction.lua                playhead direction modes
lib/grid_provider.lua            pluggable grid provider interface (monome, midigrid, virtual, simulated, push2, synthetic)
lib/grid_push2.lua               Ableton Push 2 grid adapter
lib/events.lua                   lightweight pub/sub event bus
lib/log.lua                      leveled logging with crash-capture wrappers

lib/voices/midi.lua              direct MIDI voice output
lib/voices/osc.lua               OSC voice output
lib/voices/sc_drums.lua          SuperCollider drum voice
lib/voices/softcut_zig.lua       softcut sampler voice
lib/voices/softcut_runtime.lua   buffer management runtime for softcut
lib/voices/sprite.lua            visual sprite events
lib/voices/recorder.lua          test voice (captures events)

lib/norns/nb_voice.lua           nb voice wrapper (norns only)

lib/seamstress/keyboard.lua      keyboard input handler
lib/seamstress/screen_ui.lua     seamstress screen display
lib/seamstress/grid_render.lua   simulated grid renderer
lib/seamstress/sprite_render.lua sprite drawing

lib/remote/api.lua               transport-agnostic remote control API
lib/remote/grid_api.lua          remote grid state and key injection
lib/remote/osc.lua               OSC transport for remote API

docs/grid-interface.html         interactive visual guide to the grid UI
```

All state flows through a single `ctx` table. No custom globals.

## References

- [monome/ansible](https://github.com/monome/ansible) — original kria firmware (C)
- [zjb-s/n.kria](https://github.com/zjb-s/n.kria) — norns kria port
- [Dewb/monome-rack](https://github.com/Dewb/monome-rack) — VCV Rack port
- [kria docs](https://monome.org/docs/ansible/kria/) — behavioral reference
