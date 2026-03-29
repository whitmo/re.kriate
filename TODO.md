# Verification Checklist (Pattern Persistence & Seamstress UI)

## Seamstress UI (needs GUI)
- [ ] Launch `/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua`
- [ ] Grid fills window (16x8 simulated grid centered, not left-aligned)
- [ ] Pattern slot row centered; status text readable near bottom
- [ ] Ctrl+S saves current bank (status “saved bank”)
- [ ] Ctrl+L loads current bank (status “loaded bank”; track state restored)
- [ ] Ctrl+Shift+D deletes current bank (status “deleted bank”; list now empty)
- [ ] Params → pattern persistence group: list/delete/save/load actions work; “banks: ...” message appears
- [ ] Right-click nav buttons (y=8): x=12 toggles loop hold; x=14 toggles pattern hold (latches on/off)

## Persistence Behavior
- [ ] Saving snapshots current tracks (slot1) so load restores live state
- [ ] List shows saved banks; delete removes file
- [ ] Checksum guard: corrupt file is rejected (manual if desired)

## Tests (headless)
- [ ] `./scripts/busted.sh --no-auto-insulate specs` (passes; seamstress_load_spec remains pending by design unless SEAMSTRESS_LOAD_TEST=1)


## Alt-track Grid (manual)
- [ ] Nav x=15 enters alt_track page; rows 1-4 map to tracks
- [ ] Cols 1-4 set direction (forward/reverse/pendulum/random) per row
- [ ] Cols 5-11 set division 1-7 per row
- [ ] Cols 12-15 set swing 0/25/50/100 per row; LEDs show coarse bar
- [ ] Col 16 toggles mute for that track
