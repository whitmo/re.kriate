# Quickstart: Swing/Shuffle Per Track

**Feature**: 007-swing-shuffle | **Date**: 2026-03-25

## Running Tests

```bash
# All tests
busted specs/

# Swing-specific tests only
busted specs/swing_shuffle_spec.lua
```

Requires `lua5.4` symlink at `/opt/homebrew/opt/lua/bin/lua5.4`.

## What Changed

Three shared files modified:

1. **lib/track.lua** — `new_track()` now includes `swing = 0` field
2. **lib/sequencer.lua** — `swing_duration()` helper + `track_clock()` uses swing timing
3. **lib/app.lua** — per-track `swing_N` params (0-100)

## Using Swing

Set swing via the parameter system:

```lua
params:set("swing_1", 50)  -- track 1: triplet feel
params:set("swing_2", 0)   -- track 2: straight timing
```

Swing takes effect on the next step. The value ranges from 0 (even timing) to 100 (maximum offset).

## Key Values

| Swing | Feel | Odd:Even Ratio |
|-------|------|----------------|
| 0 | Straight | 1:1 |
| 50 | Triplet shuffle | 2:1 |
| 75 | Heavy shuffle | 4:1 |
| 100 | Maximum swing | ~200:1 (floor applied) |
