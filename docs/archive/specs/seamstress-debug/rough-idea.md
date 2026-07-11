# Rough Idea: Debug Seamstress Sequencer

We still do not have a working sequencer in seamstress, nor any windows with UI. We need to debug this situation and make our software work.

- Adopt a failing test first approach to development
- Target 100% test coverage
- Break the problem into smaller scripts to test our components

## Current state

- All 87 busted unit tests pass (using mocked globals)
- The seamstress entrypoint (`re_kriate_seamstress.lua`) fails at runtime because:
  - `app.lua` calls `grid.connect()` and `metro.init()` unconditionally — these are norns-style APIs
  - In seamstress v2, grid uses `grid.add`/`grid.remove` event callbacks, not `grid.connect()`
  - The entrypoint tries to override grid handling AFTER `app.init()` already fails
- The tests pass because they mock all globals, so they never exercise the real seamstress API surface
- We have no tests that validate our code works against the seamstress runtime
