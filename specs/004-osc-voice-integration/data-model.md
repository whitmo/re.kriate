# Data Model: OSC Voice Integration

**Feature**: 004-osc-voice-integration
**Date**: 2026-03-25

## Entities

### Voice Backend Selection (per-track)

A param-driven configuration that determines which voice backend a track uses for audio output.

| Field | Type | Default | Constraint |
|-------|------|---------|------------|
| backend | option {"midi", "osc"} | "midi" (index 1) | Per-track param `voice_backend_{t}` |

**State transitions**:
- `midi → osc`: all_notes_off on MIDI voice → create OSC voice → assign to ctx.voices[t]
- `osc → midi`: all_notes_off on OSC voice → create MIDI voice → assign to ctx.voices[t]

### OSC Target (per-track)

Host and port pair that determines where OSC messages are sent for a given track.

| Field | Type | Default | Constraint |
|-------|------|---------|------------|
| host | text (string) | "127.0.0.1" | Per-track param `osc_host_{t}` |
| port | number (integer) | 57120 | Per-track param `osc_port_{t}`, range 1-65535 |

**Behavior**: When host or port changes and backend is "osc", calls `voice:set_target(host, port)` on the active OSC voice. When backend is "midi", change is stored in param but no action taken.

### Voice Instance (per-track)

The active voice object for a track. Lives on `ctx.voices[t]`. Implements the voice interface.

| Method | Signature | Description |
|--------|-----------|-------------|
| play_note | (self, note, vel, dur) | Send note event |
| all_notes_off | (self) | Silence all active notes |
| set_portamento | (self, time) | Set glide time |
| set_target | (self, host, port) | OSC only: update destination |

**MIDI voice**: `midi_voice.new(midi_dev, channel)` — from `lib/voices/midi.lua`
**OSC voice**: `osc.new(track_num, host, port)` — from `lib/voices/osc.lua`

## Context Changes

No new fields on `ctx`. Voice instances are already on `ctx.voices[t]` — the swap replaces the instance in-place. The `midi_dev` reference needed for MIDI voice recreation is a local in the `seamstress.lua` init scope (not on ctx).

### Existing ctx fields used

| Field | Type | Usage |
|-------|------|-------|
| `ctx.voices[t]` | voice instance | Swapped on backend change |
| `ctx.sprite_voices[t]` | sprite voice | Unchanged — additive alongside any backend |

## Relationships

```
params:get("voice_backend_" .. t) ──→ determines which voice factory to call
    ├─ "midi" → midi_voice.new(midi_dev, channel)
    └─ "osc"  → osc.new(t, host, port)
                    ↓
              ctx.voices[t] ← new voice instance

params:get("osc_host_" .. t) ──┐
params:get("osc_port_" .. t) ──┤
                                └─→ voice:set_target(host, port) [if backend == "osc"]

sequencer.track_clock(ctx, t) ──→ ctx.voices[t]:play_note(...)  [unchanged]
app.cleanup(ctx)               ──→ ctx.voices[t]:all_notes_off() [unchanged]
```

## Param Definitions (seamstress.lua)

Per track (t = 1..4):

| Param ID | Type | Label | Default | Range/Options |
|----------|------|-------|---------|---------------|
| `voice_backend_{t}` | option | track {t} voice | {"midi", "osc"} | index 1 (midi) |
| `osc_host_{t}` | text | track {t} osc host | "127.0.0.1" | free-form string |
| `osc_port_{t}` | number | track {t} osc port | 57120 | 1-65535 |
