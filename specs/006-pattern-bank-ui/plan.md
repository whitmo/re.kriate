# Implementation Plan: Pattern Bank Visual Feedback

**Branch**: `006-pattern-bank-ui` | **Date**: 2026-03-25 | **Spec**: `specs/006-pattern-bank-ui/spec.md`
**Input**: Feature specification from `specs/006-pattern-bank-ui/spec.md`

## Summary

Add pattern bank visual feedback to the seamstress screen_ui: a row of 9 slot indicators (empty/populated/active states), active pattern tracking on save/load, and transient confirmation messages with auto-clear. All changes confined to `lib/seamstress/screen_ui.lua` and `lib/seamstress/keyboard.lua` — no modifications to shared or norns modules.

## Technical Context

**Language/Version**: Lua 5.4 (busted test runner), seamstress v1.4.7 runtime
**Primary Dependencies**: seamstress v1.4.7, busted (test framework)
**Storage**: N/A (in-memory patterns via lib/pattern.lua, no persistence layer)
**Testing**: busted (`busted specs/`)
**Target Platform**: seamstress (macOS/Linux desktop)
**Project Type**: Sequencer script (seamstress platform)
**Performance Goals**: Screen redraw at 15-30 fps (seamstress default metro)
**Constraints**: All visual changes seamstress-only; no changes to re_kriate.lua, lib/app.lua, or lib/pattern.lua
**Scale/Scope**: 2 files modified, ~40-60 lines added, 10+ new tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-Centric Architecture | PASS | Active pattern state (`ctx.active_pattern`) and transient message (`ctx.pattern_message`) live on ctx. No globals or module state. |
| II. Platform-Parity Behavior | PASS | Pattern bank UI is seamstress-only visual feedback — not shared sequencing behavior. FR-010/SC-005 explicitly require no norns/shared changes. No parity obligation. |
| III. Test-First Sequencing Correctness | PASS | This feature is UI feedback only — does not affect sequencing logic, direction, loop bounds, or timing. TDD still applied per workflow. |
| IV. Deterministic Timing and Safe Degradation | PASS | Transient message uses `os.clock()` timestamps for expiry — deterministic, no scheduling dependency. Graceful degradation: nil ctx.patterns renders all-empty. |
| V. Spec-Driven Delivery | PASS | Full speckit pipeline: spec.md complete, plan.md (this file), tasks.md next. |

No violations. Complexity tracking not needed.

## Project Structure

### Documentation (this feature)

```text
specs/006-pattern-bank-ui/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/          # Generated checklists
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── pattern.lua              # UNCHANGED — save/load/is_populated API
├── seamstress/
│   ├── screen_ui.lua        # MODIFIED — add slot indicators + transient message rendering
│   └── keyboard.lua         # MODIFIED — set ctx.active_pattern and ctx.pattern_message on save/load
└── ...

specs/
├── screen_ui_spec.lua       # EXISTING — extend with pattern bank UI tests
└── pattern_bank_ui_spec.lua # NEW — dedicated test file for visual feedback
```

**Structure Decision**: Minimal change — extend two existing seamstress modules. New test file for the feature, extend existing screen_ui_spec if needed.

## Design

### Phase 1: Active Pattern Tracking (keyboard.lua)

**Goal**: keyboard.lua sets `ctx.active_pattern` and `ctx.pattern_message` when save/load occurs.

**Changes to `lib/seamstress/keyboard.lua`**:
- After `pattern.save(ctx, slot)`: set `ctx.active_pattern = slot` and `ctx.pattern_message = {text = "saved " .. slot, time = os.clock()}`
- After `pattern.load(ctx, slot)`: only if slot is populated, set `ctx.active_pattern = slot` and `ctx.pattern_message = {text = "loaded " .. slot, time = os.clock()}`
- Loading an empty slot: no change to active_pattern, no message (FR-005)

**Key decision**: `os.clock()` for timestamps — available in both seamstress and test environments, monotonic, no external dependency.

### Phase 2: Slot Indicator Row (screen_ui.lua)

**Goal**: Render 9 slot indicators showing empty/populated/active states.

**Changes to `lib/seamstress/screen_ui.lua`**:
- Add a `draw_pattern_slots(ctx)` local function called from `M.redraw(ctx)`
- Position: below track step positions (y ~125, near bottom of 128px screen)
- 9 indicators in a horizontal row, each a small rectangle or circle
- Three visual states:
  - **Empty**: dim color (e.g., 40, 40, 60)
  - **Populated**: medium color (e.g., 100, 100, 140)
  - **Active**: bright highlight (e.g., 200, 200, 255)
- Defensive: if `ctx.patterns` is nil, render all as empty

### Phase 3: Transient Message Display (screen_ui.lua)

**Goal**: Show temporary "saved N" / "loaded N" confirmation that auto-clears.

**Changes to `lib/seamstress/screen_ui.lua`**:
- Add transient message rendering in `M.redraw(ctx)`:
  - Check `ctx.pattern_message` exists
  - Check if `os.clock() - ctx.pattern_message.time < 1.5`
  - If valid: render message text near the slot indicators
  - If expired: clear `ctx.pattern_message = nil`
- Message replacement: handled naturally — keyboard.lua overwrites ctx.pattern_message on each action (FR-009)

## Complexity Tracking

No constitution violations. No complexity justifications needed.
