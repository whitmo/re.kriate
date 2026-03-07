# Kria Feature Inventory: Original vs re.kriate

**Date**: 2026-03-06
**Sources**: [monome.org/docs/ansible/kria](https://monome.org/docs/ansible/kria/), [monome/ansible C source](https://github.com/monome/ansible), [zjb-s/n.kria](https://github.com/zjb-s/n.kria), [Dewb/monome-rack](https://dewb.github.io/monome-rack/modules/ansible/)

---

## Table of Contents

1. [Navigation Row (Row 8)](#1-navigation-row-row-8)
2. [Core Parameter Pages](#2-core-parameter-pages)
3. [Extended Parameter Pages](#3-extended-parameter-pages)
4. [Modifier Modes](#4-modifier-modes)
5. [Scale Page](#5-scale-page)
6. [Pattern Page and Meta-Sequencer](#6-pattern-page-and-meta-sequencer)
7. [Direction Modes](#7-direction-modes)
8. [Config Page](#8-config-page)
9. [Clock/Time Page](#9-clocktime-page)
10. [Preset System](#10-preset-system)
11. [Sequencer Engine Features](#11-sequencer-engine-features)

---

## 1. Navigation Row (Row 8)

The bottom row of the 16x8 grid is the navigation bar. In the original kria firmware (0-indexed columns 0-15), the layout is:

| Column (1-indexed) | Original Kria Function | re.kriate | Status |
|---|---|---|---|
| 1-4 | Track select (4 tracks) | Track select | YES |
| 5 | (gap) | Mute toggle | CHANGED (not in original here; original mute is loop+track) |
| 6 | Trigger / Ratchet toggle | Trigger page | PARTIAL (no ratchet toggle) |
| 7 | Note / Alt Note toggle | Note page | PARTIAL (no alt note toggle) |
| 8 | Octave / Glide toggle | Octave page | PARTIAL (no glide toggle) |
| 9 | Duration page | Duration page | YES |
| 10 | (unused in original) | Velocity page | ADDED (velocity is re.kriate extension) |
| 11 | Loop modifier (hold) | (unused) | MISSING |
| 12 | Time/Division modifier (hold) | Loop modifier (hold) | MOVED (loop at 12 instead of 11) |
| 13 | Probability modifier (hold) | (unused) | MISSING |
| 14 | (unused) | (unused) | - |
| 15 | Scale page | (unused) | MISSING |
| 16 | Pattern page / Cue | Play/Stop | CHANGED (original has no play/stop on grid) |

### Acceptance Tests

#### NAV-01: Track Selection
```
GIVEN the grid is connected and the sequencer is running
WHEN the user presses grid column 1-4 on row 8
THEN the active track changes to the pressed track number (1-4)
AND the nav row highlights the selected track at brightness 12
AND other track buttons show at brightness 3
```
**Status**: IMPLEMENTED

#### NAV-02: Page Selection - Core Pages
```
GIVEN the grid is connected
WHEN the user presses grid column 6 on row 8
THEN the trigger page is displayed on rows 1-7
WHEN the user presses grid column 7 on row 8
THEN the note page is displayed
WHEN the user presses grid column 8 on row 8
THEN the octave page is displayed
WHEN the user presses grid column 9 on row 8
THEN the duration page is displayed
```
**Status**: IMPLEMENTED (columns 6-9 map to trigger/note/octave/duration)

#### NAV-03: Extended Page Toggle (Double-Press)
```
GIVEN the user is on the trigger page
WHEN the user presses column 6 on row 8 again (double-press same page key)
THEN the display switches to the ratchet/repeat page (extended trigger)
AND the page key blinks to indicate extended mode

GIVEN the user is on the note page
WHEN the user presses column 7 on row 8 again
THEN the display switches to the alt note page (extended note)

GIVEN the user is on the octave page
WHEN the user presses column 8 on row 8 again
THEN the display switches to the glide page (extended octave)
```
**Status**: NOT IMPLEMENTED -- Our code sets the page on press but has no toggle to extended subpages. The `NAV_PAGE` table in `grid_ui.lua` maps each column to a single page name with no secondary state.

#### NAV-04: Mute via Loop Modifier + Track
```
GIVEN the loop modifier key (column 11 in original) is held
WHEN the user presses a track button (columns 1-4) on row 8
THEN that track's mute state is toggled
AND the grid display reflects the muted state
```
**Status**: NOT IMPLEMENTED -- Our code has mute on a dedicated column 5 button instead. The original kria uses loop_held + track press.

#### NAV-05: Loop Modifier Hold
```
GIVEN the user presses and holds column 11 on row 8 (original layout)
THEN the display enters loop editing mode
AND releasing the key exits loop editing mode
```
**Status**: PARTIAL -- Implemented at column 12 instead of 11. Functionally works but position differs.

#### NAV-06: Time/Division Modifier Hold
```
GIVEN the user presses and holds column 12 on row 8 (original layout)
THEN the display enters time/clock division editing mode
AND the top row shows selectable clock divisions 1-16
AND releasing the key exits time editing mode
```
**Status**: NOT IMPLEMENTED -- No time modifier key exists on the grid.

#### NAV-07: Probability Modifier Hold
```
GIVEN the user presses and holds column 13 on row 8 (original layout)
THEN the display enters probability editing mode
AND rows 2-5 show per-step probability values as vertical faders
AND releasing the key exits probability editing mode
```
**Status**: NOT IMPLEMENTED -- No probability modifier key on the grid.

#### NAV-08: Scale Page
```
GIVEN the user presses column 15 on row 8
THEN the scale editor page is displayed
AND the left side shows per-track direction modes and clocking options
AND the right side shows the scale interval editor
```
**Status**: NOT IMPLEMENTED -- Column 15 is unused. Scale is only adjustable via norns params.

#### NAV-09: Pattern Page
```
GIVEN the user presses column 16 on row 8
THEN the pattern page is displayed
AND row 1 shows 16 pattern slots
AND the current pattern is highlighted
```
**Status**: NOT IMPLEMENTED -- Column 16 is used for play/stop instead.

---

## 2. Core Parameter Pages

### 2.1 Trigger Page

**Original**: Rows 1-4 show all 4 tracks simultaneously. Each row = one track. Each column = one step. Lit cells indicate active triggers. Playhead shows current position.

**re.kriate**: Same layout. Rows 1-4 = tracks 1-4. Brightness: 0 (off, outside loop), 2 (in loop, no trigger), 8 (trigger active), 15 (playhead).

#### TRIG-01: Trigger Display
```
GIVEN the trigger page is active
THEN rows 1-4 display all 4 tracks simultaneously
AND each column 1-16 represents one step
AND active triggers show at brightness 8
AND steps within the loop region but without triggers show at brightness 2
AND the playhead position shows at brightness 15
```
**Status**: IMPLEMENTED

#### TRIG-02: Trigger Toggle
```
GIVEN the trigger page is active
WHEN the user presses a cell at (column, row) where row is 1-4
THEN the trigger at that step for that track is toggled on/off
```
**Status**: IMPLEMENTED

#### TRIG-03: Note Sync on Trigger Page
```
GIVEN note_sync is enabled in config
AND the user is on the note page
WHEN the user presses a step's current note value
THEN the trigger at that step is toggled off (creating a rest)
WITHOUT switching to the trigger page
```
**Status**: NOT IMPLEMENTED -- No note_sync feature exists.

### 2.2 Note Page

**Original**: Rows 1-7 display scale degrees for the selected track. Row 1 = degree 7 (highest), Row 7 = degree 1 (lowest). Each column = one step. The active note value is shown as a lit cell at the corresponding row.

**re.kriate**: Same layout. Value display with bar visualization (all rows below value also dimly lit).

#### NOTE-01: Note Display
```
GIVEN the note page is active
THEN rows 1-7 display note values for the active track only
AND row 1 = value 7 (highest scale degree), row 7 = value 1 (lowest)
AND the active note value cell shows at brightness 10 (in loop) or 4 (outside loop)
AND cells below the value show at brightness 3 (bar visualization)
AND the playhead column shows the value cell at brightness 15
```
**Status**: IMPLEMENTED

#### NOTE-02: Note Value Edit
```
GIVEN the note page is active
WHEN the user presses a cell at (column, row) where row is 1-7
THEN the note value for that step is set to (8 - row)
```
**Status**: IMPLEMENTED

### 2.3 Octave Page

**Original**: Top row (row 1) has 6 keys (x=1-6) for selecting the base octave offset (+0 to +5) for the entire track. Rows below show per-step octave values.

**re.kriate**: Rows 1-7 show per-step octave values as a vertical bar (same as note/duration/velocity). No per-track base octave offset on the top row.

#### OCT-01: Octave Display
```
GIVEN the octave page is active
THEN rows 1-7 display octave offset values for the active track
AND the display uses the same bar visualization as other value pages
```
**Status**: IMPLEMENTED (but layout differs from original -- original has base octave on row 1)

#### OCT-02: Per-Track Base Octave
```
GIVEN the octave page is active
WHEN the user presses one of the first 6 keys on row 1
THEN the base octave frequency for that track is set to +0 through +5
```
**Status**: NOT IMPLEMENTED -- Our octave page uses the same generic value page layout as note/duration/velocity. The original has a special top row for per-track base octave.

### 2.4 Duration Page

**Original**: Row 1 is a duration multiplier selector (x=1-8, values 1-8x). Rows 2-7 show per-step duration as downward sliders (lower = longer). The multiplier affects all durations for that track.

**re.kriate**: Rows 1-7 show per-step duration values as generic bar visualization. No duration multiplier on row 1.

#### DUR-01: Duration Display
```
GIVEN the duration page is active
THEN rows 1-7 display duration values for the active track
AND the display uses bar visualization
```
**Status**: IMPLEMENTED (but layout differs from original)

#### DUR-02: Duration Multiplier
```
GIVEN the duration page is active
WHEN the user presses one of the first 8 keys on row 1
THEN the duration multiplier for that track is set (1x through 8x)
AND all subsequent duration values are multiplied by this factor
```
**Status**: NOT IMPLEMENTED -- No duration multiplier on row 1.

### 2.5 Velocity Page

**Note**: The original kria does NOT have a velocity page. Velocity is a re.kriate addition (since the original kria outputs CV/gate, not MIDI). This is appropriate for a MIDI-output sequencer.

#### VEL-01: Velocity Display
```
GIVEN the velocity page is active
THEN rows 1-7 display velocity values for the active track
AND the display uses bar visualization identical to note/octave/duration
```
**Status**: IMPLEMENTED (re.kriate extension)

---

## 3. Extended Parameter Pages

These are the "secondary" pages accessed by double-pressing a parameter key in original kria.

### 3.1 Ratchet/Repeat Page (Extended Trigger)

**Original**: Accessed by pressing the trigger key a second time (the key blinks to indicate extended mode). Shows per-step ratcheting: how many sub-triggers fire within a single step.

- Rows 2-6: Enable sub-triggers per step (up to 5 sub-divisions)
- Row 1: Increase subdivisions
- Row 7: Decrease subdivisions (long-press to clear, long-press row 1 to fill)
- Each step can have independently programmed subdivision patterns

#### RATCH-01: Access Ratchet Page
```
GIVEN the trigger page is currently displayed
WHEN the user presses the trigger page key (column 6, row 8) again
THEN the display switches to the ratchet page
AND the trigger page key blinks to indicate extended mode
```
**Status**: NOT IMPLEMENTED

#### RATCH-02: Ratchet Display
```
GIVEN the ratchet page is active
THEN rows 2-6 display the sub-trigger pattern for each step
AND each row represents one possible sub-trigger within the step's division
AND lit cells indicate active sub-triggers
AND rows 1 and 7 show subdivision controls
```
**Status**: NOT IMPLEMENTED

#### RATCH-03: Ratchet Editing
```
GIVEN the ratchet page is active
WHEN the user presses a cell in rows 2-6
THEN that sub-trigger is toggled on/off for that step
AND the ratchet pattern determines how many times the gate fires within one step
```
**Status**: NOT IMPLEMENTED

#### RATCH-04: Ratchet Playback
```
GIVEN a step has ratcheting enabled with N sub-triggers
WHEN the sequencer reaches that step
THEN N evenly-spaced gate events fire within that single step duration
```
**Status**: NOT IMPLEMENTED

### 3.2 Alt Note Page (Extended Note)

**Original**: Accessed by pressing the note key a second time. Functionally identical to the main note screen but provides a second note layer. The two note values are ADDITIVE: indices from both pages combine, then the result is mapped to the scale using modulo wrapping.

#### ALTNOTE-01: Access Alt Note Page
```
GIVEN the note page is currently displayed
WHEN the user presses the note page key (column 7, row 8) again
THEN the display switches to the alt note page
AND the note page key blinks to indicate extended mode
```
**Status**: NOT IMPLEMENTED

#### ALTNOTE-02: Alt Note Additive Behavior
```
GIVEN the note page has value N1 at step S
AND the alt note page has value N2 at step S
WHEN the sequencer reaches step S
THEN the effective note degree is (N1 + N2) modulo scale_length
AND this combined degree is used for pitch lookup in the scale
```
**Status**: NOT IMPLEMENTED

#### ALTNOTE-03: Alt Note Independent Loop
```
GIVEN the alt note parameter has its own independent loop start/end
WHEN the sequencer advances
THEN the alt note loop cycles independently of the main note loop
AND this creates polymetric note combinations
```
**Status**: NOT IMPLEMENTED

### 3.3 Glide Page (Extended Octave)

**Original**: Accessed by pressing the octave key a second time. Controls portamento/slew amount per step.

- Row 7: 0ms slew (no glide)
- Row 6: 20ms slew
- Row 5: 40ms slew
- Row 4: 60ms slew
- Row 3: 80ms slew
- Row 2: 100ms slew
- Row 1: 120ms slew

#### GLIDE-01: Access Glide Page
```
GIVEN the octave page is currently displayed
WHEN the user presses the octave page key (column 8, row 8) again
THEN the display switches to the glide page
AND the octave page key blinks to indicate extended mode
```
**Status**: NOT IMPLEMENTED

#### GLIDE-02: Glide Display
```
GIVEN the glide page is active
THEN rows 1-7 display glide/slew amounts for each step
AND row 7 = 0ms (no glide), row 1 = 120ms (maximum glide)
AND the active glide value is shown per step
```
**Status**: NOT IMPLEMENTED

#### GLIDE-03: Glide Playback
```
GIVEN a step has a non-zero glide value
WHEN the sequencer transitions to that step
THEN the pitch slides from the previous note to the new note
AND the slide duration is determined by the glide value (0-120ms)
```
**Status**: NOT IMPLEMENTED (would require voice-level portamento support)

---

## 4. Modifier Modes

Modifiers are accessed by holding a modifier key on row 8 while interacting with the grid. They apply to whichever parameter page is currently active.

### 4.1 Loop Modifier

**Original**: Hold column 11 on row 8. While held:
- First grid press sets loop start point
- Second grid press sets loop end point
- If end < start, the loop wraps around
- Pressing a track button while loop is held toggles that track's mute

**re.kriate**: Hold column 12 on row 8. Two-press loop editing (start, then end). No wrapping loops. No mute-via-loop.

#### LOOP-01: Loop Start/End Setting
```
GIVEN the loop modifier key is held
WHEN the user presses a column in rows 1-7
THEN that column is recorded as the loop start
WHEN the user presses a second column
THEN the loop boundaries are set from min(first, second) to max(first, second)
AND the active parameter's loop for the active track is updated
```
**Status**: IMPLEMENTED

#### LOOP-02: Loop Wrapping
```
GIVEN the loop modifier key is held
WHEN the user sets loop_end to a column LEFT of loop_start
THEN the loop wraps around (plays from start to step 16, then step 1 to end)
```
**Status**: NOT IMPLEMENTED -- `track.set_loop` rejects start > end.

#### LOOP-03: Mute via Loop + Track
```
GIVEN the loop modifier key is held
WHEN the user presses a track button (columns 1-4) on row 8
THEN that track's mute state is toggled
```
**Status**: NOT IMPLEMENTED -- Mute is on dedicated column 5 button instead.

#### LOOP-04: Loop Display
```
GIVEN a parameter has a non-default loop
THEN steps within the loop show increased brightness
AND steps outside the loop show reduced brightness
```
**Status**: IMPLEMENTED

#### LOOP-05: Per-Parameter Independent Loops
```
GIVEN track 1's trigger loop is steps 1-8
AND track 1's note loop is steps 1-12
WHEN the sequencer runs
THEN the trigger cycles through 8 steps
AND the note cycles through 12 steps independently
AND this creates polymetric patterns
```
**Status**: IMPLEMENTED

### 4.2 Time/Division Modifier

**Original**: Hold column 12 on row 8. While held, the top row shows clock divisions 1-16 for the current parameter. Each parameter can have its own clock division.

#### TIME-01: Time Modifier Display
```
GIVEN the time modifier key is held
THEN row 1 shows 16 columns representing clock divisions 1-16
AND the currently selected division is highlighted at brightness 8
```
**Status**: NOT IMPLEMENTED -- No time modifier on the grid. Clock division is only available via norns params (per-track, not per-parameter).

#### TIME-02: Per-Parameter Clock Division
```
GIVEN the time modifier is active on the note page
WHEN the user selects division 3
THEN the note parameter advances every 3 clock ticks
AND this is independent of the trigger's clock division
```
**Status**: NOT IMPLEMENTED -- Our sequencer uses per-track division only (all params in a track share one division). The original kria has per-parameter clock division via the time modifier.

### 4.3 Probability Modifier

**Original**: Hold column 13 on row 8. While held, 4 center rows (rows 2-5) for each column act as a vertical fader controlling per-step probability: 100%, ~75%, ~50%, ~25%, 0%.

#### PROB-01: Probability Display
```
GIVEN the probability modifier key is held
THEN rows 2-5 display per-step probability values
AND a step with full probability shows all 4 rows lit
AND a step with 50% shows the bottom 2 rows lit
AND a step with 0% shows no rows lit
```
**Status**: NOT IMPLEMENTED

#### PROB-02: Probability Editing
```
GIVEN the probability modifier key is held
WHEN the user presses a cell in rows 2-5 at a column
THEN the probability for that step is set based on the row pressed
AND row 5 = ~25%, row 4 = ~50%, row 3 = ~75%, row 2 = 100%
```
**Status**: NOT IMPLEMENTED

#### PROB-03: Probability Playback
```
GIVEN a step has probability set to 50%
WHEN the sequencer reaches that step
THEN there is approximately a 50% chance the step fires
AND the probability is evaluated independently each time the step is reached
```
**Status**: NOT IMPLEMENTED

#### PROB-04: Per-Parameter Probability
```
GIVEN the probability modifier applies to whichever page is active
THEN trigger probability, note probability, octave probability, etc. can each be set independently
AND each parameter's extended subpage has its own probability, clock division, and loop controls
```
**Status**: NOT IMPLEMENTED

---

## 5. Scale Page

**Original**: Accessed via column 15 on row 8. The scale page has two regions:

### Left Region (columns 1-8, rows 1-4): Per-Track Configuration
- Column 1, Rows 1-4: Teletype clocking toggle per track
- Column 2, Rows 1-4: Trigger clocking toggle per track
- Columns 4-8, Rows 1-4: Direction mode selector per track (5 modes x 4 tracks)

### Right Region (columns 9-16): Scale Interval Editor
- Each row represents a scale degree
- Horizontal position within the row sets the interval (in semitones) from the previous degree
- The scale is built bottom-up from the root note
- Transposition: moving the bottom row right transposes the entire scale

### Bottom Rows: Scale Slot Selection
- Rows 6-7, columns 1-16: 16 scale preset slots (8 per row)

#### SCALE-01: Scale Page Access
```
GIVEN the grid is connected
WHEN the user presses column 15 on row 8
THEN the scale editor page is displayed
```
**Status**: NOT IMPLEMENTED -- Scale is only editable via norns/seamstress params menu.

#### SCALE-02: Scale Interval Editor
```
GIVEN the scale page is active
THEN the right half of the grid shows the scale interval editor
AND each row represents one scale degree
AND pressing a column on a row sets the semitone interval for that degree
AND the scale is built bottom-up (row 7 = root, row 6 = 2nd degree, etc.)
```
**Status**: NOT IMPLEMENTED

#### SCALE-03: Scale Preset Selection
```
GIVEN the scale page is active
THEN rows 6-7 show 16 scale preset slots
AND the currently selected scale is highlighted
WHEN the user presses a scale slot
THEN that scale preset is loaded
```
**Status**: NOT IMPLEMENTED

#### SCALE-04: Live Scale Adjustment
```
GIVEN the scale page is active
WHEN the user holds a scale step key and presses another key on the same row
THEN the pitch for that scale degree is temporarily adjusted
AND the adjustment is shown dimly on the grid
AND this is a performance gesture for live transposition
```
**Status**: NOT IMPLEMENTED

---

## 6. Pattern Page and Meta-Sequencer

**Original**: Accessed via column 16 on row 8 (sets cue mode).

### 6.1 Basic Pattern Operations

#### PAT-01: Pattern Page Access
```
GIVEN the grid is connected
WHEN the user presses column 16 on row 8
THEN the pattern page is displayed
AND row 1 shows 16 pattern slots
AND the current pattern is highlighted at brightness 8
```
**Status**: NOT IMPLEMENTED -- Column 16 is play/stop.

#### PAT-02: Pattern Load
```
GIVEN the pattern page is active
WHEN the user momentarily presses a pattern slot on row 1
THEN that pattern is loaded immediately
AND all track data (triggers, notes, octaves, durations, etc.) is replaced
```
**Status**: NOT IMPLEMENTED

#### PAT-03: Pattern Store
```
GIVEN the pattern page is active
WHEN the user holds a pattern slot key on row 1
THEN the current sequence data is stored into that slot
AND the key pulses to confirm the store operation
```
**Status**: NOT IMPLEMENTED

#### PAT-04: Pattern Cueing
```
GIVEN the pattern page is active
WHEN the user holds the pattern button (column 16 row 8) and selects a pattern on row 1
THEN that pattern is cued (queued) to load at the next cue point
AND row 2 shows the cue clock divider
AND the cued pattern plays when the cue countdown reaches zero
```
**Status**: NOT IMPLEMENTED

### 6.2 Meta-Sequencer

**Original**: Activated by holding the pattern button and pressing a key on row 7.

#### META-01: Meta-Sequencer Activation
```
GIVEN the pattern page is active
WHEN the user holds the pattern button and presses a key on row 7
THEN meta-pattern mode is activated
AND the grid layout changes to show the meta-sequence
```
**Status**: NOT IMPLEMENTED

#### META-02: Meta-Sequence Display
```
GIVEN meta-pattern mode is active
THEN row 1 shows pattern selection for the current meta-step
AND row 2 shows the meta-step clock divider
AND rows 3-6 show the meta-sequence (64 possible steps across 4 rows)
AND row 7 shows the meta-sequence length/duration
```
**Status**: NOT IMPLEMENTED

#### META-03: Meta-Sequence Programming
```
GIVEN meta-pattern mode is active
WHEN the user presses a cell in rows 3-6
THEN a pattern + duration is stored at that meta-step position
AND each meta-step specifies which pattern to play and for how many loops
```
**Status**: NOT IMPLEMENTED

#### META-04: Meta-Sequence Playback
```
GIVEN meta-pattern mode is active and the sequencer is running
THEN the meta-sequencer advances through the programmed pattern sequence
AND each meta-step plays its assigned pattern for the specified duration
AND when a meta-step completes, the next pattern loads automatically
```
**Status**: NOT IMPLEMENTED

---

## 7. Direction Modes

**Original**: Configured per-track on the scale page (left region, columns 4-8, rows 1-4). Five modes:

#### DIR-01: Forward Direction
```
GIVEN a track's direction is set to Forward
WHEN the sequencer advances
THEN the playhead moves left-to-right through the loop
AND wraps from loop_end back to loop_start
```
**Status**: IMPLEMENTED (this is the only direction mode)

#### DIR-02: Reverse Direction
```
GIVEN a track's direction is set to Reverse
WHEN the sequencer advances
THEN the playhead moves right-to-left through the loop
AND wraps from loop_start back to loop_end
```
**Status**: NOT IMPLEMENTED

#### DIR-03: Triangle/Pendulum Direction
```
GIVEN a track's direction is set to Triangle
WHEN the sequencer advances
THEN the playhead bounces between loop_start and loop_end
AND reverses direction at each boundary instead of wrapping
```
**Status**: NOT IMPLEMENTED

#### DIR-04: Drunk Direction
```
GIVEN a track's direction is set to Drunk
WHEN the sequencer advances
THEN the playhead randomly moves one step forward or backward
AND wraps at loop boundaries
```
**Status**: NOT IMPLEMENTED

#### DIR-05: Random Direction
```
GIVEN a track's direction is set to Random
WHEN the sequencer advances
THEN the playhead jumps to any random step within the loop
AND each step in the loop has equal probability
```
**Status**: NOT IMPLEMENTED

---

## 8. Config Page

**Original**: Accessed by holding Key 2 (hardware button, not grid). Shows configuration options on the grid.

### 8.1 Note Sync

#### CONFIG-01: Note Sync Toggle
```
GIVEN the config page is active (Key 2 held)
THEN the left quadrant (rows 2-5, columns 2-5) shows note sync status
AND pressing any key in this region toggles note sync on/off
AND when note sync is ON, editing notes on the note page also sets/clears triggers
```
**Status**: NOT IMPLEMENTED

### 8.2 Loop Sync

#### CONFIG-02: Loop Sync Modes
```
GIVEN the config page is active
THEN the right quadrant shows loop sync options
AND there are three modes:
  - None: all parameters have fully independent loops
  - Track: parameters within a track share loop points, but tracks differ
  - All: all tracks and parameters share the same loop points
```
**Status**: NOT IMPLEMENTED (all loops are always independent)

### 8.3 Duration Tie Mode

#### CONFIG-03: Note Tie Duration
```
GIVEN the config page is active
WHEN the user presses the note-tie toggle (bottom-middle area)
THEN note tie mode is enabled/disabled
AND when enabled, setting a step's duration to maximum creates a tied note
AND tied notes do not re-trigger, creating legato phrasing
```
**Status**: NOT IMPLEMENTED

### 8.4 Brightness Config

#### CONFIG-04: Grid Brightness Setting
```
GIVEN the config page is active
THEN the top-left area (row 1, columns 1-3) shows brightness options
AND pressing column 1 sets non-varibright mode (binary on/off)
AND pressing column 2 sets 4-step varibright
AND pressing column 3 sets 16-step varibright
```
**Status**: NOT IMPLEMENTED (always assumes 16-step varibright)

---

## 9. Clock/Time Page

**Original**: Accessed via Key 1 (hardware button). Shows clock configuration.

#### CLOCK-01: Internal Clock Control
```
GIVEN the clock page is active and internal clocking is selected
THEN row 1 shows a pulse indicator
AND row 2 shows rough tempo intervals (16 steps)
AND row 3 shows fine tempo intervals (16 steps)
AND center 4 keys provide incremental tempo adjustment
```
**Status**: NOT IMPLEMENTED (clock is managed by norns/seamstress system clock)

#### CLOCK-02: External Clock Division
```
GIVEN the clock page is active and external clocking is selected
THEN row 2 shows clock division multiplier options
AND the bottom half shows sync mode glyphs:
  - Note Division Sync: trigger/note divisions are linked
  - Division Cueing: division changes quantize to loop restart
  - Division Sync: None/Track/All modes
```
**Status**: NOT IMPLEMENTED (clock sync is handled by norns/seamstress platform)

---

## 10. Preset System

**Original**: 8 preset slots accessible via hardware preset button. Each preset stores all pattern data, scale data, and configuration.

#### PRESET-01: Preset Save/Load
```
GIVEN the preset mode is active
THEN 8 slots are shown in the first column
AND the current preset is highlighted
AND double-pressing a slot loads that preset
AND pressing and holding a slot saves to that slot
```
**Status**: NOT IMPLEMENTED (no preset system)

#### PRESET-02: Preset Glyph
```
GIVEN the preset mode is active
THEN the right 8x8 quadrant shows a custom visual glyph for each preset
AND users can draw custom patterns as visual identifiers
```
**Status**: NOT IMPLEMENTED

---

## 11. Sequencer Engine Features

### 11.1 Per-Track Clock Division

#### ENGINE-01: Per-Track Division
```
GIVEN track 1 has division set to 1/8
AND track 2 has division set to 1/4
WHEN both tracks are playing
THEN track 1 advances twice as fast as track 2
```
**Status**: IMPLEMENTED -- Each track has its own `division` field and clock coroutine.

### 11.2 Per-Parameter Clock Division

#### ENGINE-02: Per-Parameter Division (via Time Modifier)
```
GIVEN track 1's trigger has time division 1
AND track 1's note has time division 3
WHEN the sequencer runs
THEN triggers fire every step
AND notes change every 3 steps
AND this creates evolving patterns where triggers repeat with different notes
```
**Status**: NOT IMPLEMENTED -- All parameters in a track share one clock. The original kria allows per-parameter division via the time modifier.

### 11.3 Trigger Clocking

#### ENGINE-03: Trigger Clocking Mode
```
GIVEN trigger clocking is enabled for a track
WHEN the sequencer clock ticks
THEN only the trigger parameter advances on each tick
AND all other parameters (note, octave, duration, etc.) advance only when a trigger fires
```
**Status**: NOT IMPLEMENTED -- All parameters always advance together on each clock tick.

### 11.4 Track Muting

#### MUTE-01: Track Mute
```
GIVEN a track is muted
WHEN the sequencer reaches a trigger on that track
THEN no note is fired
AND the playhead continues to advance (or not, depending on implementation)
```
**Status**: IMPLEMENTED -- Muted tracks skip all advancement and note output in `sequencer.step_track`.

**Note on mute behavior**: In our implementation, muted tracks do NOT advance their playheads (`step_track` returns early). In the original kria, muted tracks continue advancing their playheads silently. This is a behavioral difference.

### 11.5 Reset

#### ENGINE-04: Reset All Playheads
```
GIVEN the sequencer is running
WHEN a reset signal is received
THEN all playheads for all tracks and all parameters return to their loop_start
```
**Status**: IMPLEMENTED

---

## Summary: Feature Coverage

### Implemented Features
1. 4-track step sequencer with 16 steps per track
2. 5 parameter pages: trigger, note, octave, duration, velocity (velocity is our addition)
3. Per-parameter independent loop lengths (polymetric sequencing)
4. Grid navigation row with track select and page select
5. Loop modifier (hold to edit loop boundaries)
6. Per-track clock division (via params, not grid)
7. Track muting (via dedicated button, not loop+track gesture)
8. Scale quantization (via params, not grid editor)
9. Play/stop and reset controls
10. MIDI voice output with note-off scheduling
11. Keyboard shortcuts for seamstress (space, r, m, 1-4, q/w/e/t/y)

### Partially Implemented Features
1. Navigation row layout (differs from original: mute button, no extended page toggles, loop at different position)
2. Loop editing (works but no wrapping loops, no mute-via-loop gesture)
3. Octave page (no base octave selector on row 1)
4. Duration page (no duration multiplier on row 1)

### Missing Features (Original Kria)
1. **Extended pages**: Ratchet/repeat, alt note, glide -- accessed by double-pressing page keys
2. **Time modifier**: Per-parameter clock division on grid
3. **Probability modifier**: Per-step probability on grid
4. **Scale editor page**: Grid-based scale interval editing
5. **Pattern page**: 16 pattern slots with load/store/cue
6. **Meta-sequencer**: Sequence of patterns with per-step duration
7. **Direction modes**: Reverse, triangle/pendulum, drunk, random
8. **Config page**: Note sync, loop sync, duration tie, brightness
9. **Trigger clocking**: Parameters advance only on trigger fire
10. **Note sync**: Linked note/trigger editing
11. **Loop wrapping**: End-before-start wrapping loops
12. **Preset system**: 8 saveable presets with glyphs
13. **Clock/time page**: Grid-based clock configuration

### re.kriate Extensions (Not in Original Kria)
1. **Velocity page**: Per-step velocity (original kria is CV/gate, no velocity)
2. **Play/stop on grid**: Column 16 toggles playback (original uses hardware buttons)
3. **Dedicated mute button**: Column 5 on nav row (original uses loop+track gesture)
4. **Keyboard input**: Seamstress keyboard shortcuts for control without grid
5. **Screen display**: Desktop/norns screen showing state information
