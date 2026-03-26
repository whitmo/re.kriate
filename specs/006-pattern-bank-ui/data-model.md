# Data Model: Pattern Bank Visual Feedback

**Feature**: 006-pattern-bank-ui | **Date**: 2026-03-25

## Entities

### Active Pattern State

**Location**: `ctx.active_pattern`
**Type**: `integer (1-9) | nil`
**Default**: `nil` (no pattern active on startup)

| Field | Type | Description |
|-------|------|-------------|
| ctx.active_pattern | int or nil | Most recently saved-to or loaded-from slot number. nil = none. |

**State transitions**:
- `nil → N`: First save or load of a populated slot
- `N → M`: Save to slot M, or load populated slot M
- `N → N`: Save to same slot (overwrite), or load same slot again
- No transition on loading empty slot (FR-005)

### Transient Message

**Location**: `ctx.pattern_message`
**Type**: `{text: string, time: number} | nil`
**Default**: `nil` (no message on startup)

| Field | Type | Description |
|-------|------|-------------|
| text | string | Display text, e.g. "saved 3" or "loaded 5" |
| time | number | `os.clock()` timestamp when message was created |

**State transitions**:
- `nil → {text, time}`: Save or load action
- `{text, time} → {text2, time2}`: New action replaces previous message (FR-009)
- `{text, time} → nil`: Expiry after ~1.5 seconds (cleared during redraw)

**Expiry logic**: In `screen_ui.redraw()`, if `os.clock() - ctx.pattern_message.time >= 1.5`, set `ctx.pattern_message = nil`.

## Existing Entities (Unchanged)

### Pattern Slots

**Location**: `ctx.patterns` (created by `pattern.new_slots()`)
**Type**: Array of 16 tables, each `{populated: boolean, tracks: table|nil}`
**Usage**: `pattern.is_populated(ctx.patterns, slot_num)` — read-only from screen_ui perspective

No changes to pattern slot structure. screen_ui reads `ctx.patterns[i].populated` for slot indicator state.

## Schema Impact

Two new fields on `ctx`:
- `ctx.active_pattern` — set by keyboard.lua on save/load
- `ctx.pattern_message` — set by keyboard.lua on save/load, cleared by screen_ui.lua on expiry

No changes to existing ctx fields. No changes to pattern.lua data structures.
