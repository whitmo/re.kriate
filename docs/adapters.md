# Adapter Boundaries

**Date**: 2026-07-11
**Status**: adopted — all three boundaries implemented with worked examples
**Related**: `docs/event-layers.md` (the event model these boundaries plug into), `lib/voice_registry.lua`, `lib/behavior.lua`, `lib/platform.lua`

re.kriate has three integration axes. Each has one boundary module, one
contract, and one recipe. If integrating something requires editing
`lib/app.lua`, `lib/sequencer.lua`, or `lib/grid_ui.lua`, the boundary has
failed — file it as a bug.

```
                 ┌─────────────────────────────────────────┐
 controllers ──▶ │  cmd:* behavioral events (lib/behavior)  │ ──▶ instruments
 (input side)    │        the sequencer core inside         │    (output side)
                 └─────────────────────────────────────────┘
                        runs on: norns | seamstress | standalone
                              (lib/platform boundary)
```

## 1. Instruments (`lib/voice_registry.lua`)

An instrument is anything that can sound a note. The registry mirrors
`lib/grid_provider.lua`'s register/connect pattern.

**Contract**: a factory `(ctx, track) -> voice` returning an object with the
required methods `play_note(note, vel, dur)` and `all_notes_off()`. Optional
capabilities (`set_level`, `set_pan`, `set_portamento`, `note_on`,
`note_off`, `set_target`, `set_synthdef`, `grab`, `apply_config`) are
guarded by callers — implement what makes sense, skip the rest. The factory
reads its own configuration from params. Validation happens at `create()`
time; a broken voice is rejected with a clear error, not a mid-performance
crash.

**Recipe**:
```lua
local voice_registry = require("lib/voice_registry")
voice_registry.register("my_synth", function(ctx, track)
  return {
    play_note = function(self, note, vel, dur) --[[ sound it ]] end,
    all_notes_off = function(self) --[[ silence ]] end,
  }
end)
```
Done — "my_synth" appears in every track's voice params menu. Registration
order is load-bearing for the six built-ins (presets store the option
index); custom instruments append after them.

**Notes are also commands**: `cmd:note:play {track, note, vel, dur}` sounds
the track's voice through the behavioral layer, so an arpeggio expansion, a
remote OSC message, or a voice-command interface can play notes without
touching a voice object (see `docs/event-layers.md`, Voice behavior).

## 2. Controllers (`lib/behavior.lua` — the cmd:* vocabulary)

A controller is anything that produces user intent: the monome grid, the
computer keyboard, a Push 2, OSC remotes — and, by design, future voice
commands, TUIs, or knob/slider boxes.

**Contract**: a controller adapter *emits behavioral commands*
(`ctx.events:emit("cmd:transport:play", {})`) and never calls sequencer/
pattern/mixer functions directly. `behavior.wire_commands` (installed by
`app.init`) is the single junction that performs commands. The full command
vocabulary is `behavior.VOCAB` (validated by `specs/behavior_spec.lua`).

For *hardware grids specifically* there is a second, lower-level plug:
`lib/grid_provider.lua` (`register(name, factory)`) adapts a device to the
16x8 LED/key surface (monome, Push 2, Launchpad Pro, midigrid, simulated,
synthetic all live there). Gesture classification (`lib/button_events.lua`)
and grid-context resolution (`lib/ui_spec.lua`) sit between raw grid keys
and command emission.

**Recipe** (a two-button foot pedal, say):
```lua
my_pedal.on_press = function(button)
  if button == 1 then
    ctx.events:emit(ctx.playing and "cmd:transport:stop" or "cmd:transport:play", {})
  else
    ctx.events:emit("cmd:transport:reset", {})
  end
end
```

**Worked example in-tree**: `lib/seamstress/keyboard.lua`'s transport keys
(space/r) are the first migrated adapter — they emit `cmd:transport:*` and
keyboard.lua no longer requires the sequencer at all. The remaining
surfaces (grid transport-adjacent paths, remote api handlers, params
actions) migrate incrementally — checklist in `.ralph/agent/feature-queue.md`,
"Event-layer migration".

## 3. Execution environments (`lib/platform.lua`)

An environment is whatever hosts the Lua process and provides (or doesn't)
params/clock/metro/midi/grid/screen/osc.

| environment | entrypoint | host services |
|---|---|---|
| norns | `re_kriate.lua` | norns runtime globals, nb voices |
| seamstress | `seamstress.lua` | seamstress v1 globals, simulated grid window |
| standalone | `standalone.lua` | none — `platform.prepare_standalone()` stubs |

**Contract**: `platform.detect()` names the environment;
`platform.capabilities()` probes individual services so shared code asks
"is there a screen?" rather than "am I on norns?". A new environment's
entrypoint provides (or stubs) the host services, then calls `app.init` —
the entire core (data model, params, behavioral layer, grid providers,
voice registry) is host-agnostic above this line.

**Worked example in-tree**: `lua standalone.lua` boots the full app in a
bare Lua process — real params registry, live behavioral commands, real
scale quantization (platform ships a genuine pure-Lua musicutil), recorder
voices reporting what would have sounded — and exits nonzero on failure,
so it doubles as a smoke test. There is no realtime clock in bare Lua;
sequencing advances by manual stepping (`sequencer.step_track`), the same
mechanism the params-menu advance triggers use. A realtime standalone
scheduler is future work and slots in behind the same boundary.

## How the axes compose

A session on any environment, from any controller, into any instrument, is
the same five hops:

```
raw input → interface adapter → cmd:* event → wire_commands → module
                                                     │
                                          facts (sequencer:step,
                                           voice:note, …) → any consumer
```

The test suite enforces each boundary: `specs/voice_registry_spec.lua`
(instrument contract + a custom instrument integrated in-test),
`specs/behavior_spec.lua` (command vocabulary, wiring, stacking),
`specs/keyboard_spec.lua` (adapter contract: keys work *by emitting*),
`specs/platform_spec.lua` (the real `app.init` booting on a wiped host
surface), plus `specs/ui_spec_spec.lua`/`specs/button_events_spec.lua` for
the grid path.
