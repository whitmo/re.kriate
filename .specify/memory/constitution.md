<!--
Sync Impact Report
- Version change: 1.2.0 -> 1.3.0
- Modified principles:
  - V. Renamed "Spec-Driven Delivery, Automation, and Documentation" to
    "Documented Delivery, Automation, and Documentation". Relaxed the blanket
    requirement that every material feature flow through the full speckit
    pipeline (specs/<feature>/ with spec/plan/tasks) before implementation
    begins. That pipeline is now required only for large, user-facing
    features that warrant it; other material changes (architectural
    refactors, integration boundaries, cross-cutting layers, smaller feature
    work) instead require a design doc in docs/ (for architecturally
    significant changes) plus TDD (Principle III) plus PR review — the
    process this repo has actually been running. This reconciles the
    constitution with observed practice: the 2026-07 event-layer /
    adapter / voice-registry / platform architecture stack shipped as
    reviewed, TDD-covered PRs with docs/event-layers.md and docs/adapters.md,
    with no specs/NNN-*/ directory, and a same-day five-pass assessment
    (docs/assessment-2026-07-11.md, finding #28) flagged principle V as
    unenforced ceremony rather than a followed rule. This is a loosening,
    not a removal: it does not relax any previously-satisfied requirement,
    it recognizes an artifact path the project already uses successfully.
- Modified sections:
  - Delivery Workflow & Quality Gates: split into (a) the full speckit
    pipeline, retained for large/user-facing features, and (b) a design-doc
    + TDD + PR-review path for other material changes.
- Templates requiring updates:
  - ⚠ pending: ralph.yml hat instructions (specifier/planner/task-maker/
    analyzer) still narrate the speckit pipeline as the only delivery path.
    Out of scope for this amendment (constitution-only change); a follow-up
    should update hat instructions to acknowledge the lighter path for work
    that isn't feature-queue-driven.
- Follow-up TODOs:
  - Align ralph.yml hat descriptions with the two-path delivery workflow
    introduced here.
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

### V. Documented Delivery, Automation, and Documentation
Every material feature change MUST be captured in durable, reviewable design documentation
before merge. Large, user-facing features that warrant the full speckit pipeline
(specify → plan → tasks → analyze → implement → verify) MUST be tracked in
`specs/<feature>/` with clear requirements, design, and an implementation plan, and MUST
flow through that pipeline before implementation begins. Other material changes —
architectural refactors, integration boundaries, cross-cutting layers, and smaller feature
work — instead MUST have a design doc in `docs/` when the change is architecturally
significant (new subsystems, cross-cutting layers, integration boundaries), covering intent,
contracts, and rationale; purely local changes MAY rely on the PR description alone. Every
change MUST still satisfy Principle III (test-first) and land as a reviewed PR. Public-facing
behavior changes MUST update `README.md` and relevant docs in the same change set. Ralph
orchestrator automation, where used to drive delivery, MUST be defined in `ralph.yml`, with
hats explicitly defined with consistent event contracts (`triggers` and `publishes`); hats
that drive the speckit pipeline MUST keep it in lockstep with that pipeline. Autonomous
operation MUST be supported: hats MUST make informed decisions rather than blocking on human
input, and MUST document assumptions explicitly. Rationale: shared understanding and
operational continuity depend on current design documentation and reproducible automation
contracts that enable both human-driven and autonomous workflows — the artifact format
(specs/NNN-*/ vs. docs/) is a means to that end, not the end itself, and mandating the
heavier pipeline for every change produces documentation debt (unmaintained specs/ dirs)
rather than shared understanding.

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

For large, user-facing features queued for the full speckit pipeline:

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

For autonomous operation (ralph-driven) on this path, steps 2-8 run without human
intervention. Hats MUST make informed decisions rather than blocking. Assumptions MUST be
documented.

For other material changes (architectural refactors, integration boundaries, cross-cutting
layers, and feature work not queued through the speckit pipeline), the minimum bar is:

a. Write a design doc in `docs/` capturing intent, contracts, and rationale, when the change
   is architecturally significant; purely local changes may rely on the PR description.
b. Work test-first per Principle III: write failing test → implement → verify green.
c. Update operator/user documentation in the same change set for public-facing behavior
   changes.
d. Land as a reviewed PR; the reviewer confirms tests, docs, and (where applicable) the
   design doc are complete, or explicitly deferred with rationale.

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

**Version**: 1.3.0 | **Ratified**: 2026-03-08 | **Last Amended**: 2026-07-11
