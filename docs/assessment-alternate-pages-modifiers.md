# Assessment: Alternate Pages & Modifier Keys

**Date**: 2026-03-27
**Scope**: Current state of extended/alternate parameter pages and modifier key behavior in re.kriate

---

## Current Pages (8 total)

### Core Pages (5) — All Functional
| # | Page | Nav Key | Rows | Description |
|---|------|---------|------|-------------|
| 1 | trigger | x=6 | 1-4 (all tracks) | Toggle steps on/off |
| 2 | note | x=7 | 1-7 (active track) | Scale degree selection |
| 3 | octave | x=8 | 1-7 | Octave offset (4 = center) |
| 4 | duration | x=9 | 1-7 | Beat fractions (1/16 to 4 beats) |
| 5 | velocity | x=10 | 1-7 | MIDI velocity (re.kriate extension, not in original kria) |

### Extended Pages (3) — All Functional
| # | Page | Access | Rows | Description |
|---|------|--------|------|-------------|
| 6 | ratchet | double-tap x=6 (trigger) | 1-7 | Subdivisions per step (1=normal, 2-7=repeats) |
| 7 | alt_note | double-tap x=7 (note) | 1-7 | Secondary note offset, additive with main note |
| 8 | glide | double-tap x=8 (octave) | 1-7 | Portamento time (0ms to 1.6s) |

Extended page toggle works by pressing the same nav button a second time. All three extended pages have full engine support in `sequencer.lua` (ratchet subdivides clock, alt_note combines additively with note degree, glide sets portamento via CC 65/5 for MIDI or voice:set_portamento for OSC).

### Pages Without Extended Variants
- **duration** (x=9): No extended page mapped
- **velocity** (x=10): No extended page mapped

---

## Modifier Keys

### Implemented
| Modifier | Position | Gesture | Description | Status |
|----------|----------|---------|-------------|--------|
| Loop | x=12, y=8 | Hold + tap start/end | Edit per-parameter loop start/end | Functional (moved from original x=11) |
| Pattern | x=14, y=8 | Hold | Enter pattern slot selection overlay | Functional |
| Mute | x=5, y=8 | Tap | Toggle active track mute | Functional (differs from original kria's hold-loop+track-press gesture) |

### Not Implemented (present in original kria)
| Modifier | Original Position | Description | Plan Status |
|----------|-------------------|-------------|-------------|
| Time/Division | x=12 (original) | Per-parameter clock division (1-16) | No spec |
| Probability | x=13 (original) | Per-step trigger probability (0-100%) | Spec 011 drafted |
| Config (Key 2 hold) | Hardware key | Note sync, loop sync, duration tie, brightness | No spec |

---

## Navigation Row Layout Comparison

```
Original Kria:
 1-4:Track  5:gap  6:Trig  7:Note  8:Oct  9:Dur  10:-  11:Loop  12:Time  13:Prob  14:-  15:Scale  16:Pattern

re.kriate:
 1-4:Track  5:Mute  6:Trig  7:Note  8:Oct  9:Dur  10:Vel  11:-  12:Loop  13:-  14:Pat  15:-  16:Play/Stop
```

Key differences:
- x=5 repurposed for mute toggle (original had gap)
- x=10 added for velocity (re.kriate extension)
- x=12 is loop modifier (moved from original x=11)
- x=16 is play/stop (original used for pattern/cue)
- Time modifier (original x=12), probability modifier (original x=13), scale page (original x=15) all absent

---

## Missing Features from Original Kria

### High Impact (core kria behaviors)
1. **Per-parameter clock division** — In original kria, each parameter (trigger, note, octave, etc.) can have its own clock divider. re.kriate only supports per-track division via params menu.
2. **Trigger clocking mode** — Parameters advance only when trigger fires, not every clock tick. Not implemented.
3. **Direction modes** — Only forward implemented. Missing: reverse, pendulum/bounce, drunk (random walk), random. `lib/direction.lua` exists with structure but limited implementation.
4. **Scale editor page** — Grid-based interval editor for custom scales; currently scales only accessible via params menu.

### Medium Impact
5. **Config page** — Note sync (linked note/trigger editing), loop sync modes (None/Track/All), duration tie mode. Not implemented.
6. **Pattern meta-sequencer** — Sequence of patterns with timing. Pattern API exists in `lib/pattern.lua` but no grid-based pattern sequencing UI.

### Planned (specs exist)
7. **Trigger probability** (spec 011) — Draft spec. Would replace ratchet as trigger's extended page, which raises the question of where ratchet goes.
8. **Preset persistence** (spec 012) — Draft spec for save/load to disk.
9. **Clock sync** (spec 010) — Draft spec for MIDI clock slave/master.

---

## Open Design Questions

1. **Ratchet displacement**: Spec 011 proposes probability as trigger's extended page, displacing ratchet. Where does ratchet move? Options: standalone page nav key, 3rd-level toggle, duration's extended page.
2. **Duration/velocity extended pages**: These two core pages have no extended variants. Candidates: gate length modifier, swing/humanize, accent.
3. **Navigation row density**: 6 of 16 columns are currently unused (x=11, 13, 15 and effectively). Room exists for time modifier, scale page, and others without crowding.
4. **Modifier key model**: re.kriate uses hold-to-modify for loop and pattern. Original kria also uses this model for time and probability. Should these follow the same pattern?

---

## File References

| File | Role |
|------|------|
| `lib/grid_ui.lua:13-18` | Page definitions, EXTENDED_PAGES map |
| `lib/track.lua:8-10` | PARAMS and per-step data structures |
| `lib/sequencer.lua:143-173` | Ratchet, alt_note, glide engine logic |
| `lib/direction.lua` | Direction mode framework (partial) |
| `specs/grid_ui_spec.lua:1195-1281` | Extended page toggle tests |
| `specs/001-seamstress-kria-features/spec.md` | Comprehensive feature spec |
| `specs/011-trigger-probability/spec.md` | Probability feature (planned) |
