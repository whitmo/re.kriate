# Seamstress v2 (2.0.0-alpha) API Availability

Verified from source at ryleelyman/seamstress (main branch) and local install.

## Confirmed available modules (embedded in binary)

### Core (lua/core/)
- `clock` — clock.run, clock.sync, clock.sleep, clock.cancel (Zig backend: src/clock.zig)
- `midi` — midi.connect, note_on/note_off/cc etc. (Zig backend: src/midi.zig)
- `metro` — metro.init, start/stop (Zig backend: src/metros.zig)
- `grid` — grid.connect, g:led, g:all, g:refresh, g.key callback (Zig backend: src/monome.zig)
- `arc` — arc.connect etc.
- `osc` — osc.send, osc.event, osc.register (Zig backend: src/socket.zig)
- `screen` — full color SDL screen (Zig backend: src/screen_inner_SDL.zig)
  - screen.clear, screen.move, screen.text, screen.color(r,g,b,a), screen.level(0-15)
  - screen.rect, screen.rect_fill, screen.circle, screen.circle_fill
  - screen.key(char, modifiers, is_repeat, state) — keyboard input
  - screen.click(x, y, state, button) — mouse clicks
  - screen.mouse(x, y) — mouse movement
  - screen.wheel(x, y) — scroll wheel
  - screen.set_size(w, h, z) — resizable
  - screen.new_texture, screen.new_texture_from_file — texture support
- `params` — paramset with add_number, add_option, add_control, add_binary, add_separator
  - Note: no add_taper or add_file
  - params:lookup_param available
- `controlspec` — control specs for params
- `pmap` — parameter mapping

### Lib (lua/lib/)
- `musicutil` — scales, note names, intervals
- `lattice` — division-based sprockets
- `sequins` — pattern sequencing
- `util` — util.clamp, util.wrap, etc.
- `tabutil` — table utilities (global `tab`)
- `lfo` — LFO library
- `pattern_time` — gesture recorder
- `filters` — filter utilities
- `formatters` — param formatters
- `ui` — UI utilities

## Script loading
- seamstress loads `lua/core/seamstress.lua` which sets up all globals
- User script is then loaded and `init()` is called
- `require` paths include the script's directory (set by seamstress.state.path)
- Script directory must be correct for relative requires to work

## Key difference from norns
- No `engine`, `softcut`, `crow`, `hid`, `keyboard` modules
- No `nb` library
- Screen is 256x128 default (vs 128x64 on norns), full color, resizable
- No physical keys/encoders — use screen.key/click/mouse instead
- print() output goes to seamstress GUI console, not stdout

## Path issue
When running `seamstress /path/to/script.lua`, the script's directory is added to package.path so `require("lib/app")` works. The earlier failure was from running the script from the wrong CWD.
