# Phase 0 Research: Branch Review Decomposition Planning

## Validation Focus

- Objective: verify that the narrowed planning artifacts still match the 2026-03-08 branch-review evidence after low-hanging-fruit merges and deletions.
- Active planning targets under review:
  - PR `#11` / `pdd/seamstress-entrypoint`
  - local branch `002-modifiers-meta-config-presets`
- Resolved branches remain evidence only; they are not candidates for new implementation tasks.

## Evidence Inventory

| Evidence source | What it contributes | Signals confirmed |
| --- | --- | --- |
| `.ralph/agent/branch-review-2026-03-08.md` | Narrative summary of the completed review pass | PR `#11` and branch `002` are the only remaining high-complexity items; both require decomposition before merge or rejection |
| `docs/branch-gap-analysis.html` | Canonical in-repo branch status and next-step ordering | PR `#11` and branch `002` remain top priority; PR `#11` is marked superseded and branch `002` is the main simplification target |
| `docs/code-review.html` | Architectural and modularity guidance for simplicity-first slicing | Modular decomposition is favored over large bundled changes; review noise should be reduced |
| `/Users/whit/.agent/diagrams/re-kriate-branch-gap-map-2026-03-08.html` | External visual summary of branch risk and recommended actions | Large mixed branches should be decomposed; orchestration noise should be stripped from PR `#11`; `002` needs split review |
| `/Users/whit/.agent/diagrams/re-kriate-code-review.html` | External snapshot of code-review architecture guidance | Confirms the codebase benefits from modular decomposition rather than omnibus delivery |

## Active Scope Read

### PR `#11` / `pdd/seamstress-entrypoint`

- Shared signal across all evidence: the PR is too mixed to merge as-is.
- Blocking reasons:
  - combines runtime code, tests, docs, spec artifacts, and Ralph metadata
  - creates review noise by mixing shippable work with orchestration state
  - risks regressing `main` if merged blindly
- Evidence conflict to preserve:
  - `.ralph/agent/branch-review-2026-03-08.md` leaves room to extract shippable slices after stripping metadata noise
  - `docs/branch-gap-analysis.html` recommends closing the PR as superseded by branch `002`
- Planning implication: future execution must decide whether PR `#11` produces any slice worth salvaging or should be closed with its value sourced entirely from `002`

### Branch `002-modifiers-meta-config-presets`

- Shared signal across all evidence: this is the main remaining implementation line, but it is too large to merge in one pass.
- Blocking reasons:
  - long omnibus stack on an old base
  - mixes config UI, modifiers, scale/pattern/meta work, registry/serialization, and scaffolding
  - high merge and regression surface until simplified into review-sized slices
- Planning implication: the next task set should split `002` into coherent, dependency-ordered slices rather than prepare it for direct merge

## Decisions

### Decision 1: Canonical Evidence Set

- Decision: treat `.ralph/agent/branch-review-2026-03-08.md`, `docs/branch-gap-analysis.html`, `docs/code-review.html`, and the two `/Users/whit/.agent/diagrams/` snapshots as the validation baseline.
- Rationale: they capture both branch-specific risk and the simplicity/modularity guidance needed for decomposition planning.

### Decision 2: Preserve the PR `#11` Conflict Explicitly

- Decision: document the disagreement between the narrative review and the branch-gap dashboard instead of forcing a false single answer.
- Rationale: the validation task is to align artifacts with evidence, not to rewrite the evidence.

### Decision 3: Decomposition Planning Only

- Decision: remove review-cycle automation, CI celebration, and task-speech behavior from the planning artifacts.
- Rationale: those flows are not part of the current objective and are unsupported by the narrowed spec, plan, and tasks.

## Result

- Validation outcome: the narrowed `spec.md`, `plan.md`, and `tasks.md` match the current objective.
- Required cleanup: `data-model.md`, `quickstart.md`, and the contract files must describe decomposition planning rather than the legacy review-cycle automation bundle.
