# Kria Research Notes

## 1. Original Kria Architecture (monome/ansible C firmware)

Source: `src/ansible_grid.h` and `src/ansible_grid.c` in monome/ansible repo.

### Constants
- `KRIA_NUM_TRACKS` = 4
- `KRIA_NUM_PARAMS` = 7
- `KRIA_NUM_PATTERNS` = 16
- Steps per parameter = 16
- Presets = 8

### The 7 Parameters (enum kria_modes_t)
```
mTr       = 0  -- trigger (0/1)
mNote     = 1  -- note (scale degree 0-6)
mOct      = 2  -- octave offset
mDur      = 3  -- duration (0-5, scaled by dur_mul)
mRpt      = 4  -- repeat count (1-5) + rptBits bitmask
mAltNote  = 5  -- alternate/secondary note (0-6)
mGlide    = 6  -- glide/slew amount (0-6)
```

### Per-Track Data (kria_track struct)
- Sequence arrays: `tr[16]`, `note[16]`, `oct[16]`, `dur[16]`, `rpt[16]`, `rptBits[16]`, `alt_note[16]`, `glide[16]`
- Per-param loop control (arrays of 7): `lstart[7]`, `lend[7]`, `llen[7]`, `lswap[7]`, `tmul[7]`
- Per-step probability: `p[7][16]` — values 0=never, 1=25%, 2=50%, 3=always
- Track settings: `dur_mul`, `direction`, `octshift`, `trigger_clocked`

### Per-Parameter Independent Loop Length
Each of the 7 params per track has:
- `lstart[param]` — loop start position (0-15)
- `lend[param]` — loop end position (0-15)
- `llen[param]` — loop length
- `tmul[param]` — clock division (1-16)
- Separate playhead: `pos[track][param]`

Advancement in `kria_next_step()`:
1. Increment `pos_mul[t][p]` (sub-step counter)
2. When `pos_mul >= tmul`, advance `pos[t][p]` by direction mode
3. Wrap at loop boundaries
4. Check probability — return whether step takes effect

### Direction Modes (per-track, not per-param)
- Forward: start -> end, wrap
- Reverse: end -> start, wrap
- Triangle: ping-pong between start and end
- Drunk: randomly forward or reverse each step
- Random: jump to random position within loop

### Note Calculation
```
noteInScale = (note + alt_note) % 7
octaveBump = (note + alt_note) / 7
CV = cur_scale[noteInScale] + scale_adj[noteInScale] + (oct + octaveBump + octshift) * 12
```

### Scale System
- 16 scale slots, each with 7 intervals (semitone jumps)
- Default 7 scales = diatonic modes (Ionian through Locrian)
- Scales 7-15 = user slots
- `calc_scale(s)` computes cumulative sums for note lookup

### Grid Layout (16x8, 0-indexed)
Bottom row (y=7) = navigation:
- x=0-3: Track select
- x=5: Trigger page (double-tap for Repeat)
- x=6: Note page (double-tap for Alt Note)
- x=7: Octave page (double-tap for Glide)
- x=8: Duration page
- x=10: Loop modifier (hold)
- x=11: Time/division modifier (hold)
- x=12: Probability modifier (hold)
- x=14: Scale page
- x=15: Pattern page

Main field (rows 0-6):
- Trigger mode: rows 0-3 = all 4 tracks (16 steps each)
- Note mode: rows 0-6 = 7 scale degrees for active track
- Octave mode: row 0 = octshift selector, rows 1-6 = per-step octave bars
- Duration mode: row 0 = dur_mul selector, rows 1-6 = per-step duration bars

### Playback Logic
`clock_kria_track(trackNum)`:
1. Advance trigger param
2. If not trigger_clocked, advance note/oct/dur/alt_note/glide independently
3. If trigger fires and not muted:
   - Set CV from note calc
   - Set gate high
   - Start duration timer
   - Handle repeats if rpt > 1

### Meta-Sequencer
- 64-step sequence of pattern indices
- Per-step duration (how many cue events before advancing)
- Own loop start/end
- Cue system divides master clock

### Storage Hierarchy
```
kria_state_t
  kria_data_t k[8]           -- 8 presets
    kria_pattern p[16]        -- 16 patterns
      u8 scale
      kria_track t[4]         -- 4 tracks
        sequences[16] per param
        loop control per param
        track settings
    meta_pat[64], meta_steps[64]
```

---

## 2. n.kria (norns port) Analysis

### Module Structure
| File | Purpose |
|---|---|
| `n.kria.lua` | Main entry, globals, coroutines |
| `lib/globals.lua` | Global variable initialization |
| `lib/data_functions.lua` | Data singleton with metatable proxies |
| `lib/gkeys.lua` | Grid key input handling |
| `lib/grid_graphics.lua` | Grid LED rendering |
| `lib/screen_graphics.lua` | Screen rendering |
| `lib/transport.lua` | Sequencer advancement, clock division |
| `lib/meta.lua` | Utility functions, scale building, loop editing |
| `lib/prms.lua` | Parameter declarations |
| `lib/onboard.lua` | Key/encoder callbacks |
| `lib/nb/` | nb voice library submodule |

### Data Model
- 8 params: trig, retrig, note, transpose, octave, slide, gate, velocity
- 16 steps per param, 4 tracks
- Two-tier storage: params system for non-pattern data, separate `.kriapattern` file for step data
- Per-param: loop_first, loop_last, divisor, pos (current position)

### Voice Output
Uses nb:
```lua
nb:add_param("voice_t"..t, "voice "..t)
-- in note_clock:
local player = params:lookup_param("voice_t"..t):get_player()
player:play_note(note, velocity, duration)
```

### Lessons Learned
Good: nb integration, polymetric loops, grid layout
Bad: globals everywhere, overcomplicated Data singleton, split storage, monolithic handlers

---

## 3. Platform API Reference

### nb (sixolet/nb)
```lua
local nb = require("lib/nb/lib/nb")
nb.voice_count = 4
nb:init()
nb:add_param("voice_1", "voice 1")
nb:add_player_params()

-- Playing notes:
local player = params:lookup_param("voice_1"):get_player()
player:play_note(note, vel, length)  -- length in beats
player:note_on(note, vel)
player:note_off(note)
player:set_slew(seconds)
```

### clock
```lua
clock.run(function()
  while true do
    clock.sync(1/4)  -- sixteenth notes
    advance()
  end
end)
clock.cancel(id)
clock.get_tempo()  -- BPM
clock.get_beat_sec()  -- seconds per beat
```

### grid (1-indexed in Lua!)
```lua
local g = grid.connect()
g.key = function(x, y, z) end  -- x=1-16, y=1-8, z=0/1
g:led(x, y, brightness)  -- brightness 0-15
g:all(0)
g:refresh()
```

### musicutil
```lua
local mu = require("musicutil")
local scale = mu.generate_scale(root, "Dorian", octaves)
local quantized = mu.snap_note_to_array(note, scale)
local name = mu.note_num_to_name(note, true)
```

### lattice (alternative to raw clock for multi-division timing)
```lua
local l = require("lattice")
local lat = l:new()
local sprocket = lat:new_sprocket({
  action = function(t) step_track() end,
  division = 1/4,
})
lat:start()
sprocket:set_division(1/8)  -- change division dynamically
```

### seamstress Compatibility
Compatible: grid, clock, sequins, musicutil, lattice, params, midi
Not available: key/enc (no physical hardware), engine, softcut, crow
Different: screen API (SDL vs OLED)
nb: works via MIDI players only (no engine voices)
Lua: seamstress v1 uses Lua 5.4, norns uses 5.3 (minor differences)

---

## 4. Recommended Implementation Approach

### Phase 1 — Core (MVP)
- 4 tracks, 5 params: trigger, note, octave, duration, velocity
- 16 steps per param
- Per-param independent loop start/end
- Per-track clock division (simplify from per-param initially)
- Forward direction only
- 1 scale (major/dorian), hardcoded
- nb voice output
- Grid UI: trigger page (4-track view), note page, octave page, duration page
- No screen UI initially (grid-only)
- No patterns, no meta-sequencer

### Phase 2 — Essential Features
- Per-param clock division
- Direction modes (forward, reverse, triangle, drunk, random)
- Scale editor with multiple slots
- Velocity page
- Pattern storage (16 slots)
- Basic screen info display

### Phase 3 — Polish
- Probability per step
- Pattern cueing
- Loop modifier overlay
- Time modifier overlay
- Meta-sequencer
- Repeat/ratcheting

### Module Structure
```
re_kriate.lua          -- thin global hooks
lib/app.lua            -- init/redraw/key/enc/cleanup, grid connect
lib/track.lua          -- track data model, step values, loop control
lib/sequencer.lua      -- clock, advancement, note firing via nb
lib/grid_ui.lua        -- grid rendering and input
lib/screen_ui.lua      -- screen rendering (platform-aware)
lib/scale.lua          -- scale definitions, quantization
```

### Data Model (ctx)
```lua
ctx = {
  g = grid.connect(),
  tracks = {
    [1] = {
      params = {
        trigger  = { steps = {0,1,1,0,...}, loop_start = 1, loop_end = 16, pos = 1 },
        note     = { steps = {0,2,4,5,...}, loop_start = 1, loop_end = 8, pos = 1 },
        octave   = { steps = {3,3,3,4,...}, loop_start = 1, loop_end = 16, pos = 1 },
        duration = { steps = {2,2,3,2,...}, loop_start = 1, loop_end = 16, pos = 1 },
        velocity = { steps = {5,5,6,4,...}, loop_start = 1, loop_end = 16, pos = 1 },
      },
      division = 1,   -- clock division
      direction = 1,  -- 1=fwd, 2=rev, 3=tri, 4=drunk, 5=random
      muted = false,
    },
    -- tracks 2-4 ...
  },
  active_track = 1,
  active_page = "trigger",  -- which param page is shown
  scale = { ... },
  playing = false,
  clock_id = nil,
}
```

### Step Values (ranges, 1-indexed to match grid rows)
- trigger: 0 or 1
- note: 1-7 (scale degree)
- octave: 1-7 (mapped to octave offset, center at 4 = 0)
- duration: 1-7 (mapped to beat fractions)
- velocity: 1-7 (mapped to 0.0-1.0)
