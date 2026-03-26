# Quickstart: 005-Norns-Entrypoint

## Prerequisites

- monome norns (or norns shield)
- Optional: monome grid (128-key)
- nb library (built into norns)

## Install on Norns

```bash
# SSH into norns
ssh we@norns.local  # password: sleep

# Clone to dust/code
cd ~/dust/code
git clone <repo-url> re_kriate
```

Or via Maiden (norns web IDE at `http://norns.local/maiden`):
- Project Manager → Install from URL

## Run

1. Navigate to norns menu: SELECT → re.kriate
2. Script loads with 4 nb voices, monome grid connected
3. Controls:
   - **K2**: Play/Stop
   - **K3**: Reset playheads
   - **E1**: Select track (1-4)
   - **E2**: Select page
   - **Grid**: Full kria grid UI

## Configure Voices

In norns PARAMETERS menu:
- **voice 1-4**: Select nb player for each track
- **root note**: Base note for scale
- **scale**: Scale type
- **track N division**: Clock division per track
- **track N direction**: Step direction mode

## Run Tests

```bash
# On development machine (not norns)
cd re_kriate
busted specs/
```

Note: Tests use mocked norns APIs. The test harness at `specs/test_helpers.lua` provides stubs for `params`, `metro`, `grid`, `screen`, `clock`, `util`, and `nb`.

## Develop

```bash
# Watch tests
busted specs/ --watch

# Run specific test file
busted specs/norns_entrypoint_spec.lua

# Check syntax
luac -p re_kriate.lua lib/norns/nb_voice.lua
```

## Logging

Session logs are written to `~/.re_kriate.log` on the norns device. Check this file for crash tracebacks and diagnostics:

```bash
ssh we@norns.local
tail -f ~/.re_kriate.log
```
