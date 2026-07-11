-- lib/ui_spec.lua
-- Declarative description of the grid nav row (row 8, x=1..16).
--
-- This exists so nav-row behavior can be tested and cross-checked in one
-- place instead of drifting silently between code, comments, README, and
-- the help overlay — which is exactly what happened before this file
-- existed (see feature-queue.md "Known Issues", 2026-07-11: a stale
-- "grid 15" reference in help_overlay.lua that should have said 16, three
-- off-by-one nav comments in grid_ui.lua itself, an undocumented mixer
-- page). specs/ui_spec_spec.lua drives lib/grid_ui.lua's actual nav
-- dispatch for every entry below and asserts it matches.
--
-- This is descriptive of current nav_key()/grid_key() behavior, not yet
-- the mechanism driving it — lib/grid_ui.lua does not consume this table.
-- Wiring nav_key() to dispatch from this data is a natural follow-up once
-- this description has proven itself against the existing test suite.
--
-- Two layers:
--   1. Button events (lib/button_events.lua) — press / double_press / combo
--      / is_down ("hold"), classified from raw press-release timing alone,
--      with no idea what page or mode is active.
--   2. Context events (this file) — what a button event MEANS depends on
--      context: which page is active, which modifier (if any) is held.
--      M.NAV declares this for the nav row (row 8); M.BODY declares it for
--      rows 1-7, where the same (x,y) press means something different on
--      the trigger page vs. a value page vs. the mixer page.
--
-- `trigger` on each M.NAV entry names the button event that fires it —
-- almost everything here is plain `press`; only the four `modifier`
-- entries use `hold`. Nothing currently uses a real `double_press` or
-- `combo`: what looked like a double-press gesture (x=16's "press twice to
-- enter meta-pattern", x=6-8's "press again for the extended page") is
-- actually a single `press` whose ACTION depends on context (is
-- ctx.active_page already the target?) — a context event, not a distinct
-- button event. That distinction is why help_overlay.lua's old "press
-- twice" wording was misleading (see feature-queue.md "Known Issues").
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

-- Button events a nav entry's `trigger` field may name (layer 1, see
-- lib/button_events.lua). Only "press" and "hold" are in use today.
M.TRIGGERS = { "press", "hold", "double_press", "combo" }

M.NAV = {
  [1] = { kind = "track_select", trigger = "press", value = 1, label = "Track 1" },
  [2] = { kind = "track_select", trigger = "press", value = 2, label = "Track 2" },
  [3] = { kind = "track_select", trigger = "press", value = 3, label = "Track 3" },
  [4] = { kind = "track_select", trigger = "press", value = 4, label = "Track 4" },

  [5] = { kind = "modifier", trigger = "hold", held_field = "time_held",
          label = "Time modifier (Ansible KEY 1)" },

  [6] = { kind = "page_extended", trigger = "press", target = "trigger", extended = "ratchet",
          label = "Trigger page" },
  [7] = { kind = "page_extended", trigger = "press", target = "note", extended = "alt_note",
          label = "Note page" },
  [8] = { kind = "page_extended", trigger = "press", target = "octave", extended = "glide",
          label = "Octave page" },

  [9] = { kind = "page_cycle", trigger = "press",
          cycle = {"duration", "velocity", "probability", "mixer"},
          label = "Duration / Velocity / Probability / Mixer cycle" },

  [10] = { kind = "page", trigger = "press", target = "alt_track",
           label = "Alt-track / config (Ansible KEY 2)" },

  [11] = { kind = "modifier", trigger = "hold", held_field = "loop_held",
           extra_reset_fields = {"loop_first_press", "loop_first_y"},
           label = "Loop modifier" },
  [12] = { kind = "modifier", trigger = "hold", held_field = "pattern_held",
           label = "Pattern mode" },

  [13] = { kind = "track_toggle", trigger = "press", field = "muted", label = "Mute" },

  [14] = { kind = "modifier", trigger = "hold", held_field = "prob_held",
           label = "Probability modifier",
           known_issue = "Also reachable as a plain page via the x=9 cycle "
             .. "(3rd stop) — that page is leftover duplication from before "
             .. "this modifier existed; see feature-queue.md." },

  [15] = { kind = "page", trigger = "press", target = "scale", label = "Scale page" },

  [16] = { kind = "page_toggle2", trigger = "press", target = "alt_track", alt_target = "meta_pattern",
           label = "Meta / alt-track" },
}

-- lib/grid_ui.lua's grid_key() resolves simultaneously-held modifiers via a
-- return-early if/elseif chain in this order. loop_held is excluded here
-- because redraw() handles it separately and inconsistently (draws its
-- overlay unconditionally on top of whatever else is showing) — seeing
-- feature-queue.md "Known Issues" for the tracked bug.
M.MODIFIER_PRECEDENCE = {"pattern_held", "time_held", "prob_held"}

-- ============================================================================
-- Context events: rows 1-7 (the grid body)
-- ============================================================================
--
-- A body press's button event is always just `press` (grid_key() ignores
-- z=0 entirely except inside the pattern/alt_track/meta_pattern branches,
-- which handle release themselves) — everything interesting is which
-- CONTEXT the press lands in. Two context dimensions, checked in order:
--
--   1. Is a modifier held? (M.MODIFIER_PRECEDENCE order, then loop_held —
--      see the known precedence-mismatch bug noted above)
--   2. Otherwise, which page is active?
--
-- M.BODY_PAGES declares the second dimension — the fundamental interaction
-- pattern per page. This is a worked example, not exhaustive: it covers
-- enough page kinds (row_per_track, value_bargraph, and mixer's own
-- column layout) to prove the same declarative-and-tested approach used
-- for the nav row generalizes to the body. Pages with genuinely bespoke
-- handlers (ratchet's bitmask, alt_track, scale, meta_pattern) are named
-- but not structurally modeled here — see their dedicated M.<page>_key
-- functions in grid_ui.lua. Extending coverage to those is a natural
-- follow-up, same as nav_key() dispatch itself (see file header).
--
-- Patterns:
--   row_per_track   -- rows 1-4 are tracks 1-4. `columns` (if present)
--                      partitions the 16 columns into named ranges, each
--                      mapping to a distinct action; trigger has none
--                      (every column is a step toggle for that row/track).
--   value_bargraph  -- rows 1-7 show a value 7 (row 1) .. 1 (row 7) for
--                      ctx.active_track only; columns are steps. All pages
--                      using this pattern share the exact same handler
--                      (grid_ui.value_key), just parameterized by page name.
--   custom          -- bespoke handler, not structurally modeled here.

M.BODY_PAGES = {
  trigger = { pattern = "row_per_track", param = "trigger" },

  mixer = { pattern = "row_per_track", columns = {
    { range = {1, 7}, action = "set_level" },
    { range = {8, 8}, action = "none" }, -- gap column
    { range = {9, 15}, action = "set_pan" },
    { range = {16, 16}, action = "toggle_mute" },
  } },

  ratchet = { pattern = "custom", handler = "ratchet_key" },
  alt_track = { pattern = "custom", handler = "alt_track_key" },
  scale = { pattern = "custom", handler = "scale_key" },
  meta_pattern = { pattern = "custom", handler = "meta_pattern_key" },
}

-- Pages using the shared value_bargraph handler (grid_ui.value_key),
-- parameterized only by page/param name.
M.VALUE_BARGRAPH_PAGES = {
  "note", "octave", "duration", "velocity", "probability", "alt_note", "glide",
}

return M
