# Feature Specification: Branch Review Decomposition Planning

**Feature Branch**: `001-branch-review-followups`  
**Created**: 2026-03-08  
**Updated**: 2026-03-09  
**Status**: Draft  
**Input**: User description: "review all branches locally and remotely including open PRs. Merge low hanging fruit, make notes and plans for other unfinished work. Tidy up like Kent Beck, work on planning for increase simplicity. Visualize and document where there are gaps. Use spec-kit to spec out the next set of tasks based on your last run."

## Clarifications

### Session 2026-03-09

- Q: What unfinished work should this spec plan next? → A: The two remaining high-complexity items from the 2026-03-08 review: PR `#11` (`pdd/seamstress-entrypoint`) and local branch `002-modifiers-meta-config-presets`.
- Q: What artifacts count as planning evidence? → A: `.ralph/agent/branch-review-2026-03-08.md`, `docs/code-review.html`, `docs/branch-gap-analysis.html`, and the linked visual snapshots under `/Users/whit/.agent/diagrams/`.
- Q: Should already-merged or already-deleted low-hanging-fruit branches stay in scope? → A: No; they are historical evidence only, not planned implementation targets.
- Q: What kind of output is needed now? → A: A simplicity-first next-task set that decomposes each remaining large branch into reviewable, testable slices.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture the Remaining Planning Scope (Priority: P1)

As a maintainer, I need one current inventory of the unfinished branch-review work so planning
is based on the latest verified review evidence rather than stale branch state.

**Why this priority**: Planning against stale or already-merged branches wastes effort and
creates follow-up tasks that no longer matter.

**Independent Test**: A reviewer can inspect the planning artifact and confirm that only PR `#11`
and branch `002-modifiers-meta-config-presets` remain as active decomposition targets.

**Acceptance Scenarios**:

1. **Given** the 2026-03-08 review artifacts, **When** the planning scope is restated,
   **Then** merged, deleted, or fully subsumed branches are excluded from the active next-task set.
2. **Given** PR `#11` and branch `002-modifiers-meta-config-presets`, **When** the inventory is
   published, **Then** each includes its blocking complexity signal and evidence source.
3. **Given** canonical visuals and review notes, **When** the scope summary is written,
   **Then** it references the in-repo docs and external snapshots that justify the prioritization.

---

### User Story 2 - Decompose the Two Large Workstreams (Priority: P1)

As a maintainer, I need each remaining large branch translated into smaller reviewable slices so
the next work can be merged or rejected incrementally instead of as an omnibus change.

**Why this priority**: Both remaining items are explicitly too large to merge safely in one pass.

**Independent Test**: A reviewer can read the decomposition plan and identify a sequence of
smaller tasks for PR `#11` and branch `002` without needing extra branch discovery.

**Acceptance Scenarios**:

1. **Given** PR `#11` mixes runtime code, tests, docs, and Ralph metadata, **When** its next
   tasks are defined, **Then** the plan separates shippable slices from review noise.
2. **Given** branch `002` mixes modifiers, patterns, scale, meta, and registry changes, **When**
   its next tasks are defined, **Then** the plan breaks the branch into conceptually coherent
   slices with explicit dependency order.
3. **Given** multiple ways to split either branch, **When** the recommendation is documented,
   **Then** the simpler decomposition is chosen and the more complex alternative is rejected
   with rationale.

---

### User Story 3 - Publish a Prioritized Next-Task Set (Priority: P2)

As a maintainer, I need the decomposition work turned into a spec-ready task set so a future loop
can execute one atomic slice at a time.

**Why this priority**: The review is already done; the missing step is converting it into
actionable, ordered work.

**Independent Test**: A reviewer can inspect the generated task list and see a priority order,
dependencies, expected outcomes, and linked evidence for each next task.

**Acceptance Scenarios**:

1. **Given** the decomposition plans are complete, **When** the task set is published,
   **Then** each task is a single reviewable unit that can be finished in one or two iterations.
2. **Given** a task depends on an earlier split or validation step, **When** tasks are listed,
   **Then** the dependency is explicit.
3. **Given** the branch-gap visuals show the same top risks, **When** the task set is reviewed,
   **Then** the top-priority tasks align with those visuals.

### Edge Cases

- A branch appears unique in one artifact but is shown as already subsumed in a newer review note.
- PR `#11` contains generated or orchestration state that should be excluded from any merge plan.
- Branch `002` contains tightly coupled changes that cannot be split cleanly without documenting a
  temporary staging branch or rewrite path.
- Visual snapshots and in-repo docs disagree because one is older than the other.

## Platform & Timing Constraints *(mandatory for sequencing/runtime changes)*

- **Parity Impact**: No norns or seamstress runtime behavior changes are in scope for this feature.
- **Timing Expectations**: No timing-sensitive sequencing work is introduced here.
- **State Model Impact**: This feature only changes planning artifacts and documentation.

## Automation Contract *(mandatory when orchestration changes are in scope)*

- **Ralph Config Impact**: No `ralph.yml` behavior change is required.
- **Hat Definitions**: No new hats are introduced.
- **Event Contract**: The output of this feature is planning documentation and task definitions, not
  a new runtime event protocol.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST restate the current unfinished branch-review scope using the latest
  verified review evidence from 2026-03-08.
- **FR-002**: The system MUST exclude branches and PRs already merged, deleted, or fully subsumed
  by `main` from the active next-task set.
- **FR-003**: The system MUST identify PR `#11` and branch `002-modifiers-meta-config-presets` as
  the active planning targets unless newer review evidence explicitly supersedes them.
- **FR-004**: The system MUST document the blocking reasons that prevent each active target from
  being merged as-is.
- **FR-005**: The system MUST produce a decomposition plan for PR `#11` that distinguishes
  shippable slices from docs/metadata/review-noise slices.
- **FR-006**: The system MUST produce a decomposition plan for branch `002-modifiers-meta-config-presets`
  that groups changes into simpler, conceptually coherent work units.
- **FR-007**: The system MUST assign an intended outcome and dependency order to each proposed next
  task.
- **FR-008**: The system MUST state the simplicity rationale for each decomposition choice,
  including why a broader bundled path was not selected.
- **FR-009**: The system MUST reference `docs/code-review.html`, `docs/branch-gap-analysis.html`,
  and `.ralph/agent/branch-review-2026-03-08.md` as canonical evidence inputs.
- **FR-010**: The system MUST reference the external visual snapshots under
  `/Users/whit/.agent/diagrams/` when they reinforce or clarify the planning priority.
- **FR-011**: The system MUST produce a spec-ready next-task summary that can be translated
  directly into Spec Kit plan/tasks artifacts.
- **FR-012**: The system MUST preserve a clear distinction between completed review work and
  remaining decomposition work.

### Key Entities *(include if feature involves data)*

- **Planning Target**: A remaining unfinished branch or PR that still requires decomposition before
  merge or rejection.
- **Evidence Source**: A canonical document or visual snapshot used to justify planning decisions.
- **Decomposition Slice**: A smaller, reviewable unit extracted from a larger branch or PR.
- **Task Candidate**: A proposed next action with priority, dependency order, intended outcome,
  and linked evidence.
- **Blocked Merge Reason**: The concrete explanation for why a planning target cannot be merged
  directly.

## Assumptions & Dependencies

- `.ralph/agent/branch-review-2026-03-08.md` remains the latest verified narrative summary of the
  completed branch-review pass.
- `docs/code-review.html` and `docs/branch-gap-analysis.html` remain the canonical in-repo visual
  artifacts for review findings.
- The linked snapshots in `/Users/whit/.agent/diagrams/` are accessible during planning and may be
  cited when they add clarity beyond the in-repo docs.
- Maintainer judgment is still required before any actual branch split or merge operation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of active planning targets are backed by at least one cited evidence source.
- **SC-002**: 100% of already-resolved low-hanging-fruit branches are excluded from the active
  next-task set.
- **SC-003**: Both PR `#11` and branch `002-modifiers-meta-config-presets` receive a documented
  decomposition plan with at least one explicit simpler-than-bundle recommendation.
- **SC-004**: 100% of proposed next tasks include a priority, dependency note, and intended outcome.
- **SC-005**: A reviewer can identify the first implementation slice for each active planning
  target in one pass through the planning artifacts.
