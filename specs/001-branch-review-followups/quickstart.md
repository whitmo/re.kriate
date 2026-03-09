# Quickstart: Branch Review Decomposition Planning Validation

## Goal

Validate that the Spec Kit planning artifacts describe only the remaining decomposition work from the 2026-03-08 branch review and that they stay traceable to the evidence set.

## Inputs

- Planning artifacts:
  - `specs/001-branch-review-followups/spec.md`
  - `specs/001-branch-review-followups/plan.md`
  - `specs/001-branch-review-followups/tasks.md`
  - `specs/001-branch-review-followups/research.md`
  - `specs/001-branch-review-followups/data-model.md`
- Canonical evidence:
  - `.ralph/agent/branch-review-2026-03-08.md`
  - `docs/branch-gap-analysis.html`
  - `docs/code-review.html`
  - `/Users/whit/.agent/diagrams/re-kriate-branch-gap-map-2026-03-08.html`
  - `/Users/whit/.agent/diagrams/re-kriate-code-review.html`
- Validation contracts:
  - `contracts/review-artifact.schema.json`
  - `contracts/review-cycle.schema.json`
  - `contracts/decomposition-slice.schema.json`
  - `contracts/task-scope-summary.schema.json`

## Steps

1. Confirm the active scope is limited to PR `#11` and branch `002-modifiers-meta-config-presets`.
2. Verify that resolved low-hanging-fruit branches remain historical evidence only and do not appear as active next-task targets.
3. Cross-check each planning artifact against the evidence set for:
   - blocked-merge reasons
   - closure-first guidance for PR `#11` with salvage-only fallback
   - simplification-first guidance for branch `002-modifiers-meta-config-presets`
   - simplicity-first task ordering
4. Record any evidence conflicts explicitly, especially the disagreement over whether PR `#11` should be sliced further or closed as superseded by `002`.
5. Update `checklists/requirements.md` with the validation result and any residual conflicts.

## Validation Checklist

- Only PR `#11` and branch `002-modifiers-meta-config-presets` remain in active planning scope.
- Planning artifacts cite the canonical review docs and diagram snapshots.
- Support docs do not describe CI celebration, speech workflows, or generic review-cycle automation as in-scope outputs.
- Proposed slices and next tasks prefer modular decomposition over omnibus delivery.
- Residual evidence drift is documented rather than silently collapsed.

## Maintainer Walkthrough

1. Read `.ralph/agent/branch-review-2026-03-08.md` for the narrative review baseline.
2. Read the branch status and recommended steps in `docs/branch-gap-analysis.html`.
3. Use `docs/code-review.html` and `/Users/whit/.agent/diagrams/re-kriate-code-review.html` to confirm the modularity and simplicity guidance behind the proposed slices.
4. Review `specs/001-branch-review-followups/tasks.md` to choose the first slice:
   - for PR `#11`, decide whether any shippable slice survives the superseded read
   - for branch `002`, pick the first coherent dependency-light slice

## Operational Commands

```bash
sed -n '1,260p' specs/001-branch-review-followups/spec.md
sed -n '1,260p' specs/001-branch-review-followups/plan.md
sed -n '1,260p' specs/001-branch-review-followups/tasks.md
sed -n '1,260p' .ralph/agent/branch-review-2026-03-08.md
rg -n "pdd/seamstress-entrypoint|002-modifiers-meta-config-presets" docs/branch-gap-analysis.html /Users/whit/.agent/diagrams/re-kriate-branch-gap-map-2026-03-08.html
```

## Note

Contract filenames under `contracts/` are now aligned to the narrowed planning model (for example,
`decomposition-slice.schema.json`) and should stay synchronized with `data-model.md` entity names.
