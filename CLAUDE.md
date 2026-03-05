# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

re.kriate is a norns sequencer script inspired by kria (the Monome Ansible sequencer). It is a Lua-based script for the [monome norns](https://monome.org/docs/norns/) sound computer platform.

Reference implementations:
- [monome/ansible](https://github.com/monome/ansible) — original kria firmware (C, for Ansible eurorack module)
- [zjb-s/n.kria](https://github.com/zjb-s/n.kria) — another norns kria port
- [Dewb/monome-rack](https://github.com/Dewb/monome-rack/tree/main/firmware) — VCV Rack port of monome firmware

## Coding Standards

### No custom globals

Globals are reserved exclusively for the norns API hooks (`init`, `redraw`, `key`, `enc`, `cleanup`). All custom logic lives in modules that are `include`'d or `require`'d, and the global hooks in the main script file should be thin wrappers that delegate to those modules.

### State via context object

Do not store application state in globals or module-level variables scattered across files. Pass a single context table (e.g. `ctx`) through the call chain. Modules receive and operate on this context rather than reaching for global or upvalue state. This keeps state ownership explicit and makes the code testable.

```lua
-- re_kriate.lua (main script)
local app = require("lib/app")

local ctx

function init()
  ctx = app.init()
end

function redraw()
  app.redraw(ctx)
end

function key(n, z)
  app.key(ctx, n, z)
end

function enc(n, d)
  app.enc(ctx, n, d)
end

function cleanup()
  app.cleanup(ctx)
end
```

## Norns Development

### Script structure

Norns scripts are written in Lua. The norns runtime calls these global callbacks:
- `init()` — called on script load
- `redraw()` — draws to the norns screen (128x64 OLED)
- `key(n, z)` — physical key input (n=key number 1-3, z=0/1 for up/down)
- `enc(n, d)` — encoder input (n=encoder number 1-3, d=delta)
- `cleanup()` — called on script unload

These are the only globals we define. All other code uses modules (see Coding Standards above).

### Running on norns

Scripts live in `~/dust/code/<script-name>/` on the norns device. The main file is typically `<script-name>.lua` at the root of that directory. Maiden (the norns web IDE at `http://norns.local/maiden`) or SSH can be used to transfer files.

### Key norns APIs

- `screen` — drawing (screen.level, screen.move, screen.text, screen.line, screen.rect, etc.)
- `params` — parameter system with MIDI mapping (params:add_number, params:add_option, etc.)
- `clock` — coroutine-based timing (clock.run, clock.sleep, clock.sync)
- `midi` — MIDI I/O
- `grid` — monome grid (128 or 64 button LED grid) interaction via `grid.connect()`
- `crow` — Crow eurorack module I/O
- `engine` — SuperCollider engine loading and control
- `musicutil` — music theory utilities (scales, note names, intervals)

### Grid integration

Kria is fundamentally a grid-based sequencer. Grid connection and callbacks are set up inside `init` and stored on the context:
```lua
function M.init()
  local ctx = { ... }
  ctx.g = grid.connect()
  ctx.g.key = function(x, y, z) M.grid_key(ctx, x, y, z) end
  return ctx
end
```

### Kria concepts

Kria is a multi-track step sequencer where each track has independent loop lengths for different parameters (note, octave, duration, trigger, velocity, etc.). Key design elements:
- Per-parameter loop lengths (polymetric sequencing)
- Multiple tracks (typically 4)
- Pattern storage and recall
- Clock division per track
- Scale quantization
