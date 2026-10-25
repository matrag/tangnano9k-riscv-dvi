# Project notes: a RISC-V CPU with DVI video output on the Tang Nano 9K

These notes explain how the project is built, why it is built that way, and
what was learned along the way. They were written while the project grew,
step by step. To set up the tools, see [SETUP.md](../SETUP.md); for an
overview, the [README](../README.md).

**Goal:** a small RISC-V CPU, written from scratch in Verilog, running on a
Sipeed Tang Nano 9K FPGA board and showing an 80 x 30 color text console on a
monitor (DVI video through the board's HDMI connector).

**Approach:** many small steps. Each step is a folder you can build, flash and
check on its own, and each adds one new idea on top of the previous ones.

## Where to start

| If you want to... | Read |
|---|---|
| See the whole system at a glance | [Architecture](architecture.md) |
| Understand the CPU | [The CPU core](cpu.md) |
| Understand how a picture gets onto the HDMI cable | [Video: HDMI and text mode](video.md) |
| Follow the project step by step | [The steps](#the-steps) below |
| Avoid the traps we fell into | [Gotchas and lessons learned](gotchas.md) |
| See sizes, speeds and test results | [Results and measurements](results.md) |
| Build, simulate, flash, change the software | [Tools and workflow](toolchain.md) |

## The steps

| Step | Folder | New idea | Status |
|---|---|---|---|
| 0 | [`00_blinky`](steps/00_blinky.md) | Toolchain, pins, the 27 MHz clock, LEDs | works on the board |
| 1 | [`01_pll`](steps/01_pll.md) | PLL and clock divider, reset synchronizer | works on the board |
| 2 | [`02_hdmi`](steps/02_hdmi.md) | Video timing, TMDS encoding, serializers: a test pattern | works on the board |
| 3 | [`03_text`](steps/03_text.md) | Block RAM, font ROM, pipelining: 80 x 30 text mode | works on the board |
| 4 | [`04_cpu_sim`](steps/04_cpu_sim.md) | Our own RV32I CPU, the C compiler, testbenches | simulation only |
| 5 | [`05_cpu_leds`](steps/05_cpu_leds.md) | System-on-chip, memory-mapped IO, CPU on the board | works on the board |
| 6 | [`06_cpu_text`](steps/06_cpu_text.md) | Everything together: the CPU writes to the screen | works on the board |
| 7 | [`07_uart`](steps/07_uart.md) | Serial port to the PC: PC keyboard to the screen; 21-line scrollback in the text RAM | works on the board |
| 8 | [`08_bootloader`](steps/08_bootloader.md) | Boot ROM + serial bootloader: upload programs over USB (window or command line), no FPGA rebuild | works on the board |

## Folder layout

```
(repository root)/
  00_blinky/ ... 08_bootloader/ one folder per step: top.v, pins (.cst), Lushay project, testbenches
  lib/                          shared Verilog modules used by several steps
  sw/                           shared software: C programs, startup code, linker script, Makefile
  tools/                        Python scripts that generate data files (font, screen, program images)
  notes/                        these notes
  framework_initialise.py       sets up the tools into toolchain/ (see SETUP.md)
```

The tools themselves (RISC-V GCC, OSS CAD Suite) are not in the repository:
`framework_initialise.py` downloads them into `toolchain/` (see
[SETUP.md](../SETUP.md) and [Tools and workflow](toolchain.md)).
