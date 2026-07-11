-- lib/nav_spec.lua
-- Declarative description of the grid nav row (row 8, x=1..16).
--
-- This exists so nav-row behavior can be tested and cross-checked in one
-- place instead of drifting silently between code, comments, README, and
-- the help overlay — which is exactly what happened before this file
-- existed (see feature-queue.md "Known Issues", 2026-07-11: a stale
-- "grid 15" reference in help_overlay.lua that should have said 16, three
-- off-by-one nav comments in grid_ui.lua itself, an undocumented mixer
-- page). specs/nav_spec_spec.lua drives lib/grid_ui.lua's actual nav
-- dispatch for every entry below and asserts it matches.
--
-- This is descriptive of current nav_key()/grid_key() behavior, not yet
-- the mechanism driving it — lib/grid_ui.lua does not consume this table.
-- Wiring nav_key() to dispatch from this data is a natural follow-up once
-- this description has proven itself against the existing test suite.
--
-- Control kinds:
--   track_select  -- momentary press sets ctx.active_track = value
--   modifier      -- hold: ctx[held_field] tracks press state (true while
--                    held). While held, rows 1-7 are overlaid with this
--                    modifier's own editing behavior regardless of
--                    ctx.active_page — see grid_key()/redraw() in grid_ui.lua.
--                    `extra_reset_fields`, if present, lists ctx fields that
--                    are nil'd out on release (e.g. loop's in-progress
--                    first-press anchor).
--   page          -- momentary press sets ctx.active_page = target. No
--                    toggle-back; pressing again while already on target
--                    is a no-op.
--   page_extended -- press: switch to target. Press again while already on
--                    target: toggle to `extended`. Press target's own
--                    button while on `extended`: toggle back to target.
--   page_cycle    -- press advances through `cycle` (ordered list of page
--                    names), wrapping to the first after the last.
--   page_toggle2  -- press toggles ctx.active_page between target and
--                    alt_target. Pressing from any OTHER page goes to
--                    target first (i.e. reaching alt_target from elsewhere
--                    takes two presses).
--   track_toggle  -- momentary press flips ctx.tracks[ctx.active_track][field]

local M = {}

M.KINDS = {
  "track_select",
  "modifier",
  "page",
  "page_extended",
  "page_cycle",
  "page_toggle2",
  "track_toggle",
}

M.NAV = {
  [1] = { kind = "track_select", value = 1, label = "Track 1" },
  [2] = { kind = "track_select", value = 2, label = "Track 2" },
  [3] = { kind = "track_select", value = 3, label = "Track 3" },
  [4] = { kind = "track_select", value = 4, label = "Track 4" },

  [5] = { kind = "modifier", held_field = "time_held",
          label = "Time modifier (Ansible KEY 1)" },

  [6] = { kind = "page_extended", target = "trigger", extended = "ratchet",
          label = "Trigger page" },
  [7] = { kind = "page_extended", target = "note", extended = "alt_note",
          label = "Note page" },
  [8] = { kind = "page_extended", target = "octave", extended = "glide",
          label = "Octave page" },

  [9] = { kind = "page_cycle", cycle = {"duration", "velocity", "probability", "mixer"},
          label = "Duration / Velocity / Probability / Mixer cycle" },

  [10] = { kind = "page", target = "alt_track",
           label = "Alt-track / config (Ansible KEY 2)" },

  [11] = { kind = "modifier", held_field = "loop_held",
           extra_reset_fields = {"loop_first_press", "loop_first_y"},
           label = "Loop modifier" },
  [12] = { kind = "modifier", held_field = "pattern_held",
           label = "Pattern mode" },

  [13] = { kind = "track_toggle", field = "muted", label = "Mute" },

  [14] = { kind = "modifier", held_field = "prob_held",
           label = "Probability modifier",
           known_issue = "Also reachable as a plain page via the x=9 cycle "
             .. "(3rd stop) — that page is leftover duplication from before "
             .. "this modifier existed; see feature-queue.md." },

  [15] = { kind = "page", target = "scale", label = "Scale page" },

  [16] = { kind = "page_toggle2", target = "alt_track", alt_target = "meta_pattern",
           label = "Meta / alt-track" },
}

-- lib/grid_ui.lua's grid_key() resolves simultaneously-held modifiers via a
-- return-early if/elseif chain in this order. loop_held is excluded here
-- because redraw() handles it separately and inconsistently (draws its
-- overlay unconditionally on top of whatever else is showing) — seeing
-- feature-queue.md "Known Issues" for the tracked bug.
M.MODIFIER_PRECEDENCE = {"pattern_held", "time_held", "prob_held"}

return M
