# Decision Log: Complete Seamstress Kria Sequencer

Decisions made during implementation planning. Each should be reviewed for correctness and musical sensibility.

## D1: Simplified Ratchet (value 1-7, not sub-trigger grid)

**Context**: Original kria has a complex ratchet page where rows 2-6 represent sub-trigger patterns within a step. Our data model uses simple 1-7 values per step on a bar-graph display.

**Decision**: Use 1-7 value (1=normal, 2-7=number of subdivisions). Each subdivision fires an evenly-spaced note within the step duration.

**Trade-off**: Loses the ability to program specific sub-trigger patterns (e.g., fire on beats 1 and 3 of 4 subdivisions). But dramatically simpler to implement and consistent with our existing value page UI.

**Question for review**: Is the simplified ratchet musically sufficient? Should we plan for upgrading to full sub-trigger patterns later? Does the simplified version cover 80% of use cases?

## D2: Alt-Note is Additive (not probabilistic alternation)

**Context**: Spec originally said "notes alternate between primary and alt-note values". Research found that original kria uses ADDITIVE combination: effective_degree = (note + alt_note - 2) % scale_length + 1.

**Decision**: Additive, matching original firmware. Alt-note has its own independent loop for polymetric pitch combinations.

**Trade-off**: None -- this matches the reference implementation. The spec was corrected.

## D3: Per-Track Direction (not per-parameter)

**Context**: Original kria sets direction per-track on the scale page (5 modes x 4 tracks). We could alternatively support per-parameter direction (each param in a track could go in a different direction).

**Decision**: Per-track only. The `track.direction` field controls all param advances for that track.

**Trade-off**: Per-param direction would create more complex polymetric patterns. But original kria doesn't support it, and the UI complexity (how would you set direction per-param without a scale page?) doesn't justify it yet.

**Question for review**: Is per-param direction worth the complexity? It would mean 8 direction settings per track (one per param). The scale page UI would need to show this somehow.

## D4: No Grid Scale Page This Phase

**Context**: Original kria has a scale page (column 15) with an interval editor and per-track direction/clocking config. We currently set scale via params menu.

**Decision**: Defer grid scale page. Scale selection works via params. Direction modes are added but configured via params, not the grid.

**Trade-off**: Loses the live scale editing gesture (which is a performance feature in original kria). But the interval editor is complex UI that doesn't map cleanly to our implementation.

**Question for review**: How important is live grid-based scale editing for the musician workflow? Is params-menu scale selection sufficient for now?

## D5: No Grid Pattern Page This Phase

**Context**: Original kria has a pattern page (column 16, currently our play/stop button) with 16 slots, cue system, and meta-sequencer.

**Decision**: Build pattern.lua API (save/load/16 slots) but no grid UI for it yet. Pattern recall via keyboard shortcuts.

**Trade-off**: Pattern storage exists but isn't easily accessible during performance without the grid page. The play/stop button occupies the pattern page's column.

**Question for review**: Should play/stop move to a different interaction (e.g., hold nav button) to free column 16 for pattern page? Or is keyboard-only pattern access acceptable?

## D6: Muted Tracks Advance Silently

**Context**: Current code returns early on muted tracks (no advancement). Original kria advances muted tracks silently so unmuting at the right moment is a performance technique.

**Decision**: Change to advance-but-suppress-output, matching original kria.

**Trade-off**: Subtle behavior change. Musicians who muted a track and expected it to "pause" will find it has moved ahead when unmuted. But this matches expectations from kria.

## D7: Glide via MIDI CC (not pitch bend)

**Context**: Glide/portamento could be implemented via MIDI CC 65+5 (standard portamento) or via pitch bend messages.

**Decision**: Use CC 65 (Portamento On/Off) + CC 5 (Portamento Time). Values 1-7 map to increasing portamento times.

**Trade-off**: CC-based portamento depends on the receiving synth supporting it. Pitch bend would work universally but is more complex (need to calculate bend amounts and timing).

**Question for review**: Is CC portamento reliable enough across common MIDI synths/DAWs? Should we offer pitch bend as an alternative?

## D8: Wave Structure for Implementation

**Context**: 66 tasks across 14 user stories need to be dispatched to parallel workers.

**Decision**: 5-wave structure. Wave 0 (CI), Wave 1 (4 foundational modules), Wave 2 (3 integration tasks), Wave 3 (3 UI tasks), Wave 4 (integration tests).

**Trade-off**: More waves = more sequential waiting. Fewer waves = more merge conflicts. 5 waves balances parallelism with file-overlap safety.

## D9: Ralph as Post-Wave Reviewer

**Context**: User asked about using ralph to manage the swarm.

**Decision**: Run ralph hat loop AFTER each wave completes, not continuously during swarm execution. Musician hat evaluates musical correctness, Tester hat verifies integration.

**Trade-off**: No real-time course correction during worker execution. But ralph's sequential nature doesn't fit async monitoring, and workers are self-contained.

**Question for review**: Would a lightweight "Coordinator" ralph hat that just checks worker messages be useful? Or is post-wave review sufficient?
