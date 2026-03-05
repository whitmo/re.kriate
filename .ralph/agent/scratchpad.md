# Scratchpad — re.kriate

## 2026-03-05: Initial Research Complete

Studied all three reference implementations (monome/ansible C firmware, zjb-s/n.kria norns port, Dewb/monome-rack VCV port) plus the official kria docs and norns/seamstress platform APIs.

### Key findings:

**Original kria (ansible C firmware):**
- 4 tracks, 7 params each: trigger, note, octave, duration, repeat, alt_note, glide
- 16 steps per param, each param has independent loop start/end/length
- Per-param clock division (tmul 1-16), per-step probability (4 levels)
- 5 direction modes: forward, reverse, triangle, drunk, random (per-track, not per-param)
- 16 patterns per preset, 8 presets, meta-sequencer (64 steps chaining patterns)
- Scale system: 7 degrees per scale, 16 scale slots, notes index into scale degrees 0-6

**n.kria (existing norns port):**
- Uses nb for voices (good precedent)
- 8 params: trig, retrig, note, transpose, octave, slide, gate, velocity
- Heavy globals, singleton Data object with metatable proxies — overcomplicated
- Good grid layout reference but code organization is a cautionary tale

**Recommended simplification for re.kriate (v1):**
- Start with 5 core params: trigger, note, octave, duration, velocity
- Skip: repeat/ratcheting, alt_note, glide, transpose (add later if needed)
- Skip: meta-sequencer, probability (add later)
- Keep: per-param independent loop lengths, clock division, scale quantization, patterns
- Use nb for voices (non-negotiable per PROMPT.md)
- Simple index math for step positions (not sequins — mutable grid data doesn't need it)
- lattice or clock.sync for timing
- Follow ctx pattern strictly (no globals, no singletons)

### Platform compatibility:
- grid, clock, sequins, musicutil, lattice, params, midi — all compatible between norns and seamstress
- No key/enc in seamstress — grid-only interaction works on both
- Screen API differs — handle with platform check or skip screen for now
- nb works in seamstress via MIDI players (no engine voices)

Research notes written to .ralph/agent/kria-research.md

## 2026-03-05: Musician Review of Design

### Verdict: APPROVED with priorities

The researcher did solid work. The 5-param simplification (trigger, note, octave, duration, velocity) is exactly right — those are the params you actually perform with. Repeat/ratcheting, alt_note, glide can come later when the core feels good.

### What I like:
- Per-param independent loop lengths IS the feature. Non-negotiable for Phase 1.
- nb voice output — correct, this is how you make it composable.
- Grid-only UI for MVP — smart, works on both platforms, and grid IS the kria interface.
- ctx pattern with no globals — keeps it clean and testable.
- Forward direction only for Phase 1 — fine, get the basics right first.
- Per-track (not per-param) clock division for Phase 1 — good simplification.

### Pushback:
- "1 scale, hardcoded" is too limiting. Even for MVP, you need a root note param and a scale type param (via musicutil). The grid scale editor can wait, but parameterized scale selection is essential. A musician needs to at least change key.
- Default patterns should be musically interesting out of the box. Don't ship with all steps off — have a simple trigger pattern and a scale run on note so it makes sound immediately on first play.
- Step value range 1-7 mapping to grid rows is good and intuitive. Keep it.

### Phase 1 priorities (in build order):
1. Data model: tracks, params, loop state (lib/track.lua)
2. Sequencer engine: clock + per-param step advancement with loop wrapping (lib/sequencer.lua)
3. nb voice integration: play_note on trigger (lib/sequencer.lua)
4. Scale via params: root note + scale type, using musicutil (lib/scale.lua)
5. Grid UI: trigger page (all 4 tracks), note page, octave page, duration page (lib/grid_ui.lua)
6. Grid nav: track select, page select, loop editing overlay
7. Musically useful defaults

### Constraints for the builder:
- MUST use nb for voices — no direct MIDI or engine calls
- MUST have parameterized scale (root + type) even without grid scale editor
- MUST have per-param loop start/end working in Phase 1
- MUST have interesting defaults (not blank patterns)
- Grid layout should follow original kria conventions where possible (bottom row = nav)
- No screen UI needed yet
- No patterns/storage yet — just one live pattern per track

## 2026-03-05: Initial Build Complete (Lua Wizard)

### What was built:

**Module structure:**
- `re_kriate.lua` — thin global hooks, delegates to lib/app
- `lib/app.lua` — init (nb, params, grid, metro), redraw, key, enc, cleanup
- `lib/track.lua` — track data model, step values, loop control, advance/peek/set/toggle
- `lib/sequencer.lua` — per-track clock coroutines, per-param independent advancement, nb play_note
- `lib/scale.lua` — musicutil-based scale building, degree+octave → MIDI note
- `lib/grid_ui.lua` — trigger page (4-track), value pages (note/oct/dur/vel), nav row, loop editing

**Key design decisions:**
- One clock.run coroutine per track (not per-param) — simpler, per-param advancement happens within step_track
- Per-param loop start/end with independent positions — the core kria feature
- Grid layout: rows 1-7 data, row 8 nav (tracks 1-4, pages 6-10, loop 12, play 16)
- Trigger page shows all 4 tracks; value pages show active track only with bar display
- Duration/velocity maps: 7 levels mapping to musical values
- Scale: root_note + scale_type params, musicutil.generate_scale, 14 scale options
- Musically useful defaults: 4 distinct track patterns with triggers, melodies, varied rhythms
- Metro at 30fps for grid refresh (dirty flag pattern)

**Tests:**
- `specs/track_spec.lua` — 14 tests covering new_param, new_track, new_tracks, advance (basic, wrap, non-default loops), toggle_step, set_step, set_loop, peek
- All pass via busted and seamstress --test

**Fixed during build:**
- busted mediator_lua was installed but file missing — force reinstalled
- grid_dirty flag had redundant conditional — simplified

**Not yet built (future iterations):**
- Screen UI beyond minimal info
- Pattern storage/recall
- Direction modes (reverse, triangle, drunk, random)
- Per-param clock division
- Probability
- Meta-sequencer
