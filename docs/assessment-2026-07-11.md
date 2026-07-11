# Assessment: missing / incomplete / broken

**Date**: 2026-07-11 (post integration-boundaries stack, main @ 1c3fd40, suite 1708/1708 green)
**Method**: five independent passes (broken → incomplete → missing → test gaps → architecture debt), 44 raw findings, deduplicated to 36. Every P1/P2-correctness claim verified against current code with file references; four highest-impact claims independently re-verified.

Severity: **P1** blocks players or contributors now · **P2** real defect or valuable gap · **P3** polish. Effort: S <1h · M half-day · L multi-day.

---

## P1 — act first (5)

| # | Finding | Evidence | Action | Effort |
|---|---|---|---|---|
| 1 | **No LICENSE file.** The repo is legally unusable/unforkable by others — fatal for "extending by others". | repo root has no LICENSE/COPYING | Pick a license (norns ecosystem convention is GPL-3.0 or MIT) and commit it | S |
| 2 | **Pattern SAVE is unreachable from the grid.** A norns/grid-only player cannot capture their working state into a slot at all — edits are silently lost on pattern switch. Save exists only via seamstress keyboard (Ctrl+1-9) and params. | `grid_ui.lua pattern_key` (load/cue only); no `pattern.save` call anywhere in grid_ui | Hold-slot-to-save gesture in pattern mode (tap = load/cue, ≥0.5s hold = save via `button_events` timestamps), emitting `cmd:pattern:save` | M |
| 3 | **Seamstress grid-provider param can brick the UI.** Seamstress boots the `simulated` provider but `GRID_PROVIDER_OPTIONS` (app.lua:68) omits it — the menu mislabels the live provider as "monome", and switching away then back connects a real monome object lacking `get_led`, which errors every `grid_render.draw` frame with **no menu option that restores `simulated`**. | app.lua:68-69, 373; grid_render.lua draw path | Add `simulated` to the options (or per-platform lists), default the param to the actual boot provider, and guard `grid_render.draw` against providers lacking `get_led` | M |
| 4 | **CI flakes on an absolute wall-clock perf test.** `grid_render` "100 draws < 1000ms" runs under coverage on shared runners; failed twice on 2026-07-11 alone. Threshold was already bumped once — it will flake again. | specs/grid_render_spec.lua ~717 | Gate behind an env var like the seamstress load test, or switch to a relative budget (compare against a baseline op measured in-process) | S |
| 5 | **CHANGELOG stale ~3 months.** Nothing since 2026-04-14; today's entire architecture stack (behavioral events, voice registry, platform/standalone, UI spec) is absent. | CHANGELOG.md `[Unreleased]` contents | Backfill an Unreleased section covering PRs #135-#148; adopt "changelog entry per user-facing PR" as review convention | S |

## P2 — correctness defects (verified broken, ordered by player impact)

| # | Finding | Evidence | Action | Effort |
|---|---|---|---|---|
| 6 | **Mixer level applied twice → squared loudness curve.** `sequencer.play_note` scales velocity by `ctx.mixer.level` AND `mixer.set_level` pushes `voice:set_level` (MIDI CC7, SC amp). Fader at 0.5 ≈ 0.25 loudness on every backend honoring both. *Independently re-verified.* | sequencer.lua:326-339; voices/midi.lua:64-69; mixer.lua:58-64 | Pick one mechanism (drop the velocity scaling; voices own level) + spec asserting exactly one attenuation at level 0.5 | S |
| 7 | **Full-session presets (incl. autosave) silently lose mixer level/pan.** `preset.lua` snapshots tracks/patterns/meta/params but never `mixer.snapshot` — a mixed set reloads at level 1.0 / pan 0 every restart. *Re-verified: zero "mixer" refs in preset.lua.* | preset.lua build_payload | Add mixer snapshot/restore to the payload + roundtrip spec | S |
| 8 | **Preset load stomps newer grid edits of direction/division/swing.** Restore order: tracks deep-copied, then `apply_params` re-fires `direction_/division_/swing_` actions with stale param snapshot values (grid/keyboard edits never sync to params). | preset.lua:429-440; app.lua:536-549 | Apply params before committing the tracks copy (or skip track-shadowing params); real fix is #22 | M |
| 9 | **Hold-modifier precedence mismatch (redraw vs grid_key).** Holding loop+prob shows the loop anchor overlay drawn over the probability view while presses actually edit probability; on scale/meta pages the loop overlay draws though loop editing is unreachable. Likely the "everything destabilizes" reporter. | grid_ui.lua:59-95 vs 660-705 | Resolve ONE modifier at press time (n.kria-style single `ctx.mod`, leftmost-wins); branch both redraw and grid_key on it. Pairs with #26 | M |
| 10 | **Pattern cues accepted during meta-sequencer never apply — then fire later.** Grid accepts `pattern.cue` while `meta.active`, but the loop-boundary hook routes only to meta; the stale `cued_pattern_slot` fires unexpectedly after meta stops. *Re-verified sequencer.lua:311-320.* | grid_ui.lua:851-857; sequencer.lua:311-320 | While meta is active, route slot presses to `meta_pattern.cue` or reject; clear stale cues on meta start/toggle | S |
| 11 | **Keyboard shift+1-9 hard-loads mid-loop and desyncs `pattern_slot`.** Bypasses the cue quantization the grid uses; sets only `active_pattern`, so the grid pattern view highlights the wrong slot. | keyboard.lua:90-96 | Migrate keyboard save/load to `cmd:pattern:save/load`; make the load handler cue when playing | S |
| 12 | **`connect_grid` tears down the old grid before the new one is confirmed.** A failed provider connect (reproduced live: midigrid not installed) leaves the previous grid cleaned up. | app.lua:359-369 | Connect new inside pcall first; swap+cleanup only on success | S |

## P2 — player-facing gaps

| # | Finding | Action | Effort |
|---|---|---|---|
| 13 | **No transport control on the grid** — play/stop unreachable from the nav row entirely; worse, `re_kriate.lua`'s header comment falsely documents x=16 as play/stop | Decide a home (KEY2 combo? row-8 gesture?), wire to `cmd:transport:*`, fix the header | S |
| 14 | **No track/page copy, paste, or clear** — n.kria parity gap; wrong track must be un-toggled step by step | Hold-track + target gestures per the March parity audit design sketch | M |
| 15 | **No reset-to-defaults action** to recover a wedged session without process restart (queued since live testing) | `cmd:reset:global` params trigger + confirm gesture | M |
| 16 | **Grid visuals unhelpful / side panel not clickable** (user-requested 2026-07-11, still open). Panel has zero click handling; grid cells carry no semantic help | Design pass first; panel click routing via `screen.click` region dispatch → `cmd:*` emission is now mechanical | M/L |

## P2 — contributor-facing gaps

| # | Finding | Action | Effort |
|---|---|---|---|
| 17 | **No dev-setup/CONTRIBUTING docs**, and `scripts/busted.sh` hardcodes `/Users/whit/.luarocks` paths — a stranger cannot run the suite from the README | CONTRIBUTING.md (install lua5.4+busted, run tests, launch each entrypoint); make busted.sh path-generic | S |
| 18 | **CI never executes a real entrypoint.** `standalone.lua` self-describes as a CI smoke test and CI doesn't run it | Add `lua standalone.lua 16` step to test.yml | S |
| 19 | **docs/index.html doesn't link** event-layers.md, adapters.md, or routing.md | Add links | S |

## P2 — event-layer completion (the migration the architecture now makes mechanical)

| # | Finding | Action | Effort |
|---|---|---|---|
| 20 | **Command adoption stalled at transport**: 5 of 9 wired commands have zero production emitters; 6 planned VOCAB commands are still no-ops (pause, option:change, reset:pattern/time, load:preset, save:state) | Wire load:preset/save:state to preset.lua (exists); option:change to params:set; then migrate emitters surface-by-surface | M |
| 21 | **Mute still fragmented**: 5 writers, 2 fact names (`track:mute` vs `mixer:mute`), 2 silent paths | All writers → `cmd:track:set_mute`; one fact name; alias the old one during deprecation | M |
| 22 | **direction/division/swing: 4 writers, zero events, no params sync-back** — root cause of #8 | Route through `cmd:option:change` with bidirectional params sync (scale:root/type is the working precedent) | M |
| 23 | **Track/page select silent from keyboard, encoders, remote** — remote UIs only see grid-originated changes | Emit facts (or migrate to commands) in those surfaces | S |
| 24 | **Remote API still unwired** (`lib/remote/osc.lua` waits on a `register_handler()` that never existed) and **`sc_mixer.lua` fully orphaned** despite its 462-line spec and SC-side engine | Wire remote OSC as a cmd:* bridge (it's now the obvious design); register sc_mixer or explicitly archive it | M |
| 25 | **`ui_spec.lua` is descriptive only; `button_events.lua` has no production consumer** — the declarative layer doesn't drive dispatch yet | See #26 — one refactor closes both | M |

## P2 — architecture & test debt

| # | Finding | Action | Effort |
|---|---|---|---|
| 26 | **`nav_key()` has 5 duplicated page-select blocks**; grid_ui.lua ~1100 lines with 4 divergent page-select code paths | Dispatch nav_key from `ui_spec.NAV` (kind → handler table); fold the #9 modifier fix into the same change; ~200 lines net deletion | M |
| 27 | **seamstress.lua breaks the thin-entrypoint rule**: 190-line init() with params-menu SDL monkey-patch + clock.resume patch inline | Extract `lib/seamstress/params_menu_patch.lua` + `clock_guard.lua` | M |
| 28 | **Constitution principle V is dead letter** (specs/NNN dirs + speckit pipeline; today's stack created none) | Amend the constitution to match the working process (design docs in docs/, TDD, PR review) rather than resurrecting ceremony nobody follows | S |
| 29 | **ctx sprawl**: ~40 distinct fields, ~17 attached ad hoc outside the app.init constructor, no schema | Declare all fields in the constructor (nil-initialized, commented); consider a ctx-fields test | M |
| 30 | **14 spec files install `_G.params` fakes at module load with no isolation** — local (one process, no insulation) and CI runs differ; cross-file leaks already bit twice today | Shared `specs/lib/host_stubs.lua` with save/restore helpers; migrate files incrementally | M |
| 31 | **Zero specs exercise two modifiers held together** — exactly where #9 hides | Add combo specs alongside the #9 fix | S |
| 32 | **Persistence version field written but never validated** — a version≠1 file loads as if current | Validate on load + spec for future-version file | S |

## P3 — polish / consistency

| # | Finding | Action | Effort |
|---|---|---|---|
| 33 | MIDI clock Start resets playheads; no local path does — divergent downbeat when switching slaved/local | Converge on `cmd:transport:play` + optional reset-on-play param | S |
| 34 | `voice:note` fact fires once per step; ratchets sound 0-5 notes — fact stream infidelity | Emit in `sequencer.play_note` per actual dispatch | S |
| 35 | Redundant probability page still in x=9 cycle beside the x=14 modifier; `NAV_PAGE[9]` dead data | Remove page from cycle; delete dead entry (falls out of #26 naturally) | S |
| 36 | Bus wildcards match first-colon prefix only — `cmd:transport:*` silently never matches; `lib/ui_spec.lua` name collides with busted `*_spec.lua` convention | Error/document multi-level wildcards; rename to `lib/ui_map.lua` if it grates | S |

---

## Verified healthy (checked, no action)

- Suite 1708/1708 green; the only pending test is correctly env-gated. Log tail clean (no ERROR/CRASH since the March keyboard fix).
- `re_kriate.lua` (86 lines) and `standalone.lua` (96) honor the thin-entrypoint rule; all three entrypoints share `app.init`.
- Voice registry has all six legacy voices in preset-compatible order; push2 (42 tests) and launchpad (45) have real interface coverage; monome mirroring is tested.
- README controls/keyboard tables match the code exactly (post today's fixes); README already links the new architecture docs.
- `pattern.apply_cue` empty-slot and reset handling correct; keyboard keycode crash fixed by the table guard.

## Suggested sequencing (first five PRs)

1. **Licensing + contributor unblock** (#1, #17, #18, #19, #5) — all S, one PR, makes the repo openable.
2. **Audio correctness** (#6, #7) — two S fixes with roundtrip specs; audible today.
3. **Grid provider safety** (#3, #12) — the "bricked UI" family.
4. **Pattern integrity** (#2, #10, #11) — grid save gesture + cue/meta/keyboard coherence, all through `cmd:pattern:*`.
5. **The dispatch refactor** (#9, #26, #31, #35 together) — single resolved modifier + spec-driven nav; closes the destabilization report and deletes the most duplicated code in the repo.
