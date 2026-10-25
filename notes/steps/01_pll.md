# Step 1 - PLL clocking

[Notes index](../README.md) · Previous: [Step 0](00_blinky.md) · Next: [Step 2 - Video test pattern](02_hdmi.md)

**Folder:** [`01_pll`](../../01_pll) · **Status:** works on the board

## Goal

Make the two clocks the video output needs, and check their frequencies using only LEDs.

## What it does

Three LEDs blink at 1 Hz, each driven from a different clock:

| LED | Clock |
|---|---|
| 0 | 27 MHz crystal (reference) |
| 1 | 126 MHz PLL output |
| 2 | 25.2 MHz divided clock |
| 5 | on while the PLL is locked |

If the frequencies are right, LEDs 0-2 blink together and stay in step. A
wrong frequency shows up as one LED drifting away. S1 restarts all three in phase.

## What's new

- **rPLL** (Gowin's PLL): 27 MHz x 14 / 3 = 126 MHz. Its internal oscillator
  runs at 1008 MHz (must be 400-1200 MHz) and is divided by 8.
- **CLKDIV**: the dedicated divider block, 126 / 5 = 25.2 MHz, phase-aligned
  with its input (needed by the serializers in step 2).
- **Reset synchronizer**: the reset is applied at once but released only
  after two flip-flops in each clock domain, so it is never released right at
  a clock edge (avoids metastability). The PLL clocks are also held in reset
  until the PLL reports `lock`.

The calculation of the PLL settings is explained in the comments of
[`lib/clocks.v`](../../lib/clocks.v).

## Files

| File | Contents |
|---|---|
| [`top.v`](../../01_pll/top.v) | the three blinkers, with the `blinker` module and its reset synchronizer |
| [`clocks.v`](../../01_pll/clocks.v) | PLL + divider (the commented version lives in `lib/clocks.v`) |
| [`tangnano9k.cst`](../../01_pll/tangnano9k.cst), [`pll.lushay.json`](../../01_pll/pll.lushay.json) | pins, project |
