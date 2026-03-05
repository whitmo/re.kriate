# Implementation Plan

## Checklist

- [ ] Step 1: Create ralph.yml with core config and all 5 hats
- [ ] Step 2: Create PROMPT.md to seed the loop

## Step 1: Create ralph.yml

**Objective:** Write the ralph.yml configuration with cli, event_loop, and all five hats with full instructions.

**Implementation guidance:**
- cli backend: claude
- event_loop: PROMPT.md, work.start, LOOP_COMPLETE, max_iterations 100
- Each hat needs: name, description, triggers, publishes, instructions
- Instructions should be detailed enough that each hat knows its role, sources, conventions, and boundaries

**Test:** `ralph hats validate` passes, `ralph hats list` shows all 5 hats.

## Step 2: Create PROMPT.md

**Objective:** Write the prompt file that seeds the first researcher activation.

**Implementation guidance:**
- Point to CLAUDE.md for project conventions
- Reference the README for kria source material
- State the goal: build re.kriate, a clean kria port for norns/seamstress
- Mention key requirements: nb support, composability, simplicity, seamstress as dev target

**Test:** `ralph preflight` passes.
