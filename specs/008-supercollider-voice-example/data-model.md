# Data Model: SuperCollider Voice Example

**Feature**: 008-supercollider-voice-example
**Date**: 2026-03-25

## Entities

### SynthDef: `\rekriate_sub`

SuperCollider synth definition — a subtractive synthesizer voice.

| Arg | Type | Default | Description |
|-----|------|---------|-------------|
| `freq` | Float | 440 | Frequency in Hz (converted from MIDI note by sclang) |
| `amp` | Float | 0.5 | Amplitude 0.0-1.0 (mapped from velocity) |
| `dur` | Float | 0.5 | Duration in seconds (controls envelope) |
| `cutoff` | Float | 2000 | Filter cutoff in Hz (velocity-scaled) |
| `porta` | Float | 0.0 | Portamento lag time in seconds |
| `gate` | Int | 1 | Gate for forced release (all_notes_off) |

**Signal chain**: `Saw(freq)` → `RLPF(cutoff)` → `EnvGen(Env.perc)` → `Out`

**Lifecycle**: Created per-note, self-frees via `doneAction: 2` when envelope completes. Can be force-freed via `gate = 0` or `node.free`.

### Track Voice State (sclang)

Per-track state maintained in the sclang listener script.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nodes` | List[Node] | empty | Active synth nodes for this track |
| `portaTime` | Float | 0.0 | Current portamento time in seconds |

**Cardinality**: Exactly 4 instances (tracks 1-4).

**Node lifecycle**:
- Added to `nodes` on `/note` message receipt
- Auto-removed via `onFree` callback when synth self-frees (duration elapsed)
- Force-removed on `/all_notes_off` (frees all nodes in list)

### OSC Message Protocol

Messages sent by `lib/voices/osc.lua` (existing, not modified).

| Path | Args | Description |
|------|------|-------------|
| `/rekriate/track/{n}/note` | `midi_note:i, velocity:f, duration:f` | Play a note |
| `/rekriate/track/{n}/all_notes_off` | (none) | Silence all active notes on track |
| `/rekriate/track/{n}/portamento` | `time:f` | Set portamento glide time |

Where `{n}` is 1-4.

**Mapping rules**:
- `midi_note` → `freq`: `midi_note.midicps` (standard MIDI-to-Hz conversion)
- `velocity` → `amp`: `velocity / 127.0` (normalize to 0.0-1.0)
- `velocity` → `cutoff`: `velocity.linlin(0, 127, 400, 8000)` (velocity-sensitive filter)
- `duration` → `dur`: passed through directly (seconds)

## State Transitions

```
Track Voice State Machine:

  [Idle] --/note--> [Playing]
    ^                  |
    |                  | (duration elapsed, doneAction: 2)
    |                  v
    +---- [Freed] <---+
    ^
    | (/all_notes_off)
    +---- [Playing] (force-free all nodes)
```

## Relationships

```
re.kriate (seamstress)              SuperCollider
┌─────────────────────┐             ┌─────────────────────────┐
│ lib/voices/osc.lua  │──OSC/UDP──→│ rekriate_sub.scd        │
│  .play_note()       │   :57120   │  OSC responders (12)    │
│  .all_notes_off()   │            │  Track voice state (4)  │
│  .set_portamento()  │            │  SynthDef \rekriate_sub │
└─────────────────────┘             └─────────────────────────┘
```

No bidirectional communication. OSC is fire-and-forget (UDP).
