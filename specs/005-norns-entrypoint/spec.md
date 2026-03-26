# Feature Specification: Norns Platform Entrypoint

**Feature Branch**: `005-norns-entrypoint`
**Created**: 2026-03-25
**Status**: Draft
**Input**: User description: "Add norns platform entrypoint: complete re_kriate.lua (norns main script) that mirrors seamstress.lua feature parity but uses norns screen API, norns key/enc callbacks, and nb voice output instead of MIDI. Grid uses monome hardware provider. The current re_kriate.lua is a 56-line stub with nb voice setup and basic callbacks delegating to app.lua."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Norns Script Initialization (Priority: P1)

A norns user loads re.kriate from the norns menu. The script initializes with nb voices, connects to a monome grid, sets up logging, and presents the kria interface on the norns screen. The user sees track and page info, play/stop status, and can immediately interact via keys, encoders, and grid.

**Why this priority**: Without successful initialization, no other functionality works. This is the foundation for the entire norns experience.

**Independent Test**: Can be tested by loading the script on norns (or in tests by calling init()) and verifying that ctx is created with voices, grid, and all params registered.

**Acceptance Scenarios**:

1. **Given** the script is not loaded, **When** the user selects re.kriate from the norns menu, **Then** the script initializes with 4 nb voices, a monome grid connection, logging active, and all params (scale, division, direction) registered.
2. **Given** the script is loaded, **When** init() completes, **Then** the norns screen displays the re.kriate UI with track number, active page, and play/stop status.
3. **Given** the script is loaded, **When** init() completes, **Then** the grid metro is running and the grid responds to key presses.

---

### User Story 2 - Key and Encoder Interaction (Priority: P1)

A norns user interacts with the physical keys and encoders to control the sequencer. K2 toggles play/stop, K3 resets playheads, E1 selects tracks, and E2 selects pages. All interactions update both the screen and grid state.

**Why this priority**: Keys and encoders are the primary norns interaction method (alongside grid). Without them, the sequencer cannot be controlled.

**Independent Test**: Can be tested by calling key(n, z) and enc(n, d) with various inputs and verifying ctx state changes and that grid_dirty is set.

**Acceptance Scenarios**:

1. **Given** the sequencer is stopped, **When** the user presses K2, **Then** the sequencer starts playing.
2. **Given** the sequencer is playing, **When** the user presses K2, **Then** the sequencer stops.
3. **Given** the sequencer is playing, **When** the user presses K3, **Then** all playheads reset to their starting positions.
4. **Given** track 1 is active, **When** the user turns E1 clockwise, **Then** the active track advances to track 2.
5. **Given** the trigger page is active, **When** the user turns E2 clockwise, **Then** the active page advances to the next page.

---

### User Story 3 - Glide Support via nb Voices (Priority: P2)

A norns user programs glide values on the glide page. When the sequencer plays a step with glide enabled, the nb voice receives a portamento instruction so connected sound engines can produce smooth pitch transitions between notes.

**Why this priority**: Glide is a core kria feature. Currently nb_voice silently ignores set_portamento calls. Adding this method completes the voice interface contract for norns, achieving feature parity with MIDI and OSC backends.

**Independent Test**: Can be tested by creating an nb_voice, calling set_portamento(time), and verifying the underlying nb player receives the portamento instruction.

**Acceptance Scenarios**:

1. **Given** a track has glide value > 1, **When** the sequencer plays that step, **Then** the nb voice's set_portamento is called with the glide value before play_note.
2. **Given** a track has glide value of 1 (off), **When** the sequencer plays that step, **Then** the nb voice's set_portamento is called with 0 to disable portamento.
3. **Given** an nb player that does not support portamento, **When** set_portamento is called, **Then** the call completes without error (graceful degradation).

---

### User Story 4 - Clean Shutdown (Priority: P2)

A norns user navigates away from re.kriate or loads another script. The cleanup process stops the sequencer, silences all voices, disconnects the grid cleanly, and closes logging. No resources leak between script loads.

**Why this priority**: Clean shutdown prevents stuck notes, orphaned clocks, and resource leaks that degrade the norns experience across script changes.

**Independent Test**: Can be tested by calling cleanup() after init() and verifying all voices get all_notes_off, the grid metro stops, and the log closes.

**Acceptance Scenarios**:

1. **Given** the sequencer is playing, **When** cleanup is called, **Then** the sequencer stops and all voices receive all_notes_off.
2. **Given** the grid metro is running, **When** cleanup is called, **Then** the grid metro stops.
3. **Given** logging is active, **When** cleanup is called, **Then** the log is closed.

---

### User Story 5 - Logging Integration (Priority: P3)

The norns entrypoint integrates the logging system for diagnostics. Session start/end is logged, and critical callbacks (grid key, screen metro) are wrapped with error capture so failures are recorded rather than crashing silently.

**Why this priority**: Logging aids debugging on the norns platform where error visibility is limited. Lower priority because the core sequencer works without it.

**Independent Test**: Can be tested by verifying that init() calls log.session_start(), cleanup() calls log.close(), and grid key callback is wrapped with log.wrap.

**Acceptance Scenarios**:

1. **Given** the script loads, **When** init() runs, **Then** log.session_start() is called.
2. **Given** the grid key callback fires, **When** a grid press event occurs, **Then** the callback is wrapped with log.wrap for error capture.
3. **Given** the script unloads, **When** cleanup() runs, **Then** log.close() is called after all other cleanup.

---

### Edge Cases

- What happens when no monome grid is connected? The monome grid provider calls grid.connect() which returns a stub device on norns — the script initializes normally, grid events are just absent.
- What happens when an nb voice player is not selected? The nb_voice wrapper calls get_player() which returns nil — play_note and set_portamento check for player existence and no-op gracefully.
- What happens when set_portamento is called on an nb player that doesn't support it? The nb_voice wrapper should call the player method only if it exists, otherwise no-op.
- What happens when cleanup is called before init completes? ctx may be nil — cleanup must guard against nil ctx.
- What happens when the user rapidly switches scripts? Each cleanup/init cycle must be independent — no state leaks between loads.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The norns entrypoint MUST create 4 nb voice instances and pass them to app.init as the voices config.
- **FR-002**: The norns entrypoint MUST explicitly specify "monome" as the grid_provider when calling app.init.
- **FR-003**: The norns entrypoint MUST delegate key(n, z) to app.key(ctx, n, z) and enc(n, d) to app.enc(ctx, n, d).
- **FR-004**: The norns entrypoint MUST delegate redraw() to app.redraw(ctx).
- **FR-005**: The norns entrypoint MUST delegate cleanup() to app.cleanup(ctx) and additionally close the log.
- **FR-006**: The nb_voice module MUST implement set_portamento(time) to pass portamento instructions to the underlying nb player, no-oping gracefully if the player does not support it.
- **FR-007**: The norns entrypoint MUST call log.session_start() during init and log.close() during cleanup.
- **FR-008**: The norns entrypoint MUST wrap the grid key callback with log.wrap for error capture.
- **FR-009**: The norns entrypoint MUST NOT include OSC voice backend, sprite voices, keyboard input, simulated grid, or MIDI channel params — these are seamstress-only features.
- **FR-010**: The norns entrypoint MUST define only the 5 standard norns global hooks (init, redraw, key, enc, cleanup) with no other custom globals.

### Key Entities

- **nb_voice**: Wraps an nb player into the standard voice interface (play_note, note_on, note_off, all_notes_off, set_portamento). Lives on ctx.voices[track_num].
- **ctx**: The application context table created by app.init. Carries tracks, voices, grid, scale_notes, playing state, and all other app state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The norns entrypoint initializes successfully with 4 nb voices, a monome grid, and all params registered — verified by test.
- **SC-002**: All 5 norns global hooks (init, redraw, key, enc, cleanup) delegate correctly to app module functions — verified by test.
- **SC-003**: The nb_voice set_portamento method works for nb players that support it and no-ops gracefully for those that don't — verified by test.
- **SC-004**: At least 10 new tests covering norns entrypoint initialization, callback delegation, nb voice portamento, and cleanup — all passing.
- **SC-005**: All 536+ existing tests continue to pass with 0 failures (regression-free).
- **SC-006**: The entrypoint file defines exactly 5 globals (init, redraw, key, enc, cleanup) and no others — verified by structural check.
