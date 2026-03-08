# Branch Review - 2026-03-08

## Snapshot

- `main`: `189b773` (`origin/main`)
- Open PRs: `#11` from `pdd/seamstress-entrypoint`
- Local feature branches: `002-modifiers-meta-config-presets`, `003-step-trigger-probability`, `004-sprite-timeline-viz`, `005-cross-track-fx`, `pdd/seamstress-entrypoint`
- Remote-only branches worth review: `origin/multiclaude/calm-hawk`, `origin/multiclaude/clever-deer`, `origin/multiclaude/witty-badger`, `origin/work/proud-eagle`, `origin/work/proud-wolf`

## Current Read

### High-complexity work

- `pdd/seamstress-entrypoint` / PR `#11`
  - Rough size: broad code, tests, docs, and Ralph metadata
  - Signal: substantial dual-platform delivery with 90+ files changed
  - Risk: branch mixes runtime code, generated planning artifacts, and orchestration state
  - Recommendation: do not merge blind; review for metadata noise and separate genuinely shippable slices

- `002-modifiers-meta-config-presets`
  - Ahead of `main` with a long omnibus commit stack
  - Signal: combines config page, time modifiers, scale/pattern/meta features, registry/serialization
  - Risk: old base plus stacked features means high merge and regression surface
  - Recommendation: treat as a simplification/split candidate, not low-hanging fruit

### Likely focused candidates

- `origin/multiclaude/calm-hawk`
  - Delta: new `lib/remote/api.lua`, `lib/remote/osc.lua`, `specs/remote_api_spec.lua`
  - Hypothesis: coherent remote-control feature branch with tests
  - Next step: targeted code review, run relevant specs, decide merge or follow-up cleanup

- `origin/multiclaude/clever-deer`
  - Delta: README update plus `docs/grid-interface.html`
  - Verified status: already merged on `main` as commit `4125f5e` / PR `#12`
  - Review notes: `git cherry -v main origin/multiclaude/clever-deer` reports the branch patch as already applied; focused specs for grid and seamstress keyboard docs passed
  - Follow-up: no merge needed; keep future doc reviews focused on unique branches only

- `origin/work/proud-eagle`
  - Delta: CI coverage workflow and `scripts/coverage.sh`
  - Verified status: already merged on `main` as commit `526ba0c` / PR `#13`
  - Review notes: `git cherry -v main origin/work/proud-eagle` reports the branch patch as already applied; local verification with `./scripts/coverage.sh --summary --check 80` passed at `92.87%` total coverage with `195` specs passing
  - Follow-up: no merge needed; treat future tooling-branch reviews like remote docs branches and check patch identity before considering merge mechanics

- `origin/work/proud-wolf`
  - Delta: `docs/voices.html`
  - Hypothesis: docs-only visual explainer
  - Next step: sanity check accuracy against current voice system, then merge if clean

- `origin/multiclaude/witty-badger`
  - Delta: one commit for spec-kit templates and remote API spec
  - Hypothesis: partially subsumed by `main` commit `189b773`
  - Next step: inspect whether anything remains unique before spending review time

## Simplicity Gaps

- Branches mix product code with Ralph/session artifacts, which increases review noise and merge risk.
- There is no single durable branch dashboard in-repo; each loop has to rediscover what exists.
- Large branches are feature bundles, not review-sized slices. `002-...` and PR `#11` both need decomposition before merge.
- Documentation/visual branches exist, but there is no explicit rule for validating docs against current keybindings and voice behavior before merge.

## Proposed Order

1. Review docs-only branches still unique to `main`: `origin/work/proud-wolf`
2. Check whether `origin/multiclaude/witty-badger` still has any unique content after `main`
3. Review `origin/multiclaude/calm-hawk` as the first code-bearing merge candidate
4. Perform a decomposition review for PR `#11`
5. Perform a decomposition review for `002-modifiers-meta-config-presets`

## Definition Of Done For Future Review Tasks

- Diff understood against `main`
- Generated/runtime Ralph state excluded from merge unless intentionally needed
- Relevant tests or content verification run
- Branch either merged or documented with a specific follow-up plan
