# Swing/Shuffle Reference Research

**Feature**: 007-swing-shuffle | **Date**: 2026-03-25

## 1. Original Kria (Monome Ansible) and Swing

### Finding: Kria does NOT implement swing

After reviewing the monome/ansible CHANGELOG (all versions through v3.x), the Kria documentation at monome.org, and the Ansible Kria Feature Requests thread on lines (llllllll.co), **the original kria firmware has no swing or shuffle feature**.

The timing-related features that kria does have:
- **Clock division per track** (via Teletype or grid)
- **Step direction modes** (forward, reverse, pendulum, drunk, random) -- added in v2.0.0
- **Trigger clocking** -- when enabled, parameters besides trigger and ratchet advance only when a trigger fires, not on each clock step
- **Ratcheting** -- subdivides a step into repeated triggers

Swing has been **requested** in the Ansible Kria Feature Requests thread on lines (llllllll.co/t/ansible-kria-feature-requests/4846), where a user suggested it could be "another modifier page like duration," but it was never implemented in the official firmware.

The n.kria norns port (zjb-s/n.kria) similarly does not implement swing. Its timing improvements in v0.23 focused on accuracy and sync groups, not groove/shuffle.

**Sources**:
- [Kria documentation](https://monome.org/docs/ansible/kria/)
- [Ansible CHANGELOG](https://github.com/monome/ansible/blob/main/CHANGELOG.md)
- [Ansible Kria Feature Requests](https://llllllll.co/t/ansible-kria-feature-requests/4846)
- [n.kria GitHub](https://github.com/zjb-s/n.kria)

### Implication for re.kriate

Since kria has no swing to replicate, re.kriate's implementation is a **novel extension** of the kria concept. This gives design freedom but means there is no "canonical" behavior to match. The implementation should follow standard sequencer swing conventions (MPC/Elektron/TR-909 style) rather than trying to reverse-engineer something from kria.

---

## 2. How Hardware Sequencers Implement Swing

### Roger Linn / MPC Swing (the industry standard)

Roger Linn's implementation in the Linn LM-1 and Akai MPC series established the de facto standard for swing in electronic music.

**Algorithm**: Delay every even-numbered 16th note within each 8th note pair. The swing percentage represents the ratio of time given to the first 16th note vs. the second within each pair.

**Percentage meaning** (MPC convention):
- **50%** = no swing (both 16th notes equally spaced)
- **54%** = subtle looseness, doesn't sound like "swing" but adds life
- **58-62%** = moderate groove
- **66%** = perfect triplet feel (first 16th gets 2/3 of the 8th note, second gets 1/3)
- **71%** = heavy swing
- **75%** = maximum (MPC caps here; beyond this it no longer sounds like swing)

**Key insight from Roger Linn**: "Between 50% and around 70% are lots of wonderful little settings that, for a particular beat and tempo, can change a rigid beat into something that makes people move."

**Resolution**: The MPC uses 96 PPQN (pulses per quarter note), giving 24 ticks per 16th note. This allows very fine swing adjustments. At lower resolutions, fewer distinct swing amounts are available.

**Sources**:
- [Roger Linn interview on swing](https://www.attackmagazine.com/features/interview/roger-linn-swing-groove-magic-mpc-timing/)
- [About MPC Swing](https://palsen.tumblr.com/post/182157488304/about-mpc-swing)
- [MPC Swing in Reason](https://melodiefabriek.com/sound-tech/mpc-swing-reason/)

### Roland TR-909 Shuffle

The TR-909 was the first Roland drum machine with shuffle (the TR-808 had none).

**Algorithm**: Same basic approach -- delay even-numbered 16th notes. But the TR-909 uses **discrete steps** rather than a continuous percentage.

**Resolution**: At 96 PPQN (the TR-909's internal resolution), each 16th note spans 24 ticks. Shuffle delays the even 16th by:
- Setting 1: 2/96 of a beat (2 ticks)
- Setting 2: 4/96 of a beat (4 ticks)
- Setting 3: 6/96 of a beat (6 ticks)
- Setting 4: 8/96 of a beat (8 ticks)
- Setting 5: 10/96 of a beat (10 ticks)
- Setting 6: 12/96 of a beat (12 ticks)

This translates to approximately 50%, 52%, 54%, 56%, 58%, 60% in MPC terms. The TR-909's maximum shuffle is noticeably lighter than the MPC's maximum.

**Source**: [TR-909 shuffle implementation](https://www.modwiggler.com/forum/viewtopic.php?t=135002)

### Elektron (Digitakt/Digitone)

- **Range**: 50% to 80% (wider than MPC, allows extreme swing)
- **Scope**: Per-pattern, not per-track (all tracks in a pattern share the same swing)
- **Extra feature**: Micro-timing per step allows manual nudging beyond the global swing
- Per-track swing has been a common feature request from Elektron users

**Source**: [Elektron swing discussion](https://www.elektronauts.com/t/how-can-i-change-swing-for-each-track/60421)

### Summary of Industry Approaches

| Sequencer | Swing Range | Scope | Resolution |
|-----------|-------------|-------|------------|
| MPC | 50-75% | Per-track (via TC) | 96 PPQN continuous |
| TR-909 | ~50-60% | Global (6 steps) | 96 PPQN discrete |
| Elektron | 50-80% | Per-pattern | Fine |
| Ableton | 0-100% (mapped) | Per-clip groove | Sample-accurate |
| re.kriate | 0-100 (custom) | Per-track | Float (continuous) |

---

## 3. Clock Math for Seamstress/Norns

### The `clock.sync` API

Both norns and seamstress provide `clock.sync(beat_value [, offset])`:
- `beat_value`: fraction of a beat to sync to (e.g., 1/4 = sixteenth note)
- `offset`: optional delay in beats added to the sync point

The norns documentation shows a swing example using the offset parameter:

```lua
local offset = beat / 2
local swing = 0  -- toggles 0/1
clock.sync(beat, offset * swing)
```

This approach uses a fixed sync quantum and adds an offset on even steps. It has a drawback: it ties the swing to the sync grid, which can cause drift issues with some clock sources.

### re.kriate's Approach: Alternating Durations (already implemented)

re.kriate uses a **different and better approach** for its use case: instead of using `clock.sync`'s offset parameter, it alternates the sync duration itself between odd and even steps.

```lua
-- Even steps: shorter duration
-- Odd steps: longer duration
-- Pair always sums to 2 * division (preserves overall tempo)
clock.sync(swing_duration(div, swing, is_odd))
```

**Advantages of alternating duration over offset**:
1. **Pair-preserving**: odd + even always sums to exactly 2 * div, so overall tempo is perfectly maintained regardless of swing amount
2. **Simpler state**: no need to track absolute beat position or manage offset accumulation
3. **Works with all divisions**: scales proportionally with any clock division
4. **No drift**: each pair is self-contained; no accumulated timing error

### The Swing Duration Formula

The formula used in re.kriate (from `sequencer.swing_duration`):

```
pair = 2 * div
odd_duration = pair / (2 - S/100)
even_duration = pair - odd_duration
even_duration = max(even_duration, pair * MIN_SWING_RATIO)
```

Where `S` is swing amount (0-100) and `MIN_SWING_RATIO = 0.01`.

**Verification at key swing values**:

| Swing (S) | Odd Duration | Even Duration | Ratio (odd:even) | Feel |
|-----------|-------------|---------------|-------------------|------|
| 0 | div | div | 1:1 | Straight |
| 25 | 1.143 * div | 0.857 * div | 4:3 | Subtle groove |
| 33 | 1.2 * div | 0.8 * div | 3:2 | Light swing |
| 50 | 1.333 * div | 0.667 * div | 2:1 | Triplet feel |
| 67 | 1.5 * div | 0.5 * div | 3:1 | Heavy swing |
| 75 | 1.6 * div | 0.4 * div | 4:1 | Very heavy |
| 100 | ~2 * div | floor | max | Extreme |

**Mapping to MPC percentages** (for reference):

| re.kriate | MPC equivalent | Feel |
|-----------|----------------|------|
| 0 | 50% | Straight |
| 25 | ~57% | Subtle |
| 33 | ~60% | Light |
| 50 | 66% | Triplet |
| 67 | ~75% | MPC max |
| 100 | beyond MPC | Extreme |

The re.kriate 0-100 range maps roughly to the MPC's 50-75% range (and beyond). A value of ~67 in re.kriate corresponds to the MPC's maximum swing of 75%.

### Why Not MPC-Style 50-75 Range?

The spec uses 0-100 rather than the MPC convention of 50-75 (or 50-80 like Elektron). Reasons:
1. **0 = off** is more intuitive than **50 = off** for a parameter labeled "swing"
2. **Wider range** allows extreme effects beyond what MPC permits (useful for experimental music)
3. **Integer granularity**: 0-100 gives 101 distinct values, while 50-75 gives only 26
4. **Consistent with other 0-100 params**: feels natural alongside percentage-based controls

---

## 4. Edge Cases and Interactions

### Swing + Ratchet

**How it works in re.kriate**: Ratchet subdivisions happen *within* the swing-adjusted step duration. The `step_track` function fires after `clock.sync(swing_duration(...))` returns, meaning the ratchet's timing envelope is the swing-modified step length.

**Behavior**: If an odd step has ratchet=3, the three ratchet hits are evenly spaced within the longer (swing-extended) odd step. If an even step has ratchet=3, the three hits are crammed into the shorter even step. This creates an interesting musical effect where ratchets on odd beats are more relaxed and ratchets on even beats are more frantic.

**Potential concern**: At very high swing values (90-100), even-step ratchets happen in an extremely short window. With ratchet=7 and swing=100, each sub-hit would be approximately `(pair * 0.01) / 7` beats long. At 120 BPM with 1/16 division, that is about 0.7ms per sub-hit. This is at the edge of audibility but should not cause errors since `clock.sync` handles arbitrarily small values.

### Swing + Direction Modes

**How it works**: Direction (forward, reverse, pendulum, drunk, random) affects which *step positions* are visited. Swing affects the *timing between* steps. These are independent axes.

**Key detail**: The swing odd/even counter is based on the `step_count` variable in `track_clock`, NOT on the musical step position. This means:
- In reverse mode: step_count still goes 1, 2, 3, 4... (odd, even, odd, even), even though the sequence position goes 16, 15, 14, 13...
- In pendulum mode: the timing pattern (long-short-long-short) continues regardless of direction changes
- In random/drunk mode: timing is still strictly alternating, even though step positions are unpredictable

This is the correct behavior -- swing should create a consistent rhythmic pulse regardless of the melodic/harmonic direction.

### Swing + Clock Division

**How it works**: The swing formula uses `div` (the base division sync value) directly, so swing scales proportionally with division. A track at 1/8 notes with 50% swing has the same *ratio* of odd:even as a track at 1/16 notes with 50% swing, but the absolute timing differences are larger.

**No special handling needed**: This is automatic from the formula.

### Swing + Mute

**How it works**: The `track_clock` loop continues running while a track is muted (advancing the step counter and calling `clock.sync`). Only note output is suppressed. This means:
- The step counter continues, maintaining swing alignment
- When unmuted, the swing pattern picks up exactly where it was
- Muted tracks stay in tempo with other tracks

### Swing Changed Mid-Playback

**How it works**: `track.swing` is read on every iteration of the `track_clock` loop. If the user changes swing via the param system while the sequencer is running, the new value takes effect on the next step. There is no discontinuity because each step pair is self-contained.

**Subtle behavior**: If swing changes between the odd and even step of a pair, the pair sum may not equal exactly 2*div for that one transition. This is musically imperceptible and self-corrects on the next pair.

### Swing at Loop Boundaries

**Behavior**: The step_count (odd/even tracker) is independent of the loop position. If a track has a 5-step loop, step_count goes 1(odd), 2(even), 3(odd), 4(even), 5(odd), 6(even)... while the loop position goes 1, 2, 3, 4, 5, 1, 2, 3, 4, 5... The swing pattern is determined by the counter, not the loop position.

**Implication for odd-length loops**: With a 5-step loop at 50% swing, the timing pattern is:
```
Step pos: 1    2    3    4    5    1    2    3    ...
Counter:  1    2    3    4    5    6    7    8    ...
Timing:   long short long short long short long short ...
```

The first time step 1 plays, it gets long timing. The second time step 1 plays (after the loop wraps), it gets short timing. This creates a 2-loop (10-step) super-pattern of timing, which is musically interesting and consistent with how polymetric swing typically works.

---

## 5. Recommended Implementation for re.kriate

### Current State

Swing is **already implemented** in the codebase as of the current branch:

1. **`lib/track.lua`**: `swing = 0` field on each track (line 116)
2. **`lib/sequencer.lua`**: `swing_duration()` pure function (lines 42-54), `track_clock` uses it with a step counter (lines 100-112)
3. **`lib/app.lua`**: Per-track `swing_N` params registered (lines 65-71)
4. **`specs/swing_shuffle_spec.lua`**: 14 tests covering formula, integration, patterns, and composition

### Parameter Recommendation

| Parameter | Value |
|-----------|-------|
| Name | `swing_N` (per track) |
| Type | Integer |
| Range | 0-100 |
| Default | 0 |
| Label | "track N swing" |

**Default of 0** is correct: no swing, all steps evenly spaced, identical to behavior before swing was added.

### Musical Reference Points for Users

If documentation or tooltips are added:
- **0** = straight time (no swing)
- **25** = subtle groove (equivalent to ~57% MPC)
- **50** = triplet feel (equivalent to 66% MPC, the "classic" swing)
- **67** = heavy swing (equivalent to 75% MPC, MPC's maximum)
- **75-100** = extreme/experimental (beyond typical hardware range)

### Formula Confirmation

The formula `odd_dur = pair / (2 - S/100)` is mathematically correct and produces:
- Exact 1:1 ratio at S=0
- Exact 2:1 ratio at S=50 (spec requirement FR-004)
- Correct floor clamping at S=100 (spec requirement FR-005)

This was verified in the test suite (`specs/swing_shuffle_spec.lua`).

---

## 6. Future Considerations (Not In Scope)

These are potential enhancements observed during research, noted for future reference:

1. **Per-step micro-timing** (Elektron style): Allow individual steps to be nudged forward or backward in time. This would be a separate feature from global swing.

2. **Swing grid page**: The kria feature request thread suggested swing could be "another modifier page like duration." A grid page could show a bar-graph for per-step swing or a single row for per-track swing amount.

3. **Swing applied per step-pair rather than per step**: Some advanced sequencers allow different swing amounts for different pairs within the bar (e.g., more swing on beats 2 and 4). This would be a significant complexity increase.

4. **Velocity humanization tied to swing**: Roger Linn noted that velocity reduction on off-beat 16th notes (the swung notes) contributes to the groove feel. A "groove template" approach could couple swing timing with velocity shaping.

5. **MPC-style percentage display**: Optionally show the equivalent MPC percentage alongside the 0-100 value for users familiar with MPC workflow.
