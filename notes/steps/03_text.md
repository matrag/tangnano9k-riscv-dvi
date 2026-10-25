# Step 3 - Text mode

[Notes index](../README.md) · Previous: [Step 2](02_hdmi.md) · Next: [Step 4 - CPU in simulation](04_cpu_sim.md)

**Folder:** [`03_text`](../../03_text) · **Status:** built and simulated; the same hardware works on the board inside [step 6](06_cpu_text.md)

## Goal

An 80 x 30 color text screen from block RAM: the display the CPU will write to later.

## What it does

Shows a fixed start-up screen from [`screen.hex`](../../03_text/screen.hex): a
title bar, the full 256-character set in a double-line box, the 16 palette
colors, sample text. To show the character RAM can change while it is being
displayed, a small hardware writer puts an 8-digit hex **frame counter** on
the screen every frame through the RAM's write port.

S1 resets the counter, but the rest of the text stays: a reset doesn't reload
block RAM, only reprogramming the FPGA does.

## What's new

See [Video - Text mode](../video.md#text-mode-80-x-30-characters).

- [`lib/bram_sdp.v`](../../lib/bram_sdp.v): a block RAM written in the style
  yosys recognizes ("inference"), optionally preloaded from a hex file.
- [`lib/text_mode.v`](../../lib/text_mode.v): character RAM + font ROM + palette
  in a 3-stage pipeline.
- [`tools/bdf2hex.py`](../../tools/bdf2hex.py): converts the Spleen 8x16 font to
  `font.hex`, in the IBM PC (code page 437) character order.
- [`tools/gen_screen.py`](../../tools/gen_screen.py): generates the start-up
  screen `screen.hex`. Edit it, run it, rebuild:
  `python -I tools/gen_screen.py 03_text/screen.hex` (from the `fpga` folder).

## Files

| File | Contents |
|---|---|
| [`top.v`](../../03_text/top.v) | timing -> text mode -> HDMI, plus the frame-counter writer |
| [`font.hex`](../../03_text/font.hex), [`screen.hex`](../../03_text/screen.hex) | generated memory contents |
| [`text_mode_tb.v`](../../03_text/text_mode_tb.v) | testbench, see below |
| [`text.lushay.json`](../../03_text/text.lushay.json), [`tangnano9k.cst`](../../03_text/tangnano9k.cst) | project, pins |

## The testbench

[`text_mode_tb.v`](../../03_text/text_mode_tb.v) keeps its own copy of the font
and screen and computes the expected color of **every visible pixel** directly
from (x, y), then compares with the hardware output 3 clocks later. It also
writes two cells through the write port and saves one frame as an image
(`text_mode_tb.ppm`).

To prove the check really works, we broke the pipeline on purpose (pixel
column taken one stage too early): the testbench reported 37,618 wrong pixels.

## Results

- Testbench: **pass**, 614,400 pixels over 2 frames.
- 6 of 26 block RAMs: 4 for the character RAM (yosys builds it as 4 blocks of
  4096 x 4 bits), 2 for the font. All six carry their initial data.
- Pixel-clock logic up to **105 MHz** (needs 25.2).

## Problems we hit

- `cell` is a reserved word in Verilog-2001: renamed to `cell_data`.
  See [Gotchas](../gotchas.md#verilog-cell-is-a-reserved-word).
- Python's `cp437` codec has no symbols for codes 0x01-0x1F (it treats them
  as control characters): the scripts carry their own table for those.
