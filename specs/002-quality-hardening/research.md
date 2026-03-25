# Research: Quality Hardening — Test Gap Audit

**Feature**: 002-quality-hardening
**Date**: 2026-03-24
**Status**: Complete

## Overview

This feature requires no external research — all unknowns are internal to the codebase. The research phase consists of auditing existing test coverage against the spec's 8 user stories and identifying concrete gaps.

## Decision 1: Test Organization

**Decision**: Add new tests to existing spec files, organized by module.
**Rationale**: Keeps related tests together, avoids file proliferation. The existing 14 spec files map cleanly to the 7 gap areas.
**Alternatives considered**: Creating dedicated `specs/002-*_spec.lua` files per user story. Rejected because it fragments module coverage and makes `busted specs/` output harder to scan.

## Decision 2: Seamstress Load Test Isolation

**Decision**: Create a separate `seamstress_load_spec.lua` file gated on seamstress availability.
**Rationale**: The load test requires the real seamstress runtime, which is not available in all environments. A separate file allows it to be excluded from `busted specs/` when seamstress is absent.
**Alternatives considered**: Embedding the load test in `integration_spec.lua` with a skip guard. Rejected because the 30-second runtime would slow the fast-feedback loop for all other tests.

## Decision 3: Edge Case Test Approach

**Decision**: Use recorder voice for all note-output assertions; use mock clock for timing tests.
**Rationale**: Recorder voice is already the standard test double in the project. Mock clock patterns exist in `sequencer_spec.lua`. No need to introduce new test infrastructure.
**Alternatives considered**: Using MIDI loopback for note retrigger tests. Rejected because it introduces hardware dependency and the recorder voice captures the same semantics.

## Decision 4: Bug Fix Scope

**Decision**: Any bug exposed by a new failing test gets a minimal targeted fix in the same phase. Fixes are limited to the specific edge case — no refactoring.
**Rationale**: Constitution Principle III requires failing tests before implementation. Keeping fixes minimal reduces regression risk and review burden.
**Alternatives considered**: Collecting all bugs and fixing in a dedicated phase. Rejected because TDD discipline requires test→fix→green in tight cycles.

## Decision 5: Seamstress Load Test Duration

**Decision**: 30-second runtime with explicit memory/error checks at init, mid-run, and cleanup.
**Rationale**: Matches spec requirement SC-004. Long enough to catch resource leaks, short enough for CI.
**Alternatives considered**: 5-minute stress test. Rejected — diminishing returns beyond 30s for initialization/cleanup verification.

## Findings

### Existing Coverage Strengths
- Direction modes (forward, reverse, pendulum, drunk, random) have solid unit coverage
- Deep copy isolation in pattern save/load is well tested
- MIDI voice retrigger has basic coverage (pending note-off cancellation)
- Start/stop idempotency has initial assertions

### Critical Gaps Confirmed
All 39 gaps identified in the plan's "Identified Gaps by User Story" section are confirmed as genuine test coverage holes. No false positives — each gap represents an untested acceptance scenario from the spec.

### No NEEDS CLARIFICATION Items
All technical context is known. No external dependencies, APIs, or platform unknowns to resolve.
