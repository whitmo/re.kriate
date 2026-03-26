# Quickstart: Pattern Bank Visual Feedback

**Feature**: 006-pattern-bank-ui | **Date**: 2026-03-25

## Run Tests

```bash
busted specs/
```

Expected: 555+ passing (all existing + new pattern bank UI tests), 0 failures.

## Run Seamstress

```bash
/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua
```

## Manual Verification

1. **Slot indicators visible**: Bottom of screen shows 9 small rectangles, all dim (empty).
2. **Save pattern**: Press `ctrl+3` — slot 3 lights up as active, "saved 3" message appears briefly.
3. **Populated indicator**: Press `ctrl+5` — slots 3 and 5 now show as populated, slot 5 is active.
4. **Load pattern**: Press `shift+3` — slot 3 becomes active, "loaded 3" message appears.
5. **Empty load ignored**: Press `shift+9` (empty) — nothing changes, no message.
6. **Message auto-clear**: Wait ~1.5 seconds — confirmation message disappears.
7. **Rapid actions**: Press `ctrl+1` then immediately `ctrl+2` — message updates to "saved 2".

## Key Files

| File | Role |
|------|------|
| `lib/seamstress/screen_ui.lua` | Renders slot indicators + transient messages |
| `lib/seamstress/keyboard.lua` | Sets ctx.active_pattern + ctx.pattern_message on save/load |
| `lib/pattern.lua` | UNCHANGED — save/load/is_populated API |
| `specs/pattern_bank_ui_spec.lua` | New test file for this feature |
