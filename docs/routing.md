# Audio Routing & Mixer Guide

This guide covers how re.kriate's mixer layer interacts with external audio
systems — MIDI devices, SuperCollider, softcut, and the desktop (seamstress)
monitoring chain on macOS.

## Mixer layer overview

Each track has three mixer parameters:

| Parameter  | Range      | Default | Semantics                       |
|------------|------------|---------|---------------------------------|
| `level_<t>` | 0–100 (%) | 100     | Velocity multiplier, 0.0–1.0   |
| `pan_<t>`   | -100..+100| 0       | Stereo position, -1.0..+1.0    |
| `mute_<t>`  | off / on  | off     | Same flag as nav-row mute (x=13)|

The canonical float-unit state lives on `ctx.mixer = {level, pan}`. Params are
a UI wrapper and round-trip through preset persistence automatically.

Mute shares a single source of truth with the existing nav button and the
alt-track page — they all read/write `ctx.tracks[t].muted`.

## Per-backend routing

### MIDI voices

MIDI voices send:

- `CC 7` (Channel Volume) for level, scaled to 0..127 on the voice's channel.
- `CC 10` (Pan) for pan, with center at 64.

Any hardware synth or General MIDI soft-synth that respects CC7/CC10 will
track the mixer automatically. No extra setup required.

### OSC voices

OSC voices broadcast generic kria-style paths:

- `/rekriate/track/{n}/level <float>` — value in [0, 1]
- `/rekriate/track/{n}/pan <float>` — value in [-1, 1]

The downstream OSC consumer (custom SynthDef, ChucK patch, TouchDesigner, etc.)
is responsible for applying these mixer values on its side.

### SuperCollider melodic synth (`sc_synth`)

- `/rekriate/synth/{n}/level <float>`
- `/rekriate/synth/{n}/pan <float>`

These are handled by the SC companion script bundled with re.kriate. See
`sc/rekriate-mixer.scd` for the full channel-strip architecture (per-voice
level, aux send, master bus, metering).

### SuperCollider drum synth (`sc_drums`)

Because drums share `/rekriate/track/{n}/*` with the generic OSC voice,
mixer messages use a dedicated sub-path:

- `/rekriate/track/{n}/drum_level <float>`
- `/rekriate/track/{n}/drum_pan <float>`

### Softcut voices

Softcut voices call the injected runtime directly:

- `runtime.level(voice_id, val)` — level in [0, 1]
- `runtime.pan(voice_id, val)` — pan in [-1, 1]

On norns / seamstress this maps to `softcut.level(voice, v)` and
`softcut.pan(voice, v)` on the C side.

## Desktop monitoring (seamstress on macOS)

A common setup is to mix SC, softcut, and external MIDI into a single stereo
bus that's easy to record or stream.

### Recommended chain

```
┌──────────────┐                        ┌──────────────┐
│  re.kriate   │  MIDI (CC7/10, notes) │ Hardware or  │
│  (seamstress) ├────────────────────► │ GM soft-synth │
└──────────────┘                        └──────────────┘
        │ OSC (synth level/pan, drum level/pan)
        ▼
┌──────────────┐
│ SuperCollider│  ──► stereo out ──► BlackHole (aggregate) ──► DAW / monitor
│  sc_synth    │
│  sc_drums    │
│  softcut     │  (softcut's own audio graph sums into SC via JACK / CoreAudio)
└──────────────┘
```

### BlackHole aggregate device

1. Install [BlackHole](https://github.com/ExistentialAudio/BlackHole) (2ch or
   16ch — 2ch is enough for a stereo monitoring bus).
2. In *Audio MIDI Setup* → create a **Multi-Output Device** combining
   BlackHole 2ch with your physical output (e.g., built-in speakers).
3. Point SuperCollider's output at the Multi-Output Device. You now hear the
   mix AND can record it via any DAW that reads BlackHole as an input.

### Softcut on macOS

Softcut runs inside seamstress; its audio is routed through seamstress's
CoreAudio session. On macOS the simplest path is to let seamstress share a
session with SC (both targeting BlackHole / Multi-Output) — `softcut.level`
controls the per-voice gain into that session.

## Remote OSC control surface

For an external controller (tablet, touchscreen, bespoke UI), re.kriate
exposes:

| Path                      | Args                    | Notes                     |
|---------------------------|-------------------------|---------------------------|
| `/mixer/level <t> <val>`  | track, float 0..1       | Set level                 |
| `/mixer/level <t>`        | track                   | Query level               |
| `/mixer/pan <t> <val>`    | track, float -1..1      | Set pan                   |
| `/mixer/pan <t>`          | track                   | Query pan                 |
| `/mixer/mute <t> <0\|1>`  | track, int              | Set mute                  |
| `/mixer/mute <t>`         | track                   | Toggle mute               |
| `/mixer/get`              | —                       | Full mixer snapshot       |
| `/state/snapshot`         | —                       | Includes `mixer` key      |

Values are clamped on the Lua side — out-of-range inputs are silently snapped
to the nearest valid value rather than rejected.

## Persistence

Mixer state is part of preset snapshots automatically — because the underlying
params (`level_<t>`, `pan_<t>`, `mute_<t>`) are in the normal norns params
registry, preset save/load captures them with no schema changes. Presets
written before this feature landed load with mixer defaults (level=100,
pan=0, mute=off).
