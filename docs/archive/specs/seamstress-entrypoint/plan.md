# Implementation Plan: Seamstress Entrypoint

## Checklist

- [ ] Step 1: Voice interface and recorder voice
- [ ] Step 2: MIDI voice backend
- [ ] Step 3: Refactor sequencer to use ctx.voices
- [ ] Step 4: Refactor app.lua to accept config
- [ ] Step 5: nb voice wrapper and norns entrypoint update
- [ ] Step 6: Seamstress screen UI and keyboard input
- [ ] Step 7: Seamstress entrypoint script
- [ ] Step 8: Integration tests and manual verification

---

## Step 1: Voice interface and recorder voice

**Objective:** Establish the voice interface contract and build the recorder voice — the test foundation everything else builds on.

**Implementation guidance:**
- Create `lib/voices/recorder.lua` implementing `play_note`, `note_on`, `note_off`, `all_notes_off`, plus test helpers (`get_events`, `get_notes`, `clear`)
- Events stored in a shared buffer table (passed at construction). Each event: `{ track, note, vel, dur, beat, [type] }`
- `clock.get_beats()` for timestamps (in tests, this will come from mock clock or return 0)

**Test requirements:**
- `specs/voice_spec.lua`: recorder captures play_note calls, get_events filters by track, get_notes returns note list, clear removes only that track's events, shared buffer works across multiple recorder instances

**Integration notes:** No dependencies on other new code. Can be tested with standalone busted (mock `clock.get_beats` to return a counter).

**Demo:** Run tests, see them pass. `seamstress --test --test-dir specs`

---

## Step 2: MIDI voice backend

**Objective:** Build the MIDI voice that sends real note_on/note_off with clock-based note-off timing.

**Implementation guidance:**
- Create `lib/voices/midi.lua` implementing the voice interface
- `play_note`: note_on immediately, `clock.run(function() clock.sync(dur); note_off end)` for note-off
- Active note tracking: `active_notes[ch * 128 + note] = coroutine_id`. On retrigger, cancel pending coroutine and re-send note-off before new note-on.
- `all_notes_off`: cancel all coroutines, send note_off for all tracked notes, send CC 123
- Velocity mapping: voice receives 0.0-1.0, converts to 0-127 integer for MIDI
- Constructor: `midi_voice.new(midi_dev, channel)` — midi_dev is from `midi.connect()`, channel is 1-16

**Test requirements:**
- `specs/voice_spec.lua` (extend): create MIDI voice with a mock midi device (table with note_on/note_off/cc methods that record calls). Verify play_note sends note_on with correct args. Verify all_notes_off sends note_off for tracked notes and CC 123.
- Note-off timing is hard to unit test (requires clock). Defer to integration tests.

**Integration notes:** Depends on `clock.run`/`clock.sync` being available (seamstress runtime or norns). Unit tests mock the midi device but not the clock for note-off scheduling.

**Demo:** Unit tests pass for MIDI voice construction and note_on/all_notes_off. Note-off timing verified in Step 8.

---

## Step 3: Refactor sequencer to use ctx.voices

**Objective:** Replace the hardcoded nb call path in `lib/sequencer.lua` with `ctx.voices[track_num]`.

**Implementation guidance:**
- Change `M.play_note` from:
  ```lua
  local player = params:lookup_param("voice_" .. track_num):get_player()
  if player then player:play_note(note, velocity, duration) end
  ```
  To:
  ```lua
  local voice = ctx.voices[track_num]
  if voice then voice:play_note(note, velocity, duration) end
  ```
- That's it. One function, one change. The rest of sequencer.lua is already platform-agnostic.

**Test requirements:**
- `specs/sequencer_spec.lua`: create a ctx with recorder voices and mock tracks. Call `sequencer.step_track(ctx, 1)` with trigger=1. Verify recorder captured the note. Call with trigger=0, verify no event. Test with different note/octave/velocity/duration values and verify the recorder gets correct MIDI note (via scale_mod.to_midi).
- Existing `specs/track_spec.lua` continues to pass (track module is unchanged).

**Integration notes:** After this step, the sequencer works with any voice backend. Both entrypoints can use it.

**Demo:** `step_track` tests pass with recorder voices. The sequencer fires notes into the recorder and we can assert on them.

---

## Step 4: Refactor app.lua to accept config

**Objective:** Make `app.init` accept a config table so entrypoints can inject voices and platform-specific modules.

**Implementation guidance:**
- `M.init(config)` where config has `{ voices, screen_mod, event_buffer }`
- Move nb-specific setup (nb:init, nb:add_param, nb:add_player_params) OUT of app.lua — this becomes the norns entrypoint's responsibility
- Move voice param creation out — each entrypoint adds its own voice params (nb params for norns, MIDI channel params for seamstress)
- Keep shared setup in app.lua: track creation, scale params, division params, grid connection, grid metro
- `ctx.voices = config.voices or {}`
- Norns screen drawing stays in app.lua's `M.redraw` for now (it's minimal and norns-specific). Seamstress entrypoint will use its own screen module.
- `M.cleanup` calls `all_notes_off` on each voice in ctx.voices

**Test requirements:**
- Existing track_spec and new sequencer_spec still pass (no changes to those interfaces)
- Verify app.init returns a ctx with voices when provided

**Integration notes:** This is the biggest refactor. The norns entrypoint must be updated simultaneously (Step 5) to keep things working. Consider doing Steps 4 and 5 together as one commit.

**Demo:** After Steps 4+5, the norns entrypoint should work exactly as before (verify by reading the code — can't run norns locally). Sequencer tests pass with the new app.init signature.

---

## Step 5: nb voice wrapper and norns entrypoint update

**Objective:** Create the nb voice wrapper and update the norns entrypoint to use the new app.init config pattern.

**Implementation guidance:**
- Create `lib/norns/nb_voice.lua`: wraps `params:lookup_param(param_id):get_player()` into the voice interface. `play_note` delegates to player:play_note. `all_notes_off` is a no-op (nb handles its own cleanup).
- Update `re_kriate.lua`:
  - `require("nb")`, init nb, add nb params (moved from app.lua)
  - Create 4 nb_voice wrappers
  - Call `app.init({ voices = voices })`
  - `redraw`, `key`, `enc`, `cleanup` delegate to app as before

**Test requirements:**
- nb_voice is norns-only and can't be tested locally. Verify by code review.
- The norns entrypoint should be functionally identical to before — same params, same behavior.

**Integration notes:** Do this in the same commit as Step 4. The pair of changes (app.lua refactor + norns entrypoint update) must land together.

**Demo:** Code review confirms norns entrypoint has identical behavior. All existing tests pass.

---

## Step 6: Seamstress screen UI and keyboard input

**Objective:** Build the seamstress-specific modules: screen display and keyboard controls.

**Implementation guidance:**
- Create `lib/seamstress/screen_ui.lua`:
  - `M.redraw(ctx)` — clear, draw title, track/page, play state, per-track step positions
  - Use `screen.color()` for colored text (green = playing, red = stopped)
  - Keep it simple — this is the minimal status display
- Create `lib/seamstress/keyboard.lua`:
  - `M.key(ctx, char, modifiers, is_repeat, state)` — handle key down events
  - Space = play/stop, r = reset, 1-4 = track select, q/w/e/t/y = page select
  - Requires `lib/sequencer` for play/stop/reset

**Test requirements:**
- `specs/keyboard_spec.lua`: create a mock ctx, call keyboard.key with various chars, verify ctx state changes (active_track, active_page, playing toggled)
- Screen UI is visual — no automated test, verify manually in Step 8

**Integration notes:** These modules have no dependencies on the seamstress runtime for logic (screen_ui calls screen.* but that's only at draw time). Keyboard logic is testable with a plain ctx table.

**Demo:** Keyboard tests pass. Screen module is ready for wiring up.

---

## Step 7: Seamstress entrypoint script

**Objective:** Wire everything together into `re_kriate_seamstress.lua`.

**Implementation guidance:**
- Create `re_kriate_seamstress.lua`:
  - Require all modules: app, midi_voice, screen_ui, keyboard, track_mod
  - In `init()`: connect MIDI device, create 4 MIDI voices, add MIDI channel params, call `app.init({ voices = voices, screen_mod = screen_ui })`, set up `screen.key` callback, start screen refresh metro
  - `redraw()` delegates to screen_ui.redraw(ctx)
  - `cleanup()` calls app.cleanup(ctx) then all_notes_off on each voice
- Add MIDI device selection param if seamstress supports listing devices, otherwise hardcode `midi.connect(1)`

**Test requirements:**
- This is the integration point — tested in Step 8

**Integration notes:** This should be a thin script (< 50 lines) that wires modules together. All logic lives in lib/.

**Demo:** `seamstress re_kriate_seamstress.lua` opens the window, shows the status display. If a grid is connected, it lights up. Pressing spacebar or grid play button starts the sequencer.

---

## Step 8: Integration tests and manual verification

**Objective:** Validate everything works end-to-end.

**Implementation guidance:**
- Create `specs/integration_spec.lua` for `seamstress --test`:
  - Test that app.init with recorder voices produces a valid ctx
  - Test that step_track fires events into the recorder
  - Test that start/stop toggles playing state
  - If possible: test that clock-driven playback produces events (yield-based polling)
- Manual verification checklist:
  - [ ] `seamstress re_kriate_seamstress.lua` opens without errors
  - [ ] Screen shows "re.kriate", track/page info, "stopped"
  - [ ] Grid lights up with default pattern (if connected)
  - [ ] Spacebar starts sequencer, screen shows "playing"
  - [ ] Grid playheads advance
  - [ ] MIDI notes arrive at connected device/DAW
  - [ ] Notes stop cleanly on stop (no hanging notes)
  - [ ] Track select (1-4 keys), page select (q/w/e/t/y) work
  - [ ] Grid step editing works (toggle triggers, set values)
  - [ ] Loop editing works (hold grid 12 + press two steps)
  - [ ] r key resets playheads
  - [ ] Script exit sends all-notes-off
  - [ ] `seamstress --test --test-dir specs` passes all tests

**Test requirements:**
- All specs pass: track_spec, voice_spec, sequencer_spec, keyboard_spec, integration_spec

**Integration notes:** This is the final validation step. Fix any issues found during manual testing by going back to the appropriate step.

**Demo:** Kria comes up working in seamstress. Grid interaction, MIDI output, keyboard controls, clean stop. Tests green.
