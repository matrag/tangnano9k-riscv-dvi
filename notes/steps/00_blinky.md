# Step 0 - Blinky

[Notes index](../README.md) · Next: [Step 1 - PLL](01_pll.md)

**Folder:** [`00_blinky`](../../00_blinky) · **Status:** works on the board

## Goal

Prove the whole tool chain works - write Verilog, build, flash, see the
result - before anything harder depends on it.

## What it does

A 6-bit counter shown on the 6 LEDs, counting up about 4 times a second.
Holding **S1** resets it to 0.

## What's new

- The **27 MHz** crystal clock is the only clock: a counter divides it by
  6,750,000 to get 4 steps per second.
- The LEDs are **active low**: driving a pin to 0 turns the LED on, so the
  design outputs `led = ~count`.
- The buttons are active low too (pressed = 0) and need the pull-up set in
  the constraints file.
- The **`.cst` file** maps each port name to a package pin and sets its
  voltage standard (`LVCMOS33` for the clock, `LVCMOS18` for the 1.8 V LED/button bank).

## Files

| File | Contents |
|---|---|
| [`top.v`](../../00_blinky/top.v) | the counter |
| [`tangnano9k.cst`](../../00_blinky/tangnano9k.cst) | pins: clock 52, S1 4, LEDs 10/11/13/14/15/16 |
| [`blinky.lushay.json`](../../00_blinky/blinky.lushay.json) | Lushay Code project file |

## Problems we hit

- Lushay looked for OSS CAD Suite in `C:\oss-cad-suite`: a **workspace**
  setting was overriding the user setting. See [Toolchain](../toolchain.md).
- The project file used the wrong key for the file list (`includedFilePaths`
  instead of `includedFiles`) and the build said "No files to synthesize".
  See [Gotchas](../gotchas.md#lushay-the-project-file-key-is-includedfiles).
- S1 and S2 were swapped at first: **S1 is pin 4, S2 is pin 3**.
