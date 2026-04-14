# re.kriate Feature Gap Audit

**Date**: 2026-04-11
**Scope**: Spec vs implementation cross-reference, branch state, test coverage, open issues

---

## 1. Summary

re.kriate has 15 numbered feature specs (001-015, with 009 and 015 present only as branches or commits). Of these, specs 001-008 are fully merged. Specs 009-014 have specs drafted; most of their core features have been merged to main via separate PRs, though the original feature branches remain stale. The biggest gaps are: the Remote API is not wired into the app, softcut/sampler voice is incomplete, the SC mixer has no Lua-side test coverage, and several GitHub issues remain open for bugs and housekeeping.

---

## 2. Spec vs Implementation Status

| Spec | Title | Spec Status | Implementation | Test Coverage |
|------|-------|-------------|----------------|---------------|
| 001 | Seamstress Kria Features | Draft | COMPLETE -- core sequencer, grid UI, all pages, keyboard, screen UI | Extensive (sequencer, grid_ui, keyboard, screen_ui, integration, e2e specs) |
| 002 | Quality Hardening | Draft | COMPLETE -- branch fully merged | test_gap_hardening_spec.lua |
| 003 | Simulated Grid | Draft | COMPLETE -- simulated grid provider, synthetic grid | simulated_grid_spec, synthetic_grid_spec, synthetic_grid_behavior_spec |
| 004 | OSC Voice Integration | Draft | COMPLETE -- OSC voice backend | osc_voice_spec (533 lines) |
| 005 | Norns Entrypoint | Draft | COMPLETE -- re_kriate.lua, nb_voice | norns_entrypoint_spec (441 lines) |
| 006 | Pattern Bank UI | Draft | COMPLETE -- 16-slot pattern bank, grid overlay | pattern_bank_ui_spec, pattern_spec |
| 007 | Swing/Shuffle | Draft | MERGED to main but branch has 3 unmerged commits | swing_shuffle_spec |
| 008 | SuperCollider Voice Example | Draft | COMPLETE -- sc_synth.lua, sc_drums.lua, .scd files | sc_synth_voice_spec, sc_drums_voice_spec |
| 009 | Meta-Sequencer | Commit only (no spec dir) | COMPLETE -- lib/meta_pattern.lua merged (#108) | meta_pattern_spec |
| 010 | Clock Sync | Draft | COMPLETE -- lib/clock_sync.lua merged (#104) | clock_sync_spec, clock_sync_integration_spec |
| 011 | Trigger Probability | Draft | COMPLETE -- probability in track/sequencer/grid_ui | probability_spec |
| 012 | Preset Persistence | Draft | COMPLETE -- lib/preset.lua merged (#106) | preset_spec |
| 013 | Pattern Persistence | Draft | COMPLETE -- lib/pattern_persistence.lua | pattern_persistence_spec (317 lines) |
| 014 | Probability Grid | Draft | COMPLETE -- probability page on grid, modifier holds | probability_spec, grid_ui_spec |
| 015 | SC Mixer | No spec dir | MERGED (#110, #113) -- sc/rekriate-mixer.scd, bus architecture | **NO TEST SPEC** |

---

## 3. Feature Branches with Unmerged Work

| Branch | Unmerged Commits | Status |
|--------|-----------------|--------|
| 002-quality-hardening | 0 | Fully merged, stale |
| 003-simulated-grid | 0 | Fully merged, stale |
| 004-osc-voice-integration | 0 | Fully merged, stale |
| 005-norns-entrypoint | 0 | Fully merged, stale |
| 006-pattern-bank-ui | 0 | Fully merged, stale |
| **007-swing-shuffle** | **3 commits** | Has unmerged work: swing params, timing integration, composition tests |
| 008-supercollider-voice-example | 0 | Fully merged, stale |
| 009-meta-sequencer | 1 (spec commit only) | Stale -- feature merged via other PRs |
| **010-clock-sync** | **~40 commits** | Large branch with clock_sync implementation -- but the feature was merged to main via PR #104 separately. Branch has a "yolo" commit and probability data model scaffolding mixed in. |
| 011-trigger-probability | 1 (spec commit only) | Stale -- feature merged via other PRs |
| 012-preset-persistence | 1 (spec commit only) | Stale -- feature merged via other PRs |

**Action needed**: Branch 007-swing-shuffle has 3 unmerged commits that appear to contain real implementation work (params, timing integration, tests). These should be evaluated for merge or rebase. All other branches are stale and can be cleaned up.

---

## 4. Specced/Planned but NOT Implemented

### 4.1 Remote API -- Not Wired Into App
- `lib/remote/api.lua` exists with full command/query dispatch (transport, step editing, state snapshots)
- `lib/remote/osc.lua` and `lib/remote/grid_api.lua` exist
- **Gap**: `lib/app.lua` does NOT require or initialize the remote API. It is dead code -- never called from the main application flow.
- Test spec: `remote_api_spec.lua` and `grid_api_spec.lua` exist and test the module in isolation, but there is no integration test proving remote commands actually affect the running sequencer.

### 4.2 Softcut/Zig Voice -- Partial
- `lib/voices/softcut_zig.lua` has pitch transposition, loop support, and config
- `lib/voices/softcut_runtime.lua` has buffer management for 6 voice slots
- **Gap**: Not wired into the voice selection system in `lib/app.lua`. No params entry for selecting softcut as a voice backend. The softcut specs test the module in isolation but there is no integration with the main app.
- Test specs exist: `softcut_zig_voice_spec`, `softcut_runtime_spec`, `softcut_integration_spec`

### 4.3 SC Mixer -- No Lua Test Coverage
- `sc/rekriate-mixer.scd` merged in PRs #110 and #113
- Provides channel strips, aux sends, master bus, OSC control, metering
- **Gap**: No Lua-side test spec (`specs/sc_mixer*` does not exist). The mixer is a SuperCollider-only component with no Lua wrapper module, so testing depends entirely on manual SC integration testing.

### 4.4 Push 2 Grid Provider -- Untested in Practice
- `lib/grid_push2.lua` exists with full MIDI pad mapping, page switching, color palette
- `specs/grid_push2_spec.lua` exists with unit tests
- **Gap**: PR #112 added "Push 2 MIDI/USB protocol research" as docs only. The provider is specced and tested but likely untested on actual hardware. No integration test with the main app's grid provider selection.

### 4.5 Launchpad Pro Grid Provider -- Specced, Has Tests
- `lib/grid_launchpad_pro.lua` merged in PR #111
- `specs/grid_launchpad_pro_spec.lua` exists
- Same hardware-testing gap as Push 2.

### 4.6 Config Page (Original Kria Feature) -- Not Specced
- Original kria has a config page for note sync, loop sync modes, duration tie, brightness
- **Gap**: No spec exists. Not implemented. Listed in `docs/assessment-alternate-pages-modifiers.md` as a missing feature.

### 4.7 Per-Parameter Clock Division via Grid -- Partial
- Time modifier exists (F1 keyboard shortcut, PR #102)
- **Gap**: Per-parameter clock division (each param having its own clock divider on the grid, as in original kria) is only accessible via params menu or the F1 modifier, not as a dedicated grid page. The assessment doc notes this differs from original kria's x=12 time modifier.

### 4.8 Auto-Save on Exit (Spec 012 US4) -- Unclear
- Spec 012 specifies auto-save on script exit (P3 priority)
- `lib/preset.lua` has an `AUTOSAVE_NAME = "_autosave"` constant
- **Gap**: Need to verify if cleanup auto-save is actually wired in `lib/app.lua`. The constant exists but integration is unclear.

---

## 5. Open GitHub Issues

| # | Title | Type | Notes |
|---|-------|------|-------|
| 38 | screen_ui pattern bank rendering not wired into seamstress redraw | bug | May have been fixed by PR #99 (re-5nt wire screen_ui.draw_tray) -- needs verification |
| 39 | seamstress exits immediately when stdout is piped | bug | Platform-level issue, not yet addressed |
| 40 | feat: 009 meta-sequencer (pattern chaining) | enhancement | Feature merged via PR #107/#108 -- issue can be closed |
| 41 | feat: 010 MIDI clock sync | enhancement | Feature merged via PR #104 -- issue can be closed |
| 42 | feat: 011 trigger probability | enhancement | Feature implemented -- issue can be closed |
| 43 | feat: 012 preset persistence | enhancement | Feature merged via PR #106 -- issue can be closed |
| 44 | chore: clean up CLAUDE.md Active Technologies section | documentation | Housekeeping, still open |
| 45 | chore: automate stale remote branch cleanup | documentation | 11 stale feature branches exist |

**4 issues (#40-43) can be closed** -- their features are merged to main.

---

## 6. Merged but Under-Tested

| Feature | Merged PR(s) | Test Spec | Gap |
|---------|-------------|-----------|-----|
| SC Mixer | #110, #113 | None | No Lua tests at all -- SC-only component |
| Launchpad Pro provider | #111 | grid_launchpad_pro_spec | No hardware integration test |
| Push 2 provider | #112 (docs) | grid_push2_spec | No hardware integration test; docs-only PR |
| Pattern cueing | #107 | meta_pattern_spec | Cueing logic tested but quantized transition edge cases may be thin |
| Scale mask editor | #105 | scale_grid_spec | New spec exists; coverage depth unknown |
| Preset persistence | #106 | preset_spec | Spec exists; auto-save integration unclear |

---

## 7. Code Quality Notes

- **No TODO/FIXME/HACK comments** found in `lib/` -- codebase is clean of debt markers.
- **Design review** (docs/design-review.md) identified a **latent bug**: pattern load breaks running clock coroutine references (stale track refs in track_clock). This was flagged as high priority but it is unclear if it has been fixed.
- **Event bus role ambiguity** remains: events are emitted but inconsistently consumed. The design review recommended clarifying whether the bus is primary dispatch or observation-only.
- **Dead code**: `track_mod.advance()` was flagged as dead code (direction_mod.advance() is used instead). Status of cleanup unknown.

---

## 8. Beads Database

The beads dolt database at `/Users/whit/src/gastown/rekriate/.beads/embeddeddolt/rekriate/` is empty -- no tables or issue data found. Issue tracking is on GitHub only.

---

## 9. Test Suite Execution

**Unable to run tests in this session** -- the sandbox blocked execution of `busted` and `scripts/busted.sh`. The test suite should be run manually:
```
cd /Users/whit/src/re.kriate && ./scripts/busted.sh --no-auto-insulate specs/
```

---

## 10. Recommended Actions (Priority Order)

1. **Close stale issues** #40-43 (features already merged)
2. **Evaluate branch 007-swing-shuffle** -- 3 unmerged commits with real work
3. **Wire Remote API** into app.lua or explicitly mark it as an extension point (currently dead code)
4. **Add SC mixer Lua wrapper** with tests, or document it as SC-only
5. **Wire softcut voice** into the voice selection system or remove from the codebase
6. **Fix stale track reference bug** in sequencer pattern load (design-review high priority item)
7. **Clean up 11 stale feature branches** (002-006, 008-012)
8. **Verify auto-save** on exit is wired in app.lua cleanup
9. **Run full test suite** and verify all specs pass
10. **Investigate seamstress piped-stdout exit bug** (#39)
