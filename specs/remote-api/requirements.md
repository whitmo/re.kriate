# Requirements: Remote Control API

Q&A record from requirements clarification.

**Success criterion:** External tools can control the sequencer (play/stop, edit steps, read state) over OSC without touching ctx directly. The API is transport-agnostic so adding new backends (websocket, MIDI CC) requires no changes to the core dispatch.

---

## Q1: What operations should be remotely controllable?

The sequencer has several categories of state: transport (play/stop/reset), track config (mute, direction, division, active track), step data (per-param step values), loop boundaries, page selection, and scale.

(a) Full read/write access to everything — remote UIs can do anything the grid can do
(b) Commands only (play/stop/mute) — read state locally, send actions remotely
(c) Subset — some things are controllable remotely, others are grid-only

**A1:** (a) — Full read/write. The API should expose every sequencer operation. This enables building complete remote UIs (web, tablet, TouchOSC) that don't need a grid at all.

---

## Q2: How should the API be structured?

(a) Path-based dispatch (like OSC/REST) — `/transport/play`, `/track/mute`, `/step/set`
(b) Method-based — `api.play()`, `api.set_step(track, param, step, val)`
(c) Event-based — push state changes as events, pull commands from a queue

**A2:** (a) — Path-based dispatch. Natural fit for OSC (paths map 1:1), works for any protocol that can express "verb + args". Single `dispatch(ctx, path, args)` entry point. Handlers registered in a table keyed by path string.

---

## Q3: What transports should be supported initially?

(a) OSC only — norns and seamstress both have OSC support
(b) OSC + websocket — covers both embedded (OSC) and web (ws) clients
(c) OSC + MIDI CC — covers embedded and hardware controllers

**A3:** OSC first. The API layer is transport-agnostic, so websocket/MIDI CC transports can be added later without changing the core. OSC is the natural choice for norns/seamstress and has mature tooling (TouchOSC, Max/MSP, SuperCollider).

---

## Q4: Should the API support replies/responses?

Remote clients may want to query state (e.g., "what step is the playhead on?"). Options:

(a) Fire-and-forget — commands only, no responses. Clients subscribe to state updates separately.
(b) Request-reply — dispatch returns a value, transport sends it back to the caller.
(c) Both — commands return success/error, queries return data. Transport decides whether/how to send replies.

**A4:** (c) — Both. Commands return `true` on success, queries return data. The transport layer decides how to send replies (OSC reply messages, websocket responses, etc.). Error returns are `nil, error_message`.

---

## Q5: How does the API interact with the ctx pattern?

The CLAUDE.md convention says all state lives in ctx and modules receive it through the call chain.

(a) Handlers receive ctx directly — `handler(ctx, args)`
(b) Handlers go through module APIs — e.g., call `sequencer.start(ctx)` instead of setting `ctx.playing = true`
(c) Mix — use module APIs where they exist, touch ctx directly for simple state reads

**A5:** (c) — Mix. Use existing module APIs for operations (sequencer.start/stop/reset, track_mod.set_step/set_loop/toggle_step) to keep behavior consistent. Read ctx directly for queries (ctx.playing, ctx.active_track, ctx.tracks[t].params). This way the API doesn't duplicate logic and stays in sync with grid/keyboard behavior.

---

## Q6: How should the API validate input?

Remote input is untrusted (comes from network). How strict should validation be?

(a) Strict — validate every argument, return descriptive errors
(b) Minimal — check bounds, let Lua errors propagate for edge cases
(c) No validation — trust the caller, crash on bad input

**A6:** (a) — Strict validation. Track numbers, step numbers, param names, direction modes, division ranges — all checked before touching ctx. Error messages should be useful for debugging (e.g., "invalid track (1-4)" not just "error").

---

## Q7: Should the API support bulk state snapshots?

For building remote UIs, clients need to sync full state on connect.

(a) Yes — `/state/snapshot` returns everything a remote UI needs to render
(b) No — clients query individual paths to build their view
(c) Snapshot + subscriptions — snapshot on connect, then incremental updates

**A7:** (a) for now. `/state/snapshot` returns the full sequencer state (all tracks, all params, all step values, play state, active track/page). Subscriptions/incremental updates are future work.

---

## Summary

1. **Transport-agnostic API** with path-based dispatch — single `dispatch(ctx, path, args)` entry point
2. **Full read/write access** — transport, track, step, pattern, loop, page, scale, state snapshot
3. **OSC transport first** — natural fit for norns/seamstress, 1:1 path mapping
4. **Request-reply** — commands return true/error, queries return data
5. **Strict validation** — all remote input validated with descriptive error messages
6. **Uses existing module APIs** — sequencer.start/stop, track_mod.set_step, etc.
7. **State snapshot** — `/state/snapshot` for remote UI initialization
