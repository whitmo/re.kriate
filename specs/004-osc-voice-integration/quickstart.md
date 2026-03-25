# Quickstart: OSC Voice Integration

## Run the app (seamstress)

```bash
/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua
```

## Run tests

```bash
busted specs/
```

Requires the lua5.4 symlink: `/opt/homebrew/opt/lua/bin/lua5.4 -> /opt/homebrew/opt/lua@5.4/bin/lua`

## Configure OSC voice

In the seamstress params menu:

1. Set **track N voice** to "osc" (default is "midi")
2. Set **track N osc host** to target IP (default "127.0.0.1")
3. Set **track N osc port** to target port (default 57120)

## OSC message format

The OSC voice sends to these paths:

| Path | Args | Description |
|------|------|-------------|
| `/rekriate/track/{n}/note` | `{midi_note, velocity, duration}` | Note event |
| `/rekriate/track/{n}/all_notes_off` | `{}` | Silence track |
| `/rekriate/track/{n}/portamento` | `{time}` | Set glide time |

## Test with SuperCollider

SuperCollider listens on port 57120 by default. Example receiver:

```supercollider
OSCdef(\rekriate, { |msg| msg.postln }, '/rekriate/track/1/note');
```

## Key files

| File | Role |
|------|------|
| `lib/voices/osc.lua` | OSC voice module (existing, unchanged) |
| `seamstress.lua` | Entrypoint — voice backend params + swap logic |
| `specs/osc_voice_spec.lua` | Tests for OSC voice wiring |
