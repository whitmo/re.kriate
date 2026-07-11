# spec-kit

A lightweight spec convention for re.kriate feature design. Each spec lives in `specs/<feature-name>/` and follows a four-document progression from rough idea to implementation plan.

## Documents

| File | Purpose | When to write |
|------|---------|---------------|
| `rough-idea.md` | Raw concept, 1-10 lines | Start here. Captures the "what" before any analysis. |
| `requirements.md` | Q&A clarification of scope, constraints, decisions | After rough idea. Use question/answer format to resolve ambiguity. |
| `design.md` | Technical design: architecture, components, interfaces, data models, acceptance criteria, testing strategy | After requirements are settled. This is the main reference document. |
| `plan.md` | Step-by-step implementation checklist with per-step guidance | After design. Each step should be independently testable. |

Optional additions:
- `research/` — Supporting research files (API docs, reference analysis, timing studies)
- `summary.md` — Brief overview for external readers

## Usage

```bash
# Start a new spec
cp -r spec-kit/templates/ specs/my-feature/

# Fill in rough-idea.md first, then work through each document
```

## Conventions

1. **Q&A format for requirements** — Each question explores a decision point. Answers record the decision and rationale. Number questions sequentially (Q1, Q2, ...).

2. **Design includes acceptance criteria** — Use Given/When/Then format. Each AC maps to a testable behavior.

3. **Plan steps are incremental** — Each step ends with working tests. Steps should build on each other. Include "Implementation guidance", "Test requirements", "Integration notes", and "Demo" sections.

4. **Scope boundaries are explicit** — Design documents state what is NOT included (future work) alongside what is included.

5. **Code examples in design** — Show key interfaces and data structures as Lua code blocks. These are the contract other code depends on.

## Template variables

Templates use `{{FEATURE_NAME}}` and `{{FEATURE_DESCRIPTION}}` as placeholders. Replace these when starting a new spec.
