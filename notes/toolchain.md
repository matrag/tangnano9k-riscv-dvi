# Tools and workflow

[Back to the notes index](README.md)

## Tools used

| Tool | What for | Where |
|---|---|---|
| VS Code + **Lushay Code** extension | build, flash, run testbenches | VS Code extension |
| **OSS CAD Suite** 2024-12-08 | yosys (synthesis), nextpnr-himbaechel (place and route), gowin_pack, openFPGALoader (flashing), iverilog (simulation) | `toolchain/oss-cad-suite/` |
| **xPack GNU RISC-V Embedded GCC** 15.2.0-1 | compiling C/assembly for the CPU | `toolchain/riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/` |
| GNU **make** | building the software | on the PATH |
| **Python** 3 | data-file generators and upload tools in [`tools/`](../tools) | on the PATH; packages (pyserial) in the project's `.venv/` |

`framework_initialise.py` downloads both into `toolchain/`, creates the
virtual environment `.venv/` with pyserial, and writes the paths of the tools
and of the venv's Python into `local_paths.mk` (for `make`); see
[SETUP.md](../SETUP.md). `make` uses that Python directly, so the venv never
needs activating. Typing `python` yourself for a tool that needs pyserial
(`upload.py`, `test_upload.py`, miniterm): use the venv's, `.venv/Scripts/python`
on Windows, `.venv/bin/python` on Linux. In Lushay's settings,
`lushay.OssCadSuite.path` must point at the OSS CAD Suite folder (check the
User **and** Workspace tabs).

## The build flow

```
 .v files + .cst --> yosys (synth_gowin) --> nextpnr-himbaechel --> gowin_pack --> .fs --> openFPGALoader --> board
                         netlist .json         placed .json          bitstream
```

Lushay Code runs this for you: **FPGA Toolchain** button in the status bar ->
**Build and Program**, then choose the step's `.lushay.json`. It runs every
tool in the project folder, so relative file names (hex files) are relative
to that folder.

## Lushay project files

Each step has a `*.lushay.json`. The keys we use:

| Key | Meaning |
|---|---|
| `name` | output file names |
| `includedFiles` | **every** Verilog file of the design, relative to the project file. Always list them explicitly |
| `testBenches` | testbench files (module must be named `test`) |
| `constraintsFile` | the `.cst` pin file |
| `top` | the top module |
| `board` | `tangnano9k` |

Other keys Lushay understands: `programMode` (default `flash`),
`synthGowinOptions`, `nextPnrGowinOptions`, `skipCstChecking`, `baudRate`.

## Serial console

From step 7 the board talks to the PC over USB at 115200 baud, 8N1. Lushay:
FPGA Toolchain button -> **Serial Console** (speed from the project's
`baudRate`; it finds the board's port automatically). Lushay echoes what you
type, so with a program that echoes too, characters appear twice.

Other terminals that send every key straight to the board (no local echo):
PuTTY, Tera Term, or pyserial's `python -m serial.tools.miniterm <port> 115200`
(Ctrl+] quits). HTerm works too, but is line-based: set its newline to CR and
send control codes as hex bytes (e.g. `08` = Backspace). `make ports` in `sw/`
lists the boards' ports (USB ID `0403:6010`). Only one program can have the port open.

## Running a testbench

Lushay: FPGA Toolchain button -> run testbench -> choose the project, then
the testbench. The output (PASS/FAIL, printed text) appears in the output
panel; waveforms are written as `.vcd` files next to the project.

Long ones: `leds_tb` ~2.5 minutes, `cpu_text_tb` ~12 minutes, `terminal_tb` ~100 seconds, `boot_tb` ~6 minutes.

## Changing the software

All CPU programs are in [`sw/`](../sw). A program that belongs to one step starts
with that step's number (`07_terminal.c` is step 7's); files without a number
(`start.S`, `link.ld`, `soc.h`, `console.c/.h`) are shared by several steps.
After editing a program:

1. Open a terminal in `fpga/sw` and run `make`. This compiles every program
   and writes each `.hex` file into the step folder that uses it:

   | Program | Output |
   |---|---|
   | `04_rv32i_test.S`, `04_hello.c` | `04_cpu_sim/` |
   | `05_leds.c` | `05_cpu_leds/` |
   | `06_text.c` | `06_cpu_text/` |
   | `07_terminal.c` | `07_uart/` (also preloaded in step 8) |
   | `08_boot.c` (bootloader) | `08_bootloader/boot.hex` (boot ROM, 512 words) |

2. **Up to step 7: rebuild and reflash the FPGA.** The program is preloaded into
   the RAM as part of the bitstream, so a software change needs a new bitstream.

   **With the step 8 bitstream on the board: upload instead.** In `fpga/sw`:
   `make gui` (a small window), or `make upload PROG=<name>` - with one board
   connected it is found automatically, with several add `PORT=COM8`; `make ports`
   lists them. Then press S1 when asked. Both send `build/<name>.bin` with
   [`tools/upload.py`](../tools/upload.py); close any serial terminal first. Programs must be built for 25.2 MHz
   (`CFLAGS_<name>`) and be at most 7,936 bytes. See [Step 8](steps/08_bootloader.md#using-it).

Useful outputs in `sw/build/`: `<program>.lst` is the disassembly - every
instruction with its address and machine code. Keep it open next to a
waveform to see which instruction the CPU is executing.

### Compiler flags (from the [Makefile](../sw/Makefile))

| Flag | Why |
|---|---|
| `-march=rv32i -mabi=ilp32` | only the base instructions our CPU has |
| `-ffreestanding -nostdlib` | no operating system, no C library; `start.S` is our startup code |
| `-Os` | optimize for size |
| `-Wl,--no-relax` | the linker must not use the global-pointer register, which `start.S` doesn't set up |
| `-ffunction-sections -Wl,--gc-sections` | drop functions nobody calls |
| `-lgcc` | multiply/divide helper functions |
| `CFLAGS_06_text`, `CFLAGS_07_terminal`: `-DCPU_HZ=25200000u` | from step 6 on the CPU runs at 25.2 MHz, not 27 MHz |
| bootloader: `-T 08_boot.ld` | its own linker script: code in the boot ROM at `0x3000_0000`, stack in the top 256 bytes of RAM |
| bootloader: `-fno-delete-null-pointer-checks` | it really writes the RAM from address 0, which C would otherwise treat as a null pointer |
| bootloader: `objcopy -j .text` | only code + constants go into the ROM image (see [Gotchas](gotchas.md#objcopy-a-ram-and-a-rom-far-apart-make-a-huge-bin)) |

## Testing the upload tool

After changing `tools/upload.py` or `tools/upload_gui.py`:
`python -I tools/test_upload.py` (from `fpga`) - 15 tests against a fake
bootloader, no board needed, under a second.

## Regenerating data files

From the `fpga` folder:

| File | Command |
|---|---|
| `03_text/font.hex` | `python -I tools/bdf2hex.py tools/font/spleen-8x16.bdf 03_text/font.hex` |
| `03_text/screen.hex` | `python -I tools/gen_screen.py 03_text/screen.hex` |
