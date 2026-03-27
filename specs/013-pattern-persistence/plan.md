# Implementation Plan: Pattern Persistence (Disk + Checksum)

**Branch**: `whitmo/pattern-persistence` | **Date**: 2026-03-26 | **Spec**: `specs/013-pattern-persistence/spec.md`

## Summary
Add disk persistence for the 16-slot pattern bank (tracks + loop bounds) on both seamstress and norns. Provide a dedicated `lib/pattern_persistence.lua` with atomic save/load, checksum validation, name sanitization, and simple list/delete helpers. Deliver busted coverage for round-trip fidelity and corruption rejection. UI wiring kept minimal: expose callable API; UI/param hooks can be added after module lands.

## Technical Context
- **Language/Runtime**: Lua 5.4 (busted), seamstress v1.4.7; norns runtime (Lua 5.3) for live use
- **State pattern**: ctx carries tracks + patterns; no new globals
- **Storage**: Flat Lua table files via `tab.save/tab.load` (norns) and custom serializer on seamstress if `tab` absent
- **Data dir**: norns `~/dust/data/re_kriate/patterns/`; seamstress `path.seamstress .. "/data/re_kriate/patterns/"` with XDG fallback
- **Checksum**: pure-Lua CRC32/xxhash to avoid OS deps
- **Tests**: busted (no hardware), temp dirs under `specs/tmp` or `os.tmpname()`; clean up each test

## Constitution Check
| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-Centric | PASS | Persistence API takes ctx; no globals or module state. |
| II. Platform Parity | PASS | Identical behavior on norns + seamstress; path selection handled internally. |
| III. Test-First | PASS | New specs precede implementation; checksum failure + round-trip tests required. |
| IV. Deterministic Timing | PASS | No timing-sensitive code beyond atomic file writes; uses pure Lua. |
| V. Spec-Driven Delivery | PASS | Spec is authored; plan/tasks follow. |

## Phases
### Phase 0 – Recon (done inline)
- Read `lib/pattern.lua`, `pattern_spec.lua`, dual-platform path research.

### Phase 1 – API Design & Stubs
- Create `lib/pattern_persistence.lua` skeleton: `save`, `load`, `list`, `delete`, `data_dir`, `sanitize_name`, `checksum`.
- Keep function signatures pure; no I/O side effects until tests drive.

### Phase 2 – Tests (write first)
- New busted file `specs/pattern_persistence_spec.lua`:
  - Round-trip: populate ctx → save → load into fresh ctx → deep compare patterns & tracks.
  - Checksum failure: flip byte / tamper checksum → expect error + unchanged ctx.
  - Missing dir: delete data dir, save creates it.
  - Name sanitization: invalid name rejected; sanitizer produces safe filename.
  - List/delete: create files, list sorted, delete removes file.
- Use temp dirs; stub platform detection to both seamstress/norns paths to avoid touching real user data.

### Phase 3 – Implementation
- Data dir detection + creation.
- Serializer: use `tab.save/tab.load` when available; else write `return <lua table>` string with pretty minimal formatting.
- Atomic write: write to `.<name>.tmp`, flush, rename to `<name>.krp`.
- Checksum: compute on serialized payload, store in metadata; validate on load before mutating ctx.
- Integrate with `ctx.patterns` population flags; deep copy to `ctx.tracks`.

### Phase 4 – Wiring & UX Hooks (light)
- Add minimal entry points for callers: e.g., expose from `lib/app.lua` as `app.save_patterns(ctx, name)` and `app.load_patterns(ctx, name)` or leave as module import; avoid UI until needed.
- Log-friendly error messages for screen_ui.

### Phase 5 – Verify
- Run `busted --no-auto-insulate specs/pattern_persistence_spec.lua`.
- Spot-check data dir after test cleanup (empty).
- Re-run full suite if time.

## Risks / Mitigations
- **Path differences**: cover with tests mocking both platforms.
- **Checksum perf**: CRC32 is fast; pattern files small; acceptable.
- **Atomicity on norns**: `os.rename` is atomic on same filesystem; ensure temp file created in same dir.
- **Schema drift**: version field in file; loader fills missing fields with defaults.

## Deliverables
- `lib/pattern_persistence.lua`
- `specs/pattern_persistence_spec.lua`
- Updated feature queue already marked in-progress
