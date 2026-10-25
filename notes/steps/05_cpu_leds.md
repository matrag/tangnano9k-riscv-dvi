# Step 5 - The CPU on the board

[Notes index](../README.md) · Previous: [Step 4](04_cpu_sim.md) · Next: [Step 6 - CPU + text screen](06_cpu_text.md)

**Folder:** [`05_cpu_leds`](../../05_cpu_leds) · **Status:** works on the board

## Goal

Run the CPU on the real FPGA, with a C program controlling the LEDs and reading a button.

## What it does

Program [`sw/05_leds.c`](../../sw/05_leds.c):

1. All 6 LEDs on for 0.3 s (start-up flash).
2. "Knight Rider": one light bouncing left and right, one step every 80 ms.
3. **S2** switches between that and a binary counter.
4. **S1** resets the CPU, which restarts the program.
5. All LEDs on permanently = the CPU **trapped** (stopped on an instruction it can't run).

## What's new

- The CPU runs directly on the **27 MHz** board clock (no PLL yet).
- [`lib/soc.v`](../../lib/soc.v) becomes the one SoC for board and simulation,
  with two new registers: `TIMER` (counts clock cycles - delays are measured
  with it, so speed doesn't depend on how fast the code runs) and `BUTTONS`.
  See the [memory map](../architecture.md#memory-map).
- [`sw/soc.h`](../../sw/soc.h): register addresses and `delay_ms()` for C programs.
- **Memory-mapped IO**: `LEDS = 5` in C is just a store instruction to
  `0x1000_0000`; the address decoder sends it to the LED register instead of RAM.
- S2 goes through **two flip-flops** before the CPU sees it (synchronizer).
- The program reacts to S2 only on the change from released to pressed, and
  checks it every 10 ms, which also hides contact bounce.
- All software now lives in [`sw/`](../../sw), with one Makefile for every step.

## Files

| File | Contents |
|---|---|
| [`top.v`](../../05_cpu_leds/top.v) | reset, S2 synchronizer, SoC, LEDs (all on if trapped) |
| [`leds.hex`](../../05_cpu_leds/leds.hex) | the compiled program, preloaded into RAM |
| [`leds_tb.v`](../../05_cpu_leds/leds_tb.v) | simulates the whole `top.v` for ~1.1 s of board time (2-3 minutes) |
| [`tangnano9k.cst`](../../05_cpu_leds/tangnano9k.cst), [`cpu_leds.lushay.json`](../../05_cpu_leds/cpu_leds.lushay.json) | pins (S2 = pin 3), project |

## Results

Testbench output (times in ms of board time):

```
   0.01 ms  LEDs 111111
 300.02 ms  LEDs 000001  (+300.01 ms)
 380.04 ms  LEDs 000010  (+80.02 ms)
 ...        bounces back at LED 5
 860.17 ms  LEDs 000000  <- S2 pressed: counter starts at 0
 940.19 ms  LEDs 000001
PASS: LED program behaves as expected
```

The extra 0.02 ms per step is the time the loop's own instructions take on top of the delay.

Place-and-route: up to **60 MHz** (needs 27), 32% of the LUTs, 4 block RAMs.

## Problems we hit

- Yosys stopped: "Can not open file `program.hex`". It elaborated `soc` once
  with its default parameter value. Defaults are now empty strings.
  See [Gotchas](../gotchas.md#yosys-default-parameter-values-get-elaborated-too).
