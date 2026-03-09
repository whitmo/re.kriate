# Feature Specification: Complete Seamstress Kria Sequencer

**Feature Branch**: `001-seamstress-kria-features`
**Created**: 2026-03-06
**Status**: Draft
**Input**: Debug and complete the seamstress kria sequencer. Get all pages working, add missing kria features, use failing-test-first development with 100% test coverage. Break into smaller testable components.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic Sequencer Playback (Priority: P1)

A musician loads re.kriate in seamstress, sees the grid light up with a default pattern, presses play, and hears notes through MIDI. The trigger page shows 4 tracks with playheads advancing. They can stop, reset, and the sequencer responds immediately.

**Why this priority**: Without working playback, nothing else matters. This is the core MVP.

**Independent Test**: Start the script, press play (spacebar or grid), verify MIDI notes fire and playheads advance. Can be tested with recorder voices (no hardware needed).

**Acceptance Scenarios**:

1. **Given** the script is loaded in seamstress v1.4.7 with a grid connected, **When** the user presses the play button (grid x=16, y=8), **Then** the sequencer starts, playheads advance on all 4 tracks, and notes fire on trigger=1 steps
2. **Given** the sequencer is playing, **When** the user presses play again, **Then** the sequencer stops and all active MIDI notes are silenced (note-off + CC 123)
3. **Given** the sequencer is stopped with playheads at various positions, **When** the user presses reset (keyboard 'r'), **Then** all playheads return to their loop_start positions
4. **Given** the sequencer is playing, **When** a trigger step has value 1, **Then** a MIDI note is sent with the correct note (from scale quantization), velocity (from velocity page), and duration (from duration page)
5. **Given** no MIDI device is connected, **When** the user starts the sequencer, **Then** the sequencer runs without errors (notes are silently dropped)

---

### User Story 2 - Trigger Page Editing (Priority: P1)

A musician views the trigger page on the grid, sees all 4 tracks' trigger patterns on rows 1-4, toggles individual steps on/off, and sets per-track loop boundaries.

**Why this priority**: Trigger editing is the most fundamental interaction. The grid must reflect state changes immediately.

**Independent Test**: Toggle steps via grid input, verify track state changes and grid LED output matches.

**Acceptance Scenarios**:

1. **Given** the trigger page is active, **When** the grid redraws, **Then** rows 1-4 show trigger patterns for tracks 1-4 (bright=on, dim=off), with loop region indicated and playhead highlighted
2. **Given** the trigger page is active, **When** the user presses grid (x=5, y=2), **Then** track 2's trigger at step 5 toggles between 0 and 1
3. **Given** the user holds the loop button (grid x=12, y=8), **When** they press step 3 then step 10, **Then** the active track's trigger loop is set to steps 3-10
4. **Given** a trigger loop is set to steps 5-8, **When** the sequencer plays, **Then** the trigger playhead cycles through only steps 5-8

---

### User Story 3 - Value Page Editing: Note, Octave, Duration, Velocity (Priority: P1)

A musician switches to the note page, sees the active track's note values displayed as a bar graph on rows 1-7, and can set note values by pressing grid positions. Each value page works independently with its own loop boundaries.

**Why this priority**: All five core pages (trigger, note, octave, duration, velocity) must work for the sequencer to produce musically meaningful output.

**Independent Test**: Switch to each page, set values, verify state changes. Test that per-parameter loop boundaries work independently.

**Acceptance Scenarios**:

1. **Given** the note page is active for track 1, **When** the grid redraws, **Then** rows 1-7 show note values (row 1 = value 7, row 7 = value 1) with the current value highlighted and playhead column brighter
2. **Given** the note page is active, **When** the user presses grid (x=3, y=2), **Then** track 1's note at step 3 is set to value 6 (8 - row 2)
3. **Given** the note page is active and loop button is held, **When** the user sets a loop of steps 1-8 on the note page, **Then** only the note parameter loops at steps 1-8 while trigger may have a different loop length (polymetric)
4. **Given** different loop lengths on trigger (16) and note (8), **When** the sequencer plays 16 steps, **Then** the note sequence repeats twice while triggers play once — creating polymetric patterns
5. **Given** the octave page is active, **When** the user sets octave values, **Then** the MIDI note output shifts by octaves relative to center (value 4 = no offset)
6. **Given** the duration page is active, **When** the user sets duration to value 5 (1 beat), **Then** note-off messages are sent 1 beat after note-on
7. **Given** the velocity page is active, **When** the user sets velocity to value 7 (max), **Then** MIDI velocity is 127

---

### User Story 4 - Track and Page Navigation (Priority: P1)

A musician navigates between tracks and pages using the grid's row 8 navigation area or keyboard shortcuts.

**Why this priority**: Navigation is essential to reach all editing pages.

**Independent Test**: Press navigation buttons, verify active track/page changes.

**Acceptance Scenarios**:

1. **Given** the grid is connected, **When** the user presses grid (x=1-4, y=8), **Then** the active track changes to track 1-4 respectively
2. **Given** the grid is connected, **When** the user presses grid (x=6, y=8), **Then** the active page changes to trigger
3. **Given** the grid is connected, **When** the user presses grid (x=7/8/9/10, y=8), **Then** the active page changes to note/octave/duration/velocity respectively
4. **Given** the seamstress keyboard is available, **When** the user presses keys 1-4, **Then** the active track changes
5. **Given** the seamstress keyboard is available, **When** the user presses q/w/e/t/y, **Then** the active page changes to trigger/note/octave/duration/velocity

---

### User Story 5 - Screen UI Display (Priority: P2)

A musician sees a status display on the seamstress window showing the current track, page, play state, and per-track step positions.

**Why this priority**: Visual feedback confirms the sequencer state without requiring a grid.

**Independent Test**: Verify screen_ui.redraw produces no errors and displays correct state for various ctx configurations.

**Acceptance Scenarios**:

1. **Given** the script is running, **When** the screen redraws, **Then** it shows the title "re.kriate", active track number, active page name, and play state (playing/stopped)
2. **Given** the sequencer is playing, **When** the screen redraws, **Then** per-track step positions (step N/loop_end) are shown for all 4 tracks
3. **Given** no grid is connected, **When** the user uses keyboard controls, **Then** the screen updates to reflect track/page/play state changes

---

### User Story 6 - Clock Division Per Track (Priority: P2)

A musician sets different clock divisions per track so that track 1 runs at 1/16 notes while track 2 runs at 1/4 notes.

**Why this priority**: Clock division is a core kria feature for creating polyrhythmic textures.

**Independent Test**: Set different divisions on two tracks, step them, verify they advance at different rates.

**Acceptance Scenarios**:

1. **Given** track 1 has division=1 (1/16) and track 2 has division=5 (1/4), **When** the sequencer runs, **Then** track 1 advances 4 steps for every 1 step of track 2
2. **Given** the division parameter is exposed, **When** the user changes track 1's division, **Then** the sequencer clock for that track adjusts immediately

---

### User Story 7 - Scale Quantization (Priority: P2)

A musician selects a root note and scale type, and all note output is quantized to that scale.

**Why this priority**: Scale quantization makes the sequencer musically coherent.

**Independent Test**: Set root + scale, step the sequencer, verify output MIDI notes are all members of the selected scale.

**Acceptance Scenarios**:

1. **Given** root note is C4 (60) and scale is Major, **When** a note fires with degree=1 and octave=4, **Then** the MIDI note is C4 (60)
2. **Given** root note is C4 and scale is Major, **When** a note fires with degree=3 and octave=4, **Then** the MIDI note is E4 (64)
3. **Given** the user changes the root note or scale, **When** the next note fires, **Then** it uses the updated scale

---

### User Story 8 - Direction Modes (Priority: P3)

A musician sets a track's playback direction to forward, reverse, pendulum (bounce), drunk (random walk), or random to create evolving patterns.

**Why this priority**: Direction modes add significant musical variation. This is a standard kria feature not yet implemented.

**Independent Test**: Set direction mode, advance the sequencer N steps, verify the step positions follow the expected pattern.

**Acceptance Scenarios**:

1. **Given** a track with direction=forward and loop 1-8, **When** stepped 8 times, **Then** positions are 1,2,3,4,5,6,7,8 then back to 1
2. **Given** a track with direction=reverse and loop 1-8, **When** stepped 8 times, **Then** positions are 8,7,6,5,4,3,2,1
3. **Given** a track with direction=pendulum and loop 1-4, **When** stepped 8 times, **Then** positions are 1,2,3,4,3,2,1,2 (bounces at boundaries)
4. **Given** a track with direction=drunk and loop 1-8, **When** stepped, **Then** each step moves +1 or -1 from current position (random walk), wrapping at loop boundaries
5. **Given** a track with direction=random and loop 1-8, **When** stepped, **Then** each position is a random step within the loop bounds

---

### User Story 9 - Track Mute (Priority: P3)

A musician mutes individual tracks to silence them without losing their pattern data.

**Why this priority**: Muting is essential for live performance and arrangement.

**Independent Test**: Mute a track, step the sequencer, verify no note events fire for that track.

**Acceptance Scenarios**:

1. **Given** track 2 is muted, **When** the sequencer steps track 2 with trigger=1, **Then** no note event is produced
2. **Given** track 2 is muted, **When** the user unmutes it, **Then** notes fire normally on the next trigger step

---

### User Story 10 - Pattern Storage and Recall (Priority: P3)

A musician saves the current state of all tracks to a pattern slot and recalls it later, enabling live switching between pattern variations.

**Why this priority**: Pattern storage enables composition and live performance. Not yet implemented.

**Independent Test**: Save state to a slot, modify tracks, recall the slot, verify state is restored.

**Acceptance Scenarios**:

1. **Given** a pattern with specific trigger/note/octave/duration/velocity data, **When** the user saves to pattern slot 1, **Then** all track data is preserved
2. **Given** pattern slot 1 has saved data, **When** the user recalls slot 1, **Then** all tracks restore to the saved state
3. **Given** pattern slot 1 is recalled while playing, **When** the sequencer continues, **Then** it uses the restored pattern data from the current playhead position

---

### User Story 11 - Extended Page Toggle (Priority: P2)

A musician presses the same page navigation button twice to toggle between primary and extended views. In original kria, trigger/ratchet, note/alt-note, and octave/glide are paired as primary/extended pages.

**Why this priority**: This is the root cause of the "secondary pages don't work" report. Without the toggle mechanism, ratchet, alt-note, and glide pages are inaccessible.

**Independent Test**: Press the trigger page button once (shows trigger), press it again (shows ratchet). Press a different page button to switch away. Press trigger once again (shows trigger, not ratchet).

**Acceptance Scenarios**:

1. **Given** the trigger page is active, **When** the user presses the trigger page button (grid x=6, y=8) again, **Then** the active page switches to ratchet (extended trigger)
2. **Given** the ratchet page is active, **When** the user presses the trigger page button again, **Then** the active page switches back to trigger
3. **Given** the note page is active, **When** the user presses the note page button again, **Then** the active page switches to alt-note
4. **Given** the octave page is active, **When** the user presses the octave page button again, **Then** the active page switches to glide
5. **Given** the ratchet page is active, **When** the user presses a different page button, **Then** the active page switches to that page (primary view)

---

### User Story 12 - Glide/Portamento Page (Priority: P3)

A musician accesses the glide page (extended octave) to set per-step glide amounts, creating smooth pitch transitions between notes.

**Why this priority**: This is a kria feature the user specifically reported as non-working ("portamento amount"). Accessed via the extended page toggle on the octave button.

**Independent Test**: Toggle to glide page, set values, verify the voice receives glide/portamento information.

**Acceptance Scenarios**:

1. **Given** the glide page is active, **When** the user sets glide values per step, **Then** the voice receives glide timing information alongside note data
2. **Given** glide is set on a step, **When** that step fires, **Then** the pitch transition from the previous note to the current note is smoothed over the glide duration

---

### User Story 13 - Ratchet/Repeat Page (Priority: P3)

A musician accesses the ratchet page (extended trigger) to set per-step note repetitions, creating rapid-fire repeated notes within a single step.

**Why this priority**: This is a kria feature that adds rhythmic complexity. Accessed via the extended page toggle on the trigger button.

**Independent Test**: Toggle to ratchet page, set ratchet values, step the sequencer, verify multiple note events fire for a single step.

**Acceptance Scenarios**:

1. **Given** ratchet is set to 3 on step 5, **When** the sequencer reaches step 5, **Then** 3 evenly-spaced notes fire within that step's time division
2. **Given** ratchet is 1 (default), **When** the step fires, **Then** one note fires as normal

---

### User Story 14 - Alt-Note Page (Priority: P3)

A musician accesses the alt-note page (extended note) to set secondary note values that combine additively with primary notes, creating pitch variation through polymetric note layering.

**Why this priority**: Reported as non-working. Accessed via the extended page toggle on the note button.

**Independent Test**: Toggle to alt-note page, set values, verify combined pitch output during playback.

**Acceptance Scenarios**:

1. **Given** the note page has value 3 at step 1 and the alt-note page has value 2 at step 1, **When** the sequencer plays step 1, **Then** the effective scale degree is (3 + 2 - 2) modulo scale_length + 1 = degree 4 (additive combination)
2. **Given** the alt-note parameter has its own independent loop start/end, **When** the sequencer advances, **Then** the alt-note loop cycles independently of the main note loop, creating polymetric pitch combinations
3. **Given** all alt-note values are set to 1 (default), **When** the sequencer plays, **Then** the effective degree equals the primary note degree (no alteration)

---

### Edge Cases

- What happens when the grid is disconnected mid-session? The sequencer continues, screen shows state, grid reconnects automatically.
- What happens when loop_start equals loop_end? The parameter repeats the same value every step.
- What happens when all triggers are off? The sequencer runs silently (no notes fire).
- What happens when a MIDI note is retriggered before note-off? The pending note-off is cancelled, note-off is sent, then new note-on fires (retrigger handling).
- What happens when the user changes scale while notes are playing? Active notes complete with old pitches; next notes use the new scale.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST load and initialize in seamstress v1.4.7 without errors
- **FR-002**: System MUST run with busted unit tests achieving 100% code coverage on all lib/ modules
- **FR-003**: System MUST support all five core parameter pages: trigger, note, octave, duration, velocity
- **FR-004**: System MUST support per-parameter independent loop lengths (polymetric sequencing)
- **FR-005**: System MUST output MIDI notes with correct pitch (scale-quantized), velocity, and duration
- **FR-006**: System MUST handle note-off timing via clock-synced coroutines with retrigger safety
- **FR-007**: System MUST support grid navigation: track select (x=1-4), page select (x=6-10), loop edit (x=12), play/stop (x=16) on row 8
- **FR-008**: System MUST support keyboard fallback: space=play/stop, r=reset, 1-4=track, q/w/e/t/y=page
- **FR-009**: System MUST display status on the seamstress screen (title, track, page, play state, step positions)
- **FR-010**: System MUST send all-notes-off (CC 123) on stop and cleanup
- **FR-011**: System MUST support clock division per track (1/16 through whole note)
- **FR-012**: System MUST support scale selection via params (root note + scale type)
- **FR-013**: System MUST support track mute
- **FR-014**: Each feature MUST have a failing test written before implementation (TDD)
- **FR-015**: System MUST support extended page toggle (double-press same page button to switch primary/extended: trigger/ratchet, note/alt-note, octave/glide)
- **FR-016**: System SHOULD support direction modes (forward, reverse, pendulum, random)
- **FR-017**: System SHOULD support pattern storage and recall
- **FR-018**: System SHOULD support glide/portamento per step (extended octave page)
- **FR-019**: System SHOULD support ratchet/repeat per step (extended trigger page)
- **FR-020**: System SHOULD support alt-note per step (extended note page)

### Key Entities

- **Track**: Contains parameter pages, division, mute state, direction mode. 4 tracks total.
- **Parameter (Param)**: A sequence of 16 step values with independent loop_start, loop_end, pos. One per parameter type per track.
- **Voice**: Abstraction for note output. Implements play_note, note_on, note_off, all_notes_off. Backends: MIDI, recorder (test).
- **Scale**: Root note + scale type producing a lookup table of MIDI notes indexed by degree and octave.
- **Pattern**: A snapshot of all track state (step values, loop boundaries) that can be saved/recalled.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All busted unit tests pass (target: 100% of lib/ modules covered)
- **SC-002**: The script loads in seamstress v1.4.7, grid lights up, and screen displays status within 2 seconds of launch
- **SC-003**: All 5 core pages (trigger, note, octave, duration, velocity) are editable via grid and produce correct sequencer output
- **SC-004**: Per-parameter loop lengths produce audible polymetric patterns (different loop lengths on note vs trigger)
- **SC-005**: MIDI output plays correct notes with no hanging notes on stop (verified via recorder voice in tests)
- **SC-006**: Keyboard controls work as grid fallback for all navigation and play/stop/reset functions
- **SC-007**: Each new feature has at least one failing test before implementation code is written

## Assumptions

- Target platform is seamstress v1.4.7 (not v2.0.0-alpha which has breaking API changes)
- The norns entrypoint (re_kriate.lua) is maintained but not the focus of this work
- MIDI output uses a single MIDI device with per-track channels (channel = track number)
- Features marked SHOULD (FR-016 through FR-020) are stretch goals after core pages work
- "100% test coverage" means every public function in lib/ has at least one test, not line-level coverage metrics
