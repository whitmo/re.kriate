# Feature Specification: SuperCollider Voice Example

**Feature Branch**: `008-supercollider-voice-example`
**Created**: 2026-03-25
**Status**: Draft
**Input**: User description: "Add example SuperCollider voice: create a SuperCollider SynthDef and companion sclang script that listens for OSC messages from re.kriate's OSC voice backend, with a simple subtractive synth, setup documentation, and an OSC round-trip test."

## Assumptions

- OSC voice integration is complete (feature 004) — `lib/voices/osc.lua` sends messages in the format `/rekriate/track/{n}/note {midi_note} {velocity} {duration}`, `/rekriate/track/{n}/all_notes_off`, `/rekriate/track/{n}/portamento {time}`
- Default OSC target is `127.0.0.1:57120` (SuperCollider's default listening port)
- SuperCollider is installed and available on the user's machine — this feature provides example files, not a SuperCollider installer
- The SynthDef and sclang script are standalone files that live in the repository as examples, not as runtime dependencies of re.kriate itself
- 4 tracks are supported, each receiving notes independently via their own OSC path
- The subtractive synth is intentionally simple — it demonstrates OSC integration, not advanced sound design
- The round-trip test verifies that re.kriate's OSC voice module can communicate with the SuperCollider script, proving the full signal chain works
- Duration is handled client-side: the SynthDef uses an envelope that frees the synth after the specified duration
- Portamento (glide) is implemented as a lag on frequency, controlled per-track via the `/portamento` OSC message
- Velocity maps to amplitude (and optionally filter cutoff) for musical expressiveness

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Play Notes from re.kriate in SuperCollider (Priority: P1)

A musician has re.kriate running on seamstress with one or more tracks set to OSC voice backend. They start the companion SuperCollider script, which begins listening for OSC messages. When the sequencer plays, they hear notes from SuperCollider's subtractive synth — one voice per track, with correct pitch, velocity, and duration.

**Why this priority**: This is the fundamental value — hearing sound from SuperCollider driven by re.kriate. Without this, the example has no purpose.

**Independent Test**: Can be fully tested by starting the SuperCollider script, sending OSC note messages to it, and verifying that synth nodes are created with correct frequency, amplitude, and duration.

**Acceptance Scenarios**:

1. **Given** the SuperCollider script is running, **When** an OSC message `/rekriate/track/1/note 60 100 0.5` is received, **Then** a synth plays middle C at high velocity for 0.5 seconds
2. **Given** the SuperCollider script is running, **When** note messages arrive on tracks 1-4 simultaneously, **Then** each track produces independent sound (4 concurrent voices)
3. **Given** a note is playing, **When** its duration elapses, **Then** the synth frees itself (no manual note-off required for timed notes)
4. **Given** the SuperCollider script is running, **When** an `/rekriate/track/1/all_notes_off` message is received, **Then** all active synths on track 1 are silenced immediately

---

### User Story 2 - Portamento/Glide Between Notes (Priority: P2)

A musician enables glide on a track in re.kriate. The SuperCollider synth smoothly slides between consecutive note pitches rather than jumping discretely, creating a legato effect.

**Why this priority**: Portamento is part of the OSC voice interface and important for musical expression, but basic note playback (US1) must work first.

**Independent Test**: Can be tested by sending a portamento time message followed by two notes in quick succession, and verifying that the frequency transitions smoothly.

**Acceptance Scenarios**:

1. **Given** portamento time is set to 0.2 seconds on track 1, **When** two notes are played in sequence, **Then** the frequency glides over 0.2 seconds from the first pitch to the second
2. **Given** portamento time is 0 (default), **When** notes are played, **Then** pitch changes are instantaneous (no glide)
3. **Given** portamento is active on track 1, **When** portamento time is changed to 0, **Then** subsequent notes have no glide

---

### User Story 3 - Setup and Run the Example (Priority: P1)

A musician who has never used SuperCollider with re.kriate reads the setup documentation, installs SuperCollider (if needed), runs the companion script, and hears sound within minutes. The documentation covers prerequisites, step-by-step startup, and troubleshooting common issues.

**Why this priority**: Equal to US1 — if the user cannot figure out how to run the example, the SynthDef is useless. Documentation is the entry point.

**Independent Test**: Can be tested by following the documentation from scratch on a machine with SuperCollider installed and verifying that all steps lead to working audio output.

**Acceptance Scenarios**:

1. **Given** a user with SuperCollider installed, **When** they follow the setup documentation step by step, **Then** they hear re.kriate-driven sound from SuperCollider within 5 minutes
2. **Given** the documentation, **When** the user reads it, **Then** it covers prerequisites, how to start the SuperCollider script, how to configure re.kriate for OSC output, and how to verify the connection
3. **Given** a common failure (SuperCollider not listening, wrong port), **When** the user checks the troubleshooting section, **Then** they find guidance to diagnose and fix the issue

---

### User Story 4 - Verify OSC Round-Trip (Priority: P2)

A developer or musician wants to verify that the full OSC signal chain works — from re.kriate's OSC voice module through to SuperCollider receiving and acting on the messages. A test script exercises this path and reports success or failure.

**Why this priority**: Verification builds confidence that the integration works end-to-end. Important for maintainability but not required for basic usage.

**Independent Test**: Can be tested by running the test script with SuperCollider active and verifying it reports all checks passing.

**Acceptance Scenarios**:

1. **Given** the SuperCollider listener script is running, **When** the test script is executed, **Then** it sends test OSC messages and verifies that SuperCollider received and processed them
2. **Given** SuperCollider is not running, **When** the test script is executed, **Then** it reports a clear error indicating the receiver is not available
3. **Given** the test script completes, **When** all checks pass, **Then** a summary indicates which message types were verified (note, all_notes_off, portamento)

---

### Edge Cases

- What happens when SuperCollider is not running? OSC is UDP fire-and-forget — re.kriate sends messages regardless. No error in re.kriate. The user hears silence and should check the troubleshooting docs.
- What happens when multiple notes arrive on the same track before the first finishes? Each note creates a new synth node. Multiple synths on the same track can overlap (polyphonic within a track). `all_notes_off` frees all of them.
- What happens with MIDI note 0 or 127 (extremes)? The SynthDef converts MIDI to frequency using the standard formula. Extreme values produce very low or very high pitches but are handled correctly.
- What happens with velocity 0? Velocity 0 produces zero amplitude — effectively silence. The synth still fires and frees after duration.
- What happens with very short durations (e.g., 0.01s)? The synth plays a very short blip. The envelope release is fast enough to handle short durations without clicks (uses a minimum release time).
- What happens when portamento time is very large (e.g., 10s)? The frequency lag is 10 seconds — pitch slides very slowly. This is valid musical behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The deliverable MUST include a SuperCollider SynthDef implementing a subtractive synth with oscillator, low-pass filter with envelope, and amplitude envelope
- **FR-002**: The deliverable MUST include a sclang script that registers OSC responders for all 3 message types across all 4 tracks: `/rekriate/track/{1-4}/note`, `/rekriate/track/{1-4}/all_notes_off`, `/rekriate/track/{1-4}/portamento`
- **FR-003**: The `/note` handler MUST create a synth node with correct frequency (from MIDI note), amplitude (from velocity), and duration, freeing itself after the duration elapses
- **FR-004**: The `/all_notes_off` handler MUST free all active synth nodes on the specified track
- **FR-005**: The `/portamento` handler MUST set a per-track glide time that causes subsequent notes to slide smoothly to the target pitch
- **FR-006**: The SynthDef MUST support per-track polyphony — multiple simultaneous notes on the same track
- **FR-007**: The deliverable MUST include setup documentation covering prerequisites, startup steps, re.kriate configuration, connection verification, and troubleshooting
- **FR-008**: The deliverable MUST include a test script that verifies OSC message reception by sending known messages and checking that SuperCollider processes them
- **FR-009**: The SynthDef MUST use velocity to control both amplitude and filter cutoff for musical expressiveness
- **FR-010**: The sclang script MUST print received messages to the SuperCollider post window for debugging visibility
- **FR-011**: All deliverable files MUST work with SuperCollider's default configuration (port 57120) without requiring user-side SuperCollider configuration changes

### Key Entities

- **SynthDef (rekriate_sub)**: A named SuperCollider synth definition with parameters for frequency, amplitude, duration, filter cutoff, filter envelope amount, and portamento time. Stored in the SuperCollider server once loaded.
- **Track Voice State**: Per-track state in the sclang script tracking active synth nodes and current portamento time. Enables all_notes_off and glide behavior.
- **OSC Responder**: A registered callback in SuperCollider that listens for a specific OSC path and dispatches to the appropriate handler. One responder per message type per track (12 total: 4 tracks x 3 message types).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user following the setup documentation can hear re.kriate-driven sound from SuperCollider within 5 minutes of starting (assuming SuperCollider is already installed)
- **SC-002**: All 4 tracks can play notes simultaneously with correct pitch, velocity, and duration — verified by the round-trip test script
- **SC-003**: Portamento produces audible pitch glide between consecutive notes when glide time is non-zero — verified by the round-trip test script
- **SC-004**: The round-trip test script exercises all 3 OSC message types (note, all_notes_off, portamento) and reports pass/fail for each
- **SC-005**: No changes are required to existing re.kriate source files (`lib/`, `specs/`, entrypoints) — this feature adds new files only
