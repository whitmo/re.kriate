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
