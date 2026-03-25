# Research: Swing/Shuffle Per Track

**Feature**: 007-swing-shuffle | **Date**: 2026-03-25

## Decision 1: Swing Formula

**Decision**: Use `odd_duration = pair / (2 - S/100)` where S is swing 0-100 and pair = 2 * division.

**Rationale**: This formula produces the musically correct triplet feel at 50% swing (2:1 ratio), even split at 0%, and maximum offset at 100%. It matches the spec's FR-004 requirement exactly. Alternative linear formulas (e.g., `div * (1 + S/100)`) produce a 3:1 ratio at 50%, which is not standard triplet feel.

**Alternatives considered**:
- Linear interpolation `div * (1 ± S/100)`: Simpler but gives 3:1 ratio at S=50 (wrong per FR-004/SC-002)
- MPC-style mapping (50-100 range): Different parameterization; spec explicitly uses 0-100 range
- Lookup table: Unnecessary — formula is simple arithmetic, computed once per step

## Decision 2: Step Counter Scope

**Decision**: Step counter (odd/even tracking) is a local variable in the `track_clock` coroutine, not stored on the track table.

**Rationale**: The counter only needs to survive within a single play session. It resets on stop/start, which is natural musical behavior (start always begins on an odd step). Storing it on the track would add persistent state that has no meaning outside of active playback.

**Alternatives considered**:
- Store on track table: Would persist across stop/start, but adds unnecessary state and complicates pattern save/load (would need to exclude it)
- Store on ctx: No advantage over local; adds noise to shared state

## Decision 3: Swing as Track Scalar vs Per-Step Parameter

**Decision**: Swing is a per-track scalar (`track.swing`), like `division` and `direction`, not a per-step parameter in `PARAM_NAMES`.

**Rationale**: The spec defines swing as a single amount per track (FR-001, FR-006). It does not vary step-by-step. Adding it to `PARAM_NAMES` would give it 16 per-step values, a loop start/end, and a playhead — all meaningless for a single scalar setting. This matches how division and direction are modeled.

**Alternatives considered**:
- Per-step swing in PARAM_NAMES: Would allow per-step swing variation, but spec doesn't call for it and it would complicate the timing formula significantly

## Decision 4: Minimum Floor for Even Step Duration

**Decision**: Clamp even-step duration to 1% of pair duration (`pair * 0.01`).

**Rationale**: At 100% swing, the formula produces zero even-step duration, which would cause `clock.sync(0)` — either a no-op or error depending on platform. A 1% floor is imperceptibly short musically but prevents timing issues. The floor scales with division so it remains proportional at all tempos and divisions.

**Alternatives considered**:
- Fixed absolute minimum (e.g., 1/128 beat): Would not scale with division; could be audibly different at slow vs fast tempos
- 5% of pair: Too conservative; noticeably limits the maximum swing feel
- No floor with a guard: More fragile; relies on platform handling of zero-duration sync

## Decision 5: Pattern Backward Compatibility

**Decision**: No migration needed. Use `track.swing or 0` in the clock loop to handle tracks loaded from patterns saved before swing was added.

**Rationale**: `pattern.lua` deep-copies the entire track table. Old patterns simply lack the `swing` field. The `or 0` fallback in `sequencer.track_clock` means old patterns play with no swing (correct default). No version field or migration logic needed.

**Alternatives considered**:
- Add version field to patterns: Over-engineering for a single new field with a safe default
- Patch tracks on load: Adds complexity to pattern.lua for no benefit
