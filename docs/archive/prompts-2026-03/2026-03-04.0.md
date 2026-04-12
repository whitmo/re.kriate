# re.kriate

Build a clean kria sequencer for norns and seamstress.

## What is kria?

Kria is a multi-track step sequencer originally from the monome Ansible eurorack module. Its defining feature is per-parameter loop lengths — each track's note, octave, duration, trigger, and velocity sequences can have independent lengths, creating polymetric patterns.

## Goal

A simple, working kria implementation that:
- Runs on seamstress (primary dev target) and norns
- Uses nb for voice output
- Supports monome grid for the primary UI
- Can coexist with other norns scripts (e.g. timeparty)
- Follows the conventions in CLAUDE.md (ctx pattern, no custom globals, modular)

## References

See README.md for links to:
- monome/ansible — original kria firmware (C)
- zjb-s/n.kria — existing norns kria port
- Dewb/monome-rack — VCV Rack port
- monome.org kria docs — behavioral descriptions

## Key norns/seamstress libraries

- **sequins** — pattern sequencing with variable-length loops (natural fit for kria's per-parameter lengths)
- **timelines** — event scheduling
- **nb** — note/voice output system (required)
- **musicutil** — scales, note names, intervals

## Dev environment

- seamstress 2.0.0-alpha is installed locally
- `seamstress --test` runs busted tests
- Target both seamstress and norns compatibility

## Priorities

1. Simple and correct over feature-rich
2. Working code a human can understand and fix
3. nb voice support (non-negotiable)
4. Grid UI that makes musical sense
5. Composability — don't hog globals or resources
