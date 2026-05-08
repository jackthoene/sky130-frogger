# 🐸 Frogge

A hardware Frogger clone in synthesizable Verilog — built for the [Tiny Tapeout TTSKY26a Demoscene Competition](https://tinytapeout.com/competitions/demoscene-ttsky26a-announce/) and playable right now in [VGA Playground](https://vga-playground.com/?preset=gamepad).

No multipliers. No dividers. No RAM. No framebuffer. Pure combinational frog.

## How to Play

Guide your frog from the bottom grass to the goal zone at the top. Dodge cars, ride logs, fill all 5 lily-pad slots to advance.

**Screen layout (bottom → top):**

| Rows | Zone | What's there |
|------|------|--------------|
| 12–14 | Start | Safe grass — you spawn here |
| 8–11 | Road | 4 lanes of colored cars at different speeds |
| 7 | Median | Safe grass rest stop |
| 3–6 | River | 4 lanes of logs on water — ride them or drown |
| 2 | Goal | 5 lily-pad slots to fill |
| 0–1 | Header | Lives (green squares) and score bar |

**Rules:**
- Hit a car → lose a life
- Land in the water without a log → lose a life
- Get carried off-screen by a log → lose a life
- Land on an open lily pad → score a point, return to start
- Fill all 5 pads → they reset, keep going
- 3 lives total, then game over

## Controls

### Gamepad Pmod (primary)

Uses the [Gamepad Pmod](https://github.com/psychogenic/gamepad-pmod) on `ui_in[6:4]` — SNES/Super Famicom compatible controllers.

| Button | Action |
|--------|--------|
| D-Pad Up | Hop up one row |
| D-Pad Down | Hop down one row |
| D-Pad Left | Hop left 24px |
| D-Pad Right | Hop right 24px |
| Start | Restart game |

### Fallback (ui_in buttons)

When no gamepad is detected, the `ui_in` buttons work as directional controls:

| Button | Action |
|--------|--------|
| ui_in[0] | Up |
| ui_in[1] | Down |
| ui_in[2] | Left |
| ui_in[3] | Right |

### VGA Playground

Open [vga-playground.com/?preset=gamepad](https://vga-playground.com/?preset=gamepad), replace the `project.v` tab contents with the source, and click the gamepad icon above the display to enable the on-screen controller.

## Audio

Sound effects via PWM on the [TT Audio Pmod](https://github.com/MichaelBell/tt-audio-pmod) (`uio[7]`). Uses a 20-bit DDS (direct digital synthesis) accumulator for clean audible tones.

| Event | Sound | Frequency | Duration |
|-------|-------|-----------|----------|
| Hop | Short blip | A4 (~430 Hz) | ~83 ms |
| Death | Low warble | Alternates ~120/167 Hz | ~750 ms |
| Goal | Ascending jingle | C4 → E4 → G4 | ~1.3 s |

The goal jingle has articulation gaps between notes for a clean *doo — doo — dooooo* feel.

Enable the audio toggle in VGA Playground to hear it.

## Pinout

### VGA Output — Tiny VGA Pmod (`uo_out[7:0]`)

| Pin | Signal |
|-----|--------|
| uo_out[0] | R1 |
| uo_out[1] | G1 |
| uo_out[2] | B1 |
| uo_out[3] | vsync |
| uo_out[4] | R0 |
| uo_out[5] | G0 |
| uo_out[6] | B0 |
| uo_out[7] | hsync |

2-bit color per channel (6-bit / 64 colors total).

### Gamepad Pmod (`ui_in[6:4]`)

| Pin | Signal |
|-----|--------|
| ui_in[4] | LATCH |
| ui_in[5] | CLOCK |
| ui_in[6] | DATA |

### Audio Output (`uio[7]`)

| Pin | Signal |
|-----|--------|
| uio_out[7] | PWM audio |

## Technical Details

### Target

- **Process:** SkyWater Sky130 (TTSKY26a shuttle)
- **Category:** 1-tile demoscene entry
- **Clock:** ~25 MHz (VGA pixel clock)
- **Resolution:** 640×480 @ ~60 Hz

### Design Constraints

Everything is designed to fit in a single Tiny Tapeout tile:

- **No multipliers or dividers** — all math is addition, subtraction, shifts, and bitwise ops
- **No RAM or framebuffer** — all graphics are procedural, computed per-pixel in real time
- **No lookup tables** — obstacle patterns use power-of-2 period bitmasks (`& 7'h7F`) for free modulo
- **Manhattan distance** for any radial calculations
- **Procedural frog sprite** — eyes, pupils, belly, and legs drawn from coordinate comparisons, no ROM needed

### Architecture

| Block | Flip-flops (approx) | Description |
|-------|---------------------|-------------|
| Lane offsets | 80 | 8 × 10-bit scroll counters (4 road + 4 river) |
| Frog state | 17 | x position (10b) + row (4b) + lives (3b) |
| Game state | 17 | state (2b) + score (4b) + anim_timer (6b) + goal_slots (5b) |
| Audio | 30 | DDS accumulator (20b) + frames (8b) + type (2b) |
| Edge detect | 8 | Button history (4b) + vsync history (1b) + misc |
| **Total** | **~152** | Well within single-tile budget |

### Collision Detection

- **Road lanes:** frog center pixel inside a car → death
- **River lanes:** frog center pixel NOT on a log → death, with **8px tolerance** on each side of every log so near-misses count as safe
- **Off-screen:** `frog_x > 620` catches both right-edge and unsigned underflow
- **River carry:** frog drifts with the log it's standing on (sign-matched to lane scroll direction)

### Lane Configuration

Each lane uses period-128 obstacle patterns (`pix_x + offset) & 7'h7F`):

| Row | Type | Direction | Speed (px/frame) | Obstacle width | Color |
|-----|------|-----------|-------------------|----------------|-------|
| 8 | Road | → | 1 | 40 | Red |
| 9 | Road | ← | 2 | 32 | Yellow |
| 10 | Road | → | 3 | 28 | Purple |
| 11 | Road | ← | 1 | 48 | Orange |
| 3 | River | ← | 1 | 60 | Brown log |
| 4 | River | → | 2 | 50 | Brown log |
| 5 | River | ← | 2 | 64 | Brown log |
| 6 | River | → | 3 | 44 | Brown log |

### File Structure

When using VGA Playground with `?preset=gamepad`:

| Tab | Source | Description |
|-----|--------|-------------|
| `project.v` | Your code | Frogge game — replace this tab |
| `hvsync_generator.v` | Preset | 640×480 VGA timing generator |
| `gamepad_pmod.v` | Preset | SNES controller serial interface |

## License

SPDX-License-Identifier: Apache-2.0