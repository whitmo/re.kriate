# Feature Specification: Trigger Probability

**Feature Branch**: `011-trigger-probability`
**Created**: 2026-03-26
**Status**: Draft
**Input**: User description: "Add per-step trigger probability (0-100%) as extended page, adding controlled randomness to sequences"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set Per-Step Trigger Probability (Priority: P1)

A musician wants to introduce controlled randomness into their sequence. They navigate to the probability page (the extended trigger page, accessed by double-tapping the trigger page button) and set per-step probability values. Each step in the trigger sequence now has a probability that determines whether it actually fires when the playhead reaches it. At 100% (the default), the step always triggers. At 50%, it fires roughly half the time. At 0%, it never fires. The musician uses this to create evolving, organic patterns that vary on each loop pass without manually editing steps.

**Why this priority**: This is the core feature -- without the probability check in the sequencer step logic, nothing else in this feature matters. It delivers the primary musical value of controlled randomness.

**Independent Test**: Can be fully tested by setting probability values on track steps, running the sequencer for many iterations, and verifying that the trigger fire rate matches the configured probability within statistical tolerance. A deterministic test can seed math.random and verify exact outcomes.

**Acceptance Scenarios**:

1. **Given** all probability steps are set to 100 (default), **When** the sequencer plays through trigger steps with value 1, **Then** every trigger fires (identical to current behavior with no probability feature).
2. **Given** step 3 of track 1 has trigger=1 and probability=50, **When** the sequencer plays through step 3 many times, **Then** the step fires approximately 50% of the time.
3. **Given** step 5 of track 2 has trigger=1 and probability=0, **When** the sequencer reaches step 5, **Then** the step never fires (trigger is suppressed).
4. **Given** step 1 has trigger=0 (no trigger) and probability=100, **When** the sequencer reaches step 1, **Then** no note fires (probability only applies when trigger is 1; a non-trigger step is always silent regardless of probability).
5. **Given** a deterministic random seed, **When** the sequencer plays step 1 with probability=75, **Then** the fire/skip decision is reproducible for the same seed and step sequence.

---

### User Story 2 - Visual Feedback on Grid (Priority: P2)

A musician views the probability page on the grid and sees the probability values for each step of the active track displayed as a value page (rows 1-7 representing values 1-7, mapping to probability levels). The display uses the same value-page layout as other extended pages (ratchet, alt_note, glide), with brightness indicating the current value, loop region, and playhead position. The musician can set probability values by pressing grid positions, just like editing note or velocity values.

**Why this priority**: Without visual feedback and editing on the grid, the musician cannot interact with probability values. However the underlying sequencer logic (US1) can function without grid display, so this is P2.

**Independent Test**: Can be tested by navigating to the probability page, verifying grid LED output matches stored probability values, pressing grid positions to change values, and confirming the stored values update correctly.

**Acceptance Scenarios**:

1. **Given** the trigger page is active, **When** the user presses the trigger page button (grid x=6, y=8) again, **Then** the active page switches to "probability" (the extended trigger page).
2. **Given** the probability page is active, **When** the grid redraws, **Then** rows 1-7 display the probability value for each step of the active track, using the standard value-page layout (row 1 = value 7, row 7 = value 1).
3. **Given** the probability page is active, **When** the user presses grid (x=4, y=3), **Then** the active track's probability at step 4 is set to value 5 (8 - row 3), representing a probability level.
4. **Given** the probability page is active with the loop button held, **When** the user sets loop boundaries, **Then** the probability parameter's independent loop start/end are updated (polymetric probability loops).

---

### User Story 3 - Probability and Ratchet Interaction (Priority: P3)

A musician has both probability and ratchet values set on the same step. When probability allows the step to fire, the full ratchet subdivision plays. When probability suppresses the step, the entire ratchet burst is suppressed -- probability is evaluated once per step, not once per ratchet subdivision. This gives the musician predictable behavior: either the full rhythmic figure plays or it does not.

**Why this priority**: This is a composition concern that arises from two extended trigger features interacting. The core probability logic and grid editing are more fundamental. However, defining this interaction clearly prevents confusing musical behavior.

**Independent Test**: Can be tested by setting trigger=1, ratchet=3, probability=50 on a step, running many iterations, and verifying that when the step fires all 3 ratchet subdivisions play, and when it does not fire none play. No partial ratchets should occur.

**Acceptance Scenarios**:

1. **Given** step 1 has trigger=1, ratchet=4, and probability=100, **When** the sequencer reaches step 1, **Then** all 4 ratchet subdivisions fire (probability=100 always fires).
2. **Given** step 1 has trigger=1, ratchet=4, and probability=0, **When** the sequencer reaches step 1, **Then** no ratchet subdivisions fire (probability=0 never fires).
3. **Given** step 1 has trigger=1, ratchet=3, and probability=50, **When** the step fires (probability roll succeeds), **Then** all 3 ratchet subdivisions play; when it does not fire, zero subdivisions play. Partial ratchets never occur.
4. **Given** a track is muted, **When** the sequencer reaches a step with trigger=1 and probability=50, **Then** the probability check is skipped (mute takes precedence, same as current behavior where muted tracks produce ghost sprites but no audio).

---

### Edge Cases

- What happens when probability is 0 vs. mute? Probability=0 suppresses individual steps but the track is still "live" -- other steps with higher probability can still fire. Mute silences the entire track. These are independent mechanisms.
- What happens when probability values are reset? Loading a pattern that was saved before probability existed results in default probability=100 for all steps (no behavior change from pre-probability patterns).
- What happens with probability and random seed reproducibility? Probability uses math.random, which is not seeded by the sequencer (Lua's default seeding applies). This means patterns are non-deterministic across runs, which is the intended musical behavior. Tests that need determinism can seed math.random explicitly.
- What happens when the probability loop length differs from the trigger loop length? Each parameter has independent loop boundaries. The probability value at the current probability playhead position is used alongside the trigger value at the current trigger playhead position. This creates polymetric probability patterns.
- What happens when probability is set on a step with trigger=0? The probability value is stored but has no effect -- probability is only evaluated when trigger=1. This avoids confusion where a user might expect probability to randomly add triggers.
- What happens if probability is set and then the user switches to ratchet page (current extended trigger page)? Probability replaces ratchet as the extended page for trigger. Ratchet is reassigned -- see Assumptions below.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each track MUST store a per-step probability value as an integer from 0 to 100, with 100 as the default (always fire).
- **FR-002**: When the sequencer evaluates a trigger step with value 1, it MUST generate a random number and compare it to the step's probability value to decide whether the note fires.
- **FR-003**: When probability is 100, the step MUST always fire. When probability is 0, the step MUST never fire. Values between 0 and 100 MUST fire with the corresponding percentage likelihood.
- **FR-004**: Probability MUST be evaluated once per step, before ratchet subdivision. If the probability check fails, the entire ratchet burst is suppressed. If it passes, the full ratchet burst plays.
- **FR-005**: Probability MUST be accessible as an extended page of the trigger page, navigated via double-tap of the trigger page button (grid x=6, y=8), following the existing extended page toggle pattern.
- **FR-006**: The probability page MUST display and edit probability values using the standard value-page grid layout (rows 1-7 for values 1-7, mapping to probability levels), with brightness for loop region, current value, and playhead.
- **FR-007**: Probability MUST have independent loop start, loop end, and playhead position per track, enabling polymetric probability patterns.
- **FR-008**: Probability values MUST be preserved when saving and loading patterns.
- **FR-009**: Loading a pattern that lacks probability data (saved before this feature) MUST default all probability steps to 100 (no behavior change).
- **FR-010**: Probability MUST NOT affect steps where trigger=0. Probability is only evaluated when the trigger value is 1.
- **FR-011**: Probability MUST compose correctly with mute state: muted tracks skip probability evaluation entirely (mute takes precedence).

### Key Entities

- **Probability Value**: An integer (0-100) stored per step, per track, representing the percentage chance a trigger step fires. Stored as a parameter alongside trigger, note, octave, etc. Value 100 means always fire, 0 means never fire. Displayed on the grid as 7 brightness levels (value 1 = ~14%, value 7 = 100%), with the mapping from grid rows (1-7) to probability percentage defined at implementation time.
- **Random State**: The source of randomness for probability evaluation. Uses the runtime's math.random function. Not explicitly seeded by the sequencer, producing non-deterministic variation across loop passes (the desired musical effect).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All existing tests continue to pass with no regressions (probability defaults to 100, preserving current trigger behavior).
- **SC-002**: A step with trigger=1 and probability=100 fires 100% of the time across 1000 iterations in tests.
- **SC-003**: A step with trigger=1 and probability=0 fires 0% of the time across 1000 iterations in tests.
- **SC-004**: A step with trigger=1 and probability=50 fires between 40% and 60% of the time across 1000 iterations in tests (statistical tolerance).
- **SC-005**: Probability interacts correctly with ratchet: when a step fires, all ratchet subdivisions play; when it does not, zero play. No partial ratchets occur.
- **SC-006**: The probability page is navigable via double-tap of the trigger page button on the grid, and probability values are editable via grid key presses.
- **SC-007**: Probability has independent loop boundaries per track, enabling polymetric probability patterns that cycle at different rates than trigger patterns.
- **SC-008**: Patterns saved with probability data round-trip correctly through save/load. Patterns saved without probability data load with probability=100 defaults.

## Assumptions

- Probability is stored as an integer 0-100 on the track data structure, as a new parameter entry in the track's params table (similar to how ratchet, alt_note, and glide are stored).
- Probability replaces ratchet as the extended page for trigger. The existing extended page mapping (trigger -> ratchet) is updated to (trigger -> probability). Ratchet remains accessible -- its grid navigation assignment will be addressed separately (e.g., as a standalone page, or via a third-level toggle). This spec does not cover ratchet's new navigation home.
- The 7 grid row values (1-7) map to probability levels. The exact mapping from row values to the 0-100 integer range is an implementation detail (e.g., linear: value 1=0%, value 4=50%, value 7=100%; or custom breakpoints).
- Probability uses math.random for randomness. No custom seeding or deterministic-mode parameter is included in this feature scope.
- The probability parameter follows the same conventions as other params: 16 steps, independent loop start/end/pos, advanced by the direction module.
- No changes to platform-specific files (seamstress.lua, re_kriate.lua, lib/seamstress/, lib/norns/) -- probability lives in shared sequencer, track, and grid_ui modules only.
