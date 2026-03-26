# Feature Specification: MIDI Clock Sync

**Feature Branch**: `010-clock-sync`
**Created**: 2026-03-26
**Status**: Draft
**Input**: User description: "Add MIDI clock sync: slave to external MIDI clock or send clock to external gear, with start/stop/continue transport messages"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Receive External MIDI Clock (Priority: P1 MVP)

A musician connects re.kriate to a DAW or drum machine that sends MIDI clock. They select "external MIDI" as the clock source. The sequencer's tempo now follows the incoming MIDI clock pulses rather than the internal clock. When the external device speeds up or slows down, re.kriate follows. The musician does not need to manually set a BPM -- the tempo is derived entirely from the incoming clock stream.

**Why this priority**: Slaving to an external clock is the most common integration scenario. Musicians frequently run norns alongside a DAW or hardware sequencer and need everything locked to one master clock. Without this, re.kriate cannot participate in a multi-device setup.

**Independent Test**: Can be fully tested by sending MIDI clock messages from an external source (or test harness) to re.kriate and verifying that the sequencer advances steps in sync with the incoming pulses, at whatever tempo the external source dictates.

**Acceptance Scenarios**:

1. **Given** re.kriate with clock source set to "external MIDI", **When** an external device sends MIDI clock pulses at 120 BPM, **Then** the sequencer advances steps at a rate consistent with 120 BPM and the configured track division.
2. **Given** re.kriate slaved to external clock at 120 BPM, **When** the external device changes tempo to 90 BPM, **Then** the sequencer's step rate adjusts to match 90 BPM without user intervention.
3. **Given** re.kriate with clock source set to "external MIDI", **When** no external clock is received, **Then** the sequencer does not advance (it waits for clock pulses).
4. **Given** re.kriate with clock source set to "internal", **When** the user plays the sequencer, **Then** behavior is identical to current operation (no regression).

---

### User Story 2 - Send MIDI Clock to External Gear (Priority: P1)

A musician wants re.kriate to be the master clock for their setup. They enable clock output so that re.kriate sends MIDI clock messages to connected gear (synths, drum machines, effects pedals with tap-tempo sync). External devices lock to re.kriate's tempo. When the musician changes BPM in re.kriate, the external gear follows.

**Why this priority**: Sending clock is the complement of receiving it and equally essential for integration. Many musicians use norns as the central sequencer and need downstream gear to stay in sync.

**Independent Test**: Can be tested by enabling clock output, starting the sequencer, and verifying that MIDI clock messages are sent at the correct rate on the configured MIDI output. A MIDI monitor or test harness can verify pulse timing and count.

**Acceptance Scenarios**:

1. **Given** clock output enabled and the sequencer playing at 120 BPM, **When** observing the MIDI output, **Then** MIDI clock pulses (0xF8) are sent at a rate of 24 pulses per quarter note (24 PPQ), i.e., 48 pulses per second at 120 BPM.
2. **Given** clock output enabled and the sequencer playing, **When** the BPM changes, **Then** the MIDI clock pulse rate adjusts to reflect the new tempo.
3. **Given** clock output disabled, **When** the sequencer is playing, **Then** no MIDI clock pulses are sent on the MIDI output.

---

### User Story 3 - Transport Controls (Start/Stop/Continue) (Priority: P2)

A musician expects that when re.kriate starts, stops, or continues playback, the corresponding MIDI transport messages are sent (when acting as master) or honored (when slaved). Pressing play on the DAW starts re.kriate. Pressing stop on re.kriate stops the drum machine. Continue resumes from the current position rather than restarting from the beginning.

**Why this priority**: Transport messages are essential for a polished sync experience, but the core clock sync (US1/US2) provides value even without them. A musician can manually start/stop devices if needed. This is a strong P2 because without it the workflow is clunky.

**Independent Test**: Can be tested by sending/receiving MIDI start (0xFA), stop (0xFC), and continue (0xFB) messages and verifying the sequencer responds correctly (starts, stops, or continues from current position).

**Acceptance Scenarios**:

1. **Given** re.kriate slaved to external clock, **When** a MIDI Start message is received, **Then** the sequencer resets all playheads to loop start and begins playing.
2. **Given** re.kriate slaved to external clock and currently stopped mid-sequence, **When** a MIDI Continue message is received, **Then** the sequencer resumes from the current playhead positions (does not reset).
3. **Given** re.kriate slaved to external clock and currently playing, **When** a MIDI Stop message is received, **Then** the sequencer stops and all voices are silenced.
4. **Given** re.kriate as clock master with clock output enabled, **When** the user starts the sequencer, **Then** a MIDI Start message (0xFA) is sent before clock pulses begin.
5. **Given** re.kriate as clock master with clock output enabled, **When** the user stops the sequencer, **Then** a MIDI Stop message (0xFC) is sent and clock pulses cease.

---

### User Story 4 - Clock Status Display (Priority: P3)

A musician glances at the norns/seamstress screen and sees the current clock source and sync status at a glance. When slaved to an external clock, a visual indicator shows whether clock is being received. When acting as master, the display shows the current BPM and that clock output is active.

**Why this priority**: This is a quality-of-life improvement. The musician can verify sync status without needing an external MIDI monitor. Not required for functional sync but important for usability and debugging sync issues.

**Independent Test**: Can be tested by setting different clock modes and verifying the screen displays the correct clock source, BPM (when available), and sync status indicator.

**Acceptance Scenarios**:

1. **Given** clock source set to "internal", **When** viewing the screen, **Then** the display shows "internal" as the clock source and the current BPM.
2. **Given** clock source set to "external MIDI" and clock pulses arriving, **When** viewing the screen, **Then** the display shows "ext MIDI" as the clock source and the detected BPM.
3. **Given** clock source set to "external MIDI" and no clock pulses arriving, **When** viewing the screen, **Then** the display indicates no clock is being received (e.g., "no clock" or a stale BPM with a warning indicator).

---

### Edge Cases

- What happens when the external clock source has significant jitter (uneven pulse spacing)? The sequencer should tolerate reasonable jitter without audible artifacts. BPM display may fluctuate but step timing should remain musically usable.
- What happens when the external clock source changes tempo abruptly (e.g., from 120 BPM to 60 BPM in one beat)? The sequencer should follow the new tempo within one or two clock pulses without crashing or producing stuck notes.
- What happens when the external MIDI clock source disconnects mid-sequence? The sequencer should stop advancing (no runaway behavior). Voices that are currently sounding should be silenced after a reasonable timeout. The display should indicate loss of clock.
- What happens when switching clock source from internal to external while the sequencer is playing? The sequencer should stop, switch clock source, and wait for the user to restart (or for an external Start message). In-flight notes should be cleaned up.
- What happens when clock output is enabled but no MIDI device is connected? Clock output should degrade gracefully -- no errors or crashes. Clock messages are simply not sent.
- What happens when re.kriate receives both MIDI clock and has clock output enabled simultaneously (loop)? The system should prevent clock feedback loops by not allowing simultaneous clock input and output on the same MIDI port.
- What happens when the external clock rate is extremely slow (< 20 BPM) or extremely fast (> 300 BPM)? The sequencer should handle the full range of reasonable MIDI clock rates without special casing. Display may show a warning for extreme tempos but operation should not fail.
- What happens when a MIDI Continue message is received but the sequencer has never been started? It should behave like a Start message (reset and play from the beginning).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support selecting between "internal" and "external MIDI" clock sources via the parameter system.
- **FR-002**: When clock source is "external MIDI", the sequencer MUST derive its tempo entirely from incoming MIDI clock pulses (24 PPQ standard) and MUST NOT use the internal BPM setting.
- **FR-003**: When clock source is "external MIDI", the sequencer MUST advance steps at the correct rate based on incoming clock pulses and the track's configured division.
- **FR-004**: The system MUST support enabling/disabling MIDI clock output independently of the clock source selection.
- **FR-005**: When clock output is enabled, the system MUST send MIDI clock pulses (status byte 0xF8) at 24 pulses per quarter note, derived from the current tempo.
- **FR-006**: When clock output is enabled and the sequencer starts, the system MUST send a MIDI Start message (0xFA) before the first clock pulse.
- **FR-007**: When clock output is enabled and the sequencer stops, the system MUST send a MIDI Stop message (0xFC) and cease sending clock pulses.
- **FR-008**: When slaved to external clock, the system MUST respond to incoming MIDI Start (0xFA), Stop (0xFC), and Continue (0xFB) transport messages by starting (with playhead reset), stopping, or resuming playback respectively.
- **FR-009**: When switching clock source while the sequencer is playing, the system MUST stop playback and silence all voices before completing the switch.
- **FR-010**: The display MUST show the current clock source and, when available, the current or detected BPM.
- **FR-011**: Clock sync state (source selection, clock output enabled/disabled) MUST be stored on the context object (ctx), consistent with the project's state management pattern.
- **FR-012**: The system MUST NOT allow clock input and clock output on the same MIDI port simultaneously, to prevent feedback loops.

### Key Entities

- **Clock Source**: The source of timing for the sequencer. Either "internal" (using the platform's built-in clock at a user-set BPM) or "external MIDI" (deriving tempo from incoming MIDI clock pulses). Stored on ctx as part of clock configuration.
- **Transport State**: The current playback state of the sequencer in relation to MIDI transport: stopped, playing, or paused (after Stop, awaiting Continue). Determines how the sequencer responds to incoming transport messages and what transport messages are sent on state changes.
- **PPQ Resolution**: MIDI clock runs at 24 pulses per quarter note (24 PPQ). This is the standard MIDI clock resolution. Each pulse corresponds to 1/24 of a beat. The sequencer's division map must convert between PPQ and the configured step divisions.
- **Clock Output**: A toggle controlling whether MIDI clock pulses and transport messages are sent to external gear. Independent of clock source -- a device can slave to external clock while also forwarding clock to downstream devices (on a different MIDI port).

## Assumptions

- MIDI clock uses the standard 24 pulses per quarter note (24 PPQ) resolution, as defined by the MIDI specification.
- The norns platform provides `clock.source` for selecting external sync, and the `midi.event` callback delivers raw MIDI bytes including clock and transport messages. The seamstress platform has its own clock and midi modules with equivalent capabilities.
- The existing `clock.sync(division)` call in the sequencer's track_clock function will work correctly when the platform's clock source is set to external MIDI -- the platform handles the translation from MIDI clock pulses to `clock.sync` wakeups.
- State is stored on the ctx object per project conventions. No globals are introduced.
- The MIDI device used for clock input/output is already connected and accessible via `ctx.midi_dev` or the platform's MIDI connection API.
- Pattern save/load does not need to persist clock source selection (this is a session-level setting, not a musical pattern parameter).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When slaved to an external MIDI clock at any tempo between 40 and 240 BPM, the sequencer advances steps within 1 clock pulse of the expected timing (no drift over 16 bars).
- **SC-002**: When sending MIDI clock, the output pulse rate matches the configured BPM within 0.5% accuracy over a 4-bar window.
- **SC-003**: Transport messages (Start/Stop/Continue) are sent or responded to within 1 ms of the triggering event (sequencer start/stop or incoming MIDI message).
- **SC-004**: Switching clock source while playing does not produce stuck notes -- all voices are silenced before the switch completes.
- **SC-005**: All existing tests continue to pass with no regressions (internal clock remains the default, preserving current behavior for users who do not configure external sync).
- **SC-006**: The clock source and output settings are accessible via the parameter system and can be changed without restarting the script.
- **SC-007**: The screen displays the correct clock source and detected/configured BPM, updating within 1 second of a tempo change.
