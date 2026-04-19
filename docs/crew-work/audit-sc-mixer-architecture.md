# SC Mixer Architecture Audit

Date: 2026-04-13

Files reviewed:
- `sc/rekriate-mixer.scd`
- `sc/rekriate-voice.scd`
- `lib/mixer.lua`
- `lib/app.lua`
- `lib/grid_ui.lua`
- `lib/pattern_persistence.lua`
- `specs/015-sc-mixer/spec.md`
- `/Users/whit/src/gastown/rekriate/crew/whitmo/docs/projects/sc-mixer-spec.md`

---

## Verdict

The current **signal topology is mostly correct for SuperCollider** after the move to a dedicated internal master sum bus:

- voice synths write to per-channel buses
- channel strips run after voices
- aux runs after channels
- master runs after aux
- master reads `~mixerBuses[\masterSum]` and writes to hardware out

That is the topology I would keep. It is better than the earlier "sum on bus 0, then `ReplaceOut` bus 0" design because it avoids treating the hardware bus as an internal mix bus.

The main architectural issues now are:

1. `filter_res` exists in the API but is ignored in the SynthDef.
2. The aux send tap is labeled "pre-fader" but is actually **pre-insert except for the filter**.
3. The delay loops are structurally valid, but they need clearer semantics and damping.
4. The Lua side has drifted away from the SC contract in ways that will break metering and persistence.

---

## 1. SynthDef Topology

### What is correct

- Bus allocation in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:17) is sensible: 4 stereo channel buses, aux send, aux return, and an internal `masterSum`.
- Group ordering in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:25) is correct for SC: `voices -> channels -> aux -> master`.
- Channel strips write to `masterSum`, not directly to hardware, in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:176). That is the right SC pattern.
- Voice routing in [`sc/rekriate-voice.scd`](/Users/whit/src/re.kriate/sc/rekriate-voice.scd:133) is directionally correct: `\out` is set to the channel bus when the mixer exists, with a fallback to bus `0`.

### What I would change

- Do **not** go back to the spec's original `In.ar(0)` + `ReplaceOut.ar(0)` master topology. Once `masterSum` exists, the master synth should read `masterSum` and `Out.ar(0, sig)` exactly as it does now.
- Split `~mixerGroups[\voices]` into **per-channel voice subgroups** under the voices group. That makes ephemeral/polyphonic voices easier to manage:
  - `~mixerGroups[\voiceChannels] = Array.fill(CHANNELS, { Group.head(~mixerGroups[\voices]) });`
  - spawn every short-lived synth into its channel's subgroup
  - `all_notes_off` becomes `group.freeAll`
- Keep the conceptual distinction explicit:
  - sequencer has `TRACKS`
  - mixer has `CHANNELS`
  - add a `trackToChannel` mapping table even if it is initially `{1,2,3,4}`

---

## 2. UGen Choices

### Filter

The current filter stage in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:53) uses `HPF` / `LPF`, so `filter_res` is unused. That is the biggest UGen mismatch in the channel strip.

Use one of these instead:

- `RHPF` / `RLPF` if you want simple resonant filter behavior with low complexity
- `SVF` if you want one filter family with more consistent behavior and room to expand modes later

For this codebase, `RHPF` / `RLPF` is the pragmatic choice.

### Reverb

`FreeVerb2` is acceptable for a first pass and is a reasonable CPU tradeoff on a small mixer. I would keep it on the **aux** path.

For per-channel insert reverb, I would be cautious:

- four `FreeVerb2` instances can get muddy fast
- the shared aux already covers the main "space" use case

If insert reverb remains a requirement, keep it subtle and default-dry.

### Master Protection

`tanh` in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:140) is a soft saturator, not a true limiter. If the requirement is "never clips," use:

- `Limiter.ar` for actual peak containment
- optionally `tanh` before or after it for color

Practical chain:

```supercollider
sig = LeakDC.ar(sig);
sig = tanh(sig);
sig = Limiter.ar(sig, 0.98, 0.01);
```

### Metering

`Amplitude.kr` is fine for "activity" meters, but it is not a peak meter. If the grid should behave like a mixer meter, prefer:

- `PeakFollower.ar` or `Peak.kr` for level capture
- then downsample to `SendReply`

More importantly, the current Lua parsing of `SendReply` is wrong. `SendReply` includes `nodeID` and `replyID` before the values, so the handler in [`lib/mixer.lua`](/Users/whit/src/re.kriate/lib/mixer.lua:90) will not decode the SC payload correctly.

---

## 3. Delay Feedback

### Aux delay

The aux delay in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:108) is **structurally sound**:

- one synth instance
- `LocalIn` / `LocalOut`
- feedback clipped below runaway
- `LeakDC`
- mild saturation in the loop

That is a good place to use a real feedback loop.

What I would still add:

- a low-pass filter in the feedback path so repeats darken
- optional high-pass/DC cleanup before the write-back

Example:

```supercollider
feedback = LPF.ar(feedback, 6000);
LocalOut.ar(LeakDC.ar(feedback.tanh));
```

### Per-channel delay

The per-channel insert delay in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:66) is also valid SC, but it is a different design choice than the repo spec in [`specs/015-sc-mixer/spec.md`](/Users/whit/src/re.kriate/specs/015-sc-mixer/spec.md:103), which called for `CombL` to avoid per-instance feedback state.

My view:

- for only 4 channels, `LocalIn` / `LocalOut` per strip is acceptable
- if you keep it, add `LeakDC` and damping in the channel feedback path too
- if you want a cheaper, more obviously bounded implementation, switch the channel insert to `CombL` and rename the control from `delay_feedback` to something decay-oriented

Right now the parameter name implies a literal feedback coefficient, so the current feedback-loop implementation is the more semantically honest version.

### Send tap position

The aux send currently taps `filtered * send` in [`sc/rekriate-mixer.scd`](/Users/whit/src/re.kriate/sc/rekriate-mixer.scd:95). That means:

- post-filter
- pre-insert-reverb
- pre-insert-delay
- pre-compressor
- pre-fader/mute/pan

That is not what most readers will assume from "pre-fader send." I would choose one of these and document it explicitly:

- **post-insert, pre-fader**: my recommendation
- pre-insert, pre-fader: acceptable, but then name it that way

---

## 4. Voice-To-Bus Routing For Ephemeral Synths

For short-lived synths, the right pattern is:

1. each mixer channel owns a stereo audio bus
2. each mixer channel also owns a voice subgroup under `~mixerGroups[\voices]`
3. every ephemeral synth is spawned with `\out` set to its channel bus
4. the synth uses `doneAction: 2` and frees itself

That keeps routing trivial because the bus is the sum point, not the node.

Recommended shape:

```supercollider
~mixerGroups[\voiceChannels] = Array.fill(CHANNELS, {
    Group.head(~mixerGroups[\voices])
});

Synth.tail(~mixerGroups[\voiceChannels][channelIndex], \some_voice, [
    \out, ~mixerBuses[\channels][channelIndex],
    ...
]);
```

For one-shots and tight transients, prefer `OffsetOut.ar` in the voice SynthDef over `Out.ar`. It reduces block-boundary timing error and is a better default for ephemeral event-driven synths.

For track-oriented control:

- keep `track -> channel` mapping in Lua or sclang state
- route note events by track, but resolve to a channel bus at spawn time
- if a track changes channel assignment later, only new synths use the new bus; existing synths can die naturally or be cleared by subgroup

---

## 5. Concrete Improvements

1. Keep the current `masterSum` topology and reject the earlier bus-0-as-summing-bus approach.
2. Replace `HPF` / `LPF` with `RHPF` / `RLPF` so `filter_res` actually does something.
3. Decide and document whether aux sends are pre-insert or post-insert, then tap the correct signal.
4. Add damping to both feedback loops, not just the aux loop.
5. Use a real limiter on the master if "never clips" is a hard requirement.
6. Add per-channel voice subgroups so ephemeral synths and `all_notes_off` remain simple.
7. Separate naming:
   - mixer internals: `channels`
   - sequencer internals: `tracks`
   - mapping: `trackToChannel`

---

## 6. Implementation Drift Found During Review

These are not topology problems, but they will block the mixer from behaving correctly:

1. `lib/mixer.lua` and the rest of the app disagree about state shape.
   - `lib/mixer.lua` uses `tracks` with nested `meters` on each track.
   - `lib/grid_ui.lua` reads `mixer.channels` and `mixer.meters.channels` in [`lib/grid_ui.lua`](/Users/whit/src/re.kriate/lib/grid_ui.lua:443).

2. Meter parsing is wrong in `lib/mixer.lua`.
   - `SendReply` includes `nodeID` and `replyID`.
   - [`lib/mixer.lua`](/Users/whit/src/re.kriate/lib/mixer.lua:90) treats the first two args as meter values.

3. Persistence API names do not line up.
   - [`lib/pattern_persistence.lua`](/Users/whit/src/re.kriate/lib/pattern_persistence.lua:366) calls `ctx.mixer:deserialize(...)`
   - [`lib/mixer.lua`](/Users/whit/src/re.kriate/lib/mixer.lua:142) exposes `restore(...)`

4. The mixer tests are out of sync with the implementation.
   - `specs/mixer_spec.lua` still expects `/rekriate/mixer/channel/...` in [`specs/mixer_spec.lua`](/Users/whit/src/re.kriate/specs/mixer_spec.lua:47)
   - the current SC and app code use `/rekriate/mixer/track/...`

I ran:

```bash
busted specs/mixer_spec.lua specs/mixer_persistence_spec.lua
```

Current result:

- `6` successes
- `2` errors

The persistence failures are downstream of the Lua contract drift above.
