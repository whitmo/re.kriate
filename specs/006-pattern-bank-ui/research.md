# Research: Pattern Bank Visual Feedback

**Feature**: 006-pattern-bank-ui | **Date**: 2026-03-25

## Research Decisions

### R-001: Timestamp Source for Transient Messages

**Decision**: Use `os.clock()` for transient message expiry timing.
**Rationale**: Available in all Lua environments (seamstress, busted test runner). Monotonic CPU time — not affected by system clock changes. Simple arithmetic for expiry check.
**Alternatives considered**:
- `os.time()` — integer seconds, too coarse for 1.5s expiry
- `clock.get_beats()` — norns/seamstress clock API, adds unnecessary coupling to transport
- Injected timer function — over-engineered for a simple timestamp comparison

### R-002: State Location for Active Pattern

**Decision**: Store active pattern as `ctx.active_pattern` (integer 1-9 or nil).
**Rationale**: Follows context-centric architecture (Constitution I). Simple scalar on ctx — no new module or table needed. nil = no active pattern (startup default).
**Alternatives considered**:
- Separate UI state table — unnecessary indirection for a single field
- Module-level variable in screen_ui — violates Constitution I

### R-003: State Location for Transient Message

**Decision**: Store as `ctx.pattern_message = {text = string, time = number}` or nil.
**Rationale**: Two fields (display text + creation timestamp) naturally group as a small table on ctx. nil = no message. Expiry check is `os.clock() - msg.time < 1.5`.
**Alternatives considered**:
- Two separate ctx fields (ctx.msg_text, ctx.msg_time) — less cohesive
- Ring buffer of messages — over-engineered, spec says new message replaces old

### R-004: Slot Indicator Visual Design

**Decision**: 9 small filled rectangles in a horizontal row, using 3 color levels for empty/populated/active.
**Rationale**: Matches existing screen_ui style (solid color fills, no bitmap assets). Three distinct brightness levels are easily distinguishable on seamstress screen. Compact enough to fit below track info.
**Alternatives considered**:
- Numbered text labels — takes more horizontal space, harder to scan at a glance
- Circles — seamstress screen API uses `rect_fill`, no native circle primitive

### R-005: Where to Set Active Pattern State

**Decision**: Set `ctx.active_pattern` and `ctx.pattern_message` in keyboard.lua, immediately after the `pattern.save()`/`pattern.load()` calls.
**Rationale**: keyboard.lua already handles ctrl+N save and shift+N load. Adding 2-3 lines per branch is minimal. Keeps screen_ui.lua purely rendering (read-only on ctx). pattern.lua stays unchanged per FR-010/SC-005.
**Alternatives considered**:
- In pattern.lua itself — violates SC-005 (no changes to pattern.lua)
- In screen_ui.lua — screen module shouldn't manage action side-effects
- New callback/event system — massively over-engineered
