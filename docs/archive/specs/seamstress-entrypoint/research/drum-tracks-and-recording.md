# Drum Tracks, Live Recording, and Unusual Voices

Research for re.kriate polymetric sequencer (seamstress/norns).

---

## 1. Drum Track UI

### How Original Kria Handles Tracks

In Ansible kria, all four tracks share the same UI structure. The note page maps rows 0-6 to scale degrees (row 0 = highest pitch, row 6 = lowest). Each track outputs to a CV/gate pair. There is no drum mode -- every track is melodic.

n.kria (norns port) follows the same pattern: `data:set_step_val(t,'note',x,8-y)` maps the y-coordinate to a pitch value. No drum-specific logic exists.

### What a Drum Track Needs Differently

**The "note" parameter becomes "sound select."** Instead of choosing a scale degree (1-7), each row maps to a drum sound. In our existing `track.lua`, a melodic note value of 1-7 selects a scale degree. For a drum track, the same 1-7 range would select one of 7 drum sounds (kick, snare, closed hat, open hat, clap, rim, tom -- or whatever the user loads).

**Octave parameter is not useful.** Drums don't transpose by octave. Two options:
- Remove octave from drum tracks entirely. This simplifies the UI and frees a parameter page.
- Repurpose octave as "pitch/tune" -- a per-step tuning offset for the drum sample. Useful for pitched percussion (toms, 808 kicks, metallic sounds). Keep the same 1-7 range but map it to a pitch offset range (e.g., -6 to +6 semitones centered on 4).

**Duration works differently.** For melodic tracks, duration controls gate length. For drums, it could control sample playback length (how much of the sample plays before being cut). Alternatively, for one-shot samples, duration is irrelevant and this page could be repurposed for decay envelope or sample start position.

**Velocity and trigger work the same.** Trigger toggles are trigger toggles. Velocity maps to hit intensity. These pages need no changes.

### Grid Layout Options for Drums

**Option A: Same layout, different semantics.** Keep the existing grid layout. The note page still shows 7 rows x 16 columns, but rows represent drum sounds instead of scale degrees. Per-step, one sound is selected. This is the simplest approach and maintains UI consistency across track types.

**Option B: Rows = sounds, columns = steps (drum machine layout).** Flip the paradigm: each row is a drum sound, each column is a step. Pressing a cell toggles that sound's trigger on that step. This is the classic TR-808 / Elektron layout and what norns scripts like cyrene and ekombi use. However, this conflates the trigger and note pages into one view, losing per-step sound selection (every sound has its own trigger pattern). This is fundamentally a different sequencer model.

**Option C: Multi-row trigger view.** Hybrid approach: on the trigger page, show all drum sounds simultaneously (one row per sound, like Option B). On other parameter pages (velocity, duration), revert to the standard single-track view where rows represent parameter values. This gives the drum overview where it matters most (trigger programming) while keeping per-step parameter editing familiar.

### Recommended Approach

**Option A** is the right starting point. It requires the least code change (add a `track_type` field, change how the note value is interpreted by the voice backend) and preserves kria's core identity: each track has independent per-parameter loop lengths. Option B's "rows = sounds" layout is tempting but fundamentally changes the sequencer model -- it makes each drum sound an independent track with its own trigger sequence, which is really 7 sub-tracks. That's a bigger feature to add later.

The key data model change is small:

```lua
-- track_type field on each track
track.type = "melodic"  -- or "drum"

-- For drum tracks, note values 1-7 map to sound slots instead of scale degrees.
-- The voice backend interprets this differently:
--   melodic: note 3 + octave 4 + scale -> MIDI note number
--   drum:    note 3 -> drum sound slot 3 -> MIDI note (from drum map) or sample ID
```

A drum track needs a **sound map**: a table mapping slot numbers 1-7 to concrete sound identifiers (MIDI note numbers for GM drums, sample file paths, OSC addresses). This map is configured per-track in params.

### Per-Parameter Comparison

| Parameter | Melodic Track | Drum Track |
|-----------|--------------|------------|
| Trigger   | on/off per step | same |
| Note      | scale degree 1-7 | sound slot 1-7 |
| Octave    | octave offset 1-7 | pitch/tune offset (or removed) |
| Duration  | gate length | sample length / decay |
| Velocity  | hit intensity 1-7 | same |

---

## 2. Live Recording

### How Original Kria Handles Recording

**It doesn't.** Ansible kria is exclusively step-programmed. You press grid cells to set values on specific steps. There is no real-time recording mode in the firmware. n.kria follows the same approach.

### Recording Models

**Step recording:** The sequencer is stopped (or stepping slowly). The user plays a note (via MIDI controller, grid, or keyboard); it gets written to the current step, and the step advances. This is deterministic, precise, and easy to implement.

**Real-time recording:** The sequencer runs at tempo. The user plays notes in real time; incoming notes are quantized to the nearest step and written to the sequence. This captures performance feel but requires quantization decisions.

### Step Recording Design

The simplest and most kria-appropriate approach.

**Gesture:** Enter recording mode (hold a dedicated button, or toggle via key combo). The playhead stops advancing automatically. Play a note on a MIDI controller or a designated grid row. The note value is written to the current step, and the position advances by one. If the trigger for that step is off, it gets turned on automatically.

**For polymetric loops:** Step recording writes into whichever parameter page is active. If you're on the note page, incoming notes write to note steps. The position advances within that parameter's loop boundaries. This respects the per-parameter loop length -- when you reach `loop_end`, the position wraps to `loop_start`.

**Implementation sketch:**
```lua
function handle_step_record(ctx, track_num, incoming_note)
  local track = ctx.tracks[track_num]
  local note_param = track.params["note"]
  local trig_param = track.params["trigger"]
  local pos = note_param.pos

  -- Write the note value
  note_param.steps[pos] = incoming_note  -- scale degree or sound slot

  -- Ensure trigger is on
  trig_param.steps[pos] = 1

  -- Advance within the note param's loop
  Track.advance(note_param)
end
```

### Real-Time Recording Design

More complex, but powerful for capturing melodic phrases.

**Quantization:** When a note arrives, compute which step it's closest to. With 16 steps per loop and a known tempo + clock division, each step has a beat position. Find the nearest step to the current beat position and write there.

```lua
-- Which step is closest to the current beat?
local beats_per_step = track.division  -- e.g., 1/4 beat per step
local current_beat = clock.get_beats()
local beat_in_loop = current_beat % (loop_length * beats_per_step)
local nearest_step = math.floor(beat_in_loop / beats_per_step + 0.5) + loop_start
```

**Overdub vs replace:** Two modes, toggled by the user.
- **Replace:** Clear the loop before recording. All triggers turn off; notes played during recording fill in.
- **Overdub:** Keep existing triggers. New notes overwrite only the steps they land on. This is the more musical default -- you can layer parts by recording multiple passes.

**Polymetric complexity:** In kria, each parameter has its own loop length. Real-time recording writes into the note parameter's loop. But what about velocity? If the MIDI controller sends velocity, write that to the velocity parameter at the same step. Duration is harder -- you'd need note-on and note-off timestamps to compute gate length, then quantize that to the nearest duration value.

### Recording Input Sources

**MIDI controller:** The most natural input. norns `midi.event` / seamstress `midi.event` provides note_on/note_off with note number and velocity. Convert the MIDI note to a scale degree (using the active scale) before writing to the step.

**Grid:** Designate a row or section of the grid as a "keyboard" during recording. Bottom row could serve as a chromatic input, or a row of scale-degree buttons. This is less expressive than MIDI (no velocity) but works without external hardware.

**Computer keyboard (seamstress):** Map keys to scale degrees. Limited but functional for seamstress-only use.

### Practical Recommendations

1. **Start with step recording.** It's simple, deterministic, and fits kria's step-editing philosophy. A "record" mode where MIDI/grid input writes to the current step and advances is straightforward.
2. **Add real-time recording later.** Quantize to the step grid, overdub by default, write note + velocity simultaneously. Duration can default to whatever the step's current duration value is.
3. **norns `pattern_time` is not the right tool.** It records timestamped events for gesture playback, not for writing into a step sequencer. It preserves continuous timing rather than quantizing to a grid. Build recording logic directly into the sequencer.

---

## 3. Unusual Voices

### Voice Interface Baseline

The project already defines the voice interface via the nb-inspired pattern:

```lua
player:play_note(note, velocity, duration)
player:note_on(note, velocity)
player:note_off(note)
```

Each voice backend implements this interface. The question is: what backends beyond basic MIDI note_on/note_off are interesting, and what additional parameters do they need?

### Voice Backend Catalog

#### A. MIDI Note (baseline)

**Interface:** `note_on(note, vel)` / `note_off(note)` over a MIDI port + channel.
**Parameters:** MIDI device, channel, transpose offset.
**Unique needs:** Note-off timing (managed by the sequencer's duration parameter via `clock.run` one-shot coroutine). CC messages for expression (mod wheel, filter, etc.) can be driven by additional kria parameter pages.
**Already planned:** Yes, this is the primary voice for the seamstress entrypoint.

#### B. MIDI Drum

**Interface:** Same `note_on(note, vel)` / `note_off(note)`, but the note number maps to a drum sound rather than a pitch.
**Parameters:** MIDI device, channel, drum map (table mapping sound slots 1-7 to MIDI note numbers). General MIDI drum map places kick=36, snare=38, closed hat=42, etc.
**Unique needs:** Duration is typically irrelevant (drum hits are one-shot). The voice backend can ignore `note_off` or send it immediately. No octave transposition needed.
**Drum map example:**
```lua
{ [1]=36, [2]=38, [3]=42, [4]=46, [5]=39, [6]=37, [7]=41 }
-- kick, snare, closed hat, open hat, clap, rim, low tom
```
**Effort:** Trivial extension of the MIDI note voice. Just swap the note lookup.

#### C. Sample Player (via OSC to SuperCollider or other engine)

**Interface:** `play_note(sample_id, velocity, duration)` where `sample_id` selects a loaded sample.
**Parameters:** OSC target address, sample bank path, per-sample tuning/filter/envelope settings.
**How it works:** Send OSC messages to a SuperCollider instance running a sample player engine (e.g., Timber's `Engine_Timber`). The engine handles:
- Sample loading and voice allocation
- Per-note parameters: pitch (transpose + detune), filter (cutoff, resonance), amp envelope (ADSR), pan
- Polyphonic voice stealing

**OSC message design:**
```lua
osc.send(target, "/note_on", {sample_id, freq_or_note, velocity})
osc.send(target, "/note_off", {sample_id})
-- Or for one-shot drums:
osc.send(target, "/trigger", {sample_id, velocity, pitch_offset})
```

**What differs from MIDI:** Richer per-note parameter control. MIDI is limited to note + velocity + channel; OSC can send arbitrary parameters per trigger. This allows kria parameter pages to control sample-specific features (filter cutoff, sample start position, decay time) that map to OSC arguments rather than MIDI CCs.

**Effort:** Moderate. Requires a SuperCollider receiver (or use Timber's engine on norns). The voice backend is simple OSC messaging; the complexity is in the receiving end.

#### D. CV/Gate via Crow (norns only)

**Interface:** Set voltage on crow outputs for pitch CV and gate.
**Parameters:** Output pair assignment (outputs 1+2 for track 1, 3+4 for track 2, etc.), voltage standard (V/oct), slew time.
**How it works:**
```lua
-- note_on: set pitch CV and open gate
crow.output[cv_out].volts = (note - 60) / 12  -- V/oct from MIDI note
crow.output[gate_out].volts = 5               -- gate high

-- note_off: close gate
crow.output[gate_out].volts = 0
```
**Unique needs:** Only 4 outputs on crow, so maximum 2 CV/gate pairs (2 tracks). Slew between notes is musically useful and maps to kria's "glide" parameter. Crow's ASL (Action Specification Language) can generate envelopes directly:
```lua
crow.output[gate_out].action = "pulse(0.1, 5, 1)"  -- trigger pulse
crow.output[gate_out]()
```
**Effort:** Small. The crow API is simple. The constraint is output count.

#### E. Just Friends via Crow i2c (norns only)

**Interface:** `crow.ii.jf.play_note(pitch_volts, velocity_volts)` for polyphonic synthesis on the Just Friends module.
**Parameters:** Mode (synth/shape), polyphony (up to 6 voices), time (timbre), intone (harmonic spread).
**How it works:**
```lua
-- Enable synth mode
crow.ii.jf.mode(1)

-- Play a note (polyphonic, JF allocates voices internally)
crow.ii.jf.play_note(pitch_v, vel_v)

-- Or trigger a specific channel (1-6)
crow.ii.jf.trigger(channel, state)
```
**What's special:** Just Friends has 6 outputs that can act as 6 independent oscillators. In synth mode, `play_note` does polyphonic voice allocation internally. This means a single kria track could play chords, or multiple tracks could share JF's voice pool.
**For drums:** JF in shape mode produces envelope-like transients. Each of its 6 channels has a different harmonic relationship, making it capable of pitched percussion (metallic tones, tuned clicks).
**Effort:** Small once crow is integrated. The i2c API is 2-3 function calls.

#### F. CC/Modulation Sequences (parameter automation)

**Interface:** Instead of note_on/note_off, send `cc(cc_number, value)` or `modulate(key, value)`.
**Parameters:** MIDI device + channel, CC number, value range mapping.
**How it works:** A "CC track" doesn't play notes. Instead, its step values (1-7 range) map to CC values (0-127). On each step, the track sends a CC message. This turns kria into a modulation sequencer.
**Use cases:** Filter sweeps, effect parameter automation, controlling external gear parameters in sync with melodic tracks. With kria's independent loop lengths, you get polymetric modulation.
**Kria mapping:**
```lua
-- note page -> CC value (1-7 maps to configurable range, e.g. 0-127)
-- trigger page -> whether CC is sent on this step
-- velocity page -> could modulate CC amount (multiply value by velocity)
-- duration page -> CC slew/interpolation time to next value
-- octave page -> CC offset or second CC channel
```
**Effort:** Trivial voice backend. The interesting design question is how the UI communicates "this is a CC track" to the user.

#### G. Granular Engine Control (via OSC or engine)

**Interface:** Trigger grains or set granular parameters per step.
**Parameters:** Source buffer/file, grain size, spray (position randomization), density, pitch, pan spread, envelope shape.
**How it works:** Each step triggers a burst of grains (or changes continuous granular parameters). The kria parameter pages map to:
- Note -> grain pitch (scale degree transposition)
- Duration -> grain size
- Velocity -> grain density or amplitude
- Octave -> position in source buffer (scrub through the sample)
**OSC message design:**
```lua
osc.send(target, "/granular/trigger", {position, pitch, size, density, velocity})
```
**What's special:** Granular synthesis is inherently more "textural" than note-based synthesis. A kria track controlling a granular engine produces evolving sonic textures where polymetric loop lengths create slowly shifting patterns. This is a compelling creative application.
**Effort:** Moderate to high. Requires a granular engine on the receiving end (SuperCollider, norns softcut, or a dedicated app). The voice backend is OSC messaging; the complexity is in the granular engine itself.

### Voice Interface Design Implications

All voice backends share the core `play_note(note, vel, dur)` / `note_on` / `note_off` interface, but several backends need additional per-step parameters. The current track model has 5 parameters (trigger, note, octave, duration, velocity). Extensions for unusual voices:

**Additional parameter pages to consider:**
- **CC/mod value:** A secondary value sent alongside or instead of note data
- **Timbre/filter:** Per-step timbral control (maps to CC, OSC param, or engine param)
- **Pan:** Stereo position per step
- **Probability:** Whether a step fires (0-100%). Already present in original kria.
- **Ratchet/repeat:** Re-trigger within a step. Already present in original kria as the "repeat" page.

**The voice descriptor pattern from nb is useful.** Each voice backend should report what it supports:
```lua
function voice:describe()
  return {
    name = "MIDI Drums",
    supports_velocity = true,
    supports_duration = false,  -- one-shot, duration ignored
    supports_octave = false,    -- no transposition
    supports_bend = false,
    note_type = "drum_slot",    -- vs "scale_degree" or "midi_note"
    mod_targets = {"cc1", "cc2"},
  }
end
```
This lets the grid UI adapt: hide the octave page for drum voices, show a CC page for modulation voices, display "SOUND" instead of "NOTE" in the header.

### Summary Table

| Voice | note_on/off | Extra Params | Duration Behavior | Platform |
|-------|------------|--------------|-------------------|----------|
| MIDI Note | standard | device, ch, transpose | gate length | both |
| MIDI Drum | note = drum map lookup | device, ch, drum map | ignored (one-shot) | both |
| Sample Player | OSC trigger | sample bank, filter, env | sample playback length | both |
| CV/Gate | crow voltage | output pair, slew | gate voltage duration | norns |
| Just Friends | crow i2c | mode, time, intone | envelope-based | norns |
| CC Sequence | cc(num, val) | CC number, range | slew time | both |
| Granular | OSC trigger | position, size, density | grain size | both |

---

## Design Implications for re.kriate

1. **Track type field.** Add `track.type` ("melodic" or "drum" initially). The voice backend and grid UI consult this to determine how note values are interpreted and which parameter pages are shown.

2. **Voice descriptor.** Each voice backend reports its capabilities. The UI adapts accordingly (hide irrelevant pages, change labels).

3. **Sound map for drums.** Drum tracks need a configurable mapping from slot numbers to concrete sound identifiers. This is a per-track param, not a global setting.

4. **Step recording first.** It's simpler, fits kria's philosophy, and works identically for melodic and drum tracks. Real-time recording adds complexity (quantization, overdub) that can come later.

5. **Voice abstraction stays thin.** The `play_note` / `note_on` / `note_off` interface covers all backends. Voice-specific configuration lives in params, not in the interface. The sequencer doesn't know what kind of voice it's talking to.

6. **CC tracks are a separate track type.** They don't play notes; they send parameter values. This is a third `track.type` ("cc") alongside "melodic" and "drum".

## Sources

- [Ansible kria firmware](https://github.com/monome/ansible) -- `src/ansible_grid.c`, `src/ansible_grid.h`
- [Ansible kria docs](https://monome.org/docs/ansible/kria/) -- grid layout, parameter pages, loop configuration
- [n.kria](https://github.com/zjb-s/n.kria) -- norns port, `lib/gkeys.lua` for grid key handling, `lib/globals.lua` for constants
- [nb voice library](https://github.com/sixolet/nb) -- `lib/nb.lua`, `lib/player.lua` for voice abstraction API
- [Timber sample engine](https://github.com/markwheeler/timber) -- `lib/timber_engine.lua`, `lib/Engine_Timber.sc` for sample player architecture
- [Crow reference](https://monome.org/docs/crow/reference/) -- output voltage, ASL, i2c/Just Friends commands
- [Crow norns API](https://monome.org/docs/crow/norns/) -- norns-to-crow Lua interface
- [norns pattern_time](https://monome.org/docs/norns/reference/lib/pattern_time) -- event recording (not suitable for step recording)
- [cyrene](https://norns.community/cyrene) -- grid drum sequencer (rows = tracks, columns = beats)
- [ekombi](https://norns.community/ekombi) -- polyrhythmic drum sequencer (two-row-per-track layout)
- [kolor](https://norns.community/kolor) -- grid sample sequencer with per-step parameter locks
- [gridstep](https://norns.community/gridstep) -- step sequencer with grid recording (sequences stored as grid positions)
- [hachi](https://norns.community/hachi) -- euclidean drum machine with real-time recording
