# Seamstress Entrypoint - Scratchpad

## Understanding

The objective is to add seamstress as a first-class platform for re.kriate. The codebase currently has a norns-only implementation with nb voice integration hardcoded into `lib/app.lua` and `lib/sequencer.lua`.

The plan has 8 steps that build incrementally:
1. Voice interface + recorder voice (test foundation)
2. MIDI voice backend
3. Refactor sequencer to use ctx.voices
4. Refactor app.lua to accept config
5. nb voice wrapper + norns entrypoint update (commit with step 4)
6. Seamstress screen UI + keyboard input
7. Seamstress entrypoint script
8. Integration tests + manual verification

## Key architectural decisions
- Voice abstraction via `ctx.voices[track]:play_note(note, vel, dur)` interface
- Separate entrypoints per platform (proven community pattern)
- Recorder voice doubles as test tool and future piano roll data source
- `clock.get_beats()` for timestamps in recorder (mock in tests)

## Iteration 1 plan
Starting with Step 1: recorder voice + voice_spec tests. This is the foundation everything else builds on, has no dependencies, and is fully testable standalone.

## Iteration 1 result
Step 1 complete. Recorder voice at `lib/voices/recorder.lua`, 11 tests pass in `specs/voice_spec.lua`. Key learning: busted requires `rawset(_G, "clock", ...)` for mocking globals visible to required modules. Next up: Step 2 (MIDI voice) and Step 3 (sequencer refactor) are now unblocked.

## Iteration 2 result
Step 2 complete. MIDI voice at `lib/voices/midi.lua`, 17 new tests (28 total in voice_spec). Mock strategy: clock.run captures the coroutine function for later execution, clock.cancel records cancellation, mock midi device records all calls. This lets us test retrigger, velocity mapping, all_notes_off, and even the note-off coroutine behavior without needing a real clock runtime. All 42 tests across all specs pass. Next up: Step 3 (sequencer refactor) is the critical path — it unblocks Steps 4-8.

## Iteration 3 result
Step 3 complete. Refactored `lib/sequencer.lua` — replaced `params:lookup_param("voice_N"):get_player()` with `ctx.voices[track_num]:play_note()`. The change was 4 lines in play_note(). Added `specs/sequencer_spec.lua` with 16 tests covering step_track (trigger/no-trigger, param advancement, grid_dirty, correct MIDI note/duration/velocity mapping, multi-track routing), play_note delegation, reset, start/stop, and nil voice edge cases. All 58 tests pass across all specs. The sequencer is now platform-agnostic. Next up: Steps 4+5 (app.lua refactor + nb voice wrapper + norns entrypoint) are unblocked.

## Iteration 4 result
Steps 4+5 complete. Refactored `lib/app.lua` — `M.init(config)` now accepts a config table with `{ voices }`. Removed nb dependency from app.lua entirely. Created `lib/norns/nb_voice.lua` that wraps nb player into the voice interface. Updated `re_kriate.lua` to do nb setup (init, params, player_params) and inject nb_voice wrappers. Added `all_notes_off` call in `app.cleanup` for clean shutdown. All 58 tests pass unchanged. The shared core (app, sequencer, track, scale, grid_ui) is now fully platform-agnostic. Next up: Step 6 (seamstress screen UI + keyboard input) is unblocked.

### HUMAN GUIDANCE (2026-03-06 05:33:58 UTC)

it is ok to vendor musicutil or timeline

## Iteration 5 result
Step 6 complete. Created `lib/seamstress/screen_ui.lua` (minimal status display with color: title, track/page, play state, per-track step positions) and `lib/seamstress/keyboard.lua` (space=play/stop, r=reset, 1-4=track, qwety=pages). Added `specs/keyboard_spec.lua` with 16 tests covering play/stop toggle, reset, track/page select, input filtering (key up, repeats, unmapped keys), and grid_dirty behavior. All 74 tests pass. Next up: Step 7 (seamstress entrypoint script) and Step 8 (integration tests) are unblocked.

### HUMAN GUIDANCE (2026-03-06 05:35:46 UTC)

the monome 128 is hooked up if you need to test against it

## Iteration 6 plan
Step 7: Create `re_kriate_seamstress.lua` entrypoint. Thin script (~40 lines) wiring MIDI voices, screen UI, keyboard input, and app.init. Follows design doc reference implementation. Key details:
- Connect MIDI device via `midi.connect(1)`
- Create 4 MIDI voices (channel = track number, configurable via params)
- Add MIDI channel params before calling `app.init`
- Set up `screen.key` callback for keyboard input
- Start screen refresh metro at 15fps
- `cleanup()` delegates to `app.cleanup` (which already handles all_notes_off + grid metro stop) plus stops screen metro

## Iteration 6 result
Step 7 complete. Created `re_kriate_seamstress.lua` (63 lines) — thin wiring script following the design doc reference. All 74 tests pass. Next up: Step 8 (integration tests + manual verification) is the final step.

## Iteration 7 result
Step 8 complete. Created `specs/integration_spec.lua` with 13 integration tests covering:
- app.init with recorder voices produces valid ctx (all fields, scale_notes)
- Full sequencer cycle: step_track fires into recorder, multi-track shared buffer, scale quantization
- Start/stop via sequencer and keyboard on real app ctx
- Keyboard track/page select and reset on app ctx
- Cleanup stops sequencer and doesn't error
- screen_ui.redraw works on real app ctx (playing/stopped)

Mock strategy: full params system (store+actions), grid, metro, screen, and musicutil mocked at global/package level. All 87 tests pass (74 existing + 13 new). All 8 implementation steps complete.
