# Scratchpad — Branch Review Objective

## 2026-03-08: witty-badger uniqueness review

Investigated `origin/multiclaude/witty-badger` (commit `e767dcd`).
- Branch adds: `spec-kit/` templates + `specs/remote-api/` design docs (760 lines, 9 files)
- `git cherry -v main origin/multiclaude/witty-badger` → `-` prefix = already represented on main
- `git diff origin/multiclaude/witty-badger -- spec-kit/ specs/remote-api/` → empty = identical content
- Conclusion: **fully subsumed by main**. Safe to delete remote branch.

## Remaining review work

Per branch-review-2026-03-08.md proposed order:
1. ~~witty-badger uniqueness~~ → done, subsumed
2. ~~calm-hawk code review~~ → PR #15 MERGED since last iteration
3. ~~proud-wolf doc drift correction~~ → PR #14 MERGED since last iteration
4. PR #11 decomposition review → still OPEN (104 files, 13K+ lines)
5. 002-modifiers decomposition review → local-only, stacked omnibus

Also need: gap visualization / documentation artifact.

## 2026-03-08: Iteration — full state refresh

**Major progress since last iteration:** PRs #14-#20 all merged. Only PR #11 remains open.

**Remote branches with merged PRs (stale):**
- `origin/multiclaude/calm-hawk` → PR #15 MERGED, `git cherry` confirms `-`
- `origin/multiclaude/clever-deer` → PR #12 MERGED
- `origin/multiclaude/witty-badger` → PR #16 MERGED
- `origin/work/proud-eagle` → PR #13 MERGED
- `origin/work/proud-wolf` → PR #14 MERGED

**Local-only branches (stacked development):**
- `003-step-trigger-probability` = `004-sprite-timeline-viz` (same tip `e44bbf8`)
- `005-cross-track-fx` (one commit ahead at `a01188c`)
- `002-modifiers-meta-config-presets` (furthest ahead at `4f983eb`, 10 unique commits beyond 005)
- All are ancestors of 002 — 003/004/005 are redundant scaffolding

**Tests:** 195 successes / 0 failures on main

**Plan:** Delete stale remote branches first (quick tidy), then address local branch cleanup, then tackle decomposition reviews.

## 2026-03-08: Local branch cleanup complete

Deleted redundant local branches 003/004/005:
- `003-step-trigger-probability` (was e44bbf8) — ancestor of 002, deleted
- `004-sprite-timeline-viz` (was e44bbf8) — identical to 003, deleted
- `005-cross-track-fx` (was a01188c) — ancestor of 002, deleted

All content preserved in `002-modifiers-meta-config-presets` (4f983eb).

**Remaining local branches:**
- `main` (5422380) — active, ahead 1 of origin
- `002-modifiers-meta-config-presets` (4f983eb) — omnibus feature branch, needs decomposition
- `pdd/seamstress-entrypoint` (e44bbf8) — PR #11, needs decomposition

**Remote branches:** `origin/main`, `origin/pdd/seamstress-entrypoint` only.

**Tests:** 242 successes / 0 failures on main (up from 195 last check).

**Next:** Decomposition review of PR #11 and 002-modifiers, then gap visualization.

## 2026-03-08: PR #11 Decomposition Review

### Overview
PR #11 "Seamstress port: dual-platform kria sequencer" — 129 files, +13,458/-8,154 lines, 25 commits.

### File Breakdown by Category
| Category | Files | Description |
|----------|-------|-------------|
| Tooling/scaffolding | 67 | speckit, .specify, .codex, .ralph, worktrees |
| Spec docs | 18 | Feature specs, research, checklists |
| Lib (app code) | 15 | Core sequencer code changes |
| Tests | 13 | busted spec files |
| Test scripts | 5 | Standalone debugging scripts |
| Docs (HTML) | 4 | Generated visualizer docs |
| Other | 7 | README, CI, entrypoint, .gitignore |

### Critical Issue: Logical Regression
The branch predates PRs #7-#20 on main. It **deletes** features that main has since evolved:
- **Deletes** `lib/grid_provider.lua` — but PR #19 added the pluggable grid provider to main
- **Deletes** `lib/remote/api.lua`, `grid_api.lua`, `osc.lua` — but PRs #15, #20 added+hardened the remote API on main
- **Deletes** `specs/grid_api_spec.lua`, `grid_provider_spec.lua`, `remote_api_spec.lua` — tests for above
- **Deletes** `docs/*.html` — but PRs #12, #14, #17 added docs to main

Merging as-is would **regress main** by removing features. No git conflicts detected, but the logical conflicts are severe.

### Unique Value (worth extracting)
**New files added:**
- `lib/pattern.lua` — pattern save/load to 16 slots (new feature)
- `lib/voices/sprite.lua` — sprite voice backend
- `lib/seamstress/sprite_render.lua` — sprite rendering
- `specs/pattern_spec.lua`, `scale_spec.lua`, `screen_ui_spec.lua`, `sprite_spec.lua` — new tests

**Modified existing files with additions:**
- `lib/sequencer.lua` — direction integration, pattern hooks, ratchet/glide/alt_note
- `lib/grid_ui.lua` — extended page toggle
- `lib/app.lua` — direction mode params, pattern wiring
- `lib/track.lua` — extended track params
- `lib/seamstress/keyboard.lua` — extended page toggle
- `lib/voices/midi.lua` — set_portamento method
- `lib/voices/recorder.lua` — portamento support

### Recommended Decomposition
PR #11 should NOT be merged as-is. Instead, cherry-pick the unique value into focused PRs:

1. **PR A: Pattern storage** (~2 files) — `lib/pattern.lua` + `specs/pattern_spec.lua`
2. **PR B: Sprite voice & render** (~4 files) — `lib/voices/sprite.lua`, `lib/seamstress/sprite_render.lua`, `specs/sprite_spec.lua`
3. **PR C: Extended sequencer features** — cherry-pick changes to sequencer.lua, app.lua, track.lua for ratchet/glide/alt_note/direction integration (reconcile with main's versions)
4. **PR D: Test expansion** — `specs/scale_spec.lua`, `specs/screen_ui_spec.lua`, expanded grid_ui/sequencer/integration specs
5. **PR E: Seamstress entrypoint + keyboard** — `re_kriate_seamstress.lua` updates, keyboard changes

**Should NOT merge:**
- 67 tooling files (scaffolding, not product code)
- 4 HTML doc deletions (main has newer versions)
- 5 test_*.lua scripts (debugging artifacts)
- Remote API / grid_provider deletions (would regress main)
- .ralph state diffs (per-session artifacts)

### Verdict
Close PR #11 as superseded. Create focused PRs from cherry-picks against current main. The branch did valuable work but the world moved on around it.

## 2026-03-08: 002-modifiers-meta-config-presets Assessment

### Overview
19 unique commits, 171 files, +28,768 lines. Omnibus feature branch at `4f983eb`.

### Composition
| Category | Lines | % | Merge? |
|----------|-------|---|--------|
| Product code (lib/) | ~2,200 | 8% | Yes |
| Tests (specs/*_spec.lua) | ~13,500 | 47% | Yes |
| Spec docs (specs/001-005/) | ~1,600 | 6% | Keep |
| Scaffolding (.claude,.codex,.specify,.ralph,test_*) | ~11,400 | 39% | No |

### Code Quality: HIGH
- 11 new modules, all well-structured, following ctx pattern
- No circular dependencies. Clean downward coupling
- preset_storage.lua uses safe serialization (no eval/load)
- All modules receive context, no globals

### Dependency Graph (new modules)
```
preset_storage ← preset_page
pattern ← meta_sequencer ← pattern_page
config ← config_page
cross_track_fx (standalone)
sprite voice + render (standalone)
```

### Rebase Feasibility: MODERATE
- 20 commits on main since divergence point (311ca2f)
- 4 shared files: app.lua (+6), grid_ui.lua (+34), sequencer.lua (+55), track.lua (+20)
- Main's changes are relatively small — rebase conflicts likely resolvable
- Main added grid_provider.lua and remote/ API — 002 doesn't touch these, no regression risk

### Simplification Strategy
**Do NOT decompose into micro-PRs.** The branch is internally coherent — the features are coupled through grid_ui.lua routing. Merging piecemeal would require repeated grid_ui.lua surgery.

**Recommended approach:**
1. Rebase 002 onto main (resolve 4 file conflicts)
2. Strip scaffolding in a single commit (delete .claude/, .codex/, .specify/, test_*.lua, probe_v1.lua, ralph-002.yml)
3. Squash or consolidate the 19 commits into ~5 logical commits:
   - feat: core sequencer extensions (direction, ratchet, glide, clock div)
   - feat: pattern storage + meta-sequencer
   - feat: config + preset storage
   - feat: sprite voice + cross-track FX
   - feat: grid UI multi-mode routing + app wiring
4. Open as single PR, review the ~5K lines of product code + tests

### PR #11 vs 002 Overlap
PR #11 and 002 share a common ancestor (e44bbf8). The 002 branch contains ALL of PR #11's unique value plus additional features. **PR #11 can be closed** — 002 is its successor.

### Kent Beck Simplification Notes
- config.lua (42 lines) is almost too small to be its own module, but keeping it standalone follows single-responsibility
- pattern.lua (62 lines) similarly minimal but clean separation
- preset_storage.lua (461 lines) is the only module approaching complexity — justified by safe serialization logic
- No premature abstractions detected; each module does one thing

### Verdict
Branch is merge-ready after rebase + scaffolding strip. Code quality is high. No architectural simplification needed — the complexity matches the feature scope.

## 2026-03-08: Gap visualization document created

Created `docs/branch-gap-analysis.html` — interactive Blueprint-themed HTML document with:
- KPI summary (19 merged, 1 open, 242 tests, 92.9% coverage, 9 branches deleted)
- Branch status table (4 local, 2 remote)
- Full PR history table (all 20 PRs)
- Feature status matrix: 13 shipped / 11 in 002 branch / 12 gaps
- Mermaid architecture diagram with module detail cards for 002's new modules
- Prioritized next steps (close PR #11, rebase 002, strip scaffolding, open PR)
- Kent Beck simplicity assessment (strengths + gaps to address)

Committed as `92cae84`. Task `task-1772998856-6de8` closed.

**Objective status:** All review work complete. All tasks closed. Ready for LOOP_COMPLETE.
