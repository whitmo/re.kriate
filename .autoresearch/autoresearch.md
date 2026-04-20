# Autoresearch: SPRING_CLEAN

## Objective
Clean up the re.kriate working tree: quarantine broken specs, reconcile mixer API
divergence, remove untracked planning artifacts, and ensure a fully green test suite.

## Metrics
- **Primary**: test_errors (count, lower is better)
- **Current Best**: 0 (established by baseline quarantine)
- **Secondary**: untracked_artifacts (count of non-essential untracked files)

## Benchmark Command
```bash
busted --no-auto-insulate specs/ 2>&1 | grep -E "^[0-9]+ success"
```
Parse: extract successes/failures/errors from the summary line.

## Files in Scope
- `specs/.quarantine/` — 3 quarantined spec files + README
- `lib/mixer.lua` — actual mixer module (flat-table API)
- `specs/mixer_spec.lua` — authoritative mixer tests (604 lines, comprehensive)
- `specs/simulated_grid_spec.lua` — has 3 isolation-order failures (pre-existing)
- `.ralph/` — operational logs, old event files (cleanup candidates)
- `scripts/watch_ralph_process.sh` — untracked utility script

## Off Limits
- `lib/` source code (no functional changes during spring clean)
- Tracked spec files other than quarantined ones
- `.ralph/agent/` planning artifacts (active session state)

## Constraints
- Test suite must remain at 0 errors / 0 new failures
- No functional code changes — this is cleanup only
- Existing mixer_spec.lua already covers persistence (snapshot/restore),
  grid page drawing/interaction, voice interface, sequencer scaling, and remote API

## Judge Rubric

### Criteria
- **Cleanliness**: working tree has no unnecessary untracked files
- **Test health**: 0 errors, 0 new failures, same or higher pass count
- **Decisiveness**: quarantined specs are resolved (deleted or rewritten), not left in limbo

### Artifacts
- Test output summary
- git status showing clean tree

### Scoring
- Pass threshold: 7/10 average
- Veto criteria: any criterion below 5/10
- Weight: gate (binary pass/fail)

## What's Been Tried

- **Run 1 (KEEP, metric=0, judge=9.3/10)**: Quarantine 3 broken OOP mixer specs, remove planning artifacts. Hypothesis: isolating broken specs yields green baseline — confirmed.
- **Run 2 (KEEP, metric=0, judge=7.7/10)**: Delete quarantined specs and stale ralph logs/scripts. Hypothesis: quarantined specs are redundant given existing mixer_spec.lua coverage — confirmed. Simpler tree, same test health.
- **Run 3 (KEEP, metric=0, judge=8.8/10)**: Fix simulated-grid spec isolation by resetting renderer modifier/lock state between examples. Hypothesis: full-suite failures are caused by leaked test state rather than product regressions — confirmed. Full suite returns to green (1615 pass, 0 fail, 0 error, 1 pending).
