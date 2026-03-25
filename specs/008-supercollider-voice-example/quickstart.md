# Quickstart: SuperCollider Voice Example

**Feature**: 008-supercollider-voice-example

## Prerequisites

- SuperCollider 3.x installed ([supercollider.github.io](https://supercollider.github.io))
- re.kriate running on seamstress with OSC voice backend configured
- seamstress v1.4.7 at `/opt/homebrew/opt/seamstress@1/bin/seamstress`

## Files

| File | Purpose |
|------|---------|
| `examples/supercollider/rekriate_sub.scd` | SynthDef + OSC listener |
| `examples/supercollider/test_osc_roundtrip.lua` | Round-trip verification script |
| `docs/supercollider-setup.md` | Full setup documentation |

## Quick Start

### 1. Start SuperCollider

```
1. Open SuperCollider IDE
2. Open examples/supercollider/rekriate_sub.scd
3. Boot the server: Cmd+B (macOS) or Ctrl+B (Linux)
4. Select all code and evaluate: Cmd+Enter / Ctrl+Enter
5. You should see "re.kriate listener ready on port 57120" in the post window
```

### 2. Start re.kriate

```bash
/opt/homebrew/opt/seamstress@1/bin/seamstress -s re_kriate.lua
```

Ensure tracks are configured with OSC voice backend targeting `127.0.0.1:57120`.

### 3. Play

Press play in re.kriate. You should hear the subtractive synth responding to sequencer notes.

## Running the Round-Trip Test

With SuperCollider listener running:

```bash
/opt/homebrew/opt/seamstress@1/bin/seamstress -s examples/supercollider/test_osc_roundtrip.lua
```

Check both:
- Terminal output: shows which messages were sent
- SuperCollider post window: shows received messages

## Key Values

| SynthDef Arg | Range | Mapped From |
|-------------|-------|-------------|
| `freq` | 8.18-12543 Hz | MIDI note 0-127 via `.midicps` |
| `amp` | 0.0-1.0 | velocity / 127 |
| `cutoff` | 400-8000 Hz | velocity scaled linearly |
| `dur` | 0.01-∞ seconds | duration (passed through) |
| `porta` | 0.0-∞ seconds | portamento time |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No sound | SC server not booted | Cmd+B in SuperCollider IDE |
| No sound | Script not evaluated | Select all + Cmd+Enter |
| No sound | Wrong port | Check `NetAddr.langPort` in SC — should be 57120 |
| No sound | re.kriate not using OSC voice | Verify voice backend config |
| Clicks on short notes | Release too fast | Minimum release is 0.01s in SynthDef |
