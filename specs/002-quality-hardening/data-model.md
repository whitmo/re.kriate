# Data Model: Quality Hardening

**Feature**: 002-quality-hardening
**Date**: 2026-03-24

## No Data Model Changes

This is a test-only feature. No new entities, fields, relationships, or state transitions are introduced. All tests operate on the existing data model defined in `specs/001-seamstress-kria-features/data-model.md`.

### Entities Under Test (existing, unchanged)

| Entity | Module | Key Fields Tested |
|--------|--------|-------------------|
| param | lib/track.lua | steps[], loop_start, loop_end, pos |
| track | lib/track.lua | params{}, direction, muted, division |
| pattern_slot | lib/pattern.lua | tracks (deep copy), populated |
| scale_notes | lib/scale.lua | array of MIDI note numbers |
| voice (MIDI) | lib/voices/midi.lua | active_notes{}, pending_noteoffs{} |
| ctx | lib/app.lua | tracks[], playing, scale_notes, clock_ids |

### State Transitions Under Test (existing, unchanged)

- `track.advance()`: pos wraps within [loop_start, loop_end]
- `sequencer.start()/stop()`: ctx.playing toggles, clock_ids managed
- `pattern.save()/load()`: slot populated flag, deep copy semantics
- `direction.advance()`: pos movement per mode + advancing_forward flag
- `voice.play_note()`: active_notes tracking, note-off scheduling
