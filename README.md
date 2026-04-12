# re.kriate

A kria-inspired polymetric sequencer for [norns](https://monome.org/docs/norns/) and [seamstress](https://github.com/ryleelyman/seamstress).

Based on [kria](https://monome.org/docs/ansible/kria/) from monome Ansible — each track has independent loop lengths per parameter, creating evolving polymetric patterns.

For an interactive visual guide to the grid interface, see [`docs/html/grid-interface.html`](docs/html/grid-interface.html).

## Features

- 4 tracks with independent clocks and per-track clock division
- Per-parameter loop lengths (trigger, note, octave, duration, velocity, probability, ratchet, alt note, glide)
- Per-parameter clock divider (Time modifier)
- 5 direction modes: forward, reverse, pendulum, drunk, random
- Per-track mute and swing
- Scale quantization — 14 built-in scales plus a custom mask editor
- Trigger probability (1-7 → 0–100%) with ratchet gating
- Ratchet: per-sub-gate bitmask display on its own grid page
- Pattern bank with 16 slots, quantized cueing during playback, disk persistence
- Meta-sequencer: ordered pattern sequence with per-step loop counts
- Full session presets (tracks + patterns + meta-sequence + params) with checksum guard and autosave
- MIDI clock sync — external slave, internal master clock output, Start/Stop/Continue transport
- Multiple voice backends: MIDI, OSC, SuperCollider synth (sub/fm/wavetable), SuperCollider drums, softcut sampler, sprite (visual)
- [nb](https://github.com/sixolet/nb) voice output on norns
- Monome grid UI (16x8) with page-tray screen indicator, trigger/value pages, loop editing, hold modifiers
- Push 2 grid support (Ableton Push 2 as 16x8 monome grid)
- Help overlay (`?`), grid theme cycling (yellow/red/orange/white)
- Remote control API (OSC transport)
- Keyboard fallback controls (seamstress)

## Requirements

### Norns

- norns (any hardware revision) or norns shield
- Monome grid (128 recommended, 64 usable)
- [nb](https://github.com/sixolet/nb) library installed
- At least one nb-compatible voice (e.g. nb_mx.synths, midi, crow)

### Seamstress

- [seamstress](https://github.com/ryleelyman/seamstress) v1.4.7+ (v2 is not yet supported)
- Monome grid (128 recommended) — or use the simulated grid window
- A MIDI device for the default MIDI voice (optional; configurable per track)

## Install & Run

### Norns

From maiden (norns web REPL):

```
;install https://github.com/whitmo/re.kriate
```

Or manually clone into `~/dust/code/`:

```
cd ~/dust/code
git clone https://github.com/whitmo/re.kriate re_kriate
```

Then select **re.kriate** from the norns script menu.

### Seamstress (v1)

Clone the repo anywhere:

```
git clone https://github.com/whitmo/re.kriate
cd re.kriate
```

Run with the `-s` flag:

```
/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua
```

The script sends MIDI on channels 1-4 (one per track) by default, configurable in the params menu. See [`docs/voice-quickstart.md`](docs/voice-quickstart.md) to switch a track to OSC, SuperCollider, or softcut.

## Controls

### Grid (16x8)

```
Rows 1-7: step data (varies by page)
Row 8:    navigation

Row 8 layout:
  1-4      track select
  5        KEY 1 — time modifier (hold: per-param clock division)
  6        trigger page (press again: ratchet)
  7        note page (press again: alt note)
  8        octave page (press again: glide)
  9        cycles: duration → velocity → probability
  10       KEY 2 — config / alt-track page
  11       loop modifier (hold)
  12       pattern mode (hold)
  13       mute toggle
  14       probability modifier (hold)
  15       scale page
  16       meta (double-press: meta-pattern sequencer)
```

**Trigger page:** rows 1-4 show all 4 tracks at once. Press to toggle steps.

**Value pages** (note, octave, duration, velocity, probability, alt note, glide): rows 1-7 show the active track. Row 1 = highest value (7), row 7 = lowest (1). Press to set a step's value.

**Ratchet page:** rows 1-7 show a per-step bitmask of sub-gates (which sub-divisions of the step fire). Toggle individual sub-gates by pressing.

**Alt-track page** (nav `x=10` or `x=16`): per-track performance page. Each row is a track; columns `1-4` set direction, `5-11` set division, `13-15` set coarse swing, `16` toggles mute.

**Scale page** (nav `x=15`): select a built-in scale or edit the custom scale mask (toggle individual semitones within an octave).

**Meta-pattern page** (double-press nav `x=16`): sequence pattern slots with per-step loop counts; playback walks through the meta-sequence, each step playing its slot for N track-1 loops.

**Extended pages:** press the same nav button a second time to toggle its extended parameter:
- trigger → **ratchet** (per-step sub-gate bitmask)
- note → **alt note** (secondary note offset, additive with note degree)
- octave → **glide** (portamento amount, 1 = none, 7 = max)

**Loop editing (hold x=11):** hold the loop modifier, then press two step columns to set the loop start and end for the current page/track.

**Probability overlay (hold x=14):** hold the probability modifier to see and edit per-step trigger probability without leaving the current page.

**Pattern mode (hold x=12):** rows 1-2 become 16 pattern slots. Press a slot to load it. While the sequencer is playing, the load is *queued* and transitions at the next track-1 loop boundary (quantized cueing); cued slots render at brightness 13. When stopped, loads are immediate. Latch pattern hold by right-clicking the nav button (simulated grid).

**Right-click latches (simulated grid):** right-click nav `x=11` to latch/unlatch loop hold, `x=12` for pattern hold, `x=14` for probability hold.

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
| D | Cycle direction mode for active track |
| F1 | Toggle time modifier (per-param division overlay) |
| F2 | Jump to alt-track page |
| L | Toggle loop hold |
| Ctrl+P | Toggle probability overlay |
| Ctrl+A | Jump to alt-track page |
| Ctrl+B | List saved pattern banks |
| Ctrl+S / Ctrl+L | Save / load current pattern bank by name |
| Ctrl+Shift+D | Delete current pattern bank by name |
| Ctrl+1-9 | Save pattern to slot |
| Shift+1-9 | Load pattern from slot |
| Ctrl+Shift+T | Cycle grid theme |
| ? | Toggle help overlay |

### Pattern bank persistence

Pattern banks are stored as `.krp` files under platform data dirs (norns `dust/data`, seamstress XDG data dir) with an Adler-32 checksum guard so corrupted files are rejected before `ctx` is mutated. Bank saves include the full 16-slot bank plus meta-sequencer state.

```lua
local pp = require("lib/pattern_persistence")

local ok, path_or_err = pp.save(ctx, "my-set")
local loaded, err    = pp.load(ctx, "my-set")
local banks          = pp.list()
```

The params menu exposes save/load/list/delete actions under the **pattern persistence** group. On seamstress, keyboard shortcuts surface status messages on the screen.

### Session presets

`lib/preset.lua` snapshots a full session: all tracks, pattern bank, meta-sequence, and re.kriate-managed params (root_note, scale_type, osc host/port, clock source/output, active bank, per-track voice/channel/synthdef/sample/division/direction/swing). Presets are saved as `.krp` files with the same checksum scheme. Autosave is available via the `preset_autosave` param — on startup the `_autosave` preset is loaded; on cleanup it is rewritten.

### MIDI clock sync

`lib/clock_sync.lua` implements 24-PPQ MIDI clock sync (spec 010):

- **Internal master** (default): re.kriate drives its own clock. Enable `clock_output` to send MIDI Clock + Start/Stop/Continue out to the configured MIDI port.
- **External slave** (`clock_source = external MIDI`): the sequencer locks to incoming MIDI clock pulses, with BPM estimated over a rolling 24-pulse window. Start/Stop/Continue transport messages drive sequencer start/stop.

The screen UI shows a clock status indicator when external clock is selected.

### Parameters

- **root note** — scale root (MIDI note, default 60 / C4)
- **scale** — Major, Natural Minor, Dorian, Mixolydian, Lydian, Phrygian, Locrian, Harmonic Minor, Melodic Minor, Major Pentatonic, Minor Pentatonic, Blues Scale, Whole Tone, Chromatic, **Custom** (editable mask)
- **track N division** — clock division per track (1/16 through 1/1)
- **track N direction** — playhead direction per track
- **track N swing** — 0-100%
- **track N voice** — `midi`, `osc`, `sc_synth`, `sc_drums`, `softcut`, `none` (seamstress); nb voice on norns
- **track N midi ch** — MIDI channel (seamstress only)
- **track N sc synthdef** — `sub`, `fm`, `wavetable` (when voice = `sc_synth`)
- **clock source** — `internal` or `external MIDI`
- **clock output** — off / on
- **pattern bank name / preset name** — active bank/preset for save/load
- **preset autosave** — on/off

### Value ranges

| Parameter | Range | Meaning |
|-----------|-------|---------|
| trigger | 0-1 | on/off |
| note | 1-7 | scale degree |
| octave | 1-7 | octave offset (4 = center) |
| duration | 1-7 | 1/16 beat to 4 beats |
| velocity | 1-7 | 0.15 to 1.0 |
| ratchet | 1-7 | number of sub-gates within the step (per-gate bitmask) |
| alt note | 1-7 | degree offset added to note (1 = none) |
| glide | 1-7 | portamento amount (1 = none) |
| probability | 1-7 | trigger probability (1 = 0%, 7 = 100%) |

### Direction modes

Each track has a direction mode that controls how all its parameters step through the loop:

- **forward** — left to right, wrap at end
- **reverse** — right to left, wrap at start
- **pendulum** — bounce back and forth
- **drunk** — random walk (+/-1 or stay)
- **random** — jump to any position in loop

## Architecture

```
re_kriate.lua                    norns entrypoint (thin global hooks)
seamstress.lua                   seamstress entrypoint (voices, keyboard, sprites)

lib/app.lua                      init, params, grid, screen, key/enc orchestration
lib/sequencer.lua                clock-driven step advancement, voice output
lib/track.lua                    data model (steps, loops, defaults)
lib/grid_ui.lua                  grid display and input
lib/scale.lua                    scale quantization + custom mask
lib/pattern.lua                  in-memory pattern save/load slots
lib/pattern_persistence.lua      disk persistence (.krp, checksum-guarded)
lib/preset.lua                   full session preset save/load + autosave
lib/meta_pattern.lua             meta-sequencer (ordered pattern sequence)
lib/direction.lua                playhead direction modes
lib/clock_sync.lua               MIDI clock sync (external slave, clock output)
lib/grid_provider.lua            pluggable grid backend (monome, midigrid, virtual, simulated, push2, synthetic)
lib/grid_push2.lua               Ableton Push 2 grid adapter
lib/events.lua                   lightweight pub/sub event bus
lib/log.lua                      leveled logging with crash-capture wrappers

lib/voices/midi.lua              direct MIDI voice output
lib/voices/osc.lua               OSC voice output (SuperCollider-shaped OSC)
lib/voices/sc_synth.lua          SuperCollider melodic synth (sub/fm/wavetable)
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
lib/seamstress/help_overlay.lua  on-screen help overlay

lib/remote/api.lua               transport-agnostic remote control API
lib/remote/grid_api.lua          remote grid state and key injection
lib/remote/osc.lua               OSC transport for remote API

docs/html/grid-interface.html    interactive visual guide to the grid UI
docs/html/voices.html            voice system deep dive
docs/html/event-system-explainer.html   event bus architecture
docs/html/polymetric-sequencing.html    polymetric tutorial
docs/html/synthetic-grid-explainer.html synthetic grid explainer
```

All state flows through a single `ctx` table. No custom globals.

## Documentation

- [`docs/voice-quickstart.md`](docs/voice-quickstart.md) — voice backends and demo scripts
- [`docs/supercollider-setup.md`](docs/supercollider-setup.md) — SuperCollider voice setup
- [`docs/html/`](docs/html) — visual guides (grid, voices, events, polymetry)
- [`docs/archive/`](docs/archive) — historical snapshots and reports
- [`CHANGELOG.md`](CHANGELOG.md) — release notes

## References

- [monome/ansible](https://github.com/monome/ansible) — original kria firmware (C)
- [zjb-s/n.kria](https://github.com/zjb-s/n.kria) — norns kria port
- [Dewb/monome-rack](https://github.com/Dewb/monome-rack) — VCV Rack port
- [kria docs](https://monome.org/docs/ansible/kria/) — behavioral reference
