# Data Model: 005-Norns-Entrypoint

**Date**: 2026-03-25

## Entities

### nb_voice (modified)

Wraps an nb player into the standard voice interface. Lives at `ctx.voices[track_num]`.

| Field | Type | Description |
|-------|------|-------------|
| param_id | string | nb param ID (e.g., "voice_1") |
| play_note(note, vel, dur) | method | Delegates to nb player:play_note |
| note_on(note, vel) | method | Delegates to nb player:note_on |
| note_off(note) | method | Delegates to nb player:note_off |
| all_notes_off() | method | No-op (nb handles cleanup internally) |
| **set_portamento(time)** | method | **NEW** — Calls player:set_slew(time) if supported, no-ops otherwise |

### ctx (unchanged)

The application context table. No new fields added by this feature. All existing fields created by app.init() remain unchanged.

| Field | Source | Notes |
|-------|--------|-------|
| tracks | app.init | 4 track tables |
| active_track | app.init | 1-4 |
| active_page | app.init | page name string |
| playing | app.init | boolean |
| voices | config.voices (entrypoint) | nb_voice instances for norns |
| g | app.init via grid_provider | monome grid device |
| grid_metro | app.init | Grid refresh metro |
| grid_dirty | app.init | boolean |
| scale_notes | app.init | scale note array |
| patterns | app.init | pattern slots |
| **screen_metro** | **entrypoint** | **Norns screen refresh metro (entrypoint-managed, not in app.lua)** |

### Entrypoint-local state

| Variable | Type | Description |
|----------|------|-------------|
| ctx | table | Application context (module-local, not global) |

## Relationships

```
re_kriate.lua (entrypoint)
  ├── creates nb_voice[1..4] → ctx.voices
  ├── creates screen_metro → ctx.screen_metro
  ├── calls app.init({ voices, grid_provider="monome" }) → ctx
  ├── delegates key/enc/redraw/cleanup → app module
  └── manages log lifecycle (session_start/close)

nb_voice
  └── wraps nb player (via params:lookup_param → get_player)
       ├── play_note, note_on, note_off
       └── set_slew (portamento, if supported)

app.init
  ├── creates tracks, params, grid connection
  ├── wraps grid key callback with log.wrap
  └── starts grid_metro
```

## State Transitions

No new state transitions. The norns entrypoint follows the same lifecycle as seamstress:

1. **init**: Create voices → app.init(config) → start screen_metro → log session start
2. **running**: Key/enc → app delegation, screen_metro → redraw(), grid_metro → grid refresh
3. **cleanup**: app.cleanup(ctx) → stop screen_metro → log close
