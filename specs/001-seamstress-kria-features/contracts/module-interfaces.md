# Module Interface Contracts

**Branch**: `001-seamstress-kria-features` | **Date**: 2026-03-06

These contracts define the public interfaces between modules. All modules receive dependencies via arguments (no global access except platform hooks in entrypoints).

## lib/track.lua

```lua
-- Constants
M.NUM_TRACKS = 4
M.NUM_STEPS = 16
M.PARAM_NAMES = {"trigger", "note", "octave", "duration", "velocity",
                  "ratchet", "alt_note", "glide"}  -- extended params added
M.CORE_PARAMS = {"trigger", "note", "octave", "duration", "velocity"}
M.EXTENDED_PARAMS = {"ratchet", "alt_note", "glide"}
M.DURATION_MAP = { [1]=1/16, [2]=1/8, [3]=1/4, [4]=1/2, [5]=1, [6]=2, [7]=4 }
M.VELOCITY_MAP = { [1]=0.15, [2]=0.30, [3]=0.45, [4]=0.60, [5]=0.75, [6]=0.90, [7]=1.0 }

-- Constructors
M.new_param(default_val) -> Param
M.new_track(track_num) -> Track
M.new_tracks() -> Track[4]

-- Param operations
M.advance(param, direction?) -> value  -- direction: nil="forward", or string
M.peek(param) -> value
M.set_step(param, step, value)
M.toggle_step(param, step)  -- trigger only (toggles 0/1)
M.set_loop(param, loop_start, loop_end)

-- Track operations
M.toggle_mute(track) -> new_muted_state
```

## lib/sequencer.lua

```lua
M.DIVISION_MAP = { [1]=1/4, [2]=1/3, [3]=1/2, [4]=2/3, [5]=1, [6]=2, [7]=4 }

M.start(ctx)       -- Start clock coroutines (one per track)
M.stop(ctx)        -- Cancel clocks, silence voices
M.reset(ctx)       -- Return all playheads to loop_start
M.step_track(ctx, track_num)  -- Advance one step on a track
M.play_note(ctx, track_num, note, velocity, duration)
```

## lib/grid_ui.lua

```lua
M.PAGES = {"trigger", "note", "octave", "duration", "velocity"}
M.EXTENDED_PAGES = {trigger = "ratchet", note = "alt_note", octave = "glide"}

M.redraw(ctx)            -- Full grid redraw
M.key(ctx, x, y, z)     -- Grid key handler
M.nav_key(ctx, x, z)    -- Row 8 navigation
M.grid_key(ctx, x, y, z) -- Rows 1-7 editing
```

## lib/scale.lua

```lua
M.build_scale(root, scale_type) -> midi_notes[]
M.to_midi(degree, octave, scale_notes) -> midi_note_number
```

## lib/voices/midi.lua

```lua
M.new(midi_dev, channel) -> Voice
-- Voice methods:
voice:play_note(note, velocity, duration)
voice:note_on(note, velocity)
voice:note_off(note)
voice:all_notes_off()
voice:set_portamento(time)  -- NEW: for glide support
```

## lib/voices/recorder.lua

```lua
M.new() -> Voice  -- test-only voice, captures events
voice:play_note(note, velocity, duration)
voice:note_on(note, velocity)
voice:note_off(note)
voice:all_notes_off()
voice:set_portamento(time)  -- captures portamento events
M.get_events() -> event[]
M.get_notes() -> note[]
M.clear()
```

## lib/pattern.lua (NEW)

```lua
M.new_slots() -> Pattern[16]       -- Initialize 16 empty slots
M.save(ctx, slot_num)               -- Deep-copy current tracks into slot
M.load(ctx, slot_num)               -- Restore tracks from slot
M.is_populated(patterns, slot_num) -> boolean
```

## lib/direction.lua (NEW)

```lua
M.MODES = {"forward", "reverse", "pendulum", "drunk", "random"}
M.advance(param, direction) -> value  -- Advance param.pos per direction mode
```

## lib/seamstress/screen_ui.lua

```lua
M.redraw(ctx)  -- Draw status to seamstress screen window
```

## lib/seamstress/keyboard.lua

```lua
M.key(ctx, char, modifiers, is_repeat, state)  -- Keyboard input handler
```

## lib/app.lua

```lua
M.init(config) -> ctx    -- config.voices = Voice[]
M.rebuild_scale(ctx)
M.redraw(ctx)            -- Screen redraw
M.key(ctx, n, z)         -- norns key handler
M.enc(ctx, n, d)         -- norns encoder handler
M.cleanup(ctx)
```
