# Review Cycle Runbook

## Scope

Operational procedure for branch/PR review, merge-now/wait output generation,
multiclaude branch handling, and speech event notifications.

## Inputs

- Git local + remote refs
- GitHub PR data (via `gh` when available)
- Canonical docs:
  - `docs/code-review.html`
  - `docs/branch-gap-analysis.html`

## Run Sequence

1. `scripts/review_cycle/run_review_cycle.sh`
2. `scripts/review_cycle/ingest_ci_events.sh`
3. `scripts/review_cycle/emit_ci_celebration.sh`
4. `scripts/review_cycle/ingest_task_events.sh`
5. `scripts/review_cycle/emit_task_completion.sh`
6. `scripts/review_cycle/validate_contracts.sh`

## Expected Outputs

- `.ralph/agent/review-cycle/review-cycle.latest.json`
- `.ralph/agent/review-cycle/task-scope-summary.latest.json`
- `.ralph/agent/review-cycle/review-lists.md`
- `.ralph/agent/review-cycle/speech-events.jsonl`
- Updated canonical docs with embedded review-cycle sections

## Troubleshooting

- Missing GH data: verify `gh auth status`
- No speech: ensure `say` is available, otherwise fallback logs are used
- Contract errors: inspect missing required top-level keys in generated JSON
