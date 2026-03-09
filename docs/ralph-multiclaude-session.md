# Ralph + Multiclaude Finish Session

## Objective

Complete a focused review cycle using Ralph orchestration and multiclaude-aware branch handling,
then publish a concise finish report.

## Session Plan

1. **Preflight & Sync**
   - `git fetch --all --prune`
   - `gh auth status` (if GitHub PR enrichment is expected)

2. **Run Review Cycle Core**
   - `scripts/review_cycle/run_review_cycle.sh`

3. **Run Ralph Quietly (backend-pinned)**
   - `ralph run -q -b codex`
   - Optional backend switch trials:
     - `ralph run -q -b claude`
     - `ralph run -q -b gemini`

4. **Speech Event Flows**
   - CI celebration:
     - `scripts/review_cycle/ingest_ci_events.sh`
     - `scripts/review_cycle/emit_ci_celebration.sh`
   - Task completion:
     - `scripts/review_cycle/ingest_task_events.sh`
     - `scripts/review_cycle/emit_task_completion.sh`

5. **Validation Gate**
   - `scripts/review_cycle/validate_us1.sh`
   - `scripts/review_cycle/validate_us2.sh`
   - `scripts/review_cycle/validate_us3.sh`
   - `scripts/review_cycle/validate_us4.sh`
   - `scripts/review_cycle/validate_us5.sh`
   - `scripts/review_cycle/validate_contracts.sh`

6. **Publish Finish Report**
   - Confirm updates in:
     - `docs/code-review.html`
     - `docs/branch-gap-analysis.html`
   - Save/refresh:
     - `.ralph/agent/review-cycle/dry-run-report.md`

## Finish Report (Current Snapshot)

- Cycle ID: `cycle-20260309-004924`
- Review items: `7`
- `merge-now`: `7`
- `wait`: `0`
- Multiclaude-origin items in current cycle: `0`
- Canonical docs updated:
  - `docs/code-review.html` (`REVIEW-CYCLE-SIMPLICITY`, `REVIEW-CYCLE-MULTICLAUDE` blocks present)
  - `docs/branch-gap-analysis.html` (`REVIEW-CYCLE-GAPS` block present)
- Validation: all US validators and contract validator passing in latest run

## Definition of Done

- Review cycle artifacts regenerate without errors.
- Ralph run completes or fails with a captured reason in report.
- Speech events are idempotent (no duplicate keys on replay).
- Canonical docs carry latest embedded review-cycle sections.
- Finish report is updated with final counts and anomalies.

## Notes

- If multiclaude branches are expected but absent, verify remotes/branch names are fetched locally.
- Current contract validation checks top-level required keys; full JSON Schema semantic validation can be added as a follow-up hardening step.
