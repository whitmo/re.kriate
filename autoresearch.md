# Autoresearch: SPRING_CLEAN

## Objective
Establish a trustworthy test baseline and clean working tree by quarantining non-authoritative local artifacts and reconciling the mixer API divergence. The goal is 0 test failures, 0 errors, and a clean `git status` on the working branch.

## Metrics
- **Primary**: test_errors (count, lower is better)
- **Current Best**: 0 (0 failures + 0 errors)
- **Secondary**: untracked_artifacts (count), dirty_files (count)

## Benchmark Command
```
busted specs/ 2>&1 | grep -E "successes|failures|errors|pending"
```
Parse: extract numbers from "N successes / N failures / N errors / N pending"

## Files in Scope
- `specs/grid_mixer_spec.lua` — untracked, tests non-existent OOP mixer API
- `specs/mixer_metering_spec.lua` — untracked, tests non-existent `handle_meter` method
- `specs/mixer_persistence_spec.lua` — untracked, tests non-existent `serialize`/`deserialize`
- `lib/mixer.lua` — the actual mixer module (flat table API, NOT OOP)
- `specs/mixer_spec.lua` — the tracked/authoritative mixer spec
- `specs/015-sc-mixer/tasks.md` — untracked planning artifact
- `.agents/` — untracked agent planning cruft

## Off Limits
- `lib/mixer.lua` API design (do NOT change the existing flat API)
- Any tracked spec files that currently pass
- `sc/rekriate-mixer.scd` (SuperCollider engine)
- Remote main history

## Constraints
- All currently-passing 1615 tests must continue to pass
- No API changes to `lib/mixer.lua` — quarantine is preferred over rewriting the module
- Working tree should be clean after reconciliation (no untracked artifacts outside `.ralph/`)

## Judge Rubric

### Criteria
- **Test health**: 10 = 0 failures + 0 errors; 1 = same or more failures
- **Clean tree**: 10 = no untracked code artifacts; 1 = same clutter
- **Regression safety**: 10 = all 1615 existing tests still pass; 1 = regressions introduced
- **Documentation**: 10 = quarantine has clear rationale; 1 = files silently deleted

### Artifacts
- Capture command: `busted specs/ 2>&1 > .autoresearch/artifacts/test-output.txt`
- Types: test output, git status, quarantine README

### Scoring
- Pass threshold: 8/10 average
- Veto criteria: any criterion below 5/10
- Weight: gate (binary pass/fail)

## What's Been Tried
- **Run 1 (KEEP, metric=0, judge=9.3/10)**: Quarantine 3 broken mixer spec files to `specs/.quarantine/`, remove `.agents/` and `specs/015-sc-mixer/` planning artifacts. Hypothesis: moving non-authoritative specs out of the test path eliminates all 15 failures/errors — confirmed.

### Analysis Summary
- Local `main` is 2 commits ahead of `origin/main` (param visibility refactor + audit docs)
- 3 untracked spec files test a mixer OOP API (`mixer:handle_meter()`, `mixer:serialize()`, etc.) that does not exist — the actual `lib/mixer.lua` uses flat tables + module functions
- All 15 broken tests (3 failures + 12 errors) come from these 3 untracked files
- 2 stashes exist from `a41e1d4` containing mixer integration test WIP

## Final Status (2026-04-20)

**Spring clean objective: ACHIEVED.** Test baseline is green (1615/0/0/1). Branch has 6 clean commits ready to merge.

**Parent objective (Complete Seamstress Kria Sequencer): ACHIEVED.** All 66 tasks from tasks.md are complete. All 14 user stories pass acceptance scenarios. 10 of ~15 feature queue items landed via PRs #121-#132. Remaining queue items (re-rr0, re-7xm, re-trn, re-44c, re-lub) are beyond original spec scope.
