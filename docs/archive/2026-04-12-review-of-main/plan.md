# 2026-04-12 Review of `main` — Dispatch Plan

**Hook bead:** `re-9yr` (mayor → jasper)
**Review source:** `docs/projects/2020-04-12-review-of-main/human-review.md`
  (on branch `origin/whitmo/re-9yr-product-review`, base git-hash `7ce223`)
**Planner:** polecat jasper, 2026-04-13

## Purpose

The mayor's review of `main` (15 feature specs landed, ~14 open review items) is
to be farmed out to parallel polecats using the speckit pipeline. Each item below
is an **independently dispatchable unit** — a polecat can claim one bead, run it
through `/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement`,
and submit via `gt done` without blocking on any other chunk.

## Dispatch Philosophy

- **One bead = one polecat = one speckit feature.** Parallelism is bounded only
  by the number of available polecats.
- **Each chunk touches a disjoint area of the code** (see "Affected files" per
  row) so two polecats working concurrently should not collide in git.
- **Acceptance is self-contained:** every chunk carries its own acceptance
  criteria taken verbatim from the review.
- **Priority** follows the review: user-visible grid UX first, voices second,
  config/persistence third, adjacent cleanup last.

## Dispatch Table

Each row is ready to hand to a polecat (`gt dispatch polecat <rig> --bead <id>`
or via the hooking mechanism). Bead descriptions already include the review
citation; the speckit spec is created by the polecat as their first step.

### Wave 1 — Grid UX & visuals (touches `lib/grid_ui.lua` + seamstress screen code)

| # | Bead | Title | Review §  | Affected files | Spec slot |
|---|------|-------|-----------|----------------|-----------|
| 1 | `re-1mo` | Virtual grid aesthetics (colors, spacing, borders) | §1 UI view | `lib/seamstress/grid_render.lua`, `lib/seamstress/screen_ui.lua` | `specs/016-virtual-grid-aesthetics/` |
| 2 | `re-trn` | Dynamic info panel + `?` help overlay on right side | §1 UI view | `lib/seamstress/screen_ui.lua`, `lib/seamstress/help_overlay.lua` | `specs/017-info-panel-help/` |
| 3 | `re-lz0` | Loop modifier: modifier not page (kria form) | §2 Grid behavior | `lib/grid_ui.lua`, `lib/track.lua` | `specs/018-loop-modifier-overlay/` |
| 4 | `re-7xm` | Alt-param visuals + octave row-0 setter + glissando graphic | §2 Grid behavior | `lib/grid_ui.lua` | `specs/019-alt-param-visuals/` |
| 5 | `re-44c` | Row 7 buttons x=4 and x=13 purpose | §2 Grid behavior | `lib/grid_ui.lua` | `specs/020-control-row-audit/` |
| 6 | `re-563` | Clock divider modifier key repair | §2 Grid behavior | `lib/grid_ui.lua`, `lib/sequencer.lua` | `specs/021-clock-divider-modifier/` |
| 7 | `re-sc1` | Per-parameter probability semantics | §2 Grid behavior | `lib/track.lua`, `lib/sequencer.lua`, `lib/grid_ui.lua` | `specs/022-param-probability/` |
| 8 | `re-lub` | Scale/meta-sequence page integration (row 8 x=16) | §2 Grid behavior | `lib/grid_ui.lua`, `lib/meta_pattern.lua` | `specs/023-meta-scale-pages/` |

### Wave 2 — Voices & engine (touches `lib/voices/*` + `sc/*`)

| # | Bead | Title | Review § | Affected files | Spec slot |
|---|------|-------|----------|----------------|-----------|
| 9  | `re-mgm` | SC voice: seamstress↔SC comms + simpler launch | §Voices | `lib/voices/sc_synth.lua`, `sc/*.scd`, `docs/supercollider-setup.md` | `specs/024-sc-voice-handshake/` |
| 10 | `re-l8p` | Softcut + recorder integration (grab samples live) | §Voices | `lib/voices/softcut_zig.lua`, `lib/voices/softcut_runtime.lua`, `lib/voices/recorder.lua` | `specs/025-softcut-recorder/` |

### Wave 3 — Params, config & persistence (touches `lib/app.lua` params registration)

| # | Bead | Title | Review § | Affected files | Spec slot |
|---|------|-------|----------|----------------|-----------|
| 11 | `re-rr0` | Config cleanup: voice-scoped params, swing/voice under track, clock-sync clarity | §Config | `lib/app.lua` | `specs/026-param-reorganization/` |
| 12 | `re-2yn` | Preset/pattern unification + stock banks | §Config | `lib/preset.lua`, `lib/pattern_persistence.lua`, `lib/app.lua` | `specs/027-preset-pattern-unify/` |

### Wave 4 — Startup & introspection (small, pair-ready)

| # | Bead | Title | Review § | Affected files | Spec slot |
|---|------|-------|----------|----------------|-----------|
| 13 | `re-4fs` | Startup console state (git hash, branch, SC/softcut status) | §0 start up | `lib/seamstress/*`, `seamstress.lua` | `specs/028-startup-banner/` |
| 14 | `re-107` | `help()` callable in seamstress console (ctx, transport, debug) | §0 start up | `lib/seamstress/console.lua` (new), `seamstress.lua` | `specs/029-console-help/` |

### Adjacent cleanup (surfaced by audits, low priority, can run in parallel)

These come from `docs/crew-work/audit-feature-gaps.md` (commit `2bd6dbe`) and
are not in the review but are ripe for parallel dispatch.

| # | Bead | Title | Source | Spec slot |
|---|------|-------|--------|-----------|
| 15 | `re-cv2` | SC mixer Lua wrapper + specs | audit §4.3 | `specs/030-sc-mixer-wrapper/` |
| 16 | (file) | Wire Remote API into app.lua or delete | audit §4.1 | `specs/031-remote-api-decision/` |
| 17 | (file) | Evaluate & land/close branch `007-swing-shuffle` (3 unmerged commits) | audit §3 | n/a (branch surgery) |
| 18 | (file) | Close stale GitHub issues #40-43 (features already merged) | audit §5 | n/a (housekeeping) |
| 19 | (file) | Fix stale track reference bug on pattern load | design-review | `specs/032-pattern-load-refs/` |

## Dependency Graph

Most chunks are independent. The few real dependencies:

```
re-sc1 (param probability) ← depends on → re-rr0 (param reorg) for param IDs
re-2yn (preset unify)       ← depends on → re-rr0 (param reorg) for preset keys
re-lub (meta/scale pages)   ← may interact with → re-trn (info panel)
```

A polecat claiming `re-sc1` or `re-2yn` MUST check `re-rr0` status first. All
other chunks are independent of each other.

## Per-chunk Polecat Instructions (template)

A polecat picking up any bead in the dispatch table follows this formula:

1. `gt prime --hook` → `bd show <bead>`
2. Read the cited review section in `docs/projects/2020-04-12-review-of-main/human-review.md`.
3. `/speckit.specify "<one-line summary taken from the bead title>"` — creates
   `specs/NNN-<slug>/spec.md` using the slot from the dispatch table.
4. `/speckit.plan` — design artifacts and constitution check.
5. `/speckit.tasks` — dependency-ordered TDD tasks.
6. `/speckit.analyze` — cross-artifact consistency check.
7. `/speckit.implement` — write failing tests first, then implement.
8. Verify: `./scripts/busted.sh --no-auto-insulate specs/` + `luacheck lib/`.
9. Commit with `(<bead-id>)` in the message.
10. `gt done`.

## Queue Ordering

For ralph/autonomous dispatch, the recommended enqueue order (already applied
to `.ralph/agent/feature-queue.md`) interleaves waves so parallel polecats
pick disjoint files:

```
re-lz0  re-mgm  re-rr0  re-4fs
re-7xm  re-l8p  re-2yn  re-107
re-sc1  re-cv2  re-1mo  re-trn
re-44c  re-563  re-lub
```

This pattern ensures that when N polecats pull from the front of the queue
concurrently, they hit different areas of the codebase (grid UX / voices /
params / startup) and minimize merge pressure on the refinery.

## Done definition for this planning bead (re-9yr)

- [x] Review document located and read
- [x] Each review item mapped to an existing or newly filed bead
- [x] Missing beads filed (`re-44c`, `re-563`, `re-cv2`)
- [x] Dispatch table written with speckit spec slots reserved
- [x] Dependencies between chunks documented
- [x] Feature queue updated for ralph autonomous pickup
- [x] Findings persisted to `re-9yr` via `bd update --design`

`gt done` once the plan doc and queue update are committed.
