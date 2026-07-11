# Event Layers

**Date**: 2026-07-11
**Status**: adopted — `lib/behavior.lua` implements L1 commands + L2 stacking; migration of existing surfaces is incremental
**Related**: `lib/behavior.lua` (vocabulary + wiring + stacking), `lib/button_events.lua` (gesture classification), `lib/ui_spec.lua` (grid nav/body declarations), `specs/behavior_spec.lua`

## The model

Three layers, each ignorant of the layers above it:

```
L0  interface events    raw input, one adapter per interface
                        grid keys · keyboard chars · mouse clicks · OSC
                        [future: voice commands · TUI · knob/slider controllers]
                              │
                              │  adapter translates gesture+context → command
                              ▼
L1  behavioral events   the sequencer vocabulary, on the ctx.events bus
                        two moods:
                          commands  "cmd:" prefix — requests to act
                                    cmd:transport:play, cmd:pattern:load,
                                    cmd:track:set_mute, cmd:note:play, …
                          facts     no prefix — what happened / emerged from
                                    state+clock: sequencer:step, voice:note,
                                    pattern:cue_applied, meta:step, …
                              │
                              │  behavior.define(): expansion, re-emission
                              ▼
L2  abstract events     compositions over L1 (and other L2) events
                        song:start · section:change (intro/verse/chorus/
                        bridge/break) · fill · arp:play — pure vocabulary,
                        no new plumbing
```

**The grid is just one interface.** Nothing behavioral may live in an
interface adapter. An adapter's whole job is: classify the gesture
(`lib/button_events.lua`: press / double_press / combo / hold), resolve it in
context (`lib/ui_spec.lua` for the grid: which page is active, which modifier
is held), and emit an L1 command. A voice-command listener that hears "play"
emits `cmd:transport:play` — the same event the grid, keyboard, TUI, or a
MIDI pedal would emit — and the sequencer cannot tell who sent it.

**Commands vs facts is a hard distinction.** A command (`cmd:` prefix)
requests an action and has exactly one subscriber that performs it
(`behavior.wire_commands`). A fact reports that something already happened —
state mutated, or something emerged from clock+state (a step fired, a cue
applied at a loop boundary). Facts fan out to any number of consumers
(screen, sprites, hardware LEDs, remote bridges) and must never be load-bearing
for sequencing correctness.

Because the events bus matches wildcards on the first-colon prefix, one
subscription — `bus:on("cmd:*", …)` — observes the entire resolved command
stream regardless of source interface. That is the seam for a macro recorder,
an undo log, a command monitor in the side panel, or an OSC bridge that
forwards commands to a second machine.

**Abstract events expand, they don't implement.** `behavior.define(bus,
"section:break", {…})` registers an expansion: when `section:break` is
emitted, its constituent `cmd:*` events are re-emitted. Expansions nest
(song → section → commands), read their triggering payload (an arpeggio
computing notes from its root), and are depth-guarded against accidental
cycles. Crucially, a `cmd:*` subscriber sees identical traffic whether a
human pressed four buttons or one `song:start` fired — abstract events are
*macros in the vocabulary*, not new machinery.

## Voice behavior: same principles

Voices are output-side interface adapters. Today (2026-07-11 inventory) every
voice is driven by direct duck-typed method calls — zero voice backends
subscribe to the bus — and `voice:note` is a fire-and-forget fact with no
consumers. Direction:

- **Anything that can emit an event can play a note.** `cmd:note:play` is
  wired (behavior.wire_commands → `sequencer.play_note` → voice, emitting the
  `voice:note` fact). An L2 arpeggio is an expansion into `cmd:note:play`
  events; a voice-command interface saying "give me a C major chord" is three
  of them. No caller touches a voice object.
- **The step pipeline stays direct-call for timing.** `sequencer.step_track`
  calls voices synchronously inside the clock coroutine; routing per-step
  note dispatch through the bus would add indirection in the hot path for no
  behavioral gain. The bus carries the *facts* about what played.
- **Known gap** (from the inventory): ratcheted steps produce N `play_note`
  calls but only one `voice:note` fact. If the fact stream is to be a
  faithful behavioral record (macro recording, visualization), the fact
  should fire per sounding, not per step. Tracked in feature-queue.md.

## What the 2026-07-11 inventory found (why this layer is needed)

The full inventories are in the session record; the headline is
**fragmentation**: the same behavioral action is reachable through divergent
code paths that disagree about events:

| Action | Paths today | Event behavior |
|---|---|---|
| transport start | 6 (space key, K2, `/transport/play`, help console, params, MIDI Start) | consistent fact, but MIDI Start also resets playheads and nothing else does |
| mute | 5 writers | 2 different fact names (`track:mute`, `mixer:mute`) + 2 silent paths |
| track/page select | 4+ writers | only the grid emits facts; keyboard/remote/encoders are silent |
| pattern load | 3 writers | fact emission depends on which caller you used |
| direction/division/swing | 4 writers | zero events, no params sync-back |
| scale root/type | 2 writers | the one command-intent precedent: grid emits, app.lua subscriber does the work |

The migration is incremental and non-breaking: surfaces move one at a time
from calling modules directly to emitting `cmd:*` events (keyboard first —
it's the simplest adapter), and facts consolidate on one name per action.
`lib/remote/api.lua` remains useful as a transport that translates OSC paths
into the same commands.

## Vocabulary

The authoritative catalog is `behavior.VOCAB` in `lib/behavior.lua` — layer,
mood, payload fields, and implementation status per event —
validated by `specs/behavior_spec.lua`, including a drift alarm asserting
every event name emitted anywhere in `lib/` is cataloged. Don't duplicate the
table here; read the code.

Planned-but-unwired entries declared so interfaces can target them now:
`cmd:transport:pause`, `cmd:option:change`, `cmd:reset:pattern`,
`cmd:reset:time`, `cmd:load:preset`, `cmd:save:state`, `app:ready`, and the
L2 examples (`song:start`, `song:stop`, `section:change`, `fill`,
`arp:play`).

## Worked examples (all in specs/behavior_spec.lua, all green)

- `section:break` — static expansion muting tracks 2-4
- `arp:triad` — functional expansion reading its root note, emitting three
  `cmd:note:play` events, captured by a real recorder voice
- `song:start` — two-level stack (`section:intro` inside it), driving the
  real sequencer + pattern modules end-to-end through `wire_commands`
- cycle guard — a self-referencing definition stops at `MAX_DEPTH`
