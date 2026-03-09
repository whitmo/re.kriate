---

description: "Task list for branch review decomposition planning"

---

# Tasks: Branch Review Decomposition Planning

**Input**: Design documents from `/specs/001-branch-review-followups/`
**Prerequisites**: plan.md (required), spec.md (required), `.ralph/agent/branch-review-2026-03-08.md`, `docs/code-review.html`, `docs/branch-gap-analysis.html`

**Tests**: Validate generated planning artifacts by comparing each story output against the narrowed spec acceptance scenarios and the cited review evidence.

**Organization**: Tasks are grouped by user story so each planning outcome can be produced and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: User story label for story-phase tasks (`[US1]`, `[US2]`, `[US3]`)
- Include exact file paths in each task description

## Phase 1: Setup (Shared Planning Baseline)

**Purpose**: Replace stale review-cycle assumptions with the narrowed evidence base

- [ ] T001 Update scope framing in `specs/001-branch-review-followups/research.md` to cite only PR `#11`, branch `002-modifiers-meta-config-presets`, and the 2026-03-08 review evidence set
- [ ] T002 [P] Review `docs/code-review.html`, `docs/branch-gap-analysis.html`, and `/Users/whit/.agent/diagrams/re-kriate-branch-gap-map-2026-03-08.html` for the current top-risk signals and record any conflicts in `specs/001-branch-review-followups/research.md`
- [ ] T003 [P] Remove or rewrite stale review-cycle automation references in `specs/001-branch-review-followups/data-model.md`, `specs/001-branch-review-followups/quickstart.md`, and `specs/001-branch-review-followups/contracts/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define the evidence-backed planning model that every user story depends on

**⚠️ CRITICAL**: No user story task should begin until the planning model and evidence inventory are consistent

- [ ] T004 Define the active planning entities and field expectations in `specs/001-branch-review-followups/data-model.md` for Planning Target, Evidence Source, Blocked Merge Reason, Decomposition Slice, and Task Candidate
- [ ] T005 [P] Build an evidence inventory table in `specs/001-branch-review-followups/research.md` mapping each active target to `.ralph/agent/branch-review-2026-03-08.md`, `docs/code-review.html`, `docs/branch-gap-analysis.html`, and relevant `/Users/whit/.agent/diagrams/` snapshots
- [ ] T006 [P] Document the validation approach in `specs/001-branch-review-followups/quickstart.md` for checking future planning artifacts against the narrowed spec scenarios and cited evidence

**Checkpoint**: Planning baseline is aligned and user-story decomposition work can proceed

---

## Phase 3: User Story 1 - Capture the Remaining Planning Scope (Priority: P1) 🎯 MVP

**Goal**: Publish one current inventory of the unfinished branch-review work, backed by canonical evidence

**Independent Test**: A reviewer can inspect the scope section and confirm that only PR `#11` and branch `002-modifiers-meta-config-presets` remain active, each with evidence-backed blocking signals

### Implementation for User Story 1

- [ ] T007 [US1] Summarize the active-scope inventory in `specs/001-branch-review-followups/research.md`, explicitly excluding already-merged, deleted, or subsumed branches
- [ ] T008 [P] [US1] Record the blocked-merge reasons for PR `#11` and branch `002-modifiers-meta-config-presets` in `specs/001-branch-review-followups/data-model.md`
- [ ] T009 [US1] Add an evidence-reference section to `specs/001-branch-review-followups/quickstart.md` that shows where a maintainer verifies the active scope

**Checkpoint**: Active scope is explicit, evidence-backed, and independently reviewable

---

## Phase 4: User Story 2 - Decompose the Two Large Workstreams (Priority: P1)

**Goal**: Turn the two large targets into simpler, reviewable slices with explicit dependency order

**Independent Test**: A reviewer can identify a sequence of smaller tasks for PR `#11` and branch `002` without rediscovering branch state

### Implementation for User Story 2

- [ ] T010 [US2] Document a slice plan for PR `#11` in `specs/001-branch-review-followups/research.md`, separating shippable runtime work from docs, generated artifacts, and Ralph metadata
- [ ] T011 [P] [US2] Document a slice plan for `002-modifiers-meta-config-presets` in `specs/001-branch-review-followups/research.md`, grouping changes into coherent work units with dependency order
- [ ] T012 [US2] Capture the simplicity rationale and rejected broader-bundle alternatives for both targets in `specs/001-branch-review-followups/plan.md`

**Checkpoint**: Both active targets have a simpler-than-bundle decomposition with rationale

---

## Phase 5: User Story 3 - Publish a Prioritized Next-Task Set (Priority: P2)

**Goal**: Convert the decomposition into a spec-ready, dependency-aware task list for future loops

**Independent Test**: A reviewer can inspect the next-task set and see priorities, dependencies, intended outcomes, and linked evidence for each task

### Implementation for User Story 3

- [ ] T013 [US3] Translate the chosen decomposition into ordered implementation tasks in `specs/001-branch-review-followups/tasks.md`, keeping each task to one reviewable unit
- [ ] T014 [P] [US3] Add intended outcomes, dependency notes, and evidence citations for each proposed task in `specs/001-branch-review-followups/tasks.md`
- [ ] T015 [US3] Add a maintainer walkthrough in `specs/001-branch-review-followups/quickstart.md` showing how to select the first slice for PR `#11` and the first slice for branch `002`

**Checkpoint**: The next-task set is ready for execution in future planning/implementation loops

---

## Phase 6: Polish & Cross-Cutting Validation

**Purpose**: Final consistency checks across all planning artifacts

- [ ] T016 [P] Verify `specs/001-branch-review-followups/spec.md`, `plan.md`, `tasks.md`, `research.md`, `data-model.md`, and `quickstart.md` all use the narrowed scope and no longer describe the legacy review automation bundle
- [ ] T017 Validate the final planning artifacts against `.ralph/agent/branch-review-2026-03-08.md`, `docs/code-review.html`, and `docs/branch-gap-analysis.html`, then record the result in `specs/001-branch-review-followups/checklists/requirements.md`
- [ ] T018 [P] Confirm the `/Users/whit/.agent/diagrams/re-kriate-branch-gap-map-2026-03-08.html` and `/Users/whit/.agent/diagrams/re-kriate-code-review.html` snapshots reinforce the same priority order and note any residual drift in `specs/001-branch-review-followups/research.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks all user stories
- **Phase 3 (US1)**: Depends on Phase 2 and defines the MVP planning inventory
- **Phase 4 (US2)**: Depends on US1 because decomposition follows confirmed scope and blocked-merge reasons
- **Phase 5 (US3)**: Depends on US2 because the next-task set is derived from the chosen decomposition
- **Phase 6 (Polish)**: Depends on all user stories

### User Story Dependencies

- **US1 (P1)**: Independent after Foundational; required before any decomposition work is trustworthy
- **US2 (P1)**: Requires the US1 scope inventory and blocked-merge reasons
- **US3 (P2)**: Requires the US2 slice plans and rationale

### Parallel Opportunities

- Setup parallel: T002, T003
- Foundational parallel: T005, T006
- US1 parallel: T008 alongside T007
- US2 parallel: T011 alongside T010
- US3 parallel: T014 alongside T013
- Polish parallel: T016 and T018

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate that only PR `#11` and branch `002-modifiers-meta-config-presets` remain in scope

### Incremental Delivery

1. Publish the narrowed active-scope inventory
2. Add decomposition slices and simplicity rationale for both active targets
3. Convert those slices into the ordered next-task set
4. Run cross-artifact validation against the canonical review evidence

### Parallel Team Strategy

1. One maintainer updates the evidence inventory and planning model
2. A second maintainer can decompose PR `#11` while another decomposes branch `002`
3. Rejoin on the final prioritized task set and validation pass

---

## Notes

- `[P]` tasks are independent file updates or validation passes
- The generated task set is intentionally limited to decomposition planning, not implementation of branch code itself
- Evidence traceability is mandatory because the feature exists to avoid rediscovering stale branch state
