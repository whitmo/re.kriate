# re.kriate Feature Inventory (2026-03-31)

## Project Overview
re.kriate is a norns/seamstress sequencer inspired by monome kria. Lua-based, 4-track polymetric step sequencer with per-parameter independent loops, grid UI, multiple voice backends, and disk persistence.

## Implemented Features

### Core Sequencer (lib/sequencer.lua, 232 lines) - COMPLETE
- 4-track polymetric step sequencer (16 steps per track)
- Per-parameter independent loop lengths
- Per-track division (1/16 to 1/1 via DIVISION_MAP)
- Clock-driven with per-track coroutines
- Swing/shuffle 0-100% with triplet feel at 50%
- Ratchet support (1-7 note repeats per step)
- Probability-based note drops (per-step 0-100%)
- Portamento/glide (GLIDE_TIME_MAP)
- Sprite/visual voice output alongside audio

### Track Data Model (lib/track.lua, 208 lines) - COMPLETE
- 9 parameters per track: trigger, note, octave, duration, velocity, ratchet, alt_note, glide, probability
- Core params: trigger, note, octave, duration, velocity, probability
- Extended params: ratchet, alt_note, glide
- Per-param clock divider logic (should_advance)
- NUM_TRACKS=4, NUM_STEPS=16, DEFAULT_LOOP_LEN=6
- Musically useful default 16-step patterns per track

### Direction Modes (lib/direction.lua, 94 lines) - COMPLETE
- 5 modes: forward, reverse, pendulum, drunk (random walk), random
- Pendulum tracks advancing_forward flag

### Scale Quantization (lib/scale.lua, 37 lines) - COMPLETE
- 14 scales via musicutil: Major, Natural Minor, Dorian, Mixolydian, Lydian, Phrygian, Locrian, Harmonic Minor, Melodic Minor, Pentatonic Major, Pentatonic Minor, Blues, Whole Tone, Chromatic
- 8 octaves from configurable root note
- Scale degree + octave to MIDI conversion

### Grid Interface (lib/grid_ui.lua, 397+ lines) - COMPLETE
- 16x8 monome grid support
- 10 pages: trigger, note, octave, duration, velocity, probability, ratchet, alt_note, glide, alt_track
- Trigger page: all 4 tracks visible (rows 1-4)
- Value pages: 7-row bar graphs
- Alt-track page: direction (4 cols), division (7 cols), swing (4 cols), mute (1 col) per track
- Pattern bank UI: 16 slots on rows 1-2
- Loop editing: hold x=12 to set loop boundaries
- Extended pages: double-tap nav button to toggle (trigger<>ratchet, note<>alt_note, octave<>glide)
- Navigation row 8: tracks 1-4, mute, pages, loop edit, pattern hold, play/stop

### Voice Backends
- **MIDI** (lib/voices/midi.lua, 66 lines) - COMPLETE: note_on/off, per-channel, portamento CC 5/65, all-notes-off CC 123
- **OSC** (lib/voices/osc.lua, 49 lines) - COMPLETE: /rekriate/track/{n}/note, note_off, all_notes_off, portamento
- **Sprite/Visual** (lib/voices/sprite.lua, 168 lines) - COMPLETE: 7 shapes, track colors, echo trails, glide lines, velocity-size mapping
- **nb Voice** (lib/norns/nb_voice.lua, 37 lines) - COMPLETE: norns nb player wrapper
- **Softcut/Zig** (lib/voices/softcut_zig.lua) - PARTIAL: pitch transposition, loop support, not fully wired
- **Recorder** (lib/voices/recorder.lua, 91 lines) - COMPLETE: test utility for note capture

### Pattern Storage
- **In-memory** (lib/pattern.lua, 44 lines) - COMPLETE: 16 slots, deep copy save/load
- **Disk persistence** (lib/pattern_persistence.lua) - COMPLETE: .krp files, Adler-32 checksum, platform-aware paths (norns dust/data, seamstress XDG), save/load/list/delete

### Event System (lib/events.lua, 255 lines) - COMPLETE
- Lightweight pub/sub bus
- Wildcard support (prefix:*)
- Event taxonomy: sequencer:*, voice:*, grid:*, track:*, page:*, pattern:*, param:*

### Grid Provider (lib/grid_provider.lua) - COMPLETE
- Pluggable backend: monome (hardware), midigrid (MIDI emulation), simulated (seamstress)
- Provider registration and factory pattern

### Platform Support
- **norns** (re_kriate.lua, 72 lines) - COMPLETE: nb voices, screen metro 15fps, key/enc delegation
- **seamstress** (seamstress.lua, 93 lines) - COMPLETE: grid simulation, sprite rendering, keyboard input, MIDI port 1, 30fps

### Keyboard Controls (lib/seamstress/keyboard.lua, 111 lines) - COMPLETE
- space=play/stop, r=reset, 1-4=track, q/w/e/t/y=pages, d=direction
- ctrl+s/l=save/load bank, ctrl+b=list banks, ctrl+shift+d=delete bank
- ctrl+p=probability, ctrl+a=alt-track, ctrl+1-9=pattern save, shift+1-9=pattern load

### Screen UI (lib/seamstress/screen_ui.lua, 104 lines) - COMPLETE
- Title, track/page display, play state, 4 track positions, pattern slot indicators, transient messages

### Sprite Renderer (lib/seamstress/sprite_render.lua, 200+ lines) - COMPLETE
- 7 shape drawing functions, movement (drift+float), pulsing, echo trails, beat grid, playhead, glide lines

### App Orchestration (lib/app.lua, 393 lines) - COMPLETE
- Top-level init/redraw/key/enc/cleanup
- Params system with groups (re_kriate, output, track_*, swing_*, pattern_persistence)
- Config options: voices, sprite_voices, midi_dev, grid_provider, grid_opts

### Logging (lib/log.lua, 74 lines) - COMPLETE
- Leveled logging (info/warn/error) to ~/.re_kriate.log
- xpcall wrapper for error capture

## Partially Implemented / In Development
- **Softcut Sampler** (lib/voices/softcut_zig.lua) - config defined, pitch transposition works, not fully integrated
- **Remote API** (lib/remote/) - spec written, HTTP/WebSocket/OSC remote control, not wired into main sequencer
- **SuperCollider Voice** - reference example in spec, not auto-integrated

## Test Coverage (32 spec files)
Major specs: sequencer (1098 lines), grid_ui (1436 lines), track, pattern (385), pattern_persistence (317), direction (300), events (518), events_integration (454), grid_provider (347), grid_render (264), keyboard (446), screen_ui (168), scale (272), voice, osc_voice (533), probability (51), pattern_bank_ui (308), norns_entrypoint (441), seamstress_entrypoint (408), integration (902), e2e_integration (1098), plus test gap hardening and synthetic grid specs.

## Architecture
- Single context (ctx) table passed through call chain — no custom globals
- Modules return function tables, imported via require/include
- Per-track clock coroutines for independent timing
- Event bus for decoupled communication
- Pluggable grid providers and voice backends
- Platform abstraction via separate entrypoints

## Documentation
- README.md (244 lines): user guide, install, controls, parameters
- CLAUDE.md (117 lines): developer guide, coding standards
- 14+ numbered feature specs with requirements, plans, data models
- docs/grid-interface.html: interactive visual grid guide
- docs/design-review.md: architecture assessment
