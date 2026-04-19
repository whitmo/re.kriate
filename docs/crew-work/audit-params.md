# Params System Audit

Date: 2026-04-11

## Summary

The params system in `lib/app.lua` registers all user-facing parameters during
`M.init()`. This audit covers the worktree at HEAD on main.

---

## Complete Param Inventory

### Global (ungrouped)
| id | label | type | notes |
|----|-------|------|-------|
| `root_note` | root note | number 0-127 | formatter shows note name |
| `scale_type` | scale | option (14 scales + Custom) | rebuilds scale on change |

### Group: output (2 params)
| id | label | type |
|----|-------|------|
| `osc_host` | osc host | option (single value: 127.0.0.1) |
| `osc_port` | osc port | number 1-65535 |

### Group: track N (10 params each, x4 tracks)
| id | label | type | voice-specific? |
|----|-------|------|-----------------|
| `voice_{t}` | voice | option: midi/osc/sc_drums/softcut/sc_synth/none | -- |
| `midi_ch_{t}` | midi ch | number 1-16 | midi only |
| `sc_synthdef_{t}` | sc synthdef | option: sub/fm/wavetable | sc_synth only |
| `sample_path_{t}` | sample path | text | softcut only |
| `sample_root_{t}` | sample root | number 0-127 | softcut only |
| `sample_start_{t}` | sample start | number 0-350 | softcut only |
| `sample_end_{t}` | sample end | number 0-350 | softcut only |
| `sample_loop_{t}` | sample loop | option: off/on | softcut only |
| `division_{t}` | division | option: 1/16..1/1 | -- |
| `direction_{t}` | direction | option: forward/reverse/pendulum/drunk/random | -- |

### Per-track swing (ungrouped, 4 params)
| id | label | type |
|----|-------|------|
| `swing_{t}` | track N swing | number 0-100 |

### Group: clock sync (2 params)
| id | label | type |
|----|-------|------|
| `clock_source_mode` | clock source | option: internal/external MIDI |
| `clock_output` | clock output | option: off/on |

### Group: pattern persistence (5 params)
| id | label | type |
|----|-------|------|
| `pattern_bank_name` | bank name | text |
| `pattern_bank_save` | save bank | option (action trigger) |
| `pattern_bank_load` | load bank | option (action trigger) |
| `pattern_bank_list` | list banks | option (action trigger) |
| `pattern_bank_delete` | delete bank | option (action trigger) |

### Group: preset persistence (6 params)
| id | label | type |
|----|-------|------|
| `preset_name` | preset name | text |
| `preset_autosave` | autosave on exit | option: off/on |
| `preset_save` | save preset | option (action trigger) |
| `preset_load` | load preset | option (action trigger) |
| `preset_list` | list presets | option (action trigger) |
| `preset_delete` | delete preset | option (action trigger) |

### Group: grid (2 params)
| id | label | type |
|----|-------|------|
| `grid_provider` | grid provider | option: monome/midigrid/push2/launchpad pro/virtual |
| `grid_midi_device` | grid midi device | number 1-16 |

---

## Audit Findings

### 1. Softcut params shown for ALL voice types

**Status: YES -- still true.**

The five softcut params (`sample_path`, `sample_root`, `sample_start`,
`sample_end`, `sample_loop`) are registered unconditionally inside each
track group. They are always visible in the params menu regardless of the
selected voice type.

Their *actions* are gated (`rebuild_if_softcut` checks `VOICE_TYPES[voice_idx]
== "softcut"` before rebuilding), so changing them is harmless when another
voice is selected. But they clutter the menu: 5 irrelevant params per track
when the voice is midi, osc, sc_drums, or sc_synth.

Similarly, `midi_ch` is shown even when the voice is osc/softcut/etc., and
`sc_synthdef` is shown even for non-sc_synth voices.

**Recommendation:** Use param visibility toggling (hide/show via
`params:hide`/`params:show`) triggered by the `voice_{t}` action so only the
relevant subset is displayed. The seamstress params system supports this. If
the platform does not support dynamic visibility, consider documenting which
params apply to which voice.

### 2. Track voice and swing: per-track grouping

**Status: swing is NOT inside the per-track group.**

Each track has a `params:add_group("track_" .. t, ...)` with 10 params covering
voice, midi_ch, sc_synthdef, sample_*, division, and direction. But the swing
params are added in a separate loop *after* all track groups (lines 530-535),
as top-level ungrouped params with labels like "track 1 swing".

This means swing floats outside its track group in the menu. A user scrolling
through "track 1" group will not find swing there -- they have to scroll past
all four track groups to find the swing params.

**Recommendation:** Move swing into each track's group (bump group count from
10 to 11 and add `swing_{t}` inside the track loop).

### 3. Clock sync param

**Status: present and well-implemented.**

A "clock sync" group (2 params) provides `clock_source_mode` (internal vs
external MIDI) and `clock_output` (off/on). The implementation in
`lib/clock_sync.lua` is solid:

- Switching source while playing stops the sequencer first (FR-009 safety).
- On norns, the action calls `apply_platform_clock_source()` which sets the
  platform's own `clock_source` param to match, so there is no conflict.
- On seamstress (which has its own clock), the `clock_source` platform param
  simply does not exist (`params.lookup[sys_id]` is nil), so the platform
  call is a no-op. The re.kriate clock_sync module manages its own state.

**No conflict with seamstress's clock.** The module uses `clock.run`/
`clock.sync` like any well-behaved script; it does not override the global
clock source. External MIDI clock is decoded from raw MIDI bytes in
`attach_midi_input()` and routed into sequencer start/stop/reset -- the
platform clock runs independently.

### 4. Mixer params (level, pan per track)

**Status: NOT present in the params system.**

There are no per-track level or pan params. The softcut voice has internal
`level` and `pan` fields in its DEFAULTS table, but these are config-level,
not exposed as user-facing params.

For MIDI voices, volume/pan would be CC messages. For OSC/SC voices, level
could be sent as an OSC argument. None of this is currently parameterized.

**Recommendation:** Add a "mixer" group or per-track level/pan params. This
is a common expectation for multi-track sequencers. At minimum, per-track
level (0.0-1.0) and pan (-1.0 to 1.0) would be useful, with voice-type-
specific implementations (MIDI CC 7/10, OSC messages, softcut level/pan).

### 5. Orphaned/dead params

**Status: no orphaned params found, but minor dead code exists.**

- All registered params have active `set_action` callbacks and are referenced
  in `build_voice()` or elsewhere.
- `recorder.lua` exists in `lib/voices/` but is not referenced from `app.lua`
  or `sequencer.lua` and is not in `VOICE_TYPES`. It is dead voice code, not
  a dead param. Harmless but could be cleaned up.
- `sprite_voices` is assigned into `ctx` from config and is actively used in
  `sequencer.lua` and `sprite_render.lua` -- not orphaned.
- The `osc_host` param is an option with a single hardcoded value
  (`{"127.0.0.1"}`). This makes it un-editable by the user. It should be a
  text param or have more options if remote hosts are intended.

### 6. Menu organization

**Status: reasonable but has structural issues.**

Current layout as seen by the user:

```
--- re.kriate ---
root note
scale
> output (2)
> track 1 (10)       -- voice, midi_ch, sc_synthdef, sample_*, division, direction
> track 2 (10)
> track 3 (10)
> track 4 (10)
track 1 swing        -- orphaned outside group
track 2 swing
track 3 swing
track 4 swing
> clock sync (2)
> pattern persistence (5)
> preset persistence (6)
> grid (2)
```

**Issues:**
1. Swing params are stranded outside their track groups (see finding 2).
2. Voice-specific params (sample_*, midi_ch, sc_synthdef) are always shown
   regardless of selected voice, creating clutter (see finding 1).
3. No mixer section (see finding 4).
4. `osc_host` is a non-editable single-option dropdown.
5. Track groups have a generic count of 10 items that mix universal params
   (division, direction) with voice-specific ones (midi_ch, sample_path),
   making it hard for the user to know what matters for their current voice.

**What works well:**
- Clear group naming (track 1, track 2, etc.).
- Pattern and preset persistence are cleanly grouped.
- Clock sync is its own group, easy to find.
- Grid provider selection is tucked away in its own group.
- Root note uses a readable note-name formatter.

---

## Recommendations (priority order)

1. **Move swing into track groups.** Trivial fix: add inside the track loop,
   bump group count to 11.
2. **Add param visibility toggling.** Hide softcut params when voice is not
   softcut; hide midi_ch when voice is not midi; hide sc_synthdef when voice
   is not sc_synth. Requires `params:hide()`/`params:show()` support.
3. **Add mixer params.** Per-track level and pan, with voice-backend-specific
   implementations.
4. **Make osc_host editable.** Change from `add_option` to `add_text` so
   users can enter arbitrary hostnames.
5. **Clean up recorder.lua** if it is no longer planned for integration.
