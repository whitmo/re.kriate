# Implementation Plan: Branch Review Decomposition Planning

**Branch**: `001-branch-review-followups` | **Date**: 2026-03-09 | **Spec**: [/Users/whit/src/re.kriate/specs/001-branch-review-followups/spec.md](/Users/whit/src/re.kriate/specs/001-branch-review-followups/spec.md)
**Input**: Feature specification from `/specs/001-branch-review-followups/spec.md`

## Summary

Regenerate the planning artifacts so they only describe the two unfinished review targets from the
2026-03-08 branch review: PR `#11` (`pdd/seamstress-entrypoint`) and local branch
`002-modifiers-meta-config-presets`. The implementation remains documentation-first: consolidate
the canonical review evidence, document why each target is blocked from merge as-is, and publish a
simplicity-first decomposition plus ordered next-task set that future loops can execute one slice
at a time.

## Technical Context

**Language/Version**: Markdown specifications + HTML review artifacts + bash workflow scripts  
**Primary Dependencies**: Spec Kit templates, `git` branch/PR metadata, `.ralph/agent/branch-review-2026-03-08.md`, `docs/code-review.html`, `docs/branch-gap-analysis.html`  
**Storage**: Versioned planning docs under `specs/001-branch-review-followups/` plus cited review artifacts in `docs/` and `.ralph/agent/`  
**Testing**: Manual artifact consistency review against spec acceptance scenarios and evidence sources  
**Target Platform**: Local repository planning workflow  
**Project Type**: Documentation/process planning feature  
**Performance Goals**: A maintainer can identify the first reviewable slice for each active target in one pass through the generated artifacts  
**Constraints**: Exclude already-merged or subsumed branches, keep runtime/platform behavior out of scope, preserve evidence traceability back to the 2026-03-08 review set  
**Scale/Scope**: Two active planning targets, four canonical evidence inputs, one prioritized next-task set

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Context-Centric Architecture**: No runtime or state-management changes are introduced; only planning artifacts are updated.
- [x] **Platform-Parity Behavior**: No norns or seamstress behavior changes are proposed in this feature.
- [x] **Test-First Sequencing Correctness**: No sequencing implementation or timing logic changes are in scope.
- [x] **Deterministic Timing & Safe Degradation**: Timing/audio behavior remains untouched.
- [x] **Spec & Documentation Discipline**: Scope is captured in spec artifacts and tied back to canonical review evidence.
- [x] **Ralph Automation Contract**: No `ralph.yml`, hat, or runtime event changes are introduced.

## Project Structure

### Documentation (this feature)

```text
specs/001-branch-review-followups/
├── plan.md
├── tasks.md
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
```

### Evidence Inputs (repository and local review context)

```text
.ralph/agent/
└── branch-review-2026-03-08.md

docs/
├── code-review.html
└── branch-gap-analysis.html

/Users/whit/.agent/diagrams/
├── re-kriate-branch-gap-map-2026-03-08.html
└── re-kriate-code-review.html
```

**Structure Decision**: Keep the feature entirely documentation-centric. The implementation work is
to align the Spec Kit artifacts with the narrowed planning objective and use the review docs as the
source of truth for decomposition decisions.

## Implementation Phases

### Phase 0: Evidence Baseline

- Confirm the active scope is limited to PR `#11` and branch `002-modifiers-meta-config-presets`.
- Cross-check `.ralph/agent/branch-review-2026-03-08.md`, `docs/code-review.html`,
  `docs/branch-gap-analysis.html`, and the `/Users/whit/.agent/diagrams/` snapshots for matching
  risk signals and prioritization.
- Remove or quarantine stale planning assumptions from older review-cycle automation work so they
  do not leak into regenerated artifacts.

### Phase 1: Planning Model

- Define the planning entities that matter now: planning target, blocked merge reason,
  decomposition slice, evidence source, and task candidate.
- Record explicit blocking reasons for PR `#11` and branch `002`.
- Choose the simplest decomposition path for each target and note why broader bundle-based
  alternatives are rejected.

### Phase 2: Task Publication

- Convert the decomposition into a priority-ordered, dependency-aware task set.
- Ensure each proposed task is reviewable in one or two iterations and cites its evidence source.
- Preserve the distinction between completed review work and future decomposition execution.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | N/A |

## Post-Design Constitution Check

- [x] **Context-Centric Architecture**: Final plan only updates planning docs and evidence references.
- [x] **Platform-Parity Behavior**: No platform divergence is introduced.
- [x] **Test-First Sequencing Correctness**: No sequencing work is planned here.
- [x] **Deterministic Timing & Safe Degradation**: Timing behavior remains out of scope.
- [x] **Spec & Documentation Discipline**: The narrowed scope is reflected in plan/tasks and tied to canonical review artifacts.
- [x] **Ralph Automation Contract**: No automation contract changes are proposed.
