# Voice Quickstart

re.kriate supports 5 voice backends. Each track can use a different backend, set via the `voice` param in the norns/seamstress params menu.

| Voice | Backend | Output | Module |
|-------|---------|--------|--------|
| `midi` | Hardware/software MIDI | note_on/note_off + CC | `lib/voices/midi.lua` |
| `osc` | OSC over UDP | SuperCollider synth | `lib/voices/osc.lua` |
| `sc_drums` | OSC over UDP | SuperCollider drums | `lib/voices/sc_drums.lua` |
| `softcut` | norns softcut DSP | Sample playback | `lib/voices/softcut_zig.lua` |
| sprite | Visual events | Screen rendering | `lib/voices/sprite.lua` |

Sprite is additive — it fires alongside the audio voice, never replaces it.

## Prerequisites

| Voice | Requires |
|-------|----------|
| midi | MIDI device (hardware synth, DAW, virtual port) |
| osc | SuperCollider 3.x with `sc/rekriate-voice.scd` |
| sc_drums | SuperCollider 3.x with `examples/supercollider/rekriate_drums.scd` |
| softcut | norns hardware (softcut is a norns-native DSP engine) |
| sprite | seamstress or norns screen |

All demos run under **seamstress 1.4.7+**. The softcut demo runs in "dry mode" on seamstress (API exercised, no audio).

## Running the Demos

```bash
# MIDI voice
seamstress -s scripts/demo_midi.lua

# OSC voice (start SuperCollider first)
seamstress -s scripts/demo_osc.lua

# SC drums (start SuperCollider first)
seamstress -s scripts/demo_sc_drums.lua

# Softcut sampler (dry mode on seamstress, audio on norns)
seamstress -s scripts/demo_softcut.lua

# Sprite visuals
seamstress -s scripts/demo_sprite.lua
```

## MIDI Voice

**Module:** `lib/voices/midi.lua`

Sends standard MIDI messages: note_on, note_off, CC for portamento.

### Setup

```lua
local midi_voice = require("lib/voices/midi")
local midi_dev = midi.connect(1)       -- first MIDI device
local voice = midi_voice.new(midi_dev, 1)  -- channel 1
```

### API

```lua
voice:play_note(note, vel, dur)  -- note: MIDI 0-127, vel: 0.0-1.0, dur: beats
voice:note_on(note, vel)         -- manual note on
voice:note_off(note)             -- manual note off
voice:all_notes_off()            -- panic: silence + CC 123
voice:set_portamento(time)       -- 0=off, 1-7 mapped to CC 5/CC 65
```

### Params (per track)

- **voice** → `midi`
- **midi ch** → MIDI channel 1-16

### Notes

- Monophonic: new notes cancel active notes on the same channel.
- `play_note` schedules note_off via `clock.sync(dur)`.
- Portamento uses CC 65 (on/off) and CC 5 (time).

## OSC Voice

**Module:** `lib/voices/osc.lua`

Sends note events over UDP to SuperCollider (or any OSC receiver).

### Setup

```lua
local osc_voice = require("lib/voices/osc")
local voice = osc_voice.new(1, "127.0.0.1", 57120)  -- track 1
```

### SuperCollider Setup

1. Open SuperCollider, boot server (Cmd+B)
2. Open and evaluate `sc/rekriate-voice.scd` (Cmd+Enter on outer parens)
3. Look for: `re.kriate voice engine ready` in the post window

See [supercollider-setup.md](supercollider-setup.md) for detailed troubleshooting.

### OSC Messages

| Path | Args | Description |
|------|------|-------------|
| `/rekriate/track/{n}/note` | midi_note, velocity, duration | Play a note |
| `/rekriate/track/{n}/note_off` | midi_note | Stop a note |
| `/rekriate/track/{n}/all_notes_off` | — | Silence track |
| `/rekriate/track/{n}/portamento` | time | Set glide time |

### API

```lua
voice:play_note(note, vel, dur)  -- sends /note, schedules /note_off
voice:all_notes_off()            -- sends /all_notes_off
voice:set_portamento(time)       -- sends /portamento
voice:set_target(host, port)     -- change OSC destination at runtime
```

### Params (per track)

- **voice** → `osc`
- **osc host** → target IP (default `127.0.0.1`)
- **osc port** → target port (default `57120`)

## SC Drums Voice

**Module:** `lib/voices/sc_drums.lua`

Sends drum events to SuperCollider. MIDI note selects drum type via `note % 4`.

### Drum Mapping

| note % 4 | Drum | SynthDef |
|-----------|------|----------|
| 0 | Kick | `\rekriate_kick` — sine body with pitch sweep |
| 1 | Snare | `\rekriate_snare` — sine body + filtered noise |
| 2 | Hat | `\rekriate_hat` — metallic high-pass noise |
| 3 | Perc | `\rekriate_perc` — FM bell/metallic |

### Setup

```lua
local sc_drums = require("lib/voices/sc_drums")
local drums = sc_drums.new(1, "127.0.0.1", 57120)  -- track 1
```

### SuperCollider Setup

1. Open SuperCollider, boot server (Cmd+B)
2. Open and evaluate `examples/supercollider/rekriate_drums.scd` (Cmd+Enter)
3. Look for: `re.kriate DRUM listener ready` in the post window

### API

Same interface as OSC voice, but OSC paths use `/drum` instead of `/note`:

```lua
drums:play_note(note, vel, dur)  -- sends /drum
drums:note_on(note, vel)         -- manual trigger
drums:note_off(note)             -- cancel scheduled off
drums:all_notes_off()            -- sends /all_drums_off
drums:set_portamento(time)       -- sends /drum_portamento (pitch slide on tuned perc)
```

### Params

Same as OSC voice (osc host, osc port).

## Softcut Voice

**Module:** `lib/voices/softcut_zig.lua` + `lib/voices/softcut_runtime.lua`

Sample playback via norns softcut DSP. Pitch is set by adjusting playback rate relative to a root note.

### Setup

```lua
local softcut_zig = require("lib/voices/softcut_zig")
local softcut_runtime = require("lib/voices/softcut_runtime")

local runtime = softcut_runtime.new()
local voice = softcut_zig.new(1, runtime, {
  sample_path = "/home/we/dust/audio/common/808/kick.wav",
  root_note = 60,       -- C4 = native pitch
  start_sec = 0,        -- buffer region start
  end_sec = 1,          -- buffer region end
  loop = false,         -- one-shot
  level = 0.8,          -- 0.0-1.0
  pan = 0.0,            -- -1.0 to 1.0
  attack = 0.01,        -- fade-in seconds
  release = 0.05,       -- fade-out seconds
  rate_slew = 0.0,      -- pitch glide time
})
```

### Runtime

`softcut_runtime` manages 6 voice slots across 2 mono buffers (~5.8 min each at 48kHz). It handles:

- Buffer region allocation per voice
- Sample loading
- Playback state (enable, level, rate, loop bounds, position)

### API

```lua
voice:play_note(note, vel, dur)   -- pitch via rate = 2^((note - root) / 12)
voice:note_on(note, vel)          -- start playback
voice:note_off(note)              -- stop with release fade
voice:all_notes_off()             -- silence + stop
voice:set_portamento(val)         -- rate slew time (pitch glide)
voice:apply_config(cfg)           -- reconfigure sample, loop bounds, etc.
```

### Params (per track)

- **voice** → `softcut`
- **sample path** → absolute path to .wav file on norns
- **sample root** → MIDI note of the sample's native pitch (default 60/C4)
- **sample start** → playback start in seconds
- **sample end** → playback end in seconds
- **sample loop** → off/on

### Notes

- `voice.available` is `false` if the sample file is missing or failed to load.
- On seamstress, the runtime tracks state but produces no audio (useful for testing).

## Sprite Voice

**Module:** `lib/voices/sprite.lua`

Visual events that fire alongside audio voices. Not selected via the voice param — sprites are additive and managed by the sequencer when a sprite voice is attached to a track.

### Setup

```lua
local sprite_voice = require("lib/voices/sprite")
local sprites = sprite_voice.new(1)  -- track 1
```

### Parameter Mapping

| Sequencer param | Visual property | Range |
|-----------------|-----------------|-------|
| note (1-7) | Shape | circle, rect, triangle, diamond, star, line, dot |
| octave (1-7) | Y position | bottom to top of screen |
| velocity (1-7) | Size | 3px to 22px radius |
| step position | X position | left to right (follows playhead) |
| ratchet (1-7) | Brightness | base color → white blend |
| glide > 1 | Glide line | connects to previous note position |
| muted | Ghost sprite | 10% alpha |

### Track Colors

| Track | Color | RGB |
|-------|-------|-----|
| 1 | Orange | (255, 120, 50) |
| 2 | Cyan | (50, 180, 255) |
| 3 | Green | (80, 230, 120) |
| 4 | Purple | (200, 80, 255) |

### API

```lua
sprites:play(vals, duration, opts)
-- vals: {note, octave, velocity, alt_note, ratchet, glide}
-- duration: lifetime in beats
-- opts: {step, loop_len, muted}

sprites:get_active_events()  -- returns list of live sprite events (auto-prunes expired)
sprites:all_notes_off()      -- clear all active sprites
```

Each `play` call spawns a main sprite plus an echo sprite (1.5x size, 30% alpha, 1.5x duration). Ghost sprites (muted) skip the echo.

## Mixing Voice Backends

Each of the 4 tracks can use a different voice backend. Common configurations:

| Setup | Track 1 | Track 2 | Track 3 | Track 4 |
|-------|---------|---------|---------|---------|
| All MIDI | midi | midi | midi | midi |
| MIDI + drums | midi | midi | sc_drums | sc_drums |
| Full SC | osc | osc | sc_drums | sc_drums |
| Sampler + synth | softcut | softcut | osc | osc |

Set each track's voice in the params menu. Voice changes take effect immediately — no restart needed.
