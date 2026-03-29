# Feature Specification: Pattern Persistence to Disk (Checksum-guarded)

**Feature Branch**: `013-pattern-persistence`
**Created**: 2026-03-26
**Status**: Draft
**Input**: "Pattern persistence: save/load patterns to disk (norns + seamstress) with round-trip tests and checksum guard."

## User Scenarios & Testing

### User Story 1 — Save Pattern Bank to Disk (P1)
As a performer, I want to save all 16 pattern slots (including track params and loop bounds) to a named file so I can reload the bank across sessions or devices.

**Independent Test**: Populate distinctive step/loop data across tracks, call `pattern_persistence.save(ctx, "my-bank")`, assert a file appears in the data dir with checksum metadata.

**Acceptance**
1. Given patterns exist in memory, when saving to name "my-bank", then a file `my-bank.krp` is written under the platform data dir.
2. Given the data dir is missing, save creates it before writing.
3. Given a file with the same name exists, save overwrites atomically (write-temp + rename) so partial files are avoided.
4. After save, the file contains a checksum over the serialized payload.
5. Saving a bank must not rewrite or repurpose any in-memory pattern slot just to capture the current live tracks.
6. If save fails at any filesystem step, the in-memory bank remains unchanged.

### User Story 2 — Load Pattern Bank from Disk (P1)
As a performer, I want to load a saved pattern bank so the exact pattern slots restore, preserving steps, loop bounds, division, direction, muted flags, and param positions.

**Independent Test**: Save a bank, mutate ctx to defaults, load the bank, assert ctx.patterns and ctx.tracks match the saved state.

**Acceptance**
1. Given `my-bank.krp` exists, when load is called, then all 16 slots and their track data are restored into ctx (and pattern populated flags set).
2. If checksum validation fails, load aborts, returns error, and leaves current ctx untouched.
3. If the file is missing, load returns a not-found error without changing ctx.
4. If a slot in the file is empty, it remains unpopulated after load (no bogus defaults).
5. Load restores the exact saved slot contents; slot 1 is not treated as a hidden scratch slot for current-state restore.

### User Story 3 — Detect Corruption via Checksum (P1)
As a performer, I want corrupted pattern files to be rejected so I don’t unknowingly load broken data mid-set.

**Independent Test**: Save a bank, intentionally flip a byte in the file, then load and expect a checksum failure and unchanged ctx.

**Acceptance**
1. Checksum is stored alongside payload metadata; load recomputes and compares.
2. On mismatch, load returns an error code/message and leaves ctx unchanged.
3. A log or on-screen message is shown indicating corruption.

### User Story 4 — Platform Paths & Naming (P2)
As a developer, I want consistent, platform-correct storage paths and filename sanitization so persistence works on both norns and seamstress.

**Independent Test**: On norns, save writes to `~/dust/data/re_kriate/patterns/`; on seamstress, to `path.seamstress .. "/data/re_kriate/patterns/"` (or XDG fallback). Filenames are sanitized (lowercase, alnum, hyphen/underscore).

**Acceptance**
1. Uses platform detection to choose data dir; creates it if missing.
2. Filename sanitizer strips/normalizes disallowed chars; rejects empty names.
3. Reserved names (e.g., `_checksum`) are disallowed.

### User Story 5 — Round-trip Fidelity (P1)
As a tester, I want automated busted specs that prove save→load round-trips all pattern data (including extended params: ratchet, alt_note, glide) without loss.

**Independent Test**: A spec writes a populated ctx to disk, reloads into a fresh ctx, and deep-compares tracks/params/loop bounds/populated flags.

**Acceptance**
1. New specs cover: full round-trip, checksum failure path, invalid name sanitization, missing dir creation, empty slots preserved.
2. Tests run under seamstress test runtime and do not require norns hardware.

## Requirements

### Functional
- **FR-001**: Provide `lib/pattern_persistence.lua` exposing `save(ctx, name)`, `load(ctx, name)`, `list()`, `delete(name)`; no globals, return table.
- **FR-002**: Serialize pattern bank (16 slots) using Lua tables; include metadata `{version, timestamp, checksum, slots=[...]}`; use `tab.save`/`tab.load` on norns and the seamstress equivalent (custom serializer if needed).
- **FR-003**: Save must be atomic: write to temp file, fsync if available, then rename to target.
- **FR-004**: Load must validate checksum before mutating ctx; on failure, return error and leave ctx unchanged.
- **FR-005**: Sanitization: names lowercased, only `[a-z0-9_-]`; reject empty/invalid names; append `.krp` extension.
- **FR-006**: Data dir: norns → `~/dust/data/re_kriate/patterns/`; seamstress → `path.seamstress .. "/data/re_kriate/patterns/"` with fallback to XDG data dir if `path` missing.
- **FR-007**: On load, set `ctx.patterns[slot].populated` correctly and deep-copy into `ctx.tracks` on success; untouched on failure.
- **FR-007a**: Bank save/load must preserve user-authored slot contents exactly; implementation must not overwrite `ctx.patterns[1]` or any other slot as an implementation detail.
- **FR-007b**: If the current live track state needs separate restoration metadata, store it outside the 16 visible pattern slots.
- **FR-008**: Provide lightweight checksum (pure-Lua CRC32 or xxhash) to avoid platform deps; stored in metadata.
- **FR-009**: `list()` returns sanitized names sorted, ignoring temp files; `delete(name)` removes the file safely.
- **FR-010**: Logging/UI: return error messages suitable for screen_ui to show; no direct screen calls inside persistence module.

### Non-Functional
- **NF-001**: No platform-specific globals; choose path via detection; ctx stays the single state carrier.
- **NF-002**: Tests must clean up temporary files/directories they create.
- **NF-003**: Implementation must not change existing pattern in-memory behavior (save/load slots 1–16) or break existing tests.
- **NF-004**: Save failure paths must be side-effect free with respect to in-memory pattern-bank contents.

## Success Criteria
- SC-001: Busted specs added for round-trip fidelity, checksum failure, name sanitization, and missing-dir creation; all pass.
- SC-002: Manual save/load on seamstress shows identical pattern state before/after (visual check via existing pattern UI).
- SC-003: Corrupted file load is rejected with an error and no state change.
- SC-004: Works on both norns and seamstress without code edits (platform detection only).

## Open Questions / Assumptions
- Assume pure-Lua checksum implementation is acceptable (no OS `shasum` dependency).
- Assume extension `.krp` is acceptable for pattern banks; adjust if repo convention prefers another suffix.
- Assume path fallback for seamstress is `os.getenv("XDG_DATA_HOME") .. "/re_kriate/patterns"` when `path.seamstress` missing.
- Dev/test override allowed: `REKRIATE_PATTERN_DIR` env or test hook can redirect the data path in non-norns environments.
- Auto-save of patterns is out-of-scope (handled by higher-level preset work); this spec focuses on explicit save/load of pattern banks.
