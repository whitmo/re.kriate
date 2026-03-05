# Requirements

## User-Specified Hats

1. researcher
2. musician
3. lua wizard
4. refactorer
5. tester

## Q&A

**Q1:** What workflow — event loop or standalone hats?
**A1:** Event loop. Loop until we have a new kria for norns. Full autonomous pipeline.

**Q2:** What should the researcher focus on?
**A2:** Multiple sources:
- The old kria implementations (referenced in README)
- New norns libraries: sequins, timelines
- Other sources: seamstress, norns source code, norns standard library
- Other norns scripts as examples
- Descriptions of how kria works (behavioral/UX docs)
- Use the web carefully (not recklessly)
- Goal: build a model that works, or one a human can fix easily

**Q3:** What is the musician hat's role?
**A3:** An opinionated tester / domain expert. Priorities:
- Noto bene (nb) support — use the nb voice system
- Composability with other norns scripts (e.g. timeparty)
- Cares about simplicity above all
- Evaluates from a musician's perspective, not just technical correctness

**Q4:** Is the lua wizard the main implementer?
**A4:** Yes. Deep norns expertise:
- Follows CLAUDE.md conventions (ctx pattern, no custom globals, modules)
- Knows norns APIs: clock, params, screen, grid, midi, crow, engine
- Knows sequins, timelines
- UI management for both screen (128x64) and grid (128 LEDs)
- Norns idioms and best practices

**Q5:** What testing approach?
**A5:** Be creative. Options to explore:
- Seamstress can mock a monome grid — if code runs on both seamstress and norns, local testing is possible
- Structural checks (syntax, module structure, no global leaks, ctx pattern)
- Lua CLI for loading modules in isolation
- Dual-target seamstress+norns could unlock real local testing
- Figure out what's feasible and use it

**Q6:** How should the refactorer work?
**A6:** Periodic tidy and assessment:
- Runs regularly in the loop, not just when issues flagged
- Enforces ctx pattern, module boundaries, thin global hooks
- Looks for opportunities to keep things simple and clean
- Ongoing code hygiene, not just reactive fixes

**Q7:** What's the loop flow?
**A7:** Two phases:
1. **Design phase:** researcher + musician + lua_wizard collaborate to design the implementation. Should be straightforward since kria exists in other messier forms already.
2. **Build/iterate phase:** lua_wizard implements, tester + musician validate, refactorer tidies, loop back to iterate.

**Q8:** What's the completion condition?
**A8:** Open-ended: researcher confirms feature parity with kria and musician signs off. Seamstress might be the primary target since it's available locally (norns may not be).

**Q9:** Max iterations?
**A9:** High. Let it run autonomously.
