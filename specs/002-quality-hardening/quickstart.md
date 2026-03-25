# Quickstart: Quality Hardening

## Prerequisites

- Lua 5.4: `/opt/homebrew/opt/lua@5.4/bin/lua`
- Busted: `luarocks install busted`
- Lua 5.4 symlink: `/opt/homebrew/opt/lua/bin/lua5.4 -> /opt/homebrew/opt/lua@5.4/bin/lua`
- Seamstress v1.4.7 (for load test only): `/opt/homebrew/opt/seamstress@1/bin/seamstress`

## Run All Tests

```bash
busted specs/ --no-auto-insulate
```

Expected: 442+ successes, 0 failures, < 5 seconds.

## Run Tests for a Specific Module

```bash
busted specs/track_spec.lua --no-auto-insulate
busted specs/sequencer_spec.lua --no-auto-insulate
busted specs/voice_spec.lua --no-auto-insulate
busted specs/pattern_spec.lua --no-auto-insulate
busted specs/direction_spec.lua --no-auto-insulate
busted specs/scale_spec.lua --no-auto-insulate
busted specs/integration_spec.lua --no-auto-insulate
```

## Run Seamstress Load Test

```bash
# Requires seamstress runtime — not included in standard busted run
seamstress -s re_kriate &
SEAMSTRESS_PID=$!
sleep 30
kill $SEAMSTRESS_PID
# Check exit code and stderr for errors
```

## TDD Workflow

1. Write a failing test for the edge case
2. Run `busted specs/<module>_spec.lua` — verify it fails
3. Implement the minimal fix in `lib/<module>.lua`
4. Run `busted specs/<module>_spec.lua` — verify it passes
5. Run `busted specs/` — verify zero regressions
6. Commit: failing test + fix in same commit
