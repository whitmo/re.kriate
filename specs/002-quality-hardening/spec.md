# Feature Specification: Quality Hardening — Test Gap Audit & Edge Case Coverage

**Feature Branch**: `002-quality-hardening`
**Created**: 2026-03-24
**Status**: Draft
**Input**: Quality hardening: audit all 442 existing tests for gaps — verify loop boundary edge cases, note retrigger safety, clock stop/start idempotency, pattern save/load roundtrip fidelity, direction mode transitions, mute/unmute timing, and scale change mid-playback. Write failing tests for any uncovered edge case, then fix. Run seamstress load test to verify the script initializes and cleans up without errors or resource leaks.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Loop Boundary Edge Cases (Priority: P1)

A developer runs the test suite and confirms that sequencer loops behave correctly at their boundaries — when a loop is a single step (start == end), when a loop wraps from the last step back to the first, and when loop boundaries change while the sequencer is playing. No note is skipped, doubled, or played out of order.

**Why this priority**: Loop boundaries are the most fundamental sequencer invariant. Every parameter (trigger, note, octave, duration, velocity, ratchet, alt_note, glide) has independent loop bounds. Off-by-one errors here corrupt every musical output.

**Independent Test**: Can be tested by creating tracks with extreme loop configurations (single-step, full-range, wrapping) and verifying advance() produces the expected step sequences.

**Acceptance Scenarios**:

1. **Given** a param with loop_start == loop_end (e.g., both set to step 5), **When** advance is called repeatedly, **Then** the playhead stays on step 5 indefinitely and returns the value at step 5 each time
2. **Given** a param with loop_start=15 and loop_end=16 (last two steps), **When** advance wraps past step 16, **Then** the playhead returns to step 15 (not step 1)
3. **Given** a playing sequencer with a track looping steps 1-8, **When** the loop is changed to steps 5-12 mid-playback and the playhead is at step 3, **Then** the playhead clamps to step 5 on the next advance
4. **Given** a param with loop_start=1 and loop_end=16 (full range), **When** advance is called 32 times, **Then** the playhead cycles through all 16 steps exactly twice
5. **Given** all 8 param types on a track each have different loop lengths, **When** the sequencer plays for 100 steps, **Then** each param independently wraps at its own loop boundary without interfering with other params

---

### User Story 2 - Note Retrigger Safety (Priority: P1)

A developer verifies that when a MIDI voice receives a new note-on while a previous note is still sounding, the previous note is properly silenced before the new note begins. No orphaned MIDI notes are left hanging.

**Why this priority**: Orphaned MIDI notes are the most user-visible bug in any sequencer — a stuck note requires restarting the synth. This is a safety-critical path.

**Independent Test**: Can be tested with the recorder voice by sending rapid note-on events and verifying note-off precedes each retrigger.

**Acceptance Scenarios**:

1. **Given** a MIDI voice is playing note C4, **When** a new note D4 is triggered on the same channel before C4's duration expires, **Then** a note-off for C4 is sent before the note-on for D4
2. **Given** a MIDI voice is playing note C4, **When** the same note C4 is retriggered, **Then** a note-off for C4 is sent, followed by a fresh note-on for C4
3. **Given** a track with all 16 steps triggered and a very long duration, **When** the sequencer plays at fast tempo, **Then** every step produces exactly one note-on preceded by note-off for any active note, with no orphaned notes at the end
4. **Given** the sequencer is stopped, **When** cleanup or stop is called, **Then** all_notes_off is sent and no MIDI notes remain active

---

### User Story 3 - Clock Stop/Start Idempotency (Priority: P1)

A developer confirms that starting an already-playing sequencer, stopping an already-stopped sequencer, and rapid start/stop toggling all behave predictably without crashes, duplicated notes, or state corruption.

**Why this priority**: Users interact with start/stop continuously during performance. The sequencer must be resilient to any timing of these operations.

**Independent Test**: Can be tested by calling start/stop in various sequences and asserting state consistency.

**Acceptance Scenarios**:

1. **Given** the sequencer is already playing, **When** start is called again, **Then** the sequencer remains playing with no duplicate clock coroutines or doubled note output
2. **Given** the sequencer is stopped, **When** stop is called again, **Then** no error occurs and the state remains stopped
3. **Given** the sequencer is playing, **When** stop then start are called in rapid succession, **Then** the sequencer resumes cleanly from the current playhead positions with no orphaned coroutines
4. **Given** the sequencer is playing, **When** start/stop is toggled 50 times rapidly, **Then** the sequencer ends in a consistent state (either playing or stopped) with no resource leaks

---

### User Story 4 - Pattern Save/Load Roundtrip Fidelity (Priority: P2)

A developer saves a pattern containing tracks with non-default values for all parameters (including extended params: ratchet, alt_note, glide) and direction modes, then loads it back and confirms every value is identical.

**Why this priority**: Pattern storage is the user's memory. Data loss in save/load breaks trust in the instrument.

**Independent Test**: Can be tested by creating a pattern with known values, saving, loading, and asserting deep equality.

**Acceptance Scenarios**:

1. **Given** a pattern with custom values for all 8 params across 4 tracks, **When** save then load is performed, **Then** every step value, loop boundary, and position for all params on all tracks matches the original
2. **Given** a pattern with non-default direction modes (reverse, pendulum, drunk, random) on different tracks, **When** save then load is performed, **Then** each track's direction mode is preserved
3. **Given** a pattern where extended params (ratchet, alt_note, glide) have non-default values, **When** save then load is performed, **Then** all extended param values are preserved
4. **Given** a pattern is saved, modified, then a different slot is saved, **When** the first slot is loaded, **Then** the modifications are discarded and the original saved state is restored
5. **Given** an empty/default pattern slot, **When** load is called, **Then** the sequencer loads cleanly with default values (no error, no corruption)

---

### User Story 5 - Direction Mode Transitions (Priority: P2)

A developer confirms that changing a track's direction mode while the sequencer is playing produces a correct and musically coherent step sequence without skipping steps or crashing.

**Why this priority**: Direction changes during live performance are a key creative tool. Transitions must be seamless.

**Independent Test**: Can be tested by changing direction mode mid-sequence and verifying the next steps follow the new mode's rules.

**Acceptance Scenarios**:

1. **Given** a track playing forward at step 8, **When** direction is changed to reverse, **Then** the next step is 7 (reverse from current position)
2. **Given** a track playing in pendulum mode, **When** direction is changed to forward, **Then** the playhead continues forward from its current position
3. **Given** a track playing forward, **When** direction is changed to drunk, **Then** subsequent steps are random but always within loop bounds
4. **Given** a track playing in any direction with a single-step loop, **When** direction is changed to any other mode, **Then** the playhead stays on that single step

---

### User Story 6 - Mute/Unmute Timing (Priority: P2)

A developer confirms that muting a track silences its note output while the playhead continues advancing, and unmuting resumes note output from the correct current position.

**Why this priority**: Mute is a core performance feature. Silent advancement is a design decision documented in the project's key decisions.

**Independent Test**: Can be tested by muting a track, advancing several steps, unmuting, and verifying the playhead is at the expected position.

**Acceptance Scenarios**:

1. **Given** a playing track with triggers on every step, **When** the track is muted, **Then** no MIDI notes are sent but the playhead continues to advance each clock tick
2. **Given** a muted track with the playhead at step 5, **When** 3 clock ticks pass and the track is unmuted, **Then** the next note plays from step 8 (not step 5)
3. **Given** a muted track, **When** mute is called again (double mute), **Then** the track remains muted with no error
4. **Given** all 4 tracks are muted, **When** the sequencer plays for several beats, **Then** no notes are output but all playheads advance correctly

---

### User Story 7 - Scale Change Mid-Playback (Priority: P3)

A developer confirms that changing the active scale while the sequencer is playing causes subsequent notes to use the new scale without corrupting note values or crashing.

**Why this priority**: Scale changes are musically interesting but happen less frequently than other operations. Correctness matters but this is a lower-frequency interaction.

**Independent Test**: Can be tested by changing the scale during playback and verifying the next note event uses the new scale.

**Acceptance Scenarios**:

1. **Given** the sequencer is playing with a major scale, **When** the scale is changed to minor, **Then** the next note triggered uses the minor scale for quantization
2. **Given** a note value of 7 (the 7th scale degree) is active, **When** the scale is changed to a scale with fewer than 7 degrees, **Then** the note wraps correctly within the new scale without error
3. **Given** the scale is changed, **When** notes that were already sounding continue, **Then** they are not retroactively re-pitched (only new note-ons use the new scale)

---

### User Story 8 - Seamstress Load Test (Priority: P3)

A developer launches the script in seamstress, verifies it initializes without errors, runs for a sustained period, and cleans up without resource leaks when unloaded.

**Why this priority**: Initialization and cleanup bugs only manifest in the real runtime. This integration test catches issues that unit tests miss.

**Independent Test**: Can be tested by launching seamstress with the script, running for 30 seconds, then exiting and checking for errors.

**Acceptance Scenarios**:

1. **Given** seamstress v1.4.7 is available, **When** the script is loaded with `seamstress -s re_kriate`, **Then** the script initializes without errors and the screen draws the UI
2. **Given** the script is running in seamstress, **When** the sequencer plays for 30 seconds with all features active, **Then** no errors are logged and memory usage remains stable
3. **Given** the script is running, **When** the user exits seamstress, **Then** the cleanup function runs, all MIDI notes are silenced, and no resources are leaked

---

### Edge Cases

- What happens when loop_start is set greater than loop_end? (Should be rejected or swapped)
- What happens when a track's step values are all 0 (no triggers)? (Playhead should still advance)
- What happens when the pattern module is asked to load a slot that was never saved? (Should load defaults gracefully)
- What happens when all 4 tracks have direction=random and single-step loops? (Degenerate but valid — should not crash)
- What happens when a muted track is also the one being edited on the grid? (Visual state should still reflect edits, just no sound)
- What happens when scale is changed to a 1-degree scale? (Notes should all map to a single pitch)
- What happens when clock tempo is set to the minimum or maximum value? (Sequencer should still function)
- What happens when cleanup is called while the sequencer is mid-step (note-on sent, note-off pending)? (All notes must be silenced)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The test suite MUST cover single-step loops (loop_start == loop_end) for all param types, verifying the playhead returns the same value indefinitely
- **FR-002**: The test suite MUST cover loop wrapping at step boundaries (step 16 to step 1 and back) for forward, reverse, and pendulum directions
- **FR-003**: The test suite MUST verify that MIDI note-off is sent before note-on when retriggering a note on the same channel
- **FR-004**: The test suite MUST verify that calling start on a playing sequencer is idempotent (no duplicate coroutines or doubled output)
- **FR-005**: The test suite MUST verify that calling stop on a stopped sequencer is idempotent (no error)
- **FR-006**: The test suite MUST verify pattern save/load roundtrip for all 8 param types, direction modes, and extended params
- **FR-007**: The test suite MUST verify that changing direction mid-sequence continues from the current playhead position
- **FR-008**: The test suite MUST verify that muted tracks advance their playheads without producing note output
- **FR-009**: The test suite MUST verify that scale changes take effect on the next note-on, not retroactively
- **FR-010**: The test suite MUST verify that all_notes_off is called during cleanup
- **FR-011**: Any failing test MUST have a corresponding code fix that makes it pass
- **FR-012**: A seamstress load test MUST verify the script initializes and cleans up without errors

### Assumptions

- The existing 442 tests are correct — this feature adds coverage, it does not rewrite passing tests
- "Extended params" refers to ratchet, alt_note, and glide as defined in the existing track module
- The 8 param types are: trigger, note, octave, duration, velocity, ratchet, alt_note, glide
- Direction modes are: forward, reverse, pendulum, drunk, random (5 total)
- The seamstress load test can use a headless or short-duration approach since full interactive testing is out of scope for automated CI
- Loop boundaries are 1-indexed and range from 1 to 16 (the step count per param)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All existing 442 tests continue to pass (zero regressions)
- **SC-002**: At least 30 new edge-case tests are added covering the 7 gap areas (loop boundaries, retrigger, clock idempotency, pattern roundtrip, direction transitions, mute timing, scale change)
- **SC-003**: Every new test is written as a failing test first, then a code fix is applied (TDD discipline verified by commit history)
- **SC-004**: The seamstress load test runs the script for at least 30 seconds without errors or resource leaks
- **SC-005**: 100% of all edge cases listed in the Edge Cases section have at least one covering test
- **SC-006**: The test suite runs in under 5 seconds (no performance degradation from added tests)
