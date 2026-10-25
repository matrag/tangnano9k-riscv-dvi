# Step 6 - The CPU writes to the screen

[Notes index](../README.md) · Previous: [Step 5](05_cpu_leds.md) · Next: [Step 7 - UART](07_uart.md)

**Folder:** [`06_cpu_text`](../../06_cpu_text) · **Status:** works on the board

## Goal

Put everything together: the CPU prints text on the HDMI monitor.

## What it does

Program [`sw/06_text.c`](../../sw/06_text.c):

1. A welcome screen: blue title bar, system information, the 16 colors in a
   box, and a timed benchmark ("669 primes below 5000 found in 940 ms").
2. Then one line per second: `uptime 00:00:05   timer = 0x...`; the LEDs count seconds.
3. **S2** prints 40 colored lines, one every 50 ms. Once the screen is full,
   everything scrolls up - you can watch the hardware scrolling.

## What's new

- The CPU now runs on the **25.2 MHz pixel clock**, shared with the video, so
  it can write the character RAM directly with no clock-domain crossing.
- [`lib/soc.v`](../../lib/soc.v) got an **external bus port**: addresses
  `0x2xxx_xxxx` go to devices outside the module.
- [`lib/soc_text.v`](../../lib/soc_text.v) (new): the SoC + a "text device" that
  turns bus writes into character RAM writes and a scroll register + video timing + text mode.
- [`lib/text_mode.v`](../../lib/text_mode.v) got **hardware scrolling**: a
  `scroll` input, the character RAM used as a ring of 30 rows (step 7 makes
  the ring size a parameter, for scrollback). See
  [Video - Hardware scrolling](../video.md#hardware-scrolling).
- The character RAM is **write-only** for the CPU: a console never needs to read
  the screen back, and a read port would cost more block RAM.
- [`sw/console.c`](../../sw/console.c) / [`console.h`](../../sw/console.h): a small
  terminal library - cursor, colors, newline, automatic wrap and scroll,
  decimal/hex output.
- The Makefile builds `06_text.c` with `CPU_HZ=25200000`, and now drops unused
  functions (`--gc-sections`), so programs that don't use the console stay small.

## Files

| File | Contents |
|---|---|
| [`top.v`](../../06_cpu_text/top.v) | clocks, reset, S2, `soc_text`, `hdmi_out` |
| [`text.hex`](../../06_cpu_text/text.hex) | the compiled program (the font comes from `../03_text/font.hex`) |
| [`cpu_text_tb.v`](../../06_cpu_text/cpu_text_tb.v) | testbench, see below |
| [`tangnano9k.cst`](../../06_cpu_text/tangnano9k.cst), [`cpu_text.lushay.json`](../../06_cpu_text/cpu_text.lushay.json) | pins, project |

## The testbench

[`cpu_text_tb.v`](../../06_cpu_text/cpu_text_tb.v) runs the real program and:

- prints the screen contents as **text in the simulation log** (box characters
  drawn as `+ - |`), read straight out of the character RAM;
- checks the title, the benchmark result (669) and the "Running." line;
- presses S2 and waits for the burst: "line 40" must appear, the title must
  have scrolled off, and the scroll register must have changed (it ends at 2
  after 32 scrolls, i.e. it wrapped round the ring);
- saves one video frame as an image (`cpu_text_tb.ppm`).

It simulates about 3 s of board time and takes **about 12 minutes**.

## Results

- Testbench: **pass** (with the slow 50 ms burst: 724 s of simulation).
- All earlier testbenches still pass after the shared changes.
- Place-and-route: up to **57 MHz** (needs 25.2), 27% of the LUTs, 10 of 26 block RAMs.

## Problems we hit

- **A testbench that passed while seeing nothing.** The first version said
  PASS after 2 clock cycles: the screen RAM held unknown `X` values in
  simulation, and the comparison used `!=`. See
  [Gotchas](../gotchas.md#simulation--with-x-hides-failures).
- Yosys stopped again on a default file name (`font.hex`) - all such defaults are now empty.
- The burst line was 83 characters, wider than the screen, so it wrapped onto
  two rows. Shortened.
- On the board the burst was too fast to see the scrolling (40 lines in about
  0.1 s), so it now waits 50 ms per line.
