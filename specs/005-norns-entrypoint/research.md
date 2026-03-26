# Research: 005-Norns-Entrypoint

**Date**: 2026-03-25

## Decision 1: Screen Refresh Strategy

**Decision**: Use a metro at 15fps to trigger redraw() periodically.

**Rationale**: Norns does not automatically call redraw() during playback — only on system events. Without a metro, the screen would freeze between key/enc interactions. Seamstress uses a screen_metro at 30fps; norns OLED is lower resolution and typically 15fps is sufficient and reduces CPU load.

**Alternatives considered**:
- clock.run with clock.sleep: Works but metro is idiomatic norns and integrates with the existing grid_metro pattern in app.lua.
- Dirty flag only (redraw on state change): Would miss continuous updates like playhead position during playback.

## Decision 2: nb Voice Portamento Approach

**Decision**: Call player:set_slew(time) if the method exists on the nb player, otherwise no-op.

**Rationale**: The nb framework uses `set_slew` (not `set_portamento`) for glide/portamento. Not all nb players support it — e.g., basic sample players have no portamento concept. Checking for method existence before calling matches the nb convention of optional capabilities.

**Alternatives considered**:
- pcall wrapping: Adds overhead for every note; method check is simpler.
- Requiring portamento support: Would limit which nb players work with re.kriate.

## Decision 3: Grid Provider Configuration

**Decision**: Explicitly pass `grid_provider = "monome"` in app.init config.

**Rationale**: While "monome" is the default in grid_provider.connect(), being explicit makes the norns entrypoint self-documenting and future-proof against default changes. The seamstress entrypoint explicitly passes `grid_provider = "simulated"`.

**Alternatives considered**:
- Omit (rely on default): Works today but implicit. The spec (FR-002) explicitly requires this.

## Decision 4: Screen Metro Cleanup

**Decision**: Store screen_metro on ctx and stop it in cleanup(), following the same pattern as seamstress.lua.

**Rationale**: The grid_metro cleanup is already handled by app.cleanup(ctx). The screen_metro is entrypoint-specific (norns has its own screen rendering) and must be managed by the entrypoint, not app.lua. This mirrors seamstress.lua's ctx.screen_metro pattern.

**Alternatives considered**:
- Pass screen_metro to app.init: Over-couples app.lua to platform-specific rendering concerns.

## Decision 5: Logging Already Handled in app.lua

**Decision**: Grid key callback wrapping (FR-008) is already implemented in app.lua line 73 via `log.wrap`. The norns entrypoint only needs to add log.session_start() in init and log.close() in cleanup.

**Rationale**: app.lua wraps the grid key callback with `log.wrap("grid_key")` for all platforms. The entrypoint's responsibility is session lifecycle logging, not callback wrapping (which is shared infrastructure).

**Alternatives considered**:
- Duplicate wrapping in entrypoint: Redundant, would double-wrap the callback.

## Decision 6: No New Modules

**Decision**: All changes confined to re_kriate.lua (entrypoint) and lib/norns/nb_voice.lua (portamento). No new files needed.

**Rationale**: The existing module structure is sufficient. app.lua handles all shared logic. The norns entrypoint just needs to wire up platform-specific concerns (nb voices, monome grid, logging lifecycle, screen metro). This matches the seamstress pattern where the entrypoint is a thin wiring layer.

**Alternatives considered**:
- lib/norns/screen_ui.lua: Unnecessary — app.redraw() already handles norns screen output via the standard screen API.
