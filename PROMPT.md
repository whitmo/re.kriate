# Pass #2: Seamstress Entrypoint

## Objective

Add seamstress as a first-class platform for re.kriate. Success = `seamstress re_kriate_seamstress.lua` loads, grid works, MIDI notes play, keyboard controls function, clean stop.

## Spec

Full design, research, and plan at `specs/seamstress-entrypoint/`. Read `design.md` first, then `plan.md`.

## Key Requirements

- Voice abstraction: `ctx.voices[track]:play_note(note, vel, dur)` interface
- MIDI voice backend with `clock.run` + `clock.sync` note-off timing
- Recorder voice for tests (captures events into a buffer)
- Refactor `lib/sequencer.lua` to use `ctx.voices` instead of nb
- Refactor `lib/app.lua` to accept config (voices injected by entrypoint)
- nb voice wrapper (`lib/norns/nb_voice.lua`) so norns entrypoint still works
- Seamstress entrypoint with minimal screen UI and keyboard fallback (space=play, r=reset, 1-4=track, qwety=pages)
- Tests: unit (voice, sequencer, keyboard), integration (script loads, ctx valid)

## Acceptance Criteria

1. `seamstress re_kriate_seamstress.lua` opens without errors, shows status display
2. Grid interaction works identically to norns version
3. MIDI note_on/note_off sent on configured channels with correct timing
4. Keyboard fallback: play/stop, reset, track select, page select
5. Clean stop: all notes off, CC 123, no hanging notes
6. Norns entrypoint (`re_kriate.lua`) still works with nb voices
7. `seamstress --test --test-dir specs` passes all tests

## Implementation

Follow the 8-step plan in `specs/seamstress-entrypoint/plan.md`. Steps build incrementally — each ends with working tests. Steps 4+5 should be one commit (app refactor + norns entrypoint update).

## Constraints

- Follow CLAUDE.md conventions (ctx pattern, no custom globals, modules)
- Do not implement future work (drum tracks, recording, piano roll, plugin system, OSC voice)
- Keep `lib/track.lua`, `lib/scale.lua`, `lib/grid_ui.lua` unchanged unless necessary
- Seamstress 2.0.0-alpha is the target — all needed APIs confirmed available (see `research/seamstress-v2-api.md`)
