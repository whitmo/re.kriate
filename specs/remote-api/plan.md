# Implementation Plan: Remote Control API

## Checklist

- [ ] Step 1: Core API dispatch and validation helpers
- [ ] Step 2: Transport and track handlers
- [ ] Step 3: Step, pattern, and loop handlers
- [ ] Step 4: Page, scale, and state snapshot handlers
- [ ] Step 5: Introspection and API tests
- [ ] Step 6: OSC transport backend
- [ ] Step 7: Integration with app entrypoints

---

## Step 1: Core API dispatch and validation helpers

**Objective:** Establish the dispatch function and input validation — the foundation everything else builds on.

**Implementation guidance:**
- Create `lib/remote/api.lua` with the `handlers` table, `M.dispatch(ctx, path, args)`, and `M.list_paths()`
- Implement three validation helpers:
  - `check_track(args)` — validates `args[1]` as integer 1-`track_mod.NUM_TRACKS`
  - `check_param(name)` — validates against `track_mod.PARAM_NAMES`
  - `check_step(s)` — validates as integer 1-`track_mod.NUM_STEPS`
- Each helper returns `(validated_value, nil)` on success or `(nil, error_string)` on failure

**Test requirements:**
- Dispatch with unknown path returns `nil, "unknown path: ..."`
- Dispatch with nil args doesn't crash (defaults to `{}`)

**Integration notes:** Requires `lib/track` for constants (`NUM_TRACKS`, `NUM_STEPS`, `PARAM_NAMES`). No other dependencies at this step.

**Demo:** `api.dispatch(ctx, "/bogus")` returns an error. Validators work standalone.

---

## Step 2: Transport and track handlers

**Objective:** Add handlers for transport control (play/stop/toggle/reset/state) and track management (select/mute/direction/division/get/active).

**Implementation guidance:**
- Transport handlers delegate to `sequencer.start(ctx)`, `sequencer.stop(ctx)`, `sequencer.reset(ctx)`
- Transport state query reads `ctx.playing`
- Track select sets `ctx.active_track` after validation
- Track mute: with 1 arg toggles, with 2 args sets explicitly (`0`=unmute, `1`=mute)
- Track direction: with 2 args sets (validate against `direction_mod.MODES`), with 1 arg returns current
- Track division: with 2 args sets (validate 1-7), with 1 arg returns current
- Track get returns `{division, muted, direction}` table
- Track active returns `ctx.active_track`
- All command handlers set `ctx.grid_dirty = true`

**Test requirements:**
- `/transport/play` sets `ctx.playing = true`
- `/transport/stop` sets `ctx.playing = false`
- `/transport/toggle` toggles
- `/transport/reset` resets playhead positions to loop_start
- `/transport/state` returns "playing" or "stopped"
- `/track/select` with valid track changes `ctx.active_track`; with invalid returns error
- `/track/mute` toggles and sets explicitly
- `/track/direction` sets, gets, rejects invalid modes
- `/track/division` sets, gets, rejects out-of-range
- `/track/get` returns correct track info
- `/track/active` returns current active track

**Integration notes:** Requires `lib/sequencer` and `lib/direction` modules. These should already be in the codebase.

**Demo:** Create a ctx, dispatch transport and track commands, verify state changes.

---

## Step 3: Step, pattern, and loop handlers

**Objective:** Add handlers for reading/writing individual steps, bulk pattern operations, and loop boundary control.

**Implementation guidance:**
- `/step/set` delegates to `track_mod.set_step(param, step, value)`
- `/step/get` reads `ctx.tracks[t].params[pname].steps[s]` directly
- `/step/toggle` delegates to `track_mod.toggle_step(param, step)` (trigger param only)
- `/pattern/get` returns a **copy** of all 16 steps (not a reference)
- `/pattern/set` validates count (need 16 values), writes all steps
- `/loop/set` delegates to `track_mod.set_loop(param, start, end)`
- `/loop/get` returns `{loop_start, loop_end, pos}`

**Test requirements:**
- Step set/get round-trips correctly
- Step set validates param name and step number
- Step toggle flips trigger values
- Pattern get returns 16-element array that is a copy (modifying it doesn't affect ctx)
- Pattern set writes all 16 values; rejects too-few values
- Loop set/get works with valid boundaries

**Integration notes:** Uses `track_mod.set_step`, `track_mod.toggle_step`, `track_mod.set_loop`. These are existing functions in `lib/track.lua`.

**Demo:** Set a pattern, get it back, modify the returned copy, verify original unchanged.

---

## Step 4: Page, scale, and state snapshot handlers

**Objective:** Add page selection, scale query, and the full state snapshot.

**Implementation guidance:**
- `/page/select` validates against `PARAM_NAMES` (reuses `check_param`), sets `ctx.active_page`
- `/page/active` returns `ctx.active_page`
- `/scale/notes` returns a **copy** of `ctx.scale_notes`
- `/state/snapshot` builds a deep copy of the full sequencer state:
  - Iterate all 4 tracks, all param names
  - Copy step arrays (not reference)
  - Include loop_start, loop_end, pos for each param
  - Include track-level: division, muted, direction
  - Include top-level: playing, active_track, active_page

**Test requirements:**
- Page select with valid param name works; invalid returns error
- Page active returns current page
- Scale notes returns copy (modify without affecting ctx)
- State snapshot includes all tracks with all params, step data, loop boundaries
- Snapshot returns copies (modify without affecting ctx)

**Integration notes:** This completes the handler set. After this step, all paths are registered.

**Demo:** Get a state snapshot, verify it has the complete structure.

---

## Step 5: Introspection and API tests

**Objective:** Finalize `list_paths()` and write the comprehensive test suite.

**Implementation guidance:**
- `M.list_paths()` iterates `handlers` table, collects keys, sorts alphabetically
- Write `specs/remote_api_spec.lua` with test groups for each handler category
- Use the same mock globals pattern as `integration_spec.lua` (clock, params, grid, metro, screen, musicutil)
- Use recorder voices for ctx initialization
- Test both success and error paths for every handler

**Test requirements:**
- `list_paths()` returns sorted array containing all registered paths
- Full test coverage: transport (5 paths), track (6 paths), step (3 paths), pattern (2 paths), loop (2 paths), page (2 paths), scale (1 path), snapshot (1 path), dispatch meta (unknown path, grid dirty)
- Tests should be runnable with busted standalone (no seamstress runtime needed)

**Integration notes:** This is the verification step. If tests fail, go back and fix handlers.

**Demo:** `busted specs/remote_api_spec.lua` passes all tests.

---

## Step 6: OSC transport backend

**Objective:** Build the OSC transport that maps OSC messages to API dispatch calls.

**Implementation guidance:**
- Create `lib/remote/osc.lua` with `M.enable(ctx, opts)` and `M.disable(ctx)`
- `enable` stores previous `osc.event`, installs new handler that:
  1. Strips configurable prefix (default `/re_kriate`) from OSC path
  2. Converts OSC args to flat table
  3. Calls `api.dispatch(ctx, api_path, args)`
  4. On "unknown path" error, falls through to previous handler
  5. Sends reply to caller if `from` address provided and `opts.reply ~= false`
- Reply serialization:
  - `true` -> `{"ok"}`
  - Array table -> flat positional values
  - Key-value table -> interleaved `key, value, key, value, ...`
  - Error -> `{"error", message}`
- `disable` restores previous `osc.event`

**Test requirements:**
- OSC transport is mostly a wiring layer — primary validation is through API tests (Step 5)
- Code review for: prefix stripping, handler chaining, reply format, enable/disable idempotency

**Integration notes:** Depends on `osc` global (norns/seamstress runtime). Not testable with standalone busted. Verify manually.

**Demo:** Enable OSC, send `/re_kriate/transport/play` from external tool, sequencer starts.

---

## Step 7: Integration with app entrypoints

**Objective:** Wire the remote API into the seamstress (and optionally norns) entrypoints.

**Implementation guidance:**
- In `re_kriate_seamstress.lua` init:
  ```lua
  local osc_remote = require("lib/remote/osc")
  osc_remote.enable(ctx, { port = 10111 })
  ```
- In cleanup:
  ```lua
  osc_remote.disable(ctx)
  ```
- Optionally add params for enabling/disabling OSC remote and configuring the prefix
- Consider adding to norns entrypoint too (norns has OSC support via `osc.event`)

**Test requirements:**
- Manual: send OSC messages to running seamstress instance, verify sequencer responds
- Manual: verify script cleanup disables OSC handler

**Integration notes:** This is the final wiring step. The API and OSC transport are already tested independently.

**Demo:** Start re.kriate in seamstress, open TouchOSC/oscsend, control the sequencer remotely.
