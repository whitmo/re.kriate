# Dual-Platform Patterns: norns + seamstress

Research into how existing scripts handle running on both norns and seamstress.

## Key Finding: Nobody Does True Dual-Platform

There are no known scripts that run unmodified on both norns and seamstress from the same codebase with a single entrypoint. The community pattern is **separate entrypoints with shared core logic**. The official monome documentation does not recommend an architectural pattern for cross-platform code; it simply documents the differences.

## Case Study: meadowphysics

The most instructive example. monome maintains two separate repos:

- **norns version**: [alpha-cactus/meadowphysics](https://github.com/alpha-cactus/meadowphysics) -- `mp_midi.lua` as entrypoint
- **seamstress version**: [monome/meadowphysics-seamstress](https://github.com/monome/meadowphysics-seamstress) -- `meadowphysics.lua` as entrypoint

### What is shared

The core sequencer logic (`lib/meadowphysics.lua`) is essentially the same module in both versions. It has no platform dependencies -- it is pure data/logic operating on tables. The `lib/gridscales.lua` module is also shared. This is the key architectural insight: **the sequencer engine is platform-agnostic**.

### What differs

Everything else is separate:

| Concern | norns | seamstress |
|---------|-------|------------|
| Entrypoint | `mp_midi.lua` | `meadowphysics.lua` |
| Grid handling | inline in entrypoint | `lib/grid.lua` |
| Screen drawing | inline `redraw()` | `lib/screen.lua` (with shims) |
| Clocking | `BeatClock` library | `lib/clocking.lua` (transport callbacks) |
| Audio output | `engine.hz(f)` (PolyPerc) | MIDI only |
| Input | key/enc callbacks | `screen.key`, `screen.click`, `screen.wheel` |
| Data path | hardcoded `/home/we/dust/code/...` | `path.seamstress .. "/data/" .. seamstress.state.name` |
| Module loading | `require "meadowphysics/lib/..."` | `include("lib/...")` |

### Screen Shims in meadowphysics-seamstress

The seamstress version's `lib/screen.lua` contains norns-to-seamstress compatibility shims that override default seamstress screen functions:

```lua
-- norns-to-seamstress helpers //
screen.move = function(x, y)
    _seamstress.screen_move(x + 5, y + 5)
end

screen.rect = function(x, y, w, h)
    screen.move(x, y)
    screen.rect_fill(w, h)
end

screen.line = function(x, y)
    _seamstress.screen_line(x + 5, y + 5)
end
-- // norns-to-seamstress helpers
```

This makes the `redraw()` function callable with norns-style `screen.rect(x, y, w, h)` (4 args, position + size) even though seamstress natively uses `screen.rect(w, h)` (2 args, size only, at current position). The +5 offset accounts for a border the seamstress version adds around the screen area.

## Platform Differences That Matter

### Fully Compatible APIs (same syntax, same behavior)

- `grid` -- grid connection, `g.key`, `g:led`, `g:refresh`
- `midi` -- MIDI device connection, note_on/off, CC
- `osc` -- OSC send/receive
- `clock.run`, `clock.sync`, `clock.sleep`, `clock.cancel`, `clock.get_tempo`
- `metro` -- high-resolution timer
- `params` -- core API is compatible (add_number, add_option, add_binary, set, get, delta, bang)
- `musicutil` / `mu` -- note/scale utilities
- `util` -- clamp, round, etc.
- `tab` / `tabutil` -- table utilities
- `controlspec` -- parameter range specs

### Substantially Different APIs

**Screen:**
- norns: 128x64 monochrome, 16 brightness levels (0-15), `screen.level(v)`
- seamstress: resizable, full-color, `screen.color(r,g,b,a)` and `screen.level(v)` (which maps to grayscale)
- norns: `screen.rect(x, y, w, h)` then `screen.fill()` or `screen.stroke()`
- seamstress: `screen.move(x,y)` then `screen.rect_fill(w, h)` -- no separate stroke/fill step
- seamstress adds: `screen.set_size()`, `screen.set_position()`, mouse/keyboard callbacks
- norns has: `screen.font_face()`, `screen.font_size()`, image/PNG support

**Input:**
- norns: `key(n, z)` and `enc(n, d)` globals (physical buttons/knobs)
- seamstress: `screen.key(char, modifiers, _, state)` for keyboard, `screen.click(x, y, state, button)` for mouse, `screen.wheel(x, y)` for scroll -- completely different paradigm

**Audio:**
- norns: `engine` (SuperCollider), `softcut` (tape loops), `poll`
- seamstress: none -- MIDI/OSC only

**params differences:**
- seamstress adds `allow_pmap` argument to param constructors
- seamstress is missing `params:add_taper` and `params:add_file`
- `params:add_separator(id, name)` works on both (seamstress accepts same signature)
- `params:add({ type = "option", ... })` table syntax works on both

**Module loading:**
- norns: `include("lib/foo")` resolves relative to script dir; `require` for system libs
- seamstress v1: `include("lib/foo")` also resolves relative to script dir (inspired by norns)
- Both support `require` for standard Lua modules

### Platform Detection

There is no official cross-platform detection API. Practical detection approaches:

```lua
-- Option 1: Check for the _seamstress global (set by seamstress runtime)
local is_seamstress = (_seamstress ~= nil)
local is_norns = (_norns ~= nil)

-- Option 2: Check for the seamstress state table
local is_seamstress = (seamstress ~= nil and seamstress.state ~= nil)

-- Option 3: Check for norns-specific globals
local is_norns = (norns ~= nil and norns.state ~= nil)

-- Option 4: Check path globals
local is_seamstress = (path ~= nil and path.seamstress ~= nil)
```

The `_seamstress` and `_norns` tables are the low-level C/Zig bindings injected by each runtime before any Lua code runs. They are the most reliable detection mechanism.

## seamstress v1 vs v2

**seamstress v1** ([robbielyman/seamstress-v1](https://github.com/robbielyman/seamstress-v1)) is the stable version that meadowphysics-seamstress targets. It has close API parity with norns for grid, midi, clock, metro, params, and util.

**seamstress v2** ([robbielyman/seamstress](https://github.com/robbielyman/seamstress)) is alpha software with a significantly different architecture. It uses a new event system (`seamstress.event`) and async primitives. The screen, grid, and other APIs may differ from v1. For now, target v1.

## Transport / Clocking

seamstress v1 has `clock.transport.start` and `clock.transport.stop` as system callbacks that fire on external transport messages. The meadowphysics-seamstress version uses these to bridge external clock sources:

```lua
function clock.transport.start()
    params:set("transport_control", 0)
    params:set("transport_control", 1, true) -- silent
    transport("start")
end
```

norns handles transport through the clock system differently (BeatClock library, or the built-in clock source system). Both platforms support `clock.run(fn)` with `clock.sync(beats)` inside coroutines.

## Practical Patterns for re.kriate

Based on this research, the recommended approach:

### 1. Separate entrypoints, shared core

```
re_kriate.lua              -- norns entrypoint (globals: init, redraw, key, enc, cleanup)
re_kriate_seamstress.lua   -- seamstress entrypoint (globals: init, redraw, cleanup)
lib/
  app.lua                  -- platform-agnostic app logic (ctx pattern)
  sequencer.lua            -- pure sequencer engine (no platform deps)
  track.lua                -- track data/logic
  ...
```

### 2. Platform adapter modules

Instead of shimming the screen API to look like norns, create adapter modules that the entrypoints configure:

```lua
-- norns entrypoint
local app = require("lib/app")
local ctx
function init()
    ctx = app.init({ platform = "norns" })
end

-- seamstress entrypoint
local app = include("lib/app")
local ctx
function init()
    ctx = app.init({ platform = "seamstress" })
end
```

### 3. Keep the sequencer engine pure

The meadowphysics pattern proves this works: `lib/meadowphysics.lua` has zero platform dependencies. It operates on plain Lua tables and calls event callbacks. Our sequencer core (tracks, step advancing, loop lengths, pattern storage) should be similarly isolated.

### 4. Grid code is naturally portable

Grid API is identical on both platforms. Grid interaction code can be shared directly with no adaptation needed.

### 5. Screen code needs separate implementations

Do not try to write a universal screen abstraction. The paradigms are too different (128x64 mono vs resizable color, keys/encoders vs mouse/keyboard). Write separate screen modules for each platform, both reading from the same ctx state.

### 6. MIDI/OSC output is portable

Both platforms have identical MIDI and OSC APIs. Output code can be shared.

## Sources

- [monome/meadowphysics-seamstress](https://github.com/monome/meadowphysics-seamstress) -- official seamstress port
- [alpha-cactus/meadowphysics](https://github.com/alpha-cactus/meadowphysics) -- original norns version
- [seamstress and norns](https://monome.org/docs/grid/studies/seamstress/seamstress-and-norns/) -- official comparison docs
- [seamstress v1](https://github.com/robbielyman/seamstress-v1) -- seamstress v1 source (stable)
- [seamstress v2](https://github.com/robbielyman/seamstress) -- seamstress v2 source (alpha)
- [seamstress lines thread](https://llllllll.co/t/seamstress-is-a-lua-scripting-environment-for-musical-communication/64556) -- community discussion
- [Grid Studies: Seamstress](https://monome.org/docs/grid/studies/seamstress/) -- seamstress grid tutorial
- [norns core/norns.lua](https://github.com/monome/norns/blob/main/lua/core/norns.lua) -- norns runtime globals
