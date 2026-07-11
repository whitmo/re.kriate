# Design: Remote Control API

## Overview

A transport-agnostic remote control API for the re.kriate sequencer. External tools (TouchOSC, Max/MSP, web UIs, custom controllers) send commands and queries through a unified dispatch layer. Transport backends (OSC, websocket, MIDI CC) parse their protocol and call `api.dispatch(ctx, path, args)` — they never touch ctx directly.

**Success criterion:** OSC messages control the sequencer (play/stop, edit steps, read full state). Adding a new transport (websocket, MIDI CC) requires only a new backend module — zero changes to the core API.

**What this does NOT include:** Websocket transport, MIDI CC transport, state change subscriptions/push notifications, undo/redo, pattern bank management, multi-client conflict resolution, authentication. These are future work.

## Detailed Requirements

### Core API
1. Single dispatch entry point: `api.dispatch(ctx, path, args)` returns `(value, err)`
2. Handler registry keyed by path string — each handler receives `(ctx, args)`
3. Commands return `true` on success; queries return requested data
4. Errors return `nil, "descriptive message"`
5. Strict input validation: track numbers (1-4), step numbers (1-16), param names, direction modes, division ranges
6. Introspection: `api.list_paths()` returns sorted array of all registered paths
7. All command handlers set `ctx.grid_dirty = true` to trigger grid redraw

### Transport Control
8. `/transport/play` — start sequencer (delegates to `sequencer.start`)
9. `/transport/stop` — stop sequencer (delegates to `sequencer.stop`)
10. `/transport/toggle` — toggle play/stop
11. `/transport/reset` — reset all playheads (delegates to `sequencer.reset`)
12. `/transport/state` — query: returns `"playing"` or `"stopped"`

### Track Control
13. `/track/select <track>` — set active track
14. `/track/mute <track> [0|1]` — toggle or set mute
15. `/track/direction <track> [mode]` — set or get direction mode
16. `/track/division <track> [val]` — set or get clock division (1-7)
17. `/track/get <track>` — query: returns `{division, muted, direction}`
18. `/track/active` — query: returns active track number

### Step Data
19. `/step/set <track> <param> <step> <value>` — write a step value
20. `/step/get <track> <param> <step>` — read a step value
21. `/step/toggle <track> <step>` — toggle trigger step

### Pattern Data
22. `/pattern/get <track> <param>` — query: returns all 16 step values (copy)
23. `/pattern/set <track> <param> <v1>..<v16>` — write all 16 steps

### Loop Control
24. `/loop/set <track> <param> <start> <end>` — set loop boundaries
25. `/loop/get <track> <param>` — query: returns `{loop_start, loop_end, pos}`

### Page Selection
26. `/page/select <param_name>` — set active page (validated against PARAM_NAMES)
27. `/page/active` — query: returns active page name

### Scale
28. `/scale/notes` — query: returns copy of scale_notes array

### State Snapshot
29. `/state/snapshot` — query: returns full sequencer state (playing, active_track, active_page, all 4 tracks with all params, step values, loop boundaries, positions)

### OSC Transport
30. OSC address maps to API path (e.g., OSC `/re_kriate/transport/play` -> API `/transport/play`)
31. Configurable prefix (default `/re_kriate`) — stripped before dispatch
32. OSC args forwarded as positional arguments to handler
33. Reply messages sent to caller on configurable basis: `<path>/reply` with result or error
34. Unknown paths fall through to previous `osc.event` handler (chain-safe)
35. Enable/disable without script restart — `osc_remote.enable(ctx, opts)` / `.disable(ctx)`

## Architecture Overview

```
External Tool                    re.kriate
─────────────                    ─────────
TouchOSC ──OSC──┐
Max/MSP  ──OSC──┤   ┌─────────────────────────┐
Web UI   ──WS───┤   │  lib/remote/api.lua      │
Controller─CC───┘   │                           │
                    │  dispatch(ctx, path, args) │
    ┌───────────┐   │         │                  │
    │ Transport │   │    ┌────▼────┐             │
    │ Backends  │──▶│    │handlers │             │
    │           │   │    │ table   │             │
    │ osc.lua   │   │    └────┬────┘             │
    │ (future:  │   │         │                  │
    │  ws.lua,  │   │    ctx + module APIs       │
    │  cc.lua)  │   │  (sequencer, track_mod,    │
    └───────────┘   │   direction_mod)           │
                    └─────────────────────────────┘
```

```
lib/
  remote/
    api.lua          -- transport-agnostic dispatch + handler registry
    osc.lua          -- OSC transport backend

specs/
  remote_api_spec.lua  -- comprehensive tests for the API layer
```

## Components and Interfaces

### Core API (`lib/remote/api.lua`)

The API module owns a `handlers` table keyed by path string. Each handler is `function(ctx, args) -> value, err`.

```lua
local M = {}

-- Dispatch: the single entry point for all transports
function M.dispatch(ctx, path, args)
  local handler = handlers[path]
  if not handler then
    return nil, "unknown path: " .. tostring(path)
  end
  return handler(ctx, args or {})
end

-- Introspection
function M.list_paths()
  local paths = {}
  for path in pairs(handlers) do paths[#paths + 1] = path end
  table.sort(paths)
  return paths
end
```

Handler registration is static (defined at module load time in the handlers table). No dynamic registration needed initially.

### Validation helpers

Four reusable validators, each returning `(validated_value, err)`:

```lua
local function check_track(args)     -- validates args[1] as track 1-NUM_TRACKS
local function check_param(name)     -- validates against track_mod.PARAM_NAMES
local function check_step(s)         -- validates as step 1-NUM_STEPS
local function check_value(pname, v) -- validates value against per-param range
```

Per-param value ranges (enforced by `check_value`):
- `trigger`: 0-1
- `note`, `octave`, `duration`, `velocity`, `ratchet`, `alt_note`, `glide`: 1-7

### Handler pattern

Every handler follows the same shape:

```lua
handlers["/some/path"] = function(ctx, args)
  -- 1. Validate input
  local t, err = check_track(args)
  if not t then return nil, err end

  -- 2. Execute (delegate to module API or read ctx)
  sequencer.start(ctx)         -- for commands
  return ctx.tracks[t].muted   -- for queries

  -- 3. Mark dirty (commands only)
  ctx.grid_dirty = true
  return true
end
```

### OSC Transport (`lib/remote/osc.lua`)

Thin adapter between the norns/seamstress `osc.event` callback and `api.dispatch`.

```lua
function M.enable(ctx, opts)
  -- Store previous osc.event handler for chaining
  -- Install new osc.event that:
  --   1. Strips configurable prefix from path
  --   2. Calls api.dispatch(ctx, api_path, args)
  --   3. On unknown path, falls through to previous handler
  --   4. Sends reply to caller if opts.reply ~= false
end

function M.disable(ctx)
  -- Restore previous osc.event handler
end
```

Reply format:
- Success: `osc.send(from, path.."/reply", {"ok"})`
- Data (array): `osc.send(from, path.."/reply", flat_values)`
- Data (table): `osc.send(from, path.."/reply", interleaved_key_value_pairs)`
- Error: `osc.send(from, path.."/reply", {"error", message})`

### State Snapshot Structure

The `/state/snapshot` handler returns a deep copy of the full sequencer state:

```lua
{
  playing = false,
  active_track = 1,
  active_page = "trigger",
  tracks = {
    [1] = {
      division = 1,
      muted = false,
      direction = "forward",
      params = {
        trigger = { steps = {1,0,...}, loop_start = 1, loop_end = 16, pos = 1 },
        note    = { steps = {...}, loop_start = 1, loop_end = 16, pos = 1 },
        octave  = { ... },
        duration = { ... },
        velocity = { ... },
        -- extended params: ratchet, alt_note, glide
      }
    },
    [2] = { ... },
    [3] = { ... },
    [4] = { ... },
  }
}
```

## Error Handling

- **Unknown path:** Returns `nil, "unknown path: /foo/bar"`. OSC transport falls through to previous handler.
- **Invalid track number:** Returns `nil, "invalid track (1-4)"`.
- **Invalid step number:** Returns `nil, "invalid step (1-16)"`.
- **Invalid param name:** Returns `nil, "invalid param name"`.
- **Invalid direction mode:** Returns `nil, "invalid direction"`.
- **Division out of range:** Returns `nil, "division must be 1-7"`.
- **Missing arguments:** Returns `nil, "missing value"` or `nil, "missing start/end"`.
- **Value out of range:** Returns `nil, "value out of range (min-max)"` — enforced per param (trigger: 0-1, others: 1-7).
- **Pattern set with wrong count:** Returns `nil, "need 16 values"`.
- **Pattern set with out-of-range value:** Returns `nil, "value out of range (...) at step N"`.
- **Loop start > end:** Returns `nil, "loop start must be <= end"`.
- **Loop bounds out of range:** Returns `nil, "loop bounds must be 1-16"`.
- **OSC with no return address:** Reply silently skipped.

## Acceptance Criteria

### AC1: API dispatch works
**Given** a valid ctx with initialized tracks
**When** `api.dispatch(ctx, "/transport/play")` is called
**Then** returns `true, nil` and `ctx.playing` is true

### AC2: Input validation catches errors
**Given** a valid ctx
**When** `api.dispatch(ctx, "/track/select", {5})` is called (track 5 doesn't exist)
**Then** returns `nil, "invalid track (1-4)"` and ctx is unchanged

### AC3: Queries return data
**Given** a ctx with track 2 muted and division 4
**When** `api.dispatch(ctx, "/track/get", {2})` is called
**Then** returns `{division=4, muted=true, direction="forward"}`

### AC4: State snapshot captures everything
**Given** a ctx with modified state across all tracks
**When** `api.dispatch(ctx, "/state/snapshot")` is called
**Then** returns a table with playing, active_track, active_page, and all 4 tracks with all param step arrays, loop boundaries, and positions

### AC5: Snapshot returns copies
**Given** a state snapshot
**When** the caller modifies values in the returned table
**Then** the original ctx is not affected

### AC6: Grid dirty flag set on commands
**Given** `ctx.grid_dirty = false`
**When** any command handler is dispatched (play, stop, select, mute, set step, etc.)
**Then** `ctx.grid_dirty` is true after dispatch

### AC7: OSC transport routes messages
**Given** OSC remote is enabled with prefix `/re_kriate`
**When** an OSC message arrives at `/re_kriate/transport/play`
**Then** the prefix is stripped and `api.dispatch(ctx, "/transport/play")` is called

### AC8: OSC unknown paths fall through
**Given** OSC remote is enabled with a previous osc.event handler
**When** an OSC message arrives with a path not in the API registry
**Then** the previous handler is called (no swallowed messages)

### AC9: Introspection lists all paths
**Given** the API module is loaded
**When** `api.list_paths()` is called
**Then** returns a sorted array of all registered path strings

### AC10: All unit tests pass
**Given** the test suite at `specs/remote_api_spec.lua`
**When** tests are run via busted
**Then** all tests pass covering transport, track, step, pattern, loop, page, scale, snapshot, dispatch, and introspection

## Testing Strategy

### Layer 1: Unit tests (`specs/remote_api_spec.lua`)

Comprehensive test coverage of the API dispatch layer:
- Transport: play, stop, toggle, reset, state query
- Track: select, mute (toggle + explicit), direction (set + get + invalid), division (set + get + invalid), get info, active query
- Step: set, get, toggle, validation (invalid param, invalid step)
- Pattern: get (returns copy), set (all 16), set validation (too few values)
- Loop: set, get
- Page: select, select validation, active query
- Scale: notes query (returns copy)
- State snapshot: full state, copies not references
- Dispatch: unknown path error, grid dirty on commands
- Introspection: list_paths sorted, contains known paths

All tests use recorder voices and mock norns globals (clock, params, grid, metro, screen, musicutil).

### Layer 2: OSC transport tests (future)

OSC transport is harder to unit test (requires osc.event global). Verify by:
- Code review of prefix stripping and handler chaining logic
- Manual testing with OSC tools (e.g., `oscsend` CLI, TouchOSC)

### Layer 3: Integration (manual)

- Enable OSC remote in the seamstress entrypoint
- Send OSC messages from external tool
- Verify sequencer responds correctly
- Verify replies arrive

## Appendices

### A. Technology Choices

| Choice | Decision | Rationale |
|--------|----------|-----------|
| Dispatch pattern | Path-based with handler table | Natural OSC mapping, extensible, easy to test |
| Validation | Per-handler with shared helpers | Descriptive errors, no silent failures on untrusted input |
| State snapshot | Deep copy returned | Prevents remote callers from corrupting ctx |
| OSC handler chaining | Store/restore previous handler | Plays nicely with other scripts using osc.event |
| Reply format | Path + "/reply" suffix | Standard OSC convention, easy to route in clients |

### B. Future Work

- **Websocket transport** — For web-based remote UIs. Same dispatch, different protocol.
- **MIDI CC transport** — Map CC numbers to API paths for hardware controllers.
- **State subscriptions** — Push state changes to connected clients instead of polling.
- **Pattern bank operations** — Save/load/copy patterns via API.
- **Undo/redo** — Command journaling for remote undo.
- **Multi-client** — Conflict resolution when multiple remotes control the same state.
- **Authentication** — For network-exposed transports.
- **Custom handler registration** — Allow other scripts/modules to register their own paths.
