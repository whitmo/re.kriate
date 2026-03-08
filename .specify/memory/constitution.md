<!--
Sync Impact Report
- Version change: 0.0.0 -> 1.0.0
- Modified principles:
  - Template Principle 1 -> I. Context-Centric Architecture
  - Template Principle 2 -> II. Platform-Parity Behavior
  - Template Principle 3 -> III. Test-First Sequencing Correctness (NON-NEGOTIABLE)
  - Template Principle 4 -> IV. Deterministic Timing and Safe Degradation
  - Template Principle 5 -> V. Spec-Driven Delivery and Documentation
- Added sections:
  - Operational Constraints
  - Delivery Workflow & Quality Gates
- Removed sections:
  - None
- Templates requiring updates:
  - ✅ updated: .specify/templates/plan-template.md
  - ✅ updated: .specify/templates/spec-template.md
  - ✅ updated: .specify/templates/tasks-template.md
  - ⚠ pending (not present in repository): .specify/templates/commands/*.md
- Follow-up TODOs:
  - None
-->

# re.kriate Constitution

## Core Principles

### I. Context-Centric Architecture
All runtime state MUST flow through a single explicit context object (`ctx`) and MUST NOT
be scattered across custom globals or hidden module state. Entry-point globals are limited
to host runtime hooks (`init`, `redraw`, `key`, `enc`, `cleanup`) and must delegate to
modules. Rationale: this preserves testability, predictable ownership, and easier porting
between norns and seamstress.

### II. Platform-Parity Behavior
User-facing sequencing behavior MUST remain functionally consistent across norns and
seamstress for shared features (track stepping, loop behavior, direction modes,
quantization, and transport semantics). Platform-specific adapters (nb/MIDI, keyboard/UI)
MAY differ in implementation details, but behavioral differences MUST be documented in
feature specs and release notes. Rationale: portability is a core project promise.

### III. Test-First Sequencing Correctness (NON-NEGOTIABLE)
For every change that affects sequencing logic, direction behavior, loop bounds, timing
math, or parameter mapping, failing tests MUST be written before implementation and must
pass before merge. At minimum, unit coverage MUST include deterministic step advancement,
loop boundary handling, and parameter value mapping. Rationale: regressions in musical
timing and pattern evolution are high impact and hard to detect manually.

### IV. Deterministic Timing and Safe Degradation
Clock and scheduling changes MUST define expected timing behavior and acceptable jitter in
the relevant spec. Implementations MUST favor deterministic progression and MUST degrade
gracefully under load (no crashes, no corrupted track state, bounded missed/late events).
Any intentional timing tradeoff MUST be explicitly documented with rationale. Rationale:
musical trust depends on stable timing even when resources are constrained.

### V. Spec-Driven Delivery and Documentation
Each material feature change MUST be tracked in `specs/<feature>/` with clear requirements,
design, and an implementation plan before merge. Public-facing behavior changes MUST update
`README.md` and relevant docs in the same change set. Rationale: shared understanding and
operational continuity depend on current specs and docs.

## Operational Constraints

- Implementation language for core runtime is Lua; new dependencies SHOULD be minimal and
  justified in specs.
- Sequence data models MUST preserve backward-compatible behavior for existing default
  patterns unless a deliberate breaking change is approved under Governance.
- UI and control mappings MUST preserve the current interaction model unless explicitly
  versioned and documented as a behavioral change.

## Delivery Workflow & Quality Gates

1. Define feature scope in spec documents before implementation.
2. Add or update failing tests first for behavior-changing work.
3. Implement minimal change to satisfy tests and constraints.
4. Validate platform parity for shared behavior (norns + seamstress where applicable).
5. Update operator/user documentation in the same PR.
6. Record any accepted constitutional violations in plan complexity tracking.

## Governance

This constitution is the highest-priority engineering policy for this repository. In case
of conflict, this document overrides ad-hoc workflow notes.

Amendment procedure:
1. Propose amendment in a PR that includes updated constitution text and a Sync Impact
   Report.
2. Identify impacted templates/docs and update them in the same change set or mark explicit
   follow-up TODOs.
3. Obtain maintainer approval before merge.

Versioning policy:
- MAJOR: Remove or redefine a core principle in a backward-incompatible way.
- MINOR: Add a principle/section or materially expand governance requirements.
- PATCH: Clarifications, wording improvements, typo/non-semantic edits.

Compliance review expectations:
- Every implementation plan MUST include a Constitution Check against all core principles.
- Every PR review MUST confirm tests, parity validation, and documentation updates are
  complete or explicitly deferred with rationale.
- Periodic compliance audits SHOULD occur at least once per release cycle.

**Version**: 1.0.0 | **Ratified**: 2026-03-08 | **Last Amended**: 2026-03-08
