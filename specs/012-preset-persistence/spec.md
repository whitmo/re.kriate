# Feature Specification: Preset Persistence (Save/Load to Disk)

**Feature Branch**: `012-preset-persistence`
**Created**: 2026-03-26
**Status**: Draft
**Input**: User description: "Add preset save/load to disk using Lua tables or SQLite, supporting multiple named presets across sessions"

## User Scenarios & Testing

### User Story 1 - Save Current State to a Named Preset (Priority: P1)

A musician has spent time programming a set of patterns, tuning loop lengths, setting scale and tempo, and building a meta-sequence chain. They want to save everything to a named preset file so they can recall it tomorrow, next week, or after loading a different preset. They navigate to a save action (via params menu or key combo), enter or select a preset name, and the entire sequencer state is written to disk.

**Why this priority**: Without the ability to save, all other preset features are meaningless. This is the foundational capability — a musician loses their work every time the script unloads.

**Independent Test**: Can be tested by programming a non-default pattern (e.g., changing note values on track 1, setting a custom loop length), triggering save with a name like "my-jam", and verifying that a file appears at the expected path containing the correct state data.

**Acceptance Scenarios**:

1. **Given** the musician has modified tracks, scale, and pattern slots, **When** they save to a preset named "my-jam", **Then** a file is created at the data directory containing all current state
2. **Given** a preset named "my-jam" already exists on disk, **When** the musician saves to the same name, **Then** the existing file is overwritten with the current state
3. **Given** the musician attempts to save, **When** the data directory does not exist, **Then** the system creates the directory and saves successfully
4. **Given** the musician saves a preset, **When** the save completes, **Then** the system provides visual confirmation (screen flash or text) that the save succeeded

---

### User Story 2 - Load a Preset from Disk (Priority: P1)

A musician wants to recall a previously saved session. They navigate to a load action, select a preset by name from the available presets, and the entire sequencer state is restored — tracks, patterns, scale settings, meta-sequence chain, and all per-track parameters (division, direction, swing).

**Why this priority**: Loading is the complement of saving — together they form the minimum viable preset system. A musician needs both to preserve work across sessions.

**Independent Test**: Can be tested by saving a known state, reinitializing the script (or loading a different preset), then loading the saved preset and verifying all tracks, patterns, loop lengths, and settings match the original.

**Acceptance Scenarios**:

1. **Given** a valid preset file "my-jam" exists on disk, **When** the musician loads it, **Then** all track step data, loop boundaries, pattern slots, scale settings, and meta-sequence chain are restored to the values at save time
2. **Given** the sequencer is playing, **When** the musician loads a preset, **Then** playback stops, the state is loaded, and the musician can restart with the new state
3. **Given** the musician attempts to load a preset that does not exist, **Then** the system displays an error message and the current state is unchanged
4. **Given** a preset file exists but is corrupt (truncated or malformed), **When** the musician loads it, **Then** the system displays an error message and the current state is unchanged (no partial load)

---

### User Story 3 - Browse and Manage Presets (Priority: P2)

A musician wants to see what presets they have saved, so they can choose one to load or decide on a name for a new save. They can browse a list of available preset names. They can also delete presets they no longer need.

**Why this priority**: Browsing enhances usability but is not required for the core save/load loop. A musician who knows their preset names can save and load without a browser.

**Independent Test**: Can be tested by saving 3 presets with different names, opening the preset browser, verifying all 3 appear in the list, selecting one to load, and deleting another.

**Acceptance Scenarios**:

1. **Given** 3 preset files exist in the data directory, **When** the musician opens the preset browser, **Then** all 3 preset names are listed in alphabetical order
2. **Given** the musician is browsing presets, **When** they select a preset and confirm load, **Then** that preset is loaded (same behavior as User Story 2)
3. **Given** the musician selects a preset in the browser, **When** they choose delete and confirm, **Then** the file is removed from disk and the list updates
4. **Given** no presets exist on disk, **When** the musician opens the preset browser, **Then** the system shows an empty list with a message indicating no presets are saved

---

### User Story 4 - Auto-Save on Exit (Priority: P3)

When the musician exits the script (norns menu navigation, script change, or shutdown), the current state is automatically saved to a reserved auto-save slot. On next launch, the system can optionally restore from the auto-save, letting the musician pick up exactly where they left off.

**Why this priority**: This is a convenience feature that prevents accidental loss. It builds on the core save/load infrastructure and is not needed for a functional preset system.

**Independent Test**: Can be tested by modifying state, triggering cleanup (script unload), reloading the script, and verifying the auto-saved state is available for restoration.

**Acceptance Scenarios**:

1. **Given** the musician has been working and the script unloads (cleanup is called), **When** cleanup runs, **Then** the current state is written to a reserved auto-save file
2. **Given** an auto-save file exists from a previous session, **When** the script initializes, **Then** the system offers to restore from auto-save (via a param toggle or automatic restore)
3. **Given** the auto-save file is corrupt, **When** the script initializes, **Then** the system ignores it, logs a warning, and starts with default state

---

### Edge Cases

- What happens when the disk is full and a save is attempted? The system catches the I/O error, displays a message to the musician, and leaves any existing preset file intact (no partial writes).
- What happens when loading a preset saved with a different number of tracks (e.g., future version adds tracks)? The system loads tracks that exist in both the file and the current configuration. Missing tracks get defaults; extra tracks in the file are ignored. A warning is shown.
- What happens when loading a preset from an older version that lacks fields added in a newer version (e.g., no glide or ratchet data)? Missing fields are filled with defaults. The system includes a version marker in the preset file to guide migration.
- What happens when a preset file is manually edited and contains invalid data (e.g., step value of 99 where max is 7)? The system validates values on load and clamps out-of-range values to valid bounds.
- What happens when two presets have names that differ only in case ("My-Jam" vs "my-jam")? On case-insensitive filesystems (macOS), this is the same file. The system normalizes preset names to lowercase with hyphens to avoid collisions.
- What happens when a preset name contains special characters or spaces? The system sanitizes preset names for filesystem safety, replacing or rejecting characters that are not alphanumeric, hyphens, or underscores.
- What happens if the musician loads a preset while the meta-sequence chain is playing? Playback stops, state is replaced, chain is reset to slot 1.
- What happens if auto-save runs but there is nothing to save (freshly initialized, no changes)? The auto-save still writes (it is a snapshot of current state, even if default).

## Requirements

### Functional Requirements

- **FR-001**: System MUST serialize the complete sequencer state as Lua tables using `tab.save` (norns) or a custom Lua table serializer (seamstress). The system MUST NOT use JSON.
- **FR-002**: System MUST support saving to and loading from multiple named preset files in the data directory (`~/dust/data/re_kriate/presets/` on norns, or equivalent seamstress path)
- **FR-003**: The serialized state MUST include: all track step data (all 8 params x 16 steps x 4 tracks), loop boundaries (start/end/pos) for every param, per-track settings (division, direction, swing, muted), all 16 pattern slots, meta-sequence chain state, scale settings (root note, scale type), and a version marker
- **FR-004**: System MUST validate preset data on load, clamping out-of-range values to valid bounds and supplying defaults for missing fields
- **FR-005**: System MUST handle I/O errors gracefully — failed saves leave existing files intact, failed loads leave current state unchanged, and the musician sees a clear error message
- **FR-006**: System MUST normalize preset names to filesystem-safe strings (lowercase, alphanumeric, hyphens, underscores only)
- **FR-007**: System MUST provide a `lib/preset.lua` module that exposes `save(ctx, name)`, `load(ctx, name)`, `list()`, and `delete(name)` functions, following the project's module pattern
- **FR-008**: System MUST include a version marker in every preset file to support future migration when the state schema changes
- **FR-009**: System MUST auto-save to a reserved file name (e.g., `_autosave`) during cleanup, and offer restoration on next init
- **FR-010**: System MUST stop playback before loading a preset to prevent race conditions with the clock coroutines
- **FR-011**: System MUST support forward-compatible loading — presets saved with fewer params (e.g., before ratchet/glide existed) load successfully with defaults for missing params
- **FR-012**: Storage format decision: Lua table serialization via `tab.save`/`tab.load` is the primary approach. SQLite is [NEEDS CLARIFICATION: does SQLite add meaningful value over flat Lua files for this use case? Considerations: query capability for preset metadata, atomic writes, concurrent access. Flat Lua files are simpler and sufficient for single-user preset management. SQLite would add a dependency.]

### Key Entities

- **Preset File**: A file on disk containing the serialized sequencer state as a Lua table. Named by the musician (sanitized), stored in the data directory. Contains a version marker, timestamp, and the full state snapshot.
- **Serialized State**: The complete in-memory state flattened into a Lua table suitable for `tab.save`. Includes: `tracks` (4 tracks, each with 8 params, each param with 16 steps + loop boundaries), `patterns` (16 slots), `meta_sequence` (chain slots, loop mode), `scale` (root note, scale type index), `per_track_settings` (division, direction, swing, muted per track), and `version`.
- **Preset Metadata**: Lightweight info about a preset — name, file path, save timestamp, version marker. Used by the browser to list presets without loading the full state.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A musician can save and load a preset in under 5 seconds each (wall-clock time including UI interaction)
- **SC-002**: A preset round-trips perfectly — saving state, loading it back, and comparing yields identical track data, patterns, loop boundaries, and settings (verified by automated tests)
- **SC-003**: Loading a preset from an older version (missing fields) succeeds without errors and fills defaults for 100% of missing fields
- **SC-004**: The system handles corrupt preset files without crashing — 100% of I/O and parse errors are caught and reported to the musician
- **SC-005**: Auto-save on exit and restore on init works reliably — a musician who does nothing special gets their last session back

## Assumptions

- Storage format: Lua tables via `tab.save`/`tab.load` (norns) or custom serializer (seamstress). SQLite is [NEEDS CLARIFICATION] for whether it adds value over simple Lua files for single-user preset management.
- Presets stored in `~/dust/data/re_kriate/presets/` (norns convention) or equivalent seamstress path (e.g., `~/.local/share/re_kriate/presets/`)
- State includes: tracks (step data, loop boundaries, positions), patterns (16 slots), meta-sequence chain, scale (root note, scale type), per-track settings (division, direction, swing, muted), and tempo/clock settings if managed by the script
- `lib/pattern.lua` already provides `deep_copy` for in-memory pattern slots — the preset module can reuse or parallel this approach for serialization
- The norns `tab` library handles nested Lua tables (it does, using `tab.save` which writes `return { ... }` Lua source)
- Preset names are chosen by the musician (not auto-generated numeric slots) to be human-meaningful
- The auto-save file uses a reserved name (e.g., `_autosave`) that is excluded from the normal preset browser list
- Tempo (BPM) is a norns global param, not managed by re.kriate directly — it may or may not be included in the preset. This should be decided during planning.
