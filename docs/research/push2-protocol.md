# Ableton Push 2 MIDI & USB Display Protocol — Research Notes

**Bead:** re-0l8
**Date:** 2026-04-12
**Author:** polecat jasper
**Primary source:** [Ableton/push-interface](https://github.com/Ableton/push-interface) — *AbletonPush2MIDIDisplayInterface.asc* (revision 1.1, firmware 1.0.60, 2017-01-24)
**Scope:** What re.kriate needs to build a full `grid_provider` for Push 2, including the RGB pad grid, encoders, touch strip, buttons, and the 960×160 LCD.

---

## 1. USB Architecture

Push 2 is a composite USB 2.0 device exposing:
- **Two MIDI ports** — *Live port* (port 1) and *User port* (port 2)
- **One generic USB bulk interface** for the 960×160 RGB LCD (libusb, endpoint `0x01` OUT)

| Identifier | Value |
|------------|-------|
| USB Vendor ID | `0x2982` (Ableton) |
| USB Product ID | `0x1967` (Push 2) |
| Bulk EP OUT (display) | `0x01` |
| MIDI manufacturer sysex ID | `0x00 0x21 0x1D` (Ableton) |
| Push 2 sysex header | `F0 00 21 1D 01 01 …  F7` |

### MIDI port naming (varies by OS)

| OS | Live port | User port |
|----|-----------|-----------|
| macOS | `Ableton Push 2 Live Port` | `Ableton Push 2 User Port` |
| Windows 7 | `Ableton Push 2 nn` | `MIDIIN2/MIDIOUT2 (Ableton Push 2) nn` |
| Linux | `Ableton Push 2 nn:0` | `Ableton Push 2 nn:1` |

### MIDI modes (sysex `0x0A`)

| Mode | Value | Behavior |
|------|-------|----------|
| Live | 0 | Port 1 only for non-sysex |
| User | 1 | Port 2 only for non-sysex |
| Dual | 2 | Both ports for non-sysex (debugging) |

- Sysex is always accepted from both ports; replies return on the port of origin.
- The "User" button (CC 59) always toggles on both ports.
- **For standalone apps (e.g. re.kriate)**: set MIDI mode to User (`F0 00 21 1D 01 01 0A 01 F7`), connect to port 2.
- In Live, the User port is released when all Track/Sync/Remote switches for port 2 are turned *off* in MIDI prefs.

---

## 2. Pad Grid (8×8, MIDI notes 36–99)

### Note numbering

The 64 pads form an 8×8 matrix. MIDI note **36 = bottom-left** (scene 8, track 1), **99 = top-right** (scene 1, track 8). Notes increase left-to-right across each row; rows stack bottom-to-top.

```
row(y=1, top)    92 93 94 95 96 97 98 99
row(y=2)         84 85 86 87 88 89 90 91
row(y=3)         76 77 78 79 80 81 82 83
row(y=4)         68 69 70 71 72 73 74 75
row(y=5)         60 61 62 63 64 65 66 67
row(y=6)         52 53 54 55 56 57 58 59
row(y=7)         44 45 46 47 48 49 50 51
row(y=8, bottom) 36 37 38 39 40 41 42 43
                 col=1..8 (left→right)
```

### Formulas (1-indexed, y=1 top)

```lua
note_for(x, y) = 36 + (8 - y) * 8 + (x - 1)
x_for(note)    = ((note - 36) mod 8) + 1
y_for(note)    = 8 - floor((note - 36) / 8)
```

### Pad messages

| Event | Status | Data | Notes |
|-------|--------|------|-------|
| Pad pressed | `0x90` | note, velocity (1–127) | velocity shaped by curve + calibration |
| Pad released | `0x80` | note, `0x00` | |
| Global pad aftertouch (channel pressure) | `0xD0` | value (0–127) | highest-pressure pad wins |
| Per-pad aftertouch (poly key pressure) | `0xA0` | note, value (1–127) | only when aftertouch mode = 1 |

Aftertouch mode is toggled via sysex `0x1E` (set) / `0x1F` (get); 0 = channel pressure (default), 1 = poly key.

### Velocity curve (sysex `0x20` set, `0x21` get)

The firmware interpolates weights 0–4064 g (index 0–127, step 32 g) into velocities 1–127. The curve is writable in blocks of 16 entries starting at indices 0, 16, 32, 48, 64, 80, 96, 112.

### Pad settings (sysex `0x28` select, `0x29` get)

Three sensitivity profiles available per pad (or globally): regular (0), reduced (1), low (2). Useful to desensitize loop selectors adjacent to trigger pads.

### Individual pad calibration

Factory-calibrated 400 g reference weights per pad are readable via sysex `0x1D` and overridable (non-persistent) via `0x22`. Pad values are in 0–4095 range; reference is 1690. Mostly not relevant for grid use.

---

## 3. LED Control — RGB, White, Touch Strip

### Base addressing

LEDs accept the same note/CC message as would be sent *from* a control. Velocity selects a **color palette index** (0–127), not a raw color.

```
RGB LED (pads + RGB buttons):   Note On  0x9c note_num color_idx   (c = animation channel)
White LED (white buttons):      CC       0xBc cc_num  color_idx
Turn off:                       same message with value = 0
```

### Color palette (sysex)

Push 2 stores a 128-entry palette covering RGB (r, g, b) *and* a white channel per entry. Changes are queued until a "Reapply Color Palette" message is sent.

| Sysex | ID | Args |
|-------|----|----- |
| Set LED Color Palette Entry | `0x03` | index, r(lsb), r(msb), g(lsb), g(msb), b(lsb), b(msb), w(lsb), w(msb) |
| Get LED Color Palette Entry | `0x04` | index → reply with the same structure |
| Reapply Color Palette | `0x05` | _none_ |

- Each color byte split 8 bits → (lsb 7 bits, msb 1 bit).
- Defaults (subset):
  | Index | RGB | Notes |
  |-------|-----|-------|
  | 0 | 0,0,0 | black |
  | 122 | 204,204,204 | white |
  | 123 | 64,64,64 | light gray |
  | 124 | 20,20,20 | dark gray |
  | 125 | 0,0,255 | blue |
  | 126 | 0,255,0 | green |
  | 127 | 255,0,0 | red |
  - White palette: 0→0, 16→32, 48→84, 127→128.
  - Touch-strip palette: 8 entries (0→off, 7→full white); **not modifiable**.

### White balance (sysex `0x14` set, `0x15` get, `0x23` flash)

11 color groups (red/green/blue × {RGB buttons, RGB pads, display buttons} + white buttons + touch strip). Factor 0–1024. Used to even out translucent material differences.

> ⚠️ When USB-powered, global brightness is capped at 8 and display at ~7% to stay under the 500 mA USB limit.

### Global LED brightness (sysex `0x06` / `0x07`)

Range 0–127 (auto-capped to 8 on USB power).

### PWM correction (sysex `0x0B`)

Tunes PWM base frequency (default 100 Hz) via a 21-bit correction factor:
`f0 = 5_000_000 / (42752 + n)` — range 60–116 Hz. Set to 60 Hz (`n=40581`) for camera-friendly operation.

### LED animation (MIDI channel 1–15)

Per-LED animations are driven by the MIDI channel nibble, without continuous host traffic:

| Channel | Behavior | Duration |
|---------|----------|----------|
| 0 | No animation (also stops transition) | — |
| 1–5 | **One-shot** | 24th / 16th / 8th / quarter / half |
| 6–10 | **Pulsing** | same durations |
| 11–15 | **Blinking** | same durations |

- Start color: channel 0 message.
- Target color + transition: channel 1–15 message.
- Timing: MIDI clock (`0xF8`) advances phase by 1/24 beat; `0xFA` / `0xFB` reset the global animation phase (used for blink/pulse sync).
- In User mode, clock/start/stop/continue must arrive on **port 2**.

---

## 4. Buttons (Control Change)

Buttons use `0xB0 nn 7F` for press, `0xB0 nn 00` for release. LED color is set by `0xB0 nn idx` (same CC number). White-button LEDs use white palette; RGB-button LEDs use RGB palette.

### Full CC button map (from Appendix A, MIDI implementation chart)

| CC | Button | | CC | Button |
|----|--------|-|----|--------|
| 3 | tap tempo | | 60 | mute |
| 9 | metronome | | 61 | solo |
| 14 | tempo encoder (turn) | | 62 | page left |
| 15 | swing encoder (turn) | | 63 | page right |
| 20–27 | track 1–8 button **below** display | | 85 | play |
| 28 | master | | 86 | record |
| 29 | stop clip | | 87 | new |
| 30 | setup | | 88 | duplicate |
| 31 | layout | | 89 | automate |
| 35 | convert | | 90 | fixed length |
| 36–43 | scene 8…1 buttons (bottom → top) | | 102–109 | track 1–8 button **above** display |
| 44 | arrow left | | 110 | device |
| 45 | arrow right | | 111 | browse |
| 46 | arrow up | | 112 | mix |
| 47 | arrow down | | 113 | clip |
| 48 | select | | 116 | quantize |
| 49 | shift | | 117 | double loop |
| 50 | note | | 118 | delete |
| 51 | session | | 119 | undo |
| 52 | add device | | 64 | foot pedal 1 (sustain, configurable) |
| 53 | add track | | 69 | foot pedal 2 (hold 2, configurable) |
| 54 | octave down | | 71–78 | track 1–8 encoders (turn) |
| 55 | octave up | | 79 | master encoder (turn) |
| 56 | repeat | | |
| 57 | accent | | |
| 58 | scale | | |
| 59 | user | | |

Scene buttons: note they number **8 at the bottom (CC 36) up to 1 at the top (CC 43)**.

---

## 5. Encoders

Push 2 has 11 rotary encoders (8 track + master + tempo + swing). Detented on tempo only.

### Turn (relative CC)

```
Turn right: 0xB0 cc 0xxxxxx   (x = 1..63,  value = +delta, 7-bit 2's complement)
Turn left:  0xB0 cc 1yyyyyy   (y = 64..127, value = −delta, 7-bit 2's complement)
```

- ~210 steps per 360° (18 for detented tempo encoder).
- Encoder CCs: 14 (tempo), 15 (swing), 71–78 (track 1–8), 79 (master).

### Touch (note on/off on same position as turn)

| Encoder | Touch note |
|---------|------------|
| Tempo | 10 |
| Swing | 9 |
| Track 1–8 | 0–7 |
| Master | 79* |

*(Master encoder touch note confirmed from examples: `0x90 0x47 0x7F` = "leftmost track encoder touched" → note 71. Check `Push2-map.json` for exact master touch note.)*

Encoder touch: `0x90 note 0x7F` (touched), `0x90 note 0x00` (released).

---

## 6. Touch Strip (note 12 + pitch bend or mod wheel)

### Touch event

```
Touched:  0x90 0x0C 0x7F
Released: 0x90 0x0C 0x00
```

### Position — pitch bend (default) or mod wheel (configurable)

- Pitch bend: `0xE0 q 0ppppppp` — 14-bit value, **LSB first**. Push 2 uses only the high 8 bits (low 6 always 0). Range 0 (bottom) → 16320 (top), neutral 8192.
- Mod wheel: `0xB0 0x01 vvvvvvv` — 7-bit, 0 (bottom) to 127 (top), center 64.

### Configuration flags (sysex `0x17` set, `0x18` get, 7-bit mask)

```
bit: 6   5       4      3    2         1            0
     |   |       |      |    |         |            |
     |   |       |      |    |         |            +-- LEDs controlled by:  0=Push 2,  1=Host
     |   |       |      |    |         +-- Host sends:        0=Values,   1=Sysex
     |   |       |      |    +-- Values as:          0=Pitch bend, 1=Mod wheel
     |   |       |      +-- LEDs show:               0=Bar,        1=Point
     |   |       +-- Bar starts at:                  0=Bottom,     1=Center
     |   +-- Do autoreturn:                          0=No,         1=Yes
     +-- Autoreturn to:                              0=Bottom,     1=Center
```

Default: `0x68` (1101000) — Push 2 drives LEDs as a single point, autoreturn to center, sends pitch bend.

### Sysex LED drive (`0x19`, only when "Host sends sysex" is enabled)

31 LEDs (0 = bottom, 30 = top). 16-byte payload packs two 3-bit color indices per byte (LSB first):

| Byte | Contains |
|------|----------|
| b0 | LED0 (bits 2-0) + LED1 (bits 5-3) |
| b1 | LED2 + LED3 |
| … | … |
| b14 | LED28 + LED29 |
| b15 | LED30 only (upper bits 0) |

Colors are palette indices 0–7 (full white = 7). Touch-strip LEDs are **not animated**.

---

## 7. Pedals (jack configuration)

Default: jack 1 = sustain (CC 64), jack 2 = hold 2 (CC 69). Full configuration via sysex `0x30` / `0x31` / `0x32` (firmware ≥ 1.0.58; older `0x11` / `0x12` are deprecated). Four contacts (ring/tip × 2 jacks), per-contact CC number, curve (32 sample points), mode (Live/User/Dual), destination port. Not relevant for grid_provider.

---

## 8. Device Inquiry (universal sysex, not the Ableton-prefixed form)

```
Request: F0 7E 01 06 01 F7
Reply:   F0 7E 01 06 02 00 21 1D 67 32 02 00 maj min build_lsb build_msb s0 s1 s2 s3 s4 board F7
```

- Family code `0x1967` LSB-first → `67 32` matches USB Product ID.
- Useful for sanity check when first connecting.

---

## 9. Statistics (sysex `0x1A`)

Returns USB-vs-external power status, run ID, and uptime seconds (32-bit, 7-bit packed). A run ID of zero after a prior non-zero set indicates a reboot happened in between. Not needed for grid use but handy for diagnostics.

---

## 10. Display Interface (960×160 RGB LCD, 60 fps)

### USB layer

- Open the device via libusb (vendor `0x2982` / product `0x1967`); claim interface 0.
- All display data goes out bulk endpoint `0x01`.
- Frames run at **60 fps**, double-buffered. If no frame arrives in 2 s the display blanks.

### Frame structure

**1. Frame header** — exactly 16 bytes, fixed:
```
FF CC AA 88  00 00 00 00  00 00 00 00  00 00 00 00
```

**2. Pixel data** — 640 × 512-byte USB packets per frame (total 320 KB per frame). Driven by 60 fps → ~19.2 MB/s.

- Host can batch into larger transfers (e.g. 16 KB) for efficiency.
- Lines are sent top-to-bottom, left-to-right within each line.
- Each line: **2048 bytes** = 1920 bytes pixel data + 128 filler bytes. This alignment keeps line boundaries out of the middle of 512-byte USB packets.

### Pixel format — 16-bit `bbbbbgggggg rrrrr` (little-endian)

| Bit | 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|-----|----|----|----|----|----|----|---|---|---|---|---|---|---|---|---|---|
| | b4 | b3 | b2 | b1 | b0 | g5 | g4 | g3 | g2 | g1 | g0 | r4 | r3 | r2 | r1 | r0 |

Note: **6 bits for green**, 5 each for red/blue (classic RGB565 with green middle).

### XOR shaping (mandatory before sending)

Each line buffer must be XORed with the repeating 32-bit pattern `0xFFE7F3E7` (little-endian → first byte XOR `0xE7`, then `0xF3`, `0xE7`, `0xFF`, repeat). This is a signal-shaping pattern to reduce radiated noise on the LCD ribbon; the display hardware undoes it internally.

### Display backlight (sysex `0x08` / `0x09`)

Brightness 0–255 (14-bit in two 7-bit halves; only 8 bits used). Auto-capped to 100 (~7 %) under USB power.

### libusb allocation example (from the official manual)

```c
#define PUSH2_BULK_EP_OUT 0x01
#define TRANSFER_TIMEOUT  1000  // ms

unsigned char frame_header[16] = {
    0xff, 0xcc, 0xaa, 0x88,
    0,0,0,0, 0,0,0,0, 0,0,0,0
};

libusb_fill_bulk_transfer(frame_header_transfer, dev, PUSH2_BULK_EP_OUT,
                          frame_header, 16, cb_header_done, NULL,
                          TRANSFER_TIMEOUT);

libusb_fill_bulk_transfer(pixel_data_transfer, dev, PUSH2_BULK_EP_OUT,
                          buffer, BUFFER_SIZE, cb_pixels_done, NULL,
                          TRANSFER_TIMEOUT);
```

### Takeaway for re.kriate

- The display is **not MIDI-addressable** — it requires libusb, which neither norns nor seamstress (via standard Lua MIDI) ship.
- Grid use alone only needs the MIDI port; the LCD is a separate, optional enrichment. For a first pass, skip it.
- If we want to drive the display from norns, the path is: custom C extension → libusb → the script. Non-trivial; defer.
- If we want to drive the display from seamstress/desktop, a Lua `libusb` binding (e.g. via LuaJIT FFI or a compiled helper process) is required.

---

## 11. Summary: What re.kriate Needs for a Grid Provider

The existing `lib/grid_push2.lua` uses MIDI only and emulates a 16×8 monome grid by paging the 8×8 pad area. Findings that confirm or refine that choice:

| Concern | Verdict |
|---------|---------|
| Pad note range (36–99) | ✅ Correct; `grid_to_note(x, y) = 36 + (8 - y) * 8 + (x - 1)` matches the spec. |
| Note-on value = color palette index | ✅ Confirmed. Velocity 0–127 indexes the 128-entry palette; 0 = black. |
| Channel 0 for static LEDs | ✅ Any non-zero channel triggers animation. Use ch 0 for steady brightness. |
| Page switching via CC 62/63 | ✅ Spec-confirmed (page left/right buttons). |
| Sysex init (mode + palette) | ✅ Command IDs `0x0A` (mode), `0x03` (palette entry), `0x05` (reapply) are canonical. |
| Amber monome aesthetic | ✅ Requires rewriting 16 palette slots then `0x05`. Current implementation does this correctly. |
| USB power cap | ⚠️ Global brightness will be silently clamped to 8 under USB power. For a monome-style 0–15 brightness range, consider pre-scaling values in the palette rather than relying on hardware brightness. |
| Port selection | ⚠️ Grid provider should send `Set MIDI Mode = User` at init and communicate on port 2. Currently the provider assumes the first connected MIDI device is Push 2 — revisit device discovery. |
| Note-off vs velocity 0 | ✅ Current code handles both `0x90 … 0x00` and `0x80 … 00`. Matches spec. |
| Encoders as input | 🛠️ Not yet used by grid_provider. Could map track encoders (CC 71–78) to parameter adjustment when the grid_provider is selected; out of scope for pure grid emulation. |
| Touch strip | 🛠️ Spec allows using it as a mod wheel or sending pitch bend — irrelevant for grid protocol but useful as a bonus input later. |
| Display | 🛠️ Separate USB bulk interface; beyond the current MIDI-only provider scope. |

### Recommended next steps (for future beads, not this one)

1. **Explicit device discovery**: match on port name containing "Push 2 User Port" (macOS) / "Ableton Push 2" on the matching port index, instead of device index `1`.
2. **Send `Set MIDI Mode = User` on init** (already done in `grid_push2.lua:init_hardware` via `sysex_set_mode(0x01)`).
3. **Pre-scale the amber palette** for the USB-power brightness cap: multiply RGB values by `(brightness + 1)/128` at palette-set time to get full dynamic range without relying on the hardware cap. The default amber palette in `grid_push2.lua:107` already has sensible 16-step progression.
4. **Page indicators**: light CC 62 / CC 63 button LEDs to show the current page. (CC 62/63 are RGB buttons; send `0xB0 0x3E idx` and `0xB0 0x3F idx` to color them.)
5. **Scene buttons as row mute**: CC 36–43 map to rows 8–1 left-side; could reuse as track mutes.
6. **Track buttons above/below display**: CC 20–27 (below) and 102–109 (above) — could become parameter page selectors.
7. **Clock sync**: if we want the Push 2's own LED animations to sync with re.kriate tempo, forward the internal clock messages (`0xF8`) and `0xFA` / `0xFC` to port 2 when MIDI clock output is enabled.
8. **Display driver (separate work-stream)**: a seamstress-only feature via a compiled C helper (`push2-display`) communicating with the Lua script by pipes or OSC.

---

## 12. Reference Implementations

| Library | Language | URL | Notes |
|---------|----------|-----|-------|
| push2-python | Python | github.com/ffont/push2-python | Comprehensive; covers MIDI + display via `usb` package. Canonical reference for OSS. |
| pysha | Python | github.com/ffont/pysha | Standalone Push 2 MIDI controller built on push2-python. |
| AhPushIt | Python | github.com/jasonbirchler/AhPushIt | Sequencer-oriented. |
| push-2-led | Python | github.com/joaodotwork/push-2-led | Syphon → LCD bridge (macOS). Useful display-path reference. |
| Ableton/push-interface | Manual | github.com/Ableton/push-interface | **Canonical protocol doc**. |

---

## 13. Useful Quick-Reference Sysex Snippets

```
# Switch to User mode
F0 00 21 1D 01 01 0A 01 F7

# Reapply color palette after bulk edits
F0 00 21 1D 01 01 05 F7

# Set palette index 1 to RGB 17/13/0 (amber step 1), white=0
F0 00 21 1D 01 01 03 01 11 00 0D 00 00 00 00 00 F7

# Set global LED brightness to 64
F0 00 21 1D 01 01 06 40 F7

# Set display brightness to 255 (b_lsb=0x7F, b_msb=0x01)
F0 00 21 1D 01 01 08 7F 01 F7

# Set touch strip to host-sysex-driven LEDs, bar-from-bottom
F0 00 21 1D 01 01 17 03 F7
```

---

## Appendix: Protocol Version

- Manual revision 1.1, 24 Jan 2017. Matches firmware ≥ 1.0.60.
- Ableton explicitly reserves undocumented commands — avoid experimentation with IDs outside the documented list (risk of bricking the device, losing factory calibration, or triggering firmware-flash paths).
