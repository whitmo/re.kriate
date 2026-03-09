# Data Model: Branch Review Decomposition Planning

## Entity: PlanningTarget

- Description: A remaining branch or PR that still needs decomposition work before merge or rejection.
- Fields:
  - `id` (string, required): `branch:<name>` or `pr:<number>`
  - `display_name` (string, required)
  - `source` (enum, required): `local-branch`, `remote-branch`, `pull-request`
  - `status` (enum, required): `active`, `superseded-candidate`, `decompose-first`
  - `blocking_reasons` (array[string], required, min length 1)
  - `recommended_outcome` (string, required)
  - `evidence_source_ids` (array[string], required, min length 1)
- Validation Rules:
  - Only unresolved items may appear as `PlanningTarget`.
  - `recommended_outcome` must describe either decomposition, closure, or explicit follow-up review.

## Entity: EvidenceSource

- Description: A reviewed artifact used to justify planning scope or task priority.
- Fields:
  - `id` (string, required)
  - `path` (string, required)
  - `kind` (enum, required): `narrative-review`, `in-repo-visual`, `external-snapshot`
  - `focus` (string, required)
  - `captured_on` (string, optional)

## Entity: EvidenceAssessment

- Description: The specific finding extracted from an evidence source for one planning target.
- Fields:
  - `target_id` (string, required)
  - `evidence_source_id` (string, required)
  - `summary` (string, required)
  - `priority_signal` (enum, required): `supports-active-scope`, `supports-decomposition`, `supports-superseded-read`, `general-modularity-guidance`
  - `conflicts_with` (array[string], optional)
- Validation Rules:
  - Every active target must have at least one `supports-decomposition` or `supports-superseded-read` assessment.

## Entity: DecompositionSlice

- Description: A reviewable unit extracted from a large planning target.
- Fields:
  - `id` (string, required)
  - `target_id` (string, required)
  - `title` (string, required)
  - `goal` (string, required)
  - `depends_on` (array[string], optional)
  - `excluded_noise` (array[string], optional)
  - `simplicity_rationale` (string, required)
  - `alternatives_rejected` (array[string], required, min length 1)
- Validation Rules:
  - Each slice must represent one reviewable unit, not a bundled branch rewrite.

## Entity: TaskCandidate

- Description: A spec-ready next action derived from the chosen slice plan.
- Fields:
  - `id` (string, required)
  - `title` (string, required)
  - `priority` (enum, required): `P1`, `P2`, `P3`
  - `target_id` (string, required)
  - `outcome` (string, required)
  - `dependency_note` (string, optional)
  - `evidence_source_ids` (array[string], required, min length 1)
- Validation Rules:
  - Every task candidate must map back to one planning target and at least one evidence source.

## Entity: ValidationResult

- Description: The recorded outcome of checking the narrowed planning artifacts against review evidence.
- Fields:
  - `validated_on` (string, required, ISO date)
  - `artifact_paths` (array[string], required)
  - `status` (enum, required): `pass`, `pass-with-conflicts`, `fail`
  - `confirmed_scope` (array[string], required)
  - `residual_conflicts` (array[string], optional)
  - `notes` (array[string], optional)

## Relationships

- `PlanningTarget.evidence_source_ids` references many `EvidenceSource`.
- `EvidenceAssessment` links one `PlanningTarget` to one `EvidenceSource`.
- `DecompositionSlice.target_id` belongs to one `PlanningTarget`.
- `TaskCandidate.target_id` belongs to one `PlanningTarget`.
- `ValidationResult.confirmed_scope` must list the final active planning targets validated in the current pass.
