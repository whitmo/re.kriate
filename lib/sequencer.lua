-- lib/sequencer.lua
-- Clock-driven sequencer with per-param step advancement and voice output

local track_mod = require("lib/track")
local scale_mod = require("lib/scale")
local direction_mod = require("lib/direction")
local meta_pattern = require("lib/meta_pattern")
local log = require("lib/log")

local M = {}
local function roll(ctx)
  if ctx and ctx.rng then
    return ctx.rng() * 100
  end
  return math.random() * 100
end

-- Glide time map: step value -> portamento time in seconds
-- 1 = off, 2-7 = increasing portamento duration
M.GLIDE_TIME_MAP = {
  [1] = 0,
  [2] = 0.05,
  [3] = 0.1,
  [4] = 0.2,
  [5] = 0.4,
  [6] = 0.8,
  [7] = 1.6,
}

-- Division map: division value -> clock.sync argument
-- 1 = sixteenth notes (1/4 beat), higher = slower
M.DIVISION_MAP = {
  [1] = 1/4,   -- sixteenth
  [2] = 1/3,   -- triplet sixteenth
  [3] = 1/2,   -- eighth
  [4] = 2/3,   -- triplet eighth
  [5] = 1,     -- quarter
  [6] = 2,     -- half
  [7] = 4,     -- whole
}

-- Minimum even-step fraction of pair duration (floor to prevent zero/negative sync)
M.MIN_SWING_RATIO = 0.01

-- Compute swing-adjusted duration for a single step
-- div: base division sync value
-- swing: integer 0-100
-- is_odd: true for odd steps (1st, 3rd, 5th...)
function M.swing_duration(div, swing, is_odd)
  if swing == 0 then return div end
  local pair = 2 * div
  local odd_dur = pair / (2 - swing / 100)
  local even_dur = pair - odd_dur
  local floor = pair * M.MIN_SWING_RATIO
  if even_dur < floor then even_dur = floor end
  if is_odd then
    return pair - even_dur  -- recalc odd to preserve pair sum when floor applied
  else
    return even_dur
  end
end

-- Number of scale degrees in a heptatonic scale
local SCALE_DEGREES = 7

function M.start(ctx)
  if ctx.playing then return end
  ctx.playing = true
  if ctx.events then ctx.events:emit("sequencer:start", {}) end
  -- one clock coroutine per track
  ctx.clock_ids = {}
  for t = 1, track_mod.NUM_TRACKS do
    ctx.clock_ids[t] = clock.run(log.wrap(function()
      M.track_clock(ctx, t)
    end, "track_clock:" .. t))
  end
end

function M.stop(ctx)
  if not ctx.playing then return end
  ctx.playing = false
  if ctx.events then ctx.events:emit("sequencer:stop", {}) end
  if ctx.clock_ids then
    for _, id in ipairs(ctx.clock_ids) do
      clock.cancel(id)
    end
    ctx.clock_ids = nil
  end
  -- silence all voices (CC 123 all-notes-off)
  if ctx.voices then
    for t = 1, track_mod.NUM_TRACKS do
      local voice = ctx.voices[t]
      if voice and voice.all_notes_off then
        voice:all_notes_off()
      end
    end
  end
  -- clear all sprite voices
  if ctx.sprite_voices then
    for t = 1, track_mod.NUM_TRACKS do
      local sv = ctx.sprite_voices[t]
      if sv and sv.all_notes_off then
        sv:all_notes_off()
      end
    end
  end
end

function M.track_clock(ctx, track_num)
  local step_count = 0
  while ctx.playing do
    -- Re-read track each iteration to pick up meta-pattern switches
    local track = ctx.tracks[track_num]
    local div = M.DIVISION_MAP[track.division] or M.DIVISION_MAP[1]
    step_count = step_count + 1
    local is_odd = (step_count % 2 == 1)
    clock.sync(M.swing_duration(div, track.swing or 0, is_odd))
    if ctx.playing then
      M.step_track(ctx, track_num)
    end
  end
end

function M.step_track(ctx, track_num)
  local track = ctx.tracks[track_num]
  local dir = track.direction  -- nil defaults to "forward" inside direction.advance

  -- advance trigger first (always ticks independently)
  local vals = {}
  local trig_param = track.params.trigger
  local old_trig_pos = trig_param.pos
  if track_mod.should_advance(trig_param) then
    vals.trigger = direction_mod.advance(trig_param, dir)
  else
    vals.trigger = track_mod.peek(trig_param)
  end

  -- when trig_clock is enabled and trigger didn't fire, freeze all non-trigger params
  local trig_gates = track.trig_clock and vals.trigger ~= 1

  -- advance probability param (no self-referencing gate, subject to trigger clocking)
  local prob_param = track.params.probability
  local prob_val
  if trig_gates then
    prob_val = track_mod.peek(prob_param)
  elseif track_mod.should_advance(prob_param) then
    prob_val = direction_mod.advance(prob_param, dir)
  else
    prob_val = track_mod.peek(prob_param)
  end
  vals.probability = prob_val

  -- advance remaining params with trigger clocking + per-param probability gating
  local prob_pct = track_mod.PROBABILITY_MAP[prob_val] or 100
  for _, name in ipairs(track_mod.PARAM_NAMES) do
    if name ~= "trigger" and name ~= "probability" then
      local p = track.params[name]
      if trig_gates then
        vals[name] = track_mod.peek(p)
      elseif track_mod.should_advance(p) then
        if roll(ctx) <= prob_pct then
          vals[name] = direction_mod.advance(p, dir)
        else
          vals[name] = track_mod.peek(p)
        end
      else
        vals[name] = track_mod.peek(p)
      end
    end
  end

  -- emit step event (before mute check so listeners see all steps)
  if ctx.events then
    ctx.events:emit("sequencer:step", {track=track_num, step=track.params.trigger.pos, vals=vals})
  end

  -- fire note on trigger (probability already applied per-param above)
  if vals.trigger == 1 then
    local duration = track_mod.DURATION_MAP[vals.duration] or track_mod.DURATION_MAP[3]

    -- if muted, skip audio but still fire ghost sprite (mute takes precedence over probability)
    if track.muted then
      M.play_sprite(ctx, track_num, vals, duration, {muted = true, step = trig_param.pos, loop_len = trig_param.loop_end})
      ctx.grid_dirty = true
      return
    end

    -- probability check: evaluated once per step, before ratchet
    -- if probability fails, the entire step (including ratchet) is suppressed
    local prob_pct = track_mod.PROBABILITY_MAP[vals.probability] or 100
    if prob_pct < 100 then
      if prob_pct <= 0 or math.random(100) > prob_pct then
        ctx.grid_dirty = true
        return
      end
    end

    -- alt_note: additive pitch combination
    local effective_degree = ((vals.note - 1) + (vals.alt_note - 1)) % SCALE_DEGREES + 1
    local midi_note = scale_mod.to_midi(effective_degree, vals.octave, ctx.scale_notes)
    local velocity = track_mod.VELOCITY_MAP[vals.velocity] or track_mod.VELOCITY_MAP[4]

    -- emit voice:note event
    if ctx.events then
      ctx.events:emit("voice:note", {track=track_num, note=midi_note, vel=velocity, dur=duration})
    end

    -- apply glide/portamento
    local voice = ctx.voices and ctx.voices[track_num]
    if voice and voice.set_portamento then
      if vals.glide and vals.glide > 1 then
        voice:set_portamento(vals.glide)
      else
        voice:set_portamento(0)
      end
    end

    -- ratchet: subdivide into N evenly-spaced notes
    local ratchet_count = vals.ratchet or 1
    if ratchet_count > 1 then
      local sub_dur = duration / ratchet_count
      clock.run(log.wrap(function()
        for i = 1, ratchet_count do
          M.play_note(ctx, track_num, midi_note, velocity, sub_dur)
          if i < ratchet_count then
            clock.sync(sub_dur)
          end
        end
      end, "ratchet:" .. track_num))
    else
      M.play_note(ctx, track_num, midi_note, velocity, duration)
    end

    -- sprite voice: fire with raw kria vals (additive, alongside audio)
    M.play_sprite(ctx, track_num, vals, duration, {step = trig_param.pos, loop_len = trig_param.loop_end})
  elseif track.muted then
    -- muted track with no trigger: just mark grid dirty
    ctx.grid_dirty = true
    return
  end

  -- Meta-pattern: detect trigger loop wrap on track 1
  if track_num == 1 and ctx.meta and ctx.meta.active then
    if trig_param.pos == trig_param.loop_start and old_trig_pos ~= trig_param.loop_start then
      meta_pattern.on_loop_complete(ctx.meta, ctx)
    end
  end

  -- request grid redraw
  ctx.grid_dirty = true
end

function M.play_note(ctx, track_num, note, velocity, duration)
  local voice = ctx.voices and ctx.voices[track_num]
  if voice then
    voice:play_note(note, velocity, duration)
  end
end

function M.play_sprite(ctx, track_num, vals, duration, opts)
  local sv = ctx.sprite_voices and ctx.sprite_voices[track_num]
  if sv then
    sv:play(vals, duration, opts)
  end
end

-- Reset all playheads to loop start and tick counters
function M.reset(ctx)
  for _, track in ipairs(ctx.tracks) do
    for _, name in ipairs(track_mod.PARAM_NAMES) do
      track.params[name].pos = track.params[name].loop_start
      track.params[name].tick = 0
    end
  end
  if ctx.events then ctx.events:emit("sequencer:reset", {}) end
end

return M
