# Data Model: Swing/Shuffle Per Track

**Feature**: 007-swing-shuffle | **Date**: 2026-03-25

## Entity Changes

### Track (lib/track.lua)

**Modified entity** — add one field:

| Field | Type | Default | Range | Description |
|-------|------|---------|-------|-------------|
| `swing` | integer | 0 | 0-100 | Swing percentage; 0=even, 50=triplet, 100=max offset |

Existing fields unchanged: `params`, `division`, `muted`, `direction`.

```lua
-- In new_track():
local track = {
  params = {},
  division = 1,
  muted = false,
  direction = "forward",
  swing = 0,            -- NEW
}
```

### Sequencer Constants (lib/sequencer.lua)

**New constant**:

| Constant | Value | Description |
|----------|-------|-------------|
| `MIN_SWING_RATIO` | 0.01 | Minimum even-step fraction of pair duration (floor) |

### Sequencer Functions (lib/sequencer.lua)

**New pure function**:

```lua
M.swing_duration(div, swing, is_odd) -> number
```

- `div`: base division sync value (from DIVISION_MAP)
- `swing`: integer 0-100
- `is_odd`: boolean, true for odd steps (1st, 3rd, 5th...)
- Returns: adjusted clock.sync duration for this step

**Modified function**: `M.track_clock(ctx, track_num)` — adds local step counter, uses `swing_duration` for clock.sync.

### App Params (lib/app.lua)

**New params** (per track, 4 total):

| Param ID | Label | Type | Min | Max | Default |
|----------|-------|------|-----|-----|---------|
| `swing_1` | track 1 swing | number | 0 | 100 | 0 |
| `swing_2` | track 2 swing | number | 0 | 100 | 0 |
| `swing_3` | track 3 swing | number | 0 | 100 | 0 |
| `swing_4` | track 4 swing | number | 0 | 100 | 0 |

Action: sets `ctx.tracks[t].swing = val`

## State Transitions

```
swing = 0 (default)
  → User sets swing param → swing = N (0-100)
  → Pattern save → swing value deep-copied into pattern slot
  → Pattern load → swing restored from slot (or 0 if field absent)
  → Stop/Start → swing persists on track, step counter resets (local to coroutine)
```

## No Changes Required

- `lib/pattern.lua` — deep_copy handles new field automatically
- `lib/direction.lua` — direction operates on step sequence, independent of timing
- `lib/scale.lua` — unrelated
- `lib/grid_ui.lua` — no grid page for swing
- `lib/seamstress/` — no platform-specific changes
- `lib/norns/` — no platform-specific changes
