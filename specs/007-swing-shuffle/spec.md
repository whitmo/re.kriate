# Feature Specification: Swing/Shuffle Per Track

**Feature Branch**: `007-swing-shuffle`
**Created**: 2026-03-25
**Status**: Draft
**Input**: User description: "Add swing/shuffle per track: add a swing parameter (0-100%) per track that offsets every other step's timing, creating groove feel. Wire into sequencer clock logic."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Per-Track Swing Timing (Priority: P1 🎯 MVP)

A musician wants to add groove to their sequence by adjusting swing per track. They set a swing amount on one track so that even-numbered steps (2nd, 4th, 6th, etc.) are delayed, creating a shuffle feel. At 0% swing all steps are evenly spaced. At 50% ("triplet feel") the even steps land at the 2/3 point of the step pair. At 100% the even steps are maximally delayed, nearly coinciding with the next odd step.

**Why this priority**: Swing is the core musical feature — without timing offset, no groove feel is possible. This is the minimum viable behavior.

**Independent Test**: Can be tested by verifying that the sequencer's per-step timing durations alternate between shorter and longer values based on the swing amount, producing the expected rhythmic offset for even-numbered steps.

**Acceptance Scenarios**:

1. **Given** a track with swing set to 0%, **When** the sequencer advances through steps, **Then** all steps are evenly spaced at the track's division interval.
2. **Given** a track with swing set to 50%, **When** the sequencer advances through steps, **Then** odd steps (1st, 3rd, 5th…) take 2/3 of a step-pair's duration and even steps take 1/3, producing a triplet shuffle feel.
3. **Given** a track with swing set to 100%, **When** the sequencer advances through steps, **Then** even steps are delayed to the maximum extent (nearly the full step-pair duration on the odd step, near-zero on the even step).
4. **Given** two tracks with different swing amounts, **When** both play simultaneously, **Then** each track's timing reflects its own independent swing setting.

---

### User Story 2 - Swing Parameter Control (Priority: P1)

A musician adjusts the swing amount for each track independently using the parameter system. The swing parameter is exposed per-track alongside existing per-track parameters (division, direction) and defaults to 0% (no swing).

**Why this priority**: Without a way to set the swing value, the timing feature is inaccessible to the user. This is required for US1 to be usable.

**Independent Test**: Can be tested by creating a context, changing the swing parameter for a track, and verifying the track's swing field updates to the expected value.

**Acceptance Scenarios**:

1. **Given** a freshly initialized context, **When** inspecting any track's swing value, **Then** it defaults to 0 (no swing).
2. **Given** any track, **When** the swing parameter is set to a value between 0 and 100, **Then** the track's swing field reflects that value.
3. **Given** track 1 with swing 75 and track 2 with swing 0, **When** both are playing, **Then** track 1 has groove timing while track 2 plays straight.

---

### User Story 3 - Swing Preserved in Patterns (Priority: P2)

A musician saves a pattern with per-track swing settings and later loads it, expecting the groove feel to be restored exactly as configured.

**Why this priority**: Pattern save/load is an existing feature. Swing must round-trip through patterns to be musically useful, but this is expected to work automatically since pattern save/load deep-copies the entire track table.

**Independent Test**: Can be tested by setting swing on tracks, saving a pattern, changing swing, loading the pattern, and verifying swing values are restored.

**Acceptance Scenarios**:

1. **Given** tracks with various swing values, **When** a pattern is saved and then loaded, **Then** the swing values are restored to their saved state.
2. **Given** a pattern saved before swing was available (no swing field), **When** loaded, **Then** tracks default to 0% swing (no groove change).

---

### User Story 4 - Swing with Other Timing Features (Priority: P2)

A musician uses swing in combination with other timing features (division, ratchet, direction modes) and expects them to compose correctly without interference.

**Why this priority**: The sequencer already has division, ratchet, and direction features that affect timing. Swing must not break these interactions.

**Independent Test**: Can be tested by enabling swing alongside ratchet, non-forward direction modes, and different divisions, verifying each still operates correctly.

**Acceptance Scenarios**:

1. **Given** a track with swing and ratchet both active, **When** a step triggers, **Then** ratchet subdivisions occur within the (swing-adjusted) step timing and the overall groove is preserved.
2. **Given** a track with swing and a non-sixteenth division (e.g., eighth notes), **When** playing, **Then** swing offsets are applied relative to that division's step duration.
3. **Given** a track with swing and pendulum direction mode, **When** playing, **Then** the direction mode operates on the step sequence while swing affects the timing between steps.

---

### Edge Cases

- What happens when swing is set to exactly 100%? Even steps should have near-zero duration but must not cause zero-length or negative clock.sync values (minimum floor applied).
- What happens when swing changes mid-playback? The new swing value takes effect on the next step pair boundary — no glitch or timing reset occurs.
- What happens with swing and loop boundaries? Swing pairing (odd/even) is based on the step counter within the clock loop, not the musical step position, so it remains consistent regardless of loop start/end.
- What happens when swing is applied with the fastest division (1/16)? Swing works at all divisions — even at 1/16, the timing offset is proportional to the step duration.
- What happens when a track has swing and is muted then unmuted? The step counter continues advancing while muted, so swing pairing remains consistent when unmuted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The sequencer MUST support a per-track swing amount as an integer from 0 to 100 (representing 0% to 100%).
- **FR-002**: When swing is 0, all steps MUST be evenly spaced at the track's division interval (identical to current behavior).
- **FR-003**: When swing is non-zero, the sequencer MUST alternate step durations within each step pair — odd steps are longer, even steps are shorter — proportional to the swing amount.
- **FR-004**: The swing timing formula MUST produce triplet feel at 50% swing: odd step = 2/3 of step-pair duration, even step = 1/3 of step-pair duration.
- **FR-005**: At 100% swing, even steps MUST be delayed to the maximum extent without producing zero or negative timing values (a minimum floor MUST be enforced).
- **FR-006**: Each track MUST have an independent swing parameter that does not affect other tracks' timing.
- **FR-007**: The swing parameter MUST be exposed in the parameter system alongside existing per-track parameters (division, direction).
- **FR-008**: The swing parameter MUST default to 0 (no swing) for all tracks on initialization.
- **FR-009**: Swing values MUST be preserved when saving and loading patterns.
- **FR-010**: Swing MUST compose correctly with all existing timing features: division, ratchet, direction modes, and mute state.

### Key Entities

- **Swing Amount**: An integer (0-100) stored per track, representing the percentage of timing offset applied to even-numbered steps. Stored as `track.swing` alongside existing track fields (`division`, `muted`, `direction`).
- **Step Counter**: A per-track counter tracking odd/even step position within the clock loop, used to determine which steps get the longer vs shorter duration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All existing tests continue to pass with no regressions (swing defaults to 0, preserving current timing behavior).
- **SC-002**: Swing timing accuracy: at 50% swing, the ratio of odd-step duration to even-step duration is 2:1 (within floating-point tolerance).
- **SC-003**: Each track's swing operates independently — changing one track's swing has no effect on other tracks' timing.
- **SC-004**: Swing composes with ratchet, division, direction, and mute without errors or timing glitches.
- **SC-005**: No changes to platform-specific files (seamstress.lua, re_kriate.lua, lib/seamstress/, lib/norns/) — swing lives in shared sequencer and app modules only.
