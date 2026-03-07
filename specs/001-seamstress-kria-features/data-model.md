# Data Model: Complete Seamstress Kria Sequencer

**Branch**: `001-seamstress-kria-features` | **Date**: 2026-03-06

## Entities

### Track

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| params | table<string, Param> | see below | Parameter pages keyed by name |
| division | number (1-7) | 1 | Clock division index into DIVISION_MAP |
| muted | boolean | false | Track mute state |
| direction | string | "forward" | Playback direction: forward/reverse/pendulum/drunk/random |

**Param names (core)**: trigger, note, octave, duration, velocity
**Param names (extended)**: ratchet, alt_note, glide

Tracks are created via `track.new_track(track_num)` and stored in `ctx.tracks[1..4]`.

### Param

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| steps | number[16] | varies | Step values (trigger: 0/1, others: 1-7) |
| loop_start | number | 1 | Loop start position (1-16) |
| loop_end | number | 16 | Loop end position (1-16) |
| pos | number | 1 | Current playhead position |
| advancing_forward | boolean | true | Pendulum direction state (only used with pendulum mode) |

### Voice (interface)

| Method | Args | Description |
|--------|------|-------------|
| play_note | (note, velocity, duration) | Fire a note with scheduled note-off |
| note_on | (note, velocity) | Send note-on |
| note_off | (note) | Send note-off |
| all_notes_off | () | Silence all (CC 123 for MIDI) |
| set_portamento | (time) | Set portamento time (CC 5) and enable (CC 65) |

Implementations: `voices/midi.lua`, `voices/recorder.lua`, `norns/nb_voice.lua`

### Scale

| Field | Type | Description |
|-------|------|-------------|
| scale_notes | number[] | Array of MIDI note numbers spanning multiple octaves |

Built via `scale.build_scale(root, scale_type)` using musicutil. Queried via `scale.to_midi(degree, octave, scale_notes)`.

### Pattern (new)

| Field | Type | Description |
|-------|------|-------------|
| tracks | table | Deep copy of all 4 tracks (params, division, muted, direction) |
| populated | boolean | Whether this slot has been written to |

Stored in `ctx.patterns[1..16]`. Operations: `pattern.save(ctx, slot)`, `pattern.load(ctx, slot)`.

## Context Table (ctx)

The ctx table is the single state container passed through the entire call chain.

| Field | Type | Description |
|-------|------|-------------|
| tracks | Track[4] | The 4 sequencer tracks |
| active_track | number (1-4) | Currently selected track |
| active_page | string | Current page name (trigger/note/octave/etc) |
| extended_page | boolean | Whether extended subpage is active |
| playing | boolean | Sequencer running state |
| loop_held | boolean | Loop modifier button state |
| loop_first_press | number/nil | First step pressed during loop edit |
| grid_dirty | boolean | Flag to trigger grid redraw |
| scale_notes | number[] | Current scale lookup table |
| voices | Voice[4] | Per-track voice output backends |
| patterns | Pattern[16] | Pattern storage slots |
| clock_ids | number[4]/nil | Active clock coroutine IDs |
| g | grid | Grid connection |
| grid_metro | metro | Grid redraw timer |

## State Transitions

### Sequencer Lifecycle
```
stopped -> playing (start: create clock coroutines per track)
playing -> stopped (stop: cancel clocks, all_notes_off)
playing/stopped -> reset (return all playheads to loop_start)
```

### Page Navigation
```
any_page -> page_pressed (if different page: switch, clear extended)
same_page -> extended_toggle (if page has extension: toggle extended flag)
  trigger <-> ratchet
  note <-> alt_note
  octave <-> glide
  duration (no extension)
  velocity (no extension)
```

### Direction Advance Logic
```
forward: pos + 1, wrap at loop_end -> loop_start
reverse: pos - 1, wrap at loop_start -> loop_end
pendulum: pos +/- 1, reverse direction at boundaries
drunk: pos + random(-1, 1), clamp to loop bounds
random: pos = random(loop_start, loop_end)
```

## Validation Rules

- Step values: trigger 0-1, all others 1-7
- Loop bounds: 1 <= loop_start <= loop_end <= 16
- Division: 1-7 (index into DIVISION_MAP)
- Track number: 1-4
- Direction: must be one of forward/reverse/pendulum/drunk/random
- Ratchet: 1-7 (1 = normal single note, 2-7 = subdivisions)
- Pattern slot: 1-16
