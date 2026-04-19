# Quarantined Specs

These spec files were quarantined on 2026-04-18 because they test an OOP mixer
API that does not exist in `lib/mixer.lua`.

## Why

The actual mixer module (`lib/mixer.lua`) uses a flat-table API with module-level
functions:

```lua
M.set_level(ctx, track, value)
M.snapshot(ctx)
M.restore(ctx, snap)
```

These specs assume an OOP API that was never implemented:

- `Mixer.new()` returning an object with methods
- `mixer:handle_meter()`, `mixer.meters.tracks`
- `mixer:serialize()`, `mixer:deserialize()`
- `mixer.tracks[t].level`, `mixer.aux`, `mixer.master`

They were likely written speculatively for the SC mixer feature (spec 015) but
the implementation went a different direction.

## Files

| File | What it tests | Why it fails |
|------|--------------|--------------|
| `grid_mixer_spec.lua` | `mixer.tracks[1].level`, `draw_mixer_page` brightness | OOP track objects don't exist |
| `mixer_metering_spec.lua` | `mixer:handle_meter()`, `mixer.meters.tracks` | Metering methods don't exist |
| `mixer_persistence_spec.lua` | `mixer:serialize()`, `mixer:deserialize()` | Serialization methods don't exist |

## Resolution

These specs should be rewritten to match the actual flat-table mixer API if/when
the SC mixer feature (spec 015) is implemented, or deleted if that feature takes
a different shape.
