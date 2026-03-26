# SuperCollider Voice Setup

re.kriate can send OSC messages to SuperCollider, turning it into a standalone synthesizer voice for the sequencer. This guide covers setup and configuration.

## Prerequisites

- **SuperCollider** (3.x+) — [download](https://supercollider.github.io/downloads)
- **re.kriate** running on norns or seamstress with the OSC voice backend

## Quick Start

1. Open SuperCollider IDE
2. Open `examples/supercollider/rekriate_sub.scd`
3. Boot the server: **Cmd+B** (macOS) or **Ctrl+B** (Linux)
4. Place cursor inside outer parentheses and evaluate: **Cmd+Enter** / **Ctrl+Enter**
5. You should see in the post window:
   ```
   re.kriate listener ready on port 57120
     4 tracks, 12 OSC responders active
   ```
6. In re.kriate, set the voice backend to `osc` (see below)

## Configuring re.kriate

### Seamstress

In the params menu, set for each track you want routed to SuperCollider:

- **track N voice** → `osc`
- **track N osc host** → `127.0.0.1` (default, change if SC is on another machine)
- **track N osc port** → `57120` (SuperCollider's default sclang port)

Tracks set to `midi` will continue going out via MIDI. You can mix and match — for example, tracks 1-2 on SuperCollider and tracks 3-4 on MIDI.

### Norns

The OSC voice backend works the same way on norns. Set the voice params to `osc` and point the host/port at the machine running SuperCollider.

If SuperCollider is running on a laptop on the same network:
- Set **osc host** to the laptop's IP address (e.g., `192.168.1.42`)
- Set **osc port** to `57120`

## Architecture

```
re.kriate (norns/seamstress)
    │
    │  OSC messages (UDP)
    │  /rekriate/track/{1-4}/note     midi_note velocity duration
    │  /rekriate/track/{1-4}/all_notes_off
    │  /rekriate/track/{1-4}/portamento  time
    │
    └──► SuperCollider (sclang, port 57120)
              │
              │  Synth(\rekriate_sub, ...)
              │
              └──► scsynth (audio server)
                        │
                        └──► speakers / audio interface
```

## The SynthDef

`\rekriate_sub` is a simple subtractive synth: **Saw** oscillator → **RLPF** filter → **Env.perc** envelope.

| Arg      | Default | Description                                  |
|----------|---------|----------------------------------------------|
| `freq`   | 440     | Note frequency in Hz (from MIDI via midicps)  |
| `amp`    | 0.5     | Amplitude 0.0-1.0 (from velocity / 127)       |
| `dur`    | 0.5     | Duration in seconds (controls envelope)        |
| `cutoff` | 2000    | Filter cutoff in Hz (velocity-scaled 400-8000) |
| `porta`  | 0.0     | Portamento lag time in seconds                 |

Velocity maps to both `amp` (loudness) and `cutoff` (brightness) for musical expressiveness.

### Replacing the SynthDef

You can write your own SynthDef. It must accept at minimum: `freq`, `amp`, `dur`, `cutoff`, `porta`. It must use `doneAction: 2` on its envelope so nodes are freed after the note completes.

## Running the Round-Trip Test

With the SuperCollider listener running:

```bash
/opt/homebrew/opt/seamstress@1/bin/seamstress -s examples/supercollider/test_osc_roundtrip.lua
```

The test script sends all 3 message types (note, portamento, all_notes_off) across all 4 tracks. Check both:
- **Terminal**: shows which messages were sent
- **SC post window**: shows received messages

## Troubleshooting

### No sound

1. **Check SC server is booted**: The post window should show `SuperCollider 3 server ready`. If not, press Cmd+B.
2. **Check script is evaluated**: You should see `re.kriate listener ready on port 57120`. If not, select the outer parentheses and press Cmd+Enter.
3. **Check sclang port**: Run `NetAddr.langPort` in SC — it should return `57120`. If it returns a different port, update the OSC port param in re.kriate to match.
4. **Check audio output**: Run `{ SinOsc.ar(440, 0, 0.1) }.play` in SC. If you hear nothing, it's an audio device issue, not a re.kriate issue.
5. **Check OSC is arriving**: Add a test responder in SC:
   ```supercollider
   OSCFunc.trace(true);  // print all incoming OSC
   // ... start re.kriate and play some notes ...
   OSCFunc.trace(false); // stop printing
   ```

### Port 57120 in use

If another sclang instance is already running, the new one will bind to a different port (57121, 57122, etc.). Either quit the other instance or update the re.kriate OSC port to match `NetAddr.langPort`.

### Audio glitches / dropouts

Increase the SC audio buffer size: `s.options.hardwareBufferSize = 1024; s.reboot;`

### "SynthDef not found" errors

Make sure you evaluated the entire outer block (both parentheses), not just a portion. The SynthDef must be added before the OSC responders fire.
