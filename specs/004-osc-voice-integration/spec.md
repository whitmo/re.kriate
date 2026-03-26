# Feature Specification: OSC Voice Integration

**Feature Branch**: `004-osc-voice-integration`
**Created**: 2026-03-25
**Status**: Draft
**Input**: User description: "Add OSC voice integration: wire lib/voices/osc.lua into app.lua as an alternative voice backend alongside MIDI, with per-track OSC target params (host/port), so external synths (SuperCollider, Max/MSP) can receive note events."

## Assumptions

- OSC voice module already exists at `lib/voices/osc.lua` with the full voice interface (`play_note`, `all_notes_off`, `set_portamento`, `set_target`)
- OSC is seamstress-only; norns uses its own `nb` voice system
- Default OSC target is `127.0.0.1:57120` (SuperCollider default port)
- Per-track voice backend selection is a param, not a compile-time config — users can switch between MIDI and OSC at runtime
- All 4 tracks can independently use either MIDI or OSC
- OSC messages use the existing path format: `/rekriate/track/{n}/note`, `/rekriate/track/{n}/all_notes_off`, `/rekriate/track/{n}/portamento`
- Sprite voices (visual output) continue to fire alongside whichever audio voice is active — they are additive, not replaced

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send Notes to External Synth via OSC (Priority: P1)

A musician wants to send note events from re.kriate to an external synthesizer (SuperCollider, Max/MSP, or any OSC-capable software) running on the same machine. They select OSC as the voice backend for a track, and when the sequencer plays, note events arrive at the external synth via OSC messages.

**Why this priority**: This is the core value of the feature — without OSC output, there is no feature. Everything else builds on this.

**Independent Test**: Can be fully tested by configuring one track to use OSC, starting the sequencer, and verifying that OSC messages are sent with correct note, velocity, and duration values.

**Acceptance Scenarios**:

1. **Given** track 1 voice backend is set to "osc", **When** the sequencer fires a note on track 1, **Then** an OSC message is sent to the configured target with the correct MIDI note number, velocity, and duration
2. **Given** track 1 voice backend is set to "osc", **When** the sequencer fires portamento on track 1, **Then** an OSC portamento message is sent with the correct glide time
3. **Given** track 1 voice backend is set to "osc", **When** the sequencer stops, **Then** an OSC all_notes_off message is sent for track 1

---

### User Story 2 - Per-Track Voice Backend Selection (Priority: P1)

A musician wants to use different voice backends on different tracks — for example, tracks 1-2 on MIDI (hardware synths) and tracks 3-4 on OSC (software synths). They select the voice backend independently for each track via the params menu.

**Why this priority**: Mixed MIDI/OSC setups are a primary use case. Without per-track selection, OSC is all-or-nothing, which limits usefulness.

**Independent Test**: Can be fully tested by setting track 1 to MIDI and track 2 to OSC, playing the sequencer, and verifying that track 1 sends MIDI and track 2 sends OSC.

**Acceptance Scenarios**:

1. **Given** a fresh session with default settings, **When** the user opens the params menu, **Then** each track has a "voice backend" parameter with options "midi" and "osc"
2. **Given** track 1 is set to "midi" and track 2 is set to "osc", **When** the sequencer plays, **Then** track 1 outputs via MIDI and track 2 outputs via OSC
3. **Given** track 1 is set to "osc", **When** the user changes track 1 to "midi" while stopped, **Then** subsequent playback sends MIDI, not OSC
4. **Given** the default voice backend, **When** no param is changed, **Then** all tracks default to MIDI (backward compatible)

---

### User Story 3 - Configure OSC Target per Track (Priority: P2)

A musician runs multiple OSC-capable synths on different hosts or ports (e.g., SuperCollider on port 57120, Max/MSP on port 7400). They want to configure the OSC destination host and port independently per track.

**Why this priority**: Multi-target routing is important for real studio setups but the default (localhost:57120) covers the common single-synth case, so this can follow after basic OSC output works.

**Independent Test**: Can be fully tested by setting different hosts/ports on two OSC tracks and verifying that messages route to the correct destinations.

**Acceptance Scenarios**:

1. **Given** track 1 is set to "osc", **When** the user opens the params menu, **Then** track 1 has "osc host" and "osc port" parameters
2. **Given** track 1 has osc host "192.168.1.50" and port 7400, **When** the sequencer fires a note on track 1, **Then** the OSC message is sent to 192.168.1.50:7400
3. **Given** the user changes the osc port for track 1 while stopped, **When** playback resumes, **Then** notes are sent to the new port
4. **Given** track 1 is set to "midi", **When** the user views params, **Then** osc host and osc port params for track 1 are hidden or clearly marked as inactive

---

### User Story 4 - Runtime Voice Reconfiguration (Priority: P2)

A musician wants to switch a track's voice backend or change its OSC target during a session without restarting the script. Changes take effect on the next note, with no stuck notes from the previous backend.

**Why this priority**: Live performance and studio iteration depend on reconfiguring without restart. This builds on US2 and US3 but focuses on safe transitions.

**Independent Test**: Can be fully tested by switching a track from MIDI to OSC mid-session and verifying that the old backend silences and the new backend activates cleanly.

**Acceptance Scenarios**:

1. **Given** track 1 is playing via MIDI, **When** the user changes track 1 to "osc", **Then** all_notes_off is sent on the MIDI backend before switching, and subsequent notes go to OSC
2. **Given** track 1 is playing via OSC to port 57120, **When** the user changes the osc port to 7400, **Then** subsequent notes go to port 7400
3. **Given** track 1 is playing via OSC, **When** the user changes track 1 to "midi", **Then** all_notes_off is sent on the OSC backend before switching, and subsequent notes go to MIDI

---

### User Story 5 - Seamstress-Only Activation (Priority: P3)

The OSC voice option is only available on the seamstress platform. On norns, the voice params show the norns-native voice options (nb) with no OSC option visible.

**Why this priority**: Platform separation is a code hygiene concern, not a user-facing feature. The existing architecture already isolates platform-specific code.

**Independent Test**: Can be tested by verifying that the seamstress entrypoint creates voice backend params and the norns entrypoint does not.

**Acceptance Scenarios**:

1. **Given** the script is running on seamstress, **When** the user opens the params menu, **Then** voice backend selection (midi/osc) and OSC target params are visible
2. **Given** the script is running on norns, **When** the user opens the params menu, **Then** no voice backend or OSC target params are present

---

### Edge Cases

- What happens when the user sets an unreachable OSC host/port? OSC is fire-and-forget (UDP) — messages are sent regardless. No error is raised; the synth simply doesn't receive them. No special handling needed.
- What happens when the user changes voice backend while the sequencer is playing? The old backend receives all_notes_off, then the new backend is swapped in. The next note fires on the new backend.
- What happens when the user sets the same host/port for multiple tracks? This is valid — the receiving synth differentiates tracks by OSC path (`/rekriate/track/{n}/...`).
- What happens on cleanup (script unload) with OSC voices active? Each OSC voice receives all_notes_off during cleanup, same as MIDI.
- What happens when osc port param is set to an invalid value (e.g., 0, 99999)? Port param is constrained to valid range (1-65535) by the param definition.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a per-track "voice backend" parameter with options "midi" and "osc", defaulting to "midi"
- **FR-002**: When a track's voice backend is set to "osc", the system MUST send note events as OSC messages to the configured target using the existing OSC voice module
- **FR-003**: System MUST provide per-track "osc host" and "osc port" parameters, defaulting to "127.0.0.1" and 57120
- **FR-004**: When the voice backend param changes, the system MUST send all_notes_off to the outgoing backend before activating the new one
- **FR-005**: When the osc host or osc port params change, the system MUST update the active OSC voice's target so the next message goes to the new destination
- **FR-006**: Voice backend and OSC target params MUST only be created in the seamstress entrypoint, not in the norns entrypoint
- **FR-007**: Sprite voices (visual output) MUST continue to fire alongside whichever audio voice backend is active
- **FR-008**: All tracks MUST default to MIDI voice backend when no params are changed (backward compatibility)
- **FR-009**: The osc port param MUST be constrained to the valid range 1-65535

### Key Entities

- **Voice Backend Selection**: Per-track configuration that determines whether a track outputs via MIDI or OSC. Stored as a param value, mapped to a voice instance on ctx.voices[track_num].
- **OSC Target**: Per-track host and port pair that determines where OSC messages are sent. Defaults to localhost:57120. Reconfigurable at runtime via params.
- **Voice Instance**: The active voice object for a track (either MIDI or OSC). Implements the voice interface (play_note, all_notes_off, set_portamento). Lives on ctx.voices[track_num].

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 4 tracks can independently send note events via OSC to a configurable target, verified by automated tests capturing outbound OSC messages
- **SC-002**: Switching a track between MIDI and OSC mid-session produces no stuck notes and no dropped notes on the new backend, verified by test scenarios
- **SC-003**: Default behavior (all MIDI) is preserved — existing users see no change unless they configure OSC params
- **SC-004**: At least 15 new tests cover OSC voice wiring, param actions, backend switching, and edge cases
- **SC-005**: All existing tests (512+) continue to pass with no regressions
