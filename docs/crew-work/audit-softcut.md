# Softcut Voice Audit

Date: 2026-04-11

Files reviewed:
- `lib/voices/softcut_zig.lua` -- voice backend (sampler)
- `lib/voices/softcut_runtime.lua` -- buffer management runtime
- `lib/voices/recorder.lua` -- event recorder voice
- `lib/app.lua` -- param registration and voice construction
- `lib/sequencer.lua` -- dispatch interface
- `specs/softcut_zig_voice_spec.lua` -- 7 tests
- `specs/softcut_runtime_spec.lua` -- 14 tests
- `specs/softcut_integration_spec.lua` -- 10 tests

---

## 1. Mapped Params

Per-track params registered in `app.lua` (lines 248-265):

| Param ID | Type | Default | Notes |
|---|---|---|---|
| `sample_path_{t}` | text | `""` | File path to audio sample |
| `sample_root_{t}` | number 0-127 | 60 (C4) | Root note for pitch mapping |
| `sample_start_{t}` | number 0-350 | 0 | Start position in seconds |
| `sample_end_{t}` | number 0-350 | 1 | End position in seconds |
| `sample_loop_{t}` | option off/on | off | Loop playback |

Additional config in `softcut_zig.lua` DEFAULTS (not exposed as norns params):

| Config key | Default | Notes |
|---|---|---|
| `level` | 1.0 | Voice level (used as velocity multiplier) |
| `pan` | 0.0 | Stereo pan (-1 to 1) |
| `attack` | 0.01 | Fade-in time |
| `release` | 0.05 | Fade-out time |
| `rate_slew` | 0.0 | Portamento/rate slew |

**Finding:** `level`, `pan`, `attack`, and `release` are internal config only -- they have no corresponding norns params and cannot be adjusted by the user at runtime (beyond the initial DEFAULTS). This is a significant gap.

---

## 2. Recording Capability

**No.** The `recorder.lua` voice is an event logger, not an audio recorder. It captures `play_note`, `note_on`, `note_off`, `all_notes_off`, and `set_portamento` calls as timestamped event objects in a Lua table. It is used for testing and visualization, not for audio capture.

The `softcut_runtime.lua` does define `rec_level` and `pre_level` methods, but both are **no-ops** (lines 127-131):

```lua
function runtime.rec_level(_voice_id, _val)
end

function runtime.pre_level(_voice_id, _val)
end
```

Neither `softcut_zig.lua` nor `app.lua` call `rec_level` or `pre_level`. There is no code path that enables recording into softcut buffers.

---

## 3. Record-then-play Pipeline

**Does not exist.** A user without samples cannot record/grab audio and play it via softcut. The only way to use softcut is to provide a pre-existing sample file via the `sample_path` param. If `sample_path` is empty or the file is missing, the voice sets `available = false` and all `play_note`/`note_on` calls return `nil, "sample_missing"`.

To enable this pipeline, the following would be needed:
- Wire `rec_level`/`pre_level` to actual softcut calls in the runtime
- Add a param or UI control to arm recording on a voice slot
- Route audio input to the voice's buffer region
- After recording, mark the voice as `available = true` without requiring `sample_path`

---

## 4. Voice Interface Contract

The sequencer (`lib/sequencer.lua` line 269-273) calls voices through this interface:

```
voice:play_note(note, velocity, duration)
voice:set_portamento(val)
voice:all_notes_off()
```

And indirectly via `play_note` -> `note_on` -> `note_off`.

**`softcut_zig` implements:**
- `play_note(note, vel, dur)` -- yes
- `note_on(note, vel)` -- yes
- `note_off(note)` -- yes
- `all_notes_off()` -- yes
- `set_portamento(val)` -- yes
- `apply_config(cfg)` -- yes (rebuild)

**`softcut_zig` does NOT implement:**
- `set_level(val)` -- **missing**
- `set_pan(val)` -- **missing**

Neither `set_level` nor `set_pan` appear anywhere in the codebase (grep returns zero results across all of `lib/` and `specs/`). This means the mixer work has not yet landed, or these methods are planned but not yet part of any voice contract. The `level` and `pan` values are baked in at config time and during `note_on` (velocity * level), but there is no way to adjust them dynamically from a mixer UI.

---

## 5. What's Missing or Broken

### Missing

1. **No runtime-adjustable level/pan params.** The `level`, `pan`, `attack`, and `release` config values in `softcut_zig.lua` DEFAULTS are not exposed as norns params. A user cannot adjust voice volume or panning without editing code.

2. **No `set_level` / `set_pan` methods.** The mixer voice interface is not implemented. When mixer work lands, softcut voices will need these methods.

3. **No recording pipeline.** `rec_level` and `pre_level` are stubbed as no-ops in the runtime. There is no way to capture live audio into softcut buffers.

4. **No real norns softcut integration.** The runtime is a state-tracking mock -- it stores values in Lua tables but never calls the actual norns `softcut` API. For real hardware, a bridge layer is needed that forwards `runtime.level(id, val)` -> `softcut.level(id, val)`, etc. The `buffer_read_mono` fallback path (line 127-128 of `softcut_zig.lua`) calls `runtime.buffer_read_mono` which just returns `file_exists(path)` -- it does not actually load audio data.

5. **`sample_start` / `sample_end` params are integers.** In `app.lua` line 250-251, both are `add_number(..., 0, 350, ...)` which produces integer values. The softcut_zig config treats them as seconds (`start_sec`, `end_sec`), so sub-second precision for sample boundaries is impossible through the param UI.

### Potentially Broken

6. **`note_off` clears from `active_notes` but note was never added there by `note_on`.** In `note_on()` (line 183), only `self.active_note = note` is set (singular). But `note_off()` (line 195) does `self.active_notes[note] = nil` (plural). The `active_notes` table is only populated by `play_note()` (line 211), not by standalone `note_on()`. This means if a caller uses `note_on` then `note_off` directly (without `play_note`), the `active_notes` table is unaffected, which is fine but inconsistent. The `active_note` (singular) field is the real state tracker for note_on/note_off.

7. **`level_cut` is a no-op.** The runtime defines `level_cut` (line 133) as a no-op, and it is never called by the voice. Cross-voice routing is not implemented.

---

## Test Coverage

| Spec file | Test count | Coverage |
|---|---|---|
| `softcut_zig_voice_spec.lua` | 7 | Config apply, note_on rate mapping, play_note clock scheduling, portamento, retrigger, all_notes_off, missing sample, load failure |
| `softcut_runtime_spec.lua` | 14 | Buffer allocation, voice state accessors, sample loading, file_exists, no-op methods, warnings |
| `softcut_integration_spec.lua` | 10 | VOICE_TYPES includes softcut, build_voice, shared runtime, sequencer dispatch, missing/empty sample, param rebuild, cleanup |

Tests are solid for the current scope. No tests exist for recording, `set_level`, `set_pan`, or real norns softcut API integration.
