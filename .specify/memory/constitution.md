<!--
Sync Impact Report
- Version change: 1.1.0 -> 1.2.0
- Modified principles:
  - V. Expanded to require full speckit pipeline flow and autonomous operation support
- Modified sections:
  - Operational Constraints: added feature-queue.md requirement
  - Delivery Workflow: rewritten as 10-step speckit-driven pipeline with autonomous mode
- Templates requiring updates:
  - ✅ updated: ralph.yml (TDD speckit pipeline with 6 hats)
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

Host-provided globals from norns or seamstress SHOULD be wrapped behind `ctx` adapters
unless direct runtime hook access is required. Rationale: adapter boundaries improve
modularity and isolation while preserving platform integration.


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

### V. Spec-Driven Delivery, Automation, and Documentation
Each material feature change MUST be tracked in `specs/<feature>/` with clear requirements,
design, and an implementation plan before merge. Public-facing behavior changes MUST update
`README.md` and relevant docs in the same change set. Ralph orchestrator automation MUST be
defined in `ralph.yml`, with hats explicitly defined with consistent event contracts
(`triggers` and `publishes`) that match the speckit pipeline (specify → plan → tasks →
analyze → implement → verify). Features MUST flow through the full speckit pipeline before
implementation begins. Autonomous operation MUST be supported: hats MUST make informed
decisions rather than blocking on human input, and MUST document assumptions explicitly.
Rationale: shared understanding and operational continuity depend on current specs, docs,
and reproducible automation contracts that enable both human-driven and autonomous workflows.

## Operational Constraints

- Implementation language for core runtime is Lua; new dependencies SHOULD be minimal and
  justified in specs.
- Sequence data models MUST preserve backward-compatible behavior for existing default
  patterns unless a deliberate breaking change is approved under Governance.
- UI and control mappings MUST preserve the current interaction model unless explicitly
  versioned and documented as a behavioral change.
- `ralph.yml` is the source of truth for orchestrator behavior; hat names, triggers, and
  published events MUST be unique, documented, and kept consistent with specs.
- Feature work MUST be queued in `.ralph/agent/feature-queue.md` for autonomous operation.
  Each feature is a single line: `- [ ] <description>` (pending), `- [~] <description>`
  (in-progress), or `- [x] <description>` (done).

## Delivery Workflow & Quality Gates

1. Queue feature in `.ralph/agent/feature-queue.md`.
2. Specifier creates spec via speckit pipeline (`/speckit.specify`).
3. Planner creates technical plan with constitution check (`/speckit.plan`).
4. Task Maker generates TDD-ordered tasks (`/speckit.tasks`).
5. Analyzer validates consistency across spec/plan/tasks (`/speckit.analyze`).
6. TDD Implementer works test-first: write failing test → implement → verify green.
7. Verifier validates: lint, full test suite, structural checks, TDD compliance.
8. Repeat steps 6-7 until all tasks complete, then advance to next queued feature.
9. Update operator/user documentation in the same change set.
10. Record any accepted constitutional violations in plan complexity tracking.

For autonomous operation (ralph-driven), steps 2-8 run without human intervention.
Hats MUST make informed decisions rather than blocking. Assumptions MUST be documented.

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

**Version**: 1.2.0 | **Ratified**: 2026-03-08 | **Last Amended**: 2026-03-24
