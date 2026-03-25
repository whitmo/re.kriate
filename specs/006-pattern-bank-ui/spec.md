# Feature Specification: Pattern Bank Visual Feedback

**Feature Branch**: `006-pattern-bank-ui`
**Created**: 2026-03-25
**Status**: Draft
**Input**: Add pattern bank visual feedback to screen_ui showing active/populated pattern slots and transient save/load confirmation

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Active Pattern Indicator (Priority: P1)

As a performer, I want to see which pattern slot is currently active on screen so I can keep track of where I am during a live set without guessing.

**Why this priority**: Knowing which pattern you're on is essential context for performance — without it, saving/loading patterns is a blind operation.

**Independent Test**: Can be tested by loading a pattern and verifying the screen shows the correct slot number as active.

**Acceptance Scenarios**:

1. **Given** no pattern has been loaded or saved, **When** the screen renders, **Then** no pattern slot is highlighted as active (default state shows no active pattern).
2. **Given** the user saves to pattern slot 3 (ctrl+3), **When** the screen renders, **Then** slot 3 is visually indicated as the active pattern.
3. **Given** the user loads pattern slot 5 (shift+5), **When** the screen renders, **Then** slot 5 is visually indicated as the active pattern.
4. **Given** slot 3 is active, **When** the user saves to slot 7, **Then** the active indicator moves from slot 3 to slot 7.

---

### User Story 2 - Populated Slot Indicators (Priority: P1)

As a performer, I want to see at a glance which pattern slots have saved data so I know which slots are available to load and which are empty.

**Why this priority**: Equally critical to active slot — loading an empty slot is a no-op that wastes performance time. Seeing populated vs empty slots enables confident pattern switching.

**Independent Test**: Can be tested by saving patterns to specific slots and verifying the screen distinguishes populated from empty slots.

**Acceptance Scenarios**:

1. **Given** all pattern slots are empty, **When** the screen renders, **Then** all 9 slot indicators appear in the empty/dim state.
2. **Given** the user saves to slots 1, 3, and 5, **When** the screen renders, **Then** slots 1, 3, and 5 appear visually distinct from empty slots 2, 4, 6-9.
3. **Given** slot 3 is populated, **When** the user saves new data to slot 3 (overwrite), **Then** slot 3 remains shown as populated.

---

### User Story 3 - Transient Save/Load Feedback (Priority: P2)

As a performer, I want brief on-screen confirmation when I save or load a pattern so I have confidence the action succeeded, especially in high-pressure live situations.

**Why this priority**: Nice-to-have but not blocking — the slot indicators (US1+US2) already show state. Transient feedback adds confirmation and reduces uncertainty.

**Independent Test**: Can be tested by triggering a save/load action and verifying a temporary message appears on screen, then disappears after a short duration.

**Acceptance Scenarios**:

1. **Given** the user presses ctrl+3 to save, **When** the screen renders, **Then** a brief confirmation message (e.g., "saved 3") appears on screen.
2. **Given** the user presses shift+5 to load a populated slot, **When** the screen renders, **Then** a brief confirmation message (e.g., "loaded 5") appears on screen.
3. **Given** a confirmation message is showing, **When** approximately 1.5 seconds have elapsed, **Then** the message is no longer visible.
4. **Given** a "saved 3" message is showing, **When** the user immediately loads slot 1, **Then** the message updates to "loaded 1" and the timer resets.

---

### User Story 4 - Seamstress-Only Scope (Priority: P1)

As a developer, I want pattern bank visual feedback to be confined to the seamstress platform so the norns entrypoint remains unaffected and the shared app module stays platform-agnostic.

**Why this priority**: Architectural integrity — the screen_ui module is seamstress-only and pattern visual feedback should not leak into shared code or the norns platform.

**Independent Test**: Can be tested by verifying no changes to re_kriate.lua (norns entrypoint) or lib/app.lua, and that all new visual code lives in lib/seamstress/ modules.

**Acceptance Scenarios**:

1. **Given** the pattern bank UI feature is complete, **When** inspecting re_kriate.lua, **Then** it contains no pattern indicator or transient feedback code.
2. **Given** the pattern bank UI feature is complete, **When** inspecting lib/app.lua, **Then** it contains no screen rendering or pattern UI logic.
3. **Given** the pattern bank UI feature is complete, **When** running the full test suite, **Then** all existing 555+ tests continue to pass.

---

### Edge Cases

- What happens when the user loads an empty slot? The active pattern indicator should NOT change (load is a no-op for empty slots), and no confirmation message appears.
- What happens when the user saves to slot 9 (highest keyboard-accessible slot)? Works identically to slots 1-8 — slot 9 is the upper bound of keyboard-accessible slots.
- What happens when the user rapidly saves/loads multiple slots within 1.5 seconds? Each action replaces the previous confirmation message and resets the fade timer.
- What happens on first launch before any save/load? No active pattern indicator is shown — the slot row shows all empty/dim slots.
- What happens if ctx.patterns is nil (defensive)? The slot indicator row renders all slots as empty without error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The screen display MUST show a row of 9 pattern slot indicators (slots 1-9, matching keyboard-accessible range).
- **FR-002**: Each slot indicator MUST visually distinguish between three states: empty (no saved data), populated (has saved data), and active (most recently saved-to or loaded-from).
- **FR-003**: The active pattern slot MUST update when the user saves a pattern (the saved-to slot becomes active).
- **FR-004**: The active pattern slot MUST update when the user loads a populated pattern (the loaded-from slot becomes active).
- **FR-005**: Loading an empty pattern slot MUST NOT change the active pattern indicator (because the load is a no-op).
- **FR-006**: The screen display MUST show a transient confirmation message when a pattern is saved, indicating the action and slot number.
- **FR-007**: The screen display MUST show a transient confirmation message when a pattern is loaded from a populated slot.
- **FR-008**: Transient confirmation messages MUST automatically disappear after approximately 1.5 seconds.
- **FR-009**: A new save/load action while a confirmation message is visible MUST replace the message and reset the timer.
- **FR-010**: All pattern bank visual feedback MUST be confined to seamstress-specific modules — no changes to the norns entrypoint, shared app module, or pattern storage module.

### Key Entities

- **Active Pattern State**: Tracks which pattern slot (1-9 or none) was most recently saved-to or loaded-from. Lives on the context object. Defaults to none on startup.
- **Transient Message**: A temporary text notification with an action label ("saved"/"loaded"), a slot number, and a creation timestamp for expiry calculation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The screen displays 9 pattern slot indicators that correctly reflect populated/empty/active state at all times.
- **SC-002**: Save and load actions produce visible confirmation feedback that auto-clears within 2 seconds.
- **SC-003**: At least 10 new tests cover pattern bank visual feedback (slot indicators, active tracking, transient messages, edge cases).
- **SC-004**: All 555+ existing tests continue to pass with zero regressions.
- **SC-005**: No modifications to re_kriate.lua (norns), lib/app.lua (shared), or lib/pattern.lua (storage) — visual feedback is seamstress-only.

## Assumptions

- The keyboard shortcuts (ctrl+1-9 save, shift+1-9 load) already exist in lib/seamstress/keyboard.lua and are tested. This feature adds visual feedback only.
- The pattern module (lib/pattern.lua) API — save, load, is_populated, new_slots — is stable and requires no changes.
- Slots 10-16 exist in the pattern module but are not keyboard-accessible, so the UI shows only slots 1-9.
- The seamstress screen resolution is 256x128 pixels, providing adequate space for a compact slot indicator row.
- The transient message duration of ~1.5 seconds is a reasonable default for live performance feedback — short enough to not clutter, long enough to read.
