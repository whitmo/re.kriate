# Tasks: Pattern Persistence (Disk + Checksum)
**Branch**: `whitmo/pattern-persistence` | **Order**: test-first

Prereqs: `specs/013-pattern-persistence/spec.md`, `plan.md`

## Phase A — Tests First
- [x] Write busted test `specs/pattern_persistence_spec.lua` scaffold with helpers for temp dir, ctx factory.
- [x] Add round-trip test: populate ctx, save to temp dir, load into fresh ctx, deep-compare patterns/tracks/populated flags.
- [x] Add checksum failure test: tamper saved file or metadata, expect load error + unchanged ctx.
- [x] Add missing-dir creation test: remove temp dir, save succeeds and creates dir.
- [x] Add name sanitization test: invalid name rejected; sanitizer produces safe filename and extension.
- [x] Add list/delete tests: create multiple files, ensure `list()` sorted, `delete()` removes, list shrinks. (Also ignores temp/noise files; overwrite checksum change.)

## Phase B — Implementation
- [x] Implement `lib/pattern_persistence.lua` stubs: sanitize_name, data_dir detection (norns + seamstress + fallback), checksum (pure Lua), atomic write, safe load with checksum validation, list, delete.
- [x] Wire round-trip into ctx: on load success set populated flags and deep-copy into ctx.tracks; leave ctx untouched on error.
- [x] Provide clear error messages (strings) for UI/log consumers; do not call screen directly.

## Phase C — Verification
- [x] Run targeted tests: `busted --no-auto-insulate specs/pattern_persistence_spec.lua`.
- [ ] If time, run full suite: `busted --no-auto-insulate specs/`.
- [x] Document quick usage snippet in spec folder or README note if needed.
