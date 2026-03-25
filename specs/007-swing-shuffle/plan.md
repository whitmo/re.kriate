# Implementation Plan: Swing/Shuffle Per Track

**Branch**: `007-swing-shuffle` | **Date**: 2026-03-25 | **Spec**: `specs/007-swing-shuffle/spec.md`
**Input**: Feature specification from `specs/007-swing-shuffle/spec.md`

## Summary

Add per-track swing timing to the sequencer. Each track gets a `swing` integer (0-100) that alternates step durations within pairs — odd steps are lengthened, even steps shortened — producing groove/shuffle feel. At 0% all steps are even; at 50% triplet feel (2:1 ratio); at 100% maximum offset (with a minimum floor). Three files modified: `lib/track.lua` (data model), `lib/sequencer.lua` (clock logic), `lib/app.lua` (param registration). No platform-specific changes.

## Technical Context

**Language/Version**: Lua 5.4 (busted test runner), seamstress v1.4.7 runtime
**Primary Dependencies**: seamstress v1.4.7, busted (test framework)
**Storage**: N/A (in-memory patterns via lib/pattern.lua, no persistence layer)
**Testing**: busted (`busted specs/`)
**Target Platform**: seamstress (macOS/Linux desktop) + norns (shared modules)
**Project Type**: Sequencer script (multi-platform)
**Performance Goals**: Clock timing accuracy within float tolerance; no perceptible jitter from swing calculation
**Constraints**: No changes to platform-specific files per SC-005. Swing lives in shared modules only (lib/track.lua, lib/sequencer.lua, lib/app.lua).
**Scale/Scope**: 3 files modified, ~30-50 lines added, 15-20 new tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-Centric Architecture | PASS | `track.swing` is a field on each track within `ctx.tracks[]`. Step counter is local to the clock coroutine. No globals or module state added. |
| II. Platform-Parity Behavior | PASS | Swing is shared sequencing behavior in `lib/sequencer.lua` and `lib/track.lua` — works identically on norns and seamstress. Param registration in `lib/app.lua` is shared. |
| III. Test-First Sequencing Correctness | PASS | Swing directly affects timing math and step advancement. Failing tests MUST be written before implementation: timing ratio verification, edge cases (0%, 50%, 100%), composition with ratchet/division/direction. |
| IV. Deterministic Timing and Safe Degradation | PASS | Swing formula is purely arithmetic — deterministic given swing value and division. Minimum floor prevents zero/negative clock.sync values. Graceful at swing=0 (identical to current behavior). |
| V. Spec-Driven Delivery | PASS | Full speckit pipeline: spec.md complete, plan.md (this file), tasks.md next via /speckit.tasks. |

No violations. Complexity tracking not needed.

## Project Structure

### Documentation (this feature)

```text
specs/007-swing-shuffle/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/          # Generated checklists
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── track.lua            # MODIFIED — add swing field to new_track()
├── sequencer.lua        # MODIFIED — add swing_duration(), modify track_clock() for step counter + swing timing
├── app.lua              # MODIFIED — add per-track swing params
├── pattern.lua          # UNCHANGED — deep_copy handles swing field automatically
├── seamstress/          # UNCHANGED — no platform-specific changes
└── norns/               # UNCHANGED — no platform-specific changes

specs/
└── swing_shuffle_spec.lua  # NEW — dedicated test file for swing/shuffle
```

**Structure Decision**: Minimal change — extend three existing shared modules. New test file for the feature. No new modules needed.

## Design

### Swing Timing Formula

The swing amount S (0-100) determines the duration split within each step pair:

```
pair_duration = 2 * division_sync
odd_duration  = pair_duration / (2 - S / 100)
even_duration = pair_duration - odd_duration
even_duration = max(even_duration, MIN_SWING_FLOOR)
```

Where `MIN_SWING_FLOOR = pair_duration * 0.01` (1% of pair, prevents zero/negative).

Verification at key points:
- **S=0**: odd = 2d/2 = d, even = 2d - d = d (even split)
- **S=50**: odd = 2d/1.5 = 4d/3, even = 2d/3 (ratio 2:1, triplet feel)
- **S=100**: odd = 2d/1 = 2d, even = 0 → clamped to floor

### Phase 1: Track Data Model (track.lua)

**Goal**: Add `swing` field defaulting to 0.

**Changes to `lib/track.lua`**:
- In `new_track()`: add `swing = 0` to the track table, alongside `division`, `muted`, `direction`

No changes to `PARAM_NAMES`, `CORE_PARAMS`, or `EXTENDED_PARAMS` — swing is a per-track scalar like `division`, not a per-step parameter.

### Phase 2: Swing Timing Logic (sequencer.lua)

**Goal**: Alternate step durations based on swing amount.

**Changes to `lib/sequencer.lua`**:

1. Add `M.MIN_SWING_RATIO = 0.01` constant (minimum even-step fraction of pair)

2. Add `M.swing_duration(div, swing, is_odd)` pure function:
   - If swing == 0, return div (fast path, no calculation)
   - Compute pair = 2 * div
   - Compute odd_dur = pair / (2 - swing / 100)
   - Compute even_dur = pair - odd_dur
   - Apply floor: even_dur = max(even_dur, pair * MIN_SWING_RATIO)
   - Return odd_dur if is_odd, else even_dur

3. Modify `M.track_clock(ctx, track_num)`:
   - Add local `step_count = 0` before the while loop
   - Inside loop: increment step_count, compute `is_odd = (step_count % 2 == 1)`
   - Replace `clock.sync(div)` with `clock.sync(M.swing_duration(div, track.swing or 0, is_odd))`

**Key decision**: Step counter is local to the clock coroutine, not stored on the track. This means it resets on stop/start, which is fine — the spec says swing pairing is based on the step counter within the clock loop. If swing changes mid-playback, the new value takes effect immediately (read each iteration), with odd/even alignment maintained by the counter.

### Phase 3: Swing Parameter (app.lua)

**Goal**: Expose swing as a per-track param.

**Changes to `lib/app.lua`**:
- Add per-track swing param block (after the direction params):
  ```lua
  for t = 1, track_mod.NUM_TRACKS do
    params:add_number("swing_" .. t, "track " .. t .. " swing", 0, 100, 0)
    params:set_action("swing_" .. t, function(val)
      ctx.tracks[t].swing = val
    end)
  end
  ```

### Phase 4: Pattern Round-Trip (verification only)

**Goal**: Verify swing is preserved through pattern save/load.

No code changes needed — `pattern.lua` uses `deep_copy(ctx.tracks)` which copies all fields including `swing`. Tests verify this works correctly, including backward compatibility (patterns saved without swing field default to 0 via `track.swing or 0` in the clock).

### Phase 5: Composition with Existing Features (verification only)

**Goal**: Verify swing composes with ratchet, division, direction, and mute.

No code changes needed — the design naturally composes:
- **Ratchet**: Subdivisions happen within the swing-adjusted step duration (ratchet fires inside `step_track`, which is called after the swing-adjusted `clock.sync`)
- **Division**: Swing scales proportionally with any division value (formula uses `div` directly)
- **Direction**: Direction affects step sequence order; swing affects timing between steps. Independent axes.
- **Mute**: Muted tracks still advance the step counter (clock loop continues), maintaining swing alignment when unmuted.

Tests verify each composition.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
