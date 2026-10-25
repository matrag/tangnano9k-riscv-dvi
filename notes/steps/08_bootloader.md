# Step 8 - Serial bootloader

[Notes index](../README.md) · Previous: [Step 7](07_uart.md)

**Folder:** [`08_bootloader`](../../08_bootloader) · **Status:** works on the board (upload through the window confirmed)

## Goal

Load new programs over USB in about a second, instead of rebuilding and
reflashing the FPGA for every software change.

## What it does

```
 reset (power-up or S1) --> CPU starts in the BOOT ROM (0x3000_0000)
                                 |  bootloader: "[boot] ... waiting 1 s for an upload"
                                 |-- upload arrives, CRC correct --> runs the uploaded program
                                 |-- upload broken -------------------> "ERROR ...", waits for a new one
                                 '-- nothing within 1 s --------------> runs the program already in RAM
```

- The RAM is preloaded with step 7's terminal, so without a PC the board
  behaves like step 7 - one second later.
- An uploaded program stays in RAM: after S1 the bootloader waits 1 s, then
  runs it again. Power-off brings back the program from the bitstream.
- LEDs: LED 0 on = bootloader running, LED 1 flickers while loading.

## Using it

Flash the step 8 bitstream once (`08_bootloader/bootloader.lushay.json`) and
close any serial terminal (only one program can use the board's port). Then
upload with the window or the command line - both use the same code
([`tools/upload.py`](../../tools/upload.py)).

**The window** - `make gui` in `fpga/sw` (or `python -I tools/upload_gui.py` from `fpga`):

```
 Board:   [ COM3 - USB Serial Port, serial FACTORYAIOT_PRO  v ] [ Refresh ]
 Program: [ ...\fpga\sw\build\07_terminal.bin                ] [Browse...]
            07_terminal.bin: 1840 bytes, CRC-32 D2B6CB3C
                                                         [Upload] [Cancel]
 +---------------------------------------------------------------------+
 | Press S1 on the board (waiting up to 30 s) ...                      |
 | board: [boot] rv32i_core bootloader - waiting 1 s for an upload     |
 | board: [boot] OK - starting the uploaded program                    |
 +---------------------------------------------------------------------+
```

- **Board** lists every connected Tang Nano (found by its USB ID `0403:6010`);
  with several, choose one. **Refresh** after plugging a board in.
- **Program** is a `.bin` from `sw/build/` - run `make` first; the window
  doesn't compile.
- **Upload**, then press **S1** on the board. The log shows each step and
  whether the upload worked: board messages in blue, success in green, errors
  in red. **Cancel** stops waiting for S1. The window does only this - to see
  what the program sends afterwards, use a serial terminal.
- The last board and program are remembered in `%USERPROFILE%\.rv32i_upload.json`.

**The command line** - in `fpga/sw`:

| Command | What it does |
|---|---|
| `make ports` | lists the connected Tang Nano boards with their COM ports |
| `make upload PROG=07_terminal` | builds if needed, then uploads; with one board connected it is found automatically |
| `make upload PROG=07_terminal PORT=COM8` | uploads to that board (needed when several are connected) |
| `python -I ../tools/upload.py build/07_terminal.bin --port COM8 --monitor` | the tool directly; `--monitor` keeps printing the program's output |

With several boards and no `PORT`, the tool lists them and stops - it never
guesses which board to overwrite. To find out which COM port is which board,
press S1 on one: only that one answers.

When it says *Press S1*, press S1. At 115200 baud a byte takes 87 us, so the
transfer needs about 0.09 s per KB (calculated, not yet measured on the board).

Programs for this step must be built for **25.2 MHz** (`CFLAGS_<name> :=
-DCPU_HZ=25200000u` in the Makefile, as for `06_text` and `07_terminal`).
`05_leds.c` is built for step 5's 27 MHz, so uploaded here it runs about 7% slow.

## What's new

**Hardware** - small, all in [`lib/soc.v`](../../lib/soc.v) and passed through
[`lib/soc_text.v`](../../lib/soc_text.v):

- An optional **boot ROM**: 2 KB at `0x3000_0000` (`HAS_BOOT_ROM`,
  `BOOT_PROGRAM`). It is the same RAM module as the program RAM with its write
  strobes forced to 0 - a store to it is answered but changes nothing. One
  more block RAM (11 of 26).
- A **reset address** parameter (`RESET_PC`), passed to the CPU, which already
  had it: `0x3000_0000` here, `0` (the default) in the earlier steps.

**Software:**

- [`sw/08_boot.c`](../../sw/08_boot.c) - the bootloader, in C, with
  [`sw/08_boot_start.S`](../../sw/08_boot_start.S) (sets the stack, calls `boot_main`) and
  [`sw/08_boot.ld`](../../sw/08_boot.ld) (code in the ROM, stack in the top 256 bytes of RAM).
- [`tools/upload.py`](../../tools/upload.py) - the PC side (pyserial): finds the boards,
  runs the protocol, and is the command line tool.
- [`tools/upload_gui.py`](../../tools/upload_gui.py) - the upload window (tkinter, part of Python).
- [`tools/test_upload.py`](../../tools/test_upload.py) - tests for the upload code, without a board.
- `make upload`, `make ports`, `make gui` in [`sw/Makefile`](../../sw/Makefile).
- The existing programs, `start.S` and `link.ld` are **unchanged**.

## The protocol

All numbers little-endian:

| Direction | Bytes | Meaning |
|---|---|---|
| board -> PC | `[boot] ... waiting 1 s for an upload` | the PC waits for this line after you press S1 |
| PC -> board | `U P L D` | magic: an upload follows (other bytes before it are ignored) |
| PC -> board | 4 | program size in bytes, 1 to 7,936 |
| PC -> board | size | the program, written to RAM from address 0 |
| PC -> board | 4 | CRC-32 of the program |
| board -> PC | `[boot] OK ...` or `[boot] ERROR: ...` | result |

- **CRC-32** is the standard checksum of zip files and Ethernet (IEEE,
  bit-reversed polynomial `0xEDB88320`); the PC side is Python's `zlib.crc32`.
  The bootloader computes it bit by bit while the bytes arrive - no table, so it
  costs only a few instructions of ROM.
- **Keeping up:** at 115200 baud a byte arrives every 2,190 clock cycles. Storing
  it and the 8 CRC steps take a few hundred, so the bootloader keeps up with a
  continuous stream; the 16-byte receive FIFO absorbs short delays.
- **Timeouts:** 1 s for the start of an upload, 100 ms between bytes during it.
- **Wait for the end of the line:** the PC sends only after a complete `[boot]`
  line (up to its `\n`). While the bootloader is printing it doesn't read, and more
  than 16 bytes arriving then would overflow the receive FIFO. `upload.py` reads
  whole lines, so it follows this rule.
- **After an error** the RAM may hold half a program, so the bootloader never
  runs it: it waits for a new upload without a time limit (or press S1).

## Memory use

| Region | Who uses it |
|---|---|
| boot ROM `0x3000_0000`, 2 KB | bootloader code and messages: 1,152 bytes (56%) |
| RAM `0x0000` - `0x1EFF` | the uploaded program: at most **7,936 bytes** |
| RAM `0x1F00` - `0x1FFF` | the bootloader's stack (only while it runs) |

The bootloader has **no global variables** - everything is in local variables -
so it needs no RAM except its stack. The linker script checks this
(`ASSERT(SIZEOF(.bss) == 0 ...)`).

## Known limitation: S1 doesn't restore initialized globals

S1 resets the CPU, not the RAM. Global variables **with** a starting value
(`int lives = 3;`, the `.data` section) get that value only when the program
image is loaded - by the bitstream or by an upload. After the program has
changed them, S1 re-runs `main()` with the changed values. Globals without a
starting value (`.bss`) are cleared by `start.S` every time, and local
variables are always fresh. Our programs set their state in code, so they are
not affected. Not fixed on purpose; a fix would keep a copy of the starting
values and have `start.S` copy them back at every start. See
[Gotchas](../gotchas.md#s1-doesnt-restore-initialized-global-variables).

## Files

| File | Contents |
|---|---|
| [`top.v`](../../08_bootloader/top.v) | step 7's system with the boot ROM and `RESET_PC = 0x3000_0000` |
| [`boot.hex`](../../08_bootloader/boot.hex) | the bootloader, generated by `make` in `sw/` (512 words) |
| [`boot_tb.v`](../../08_bootloader/boot_tb.v) | testbench, see below |
| [`tangnano9k.cst`](../../08_bootloader/tangnano9k.cst), [`bootloader.lushay.json`](../../08_bootloader/bootloader.lushay.json) | pins (as step 7), project |

The RAM image (`../07_uart/terminal.hex`) and the font (`../03_text/font.hex`)
are used from their steps, not copied.

## The testbench

[`boot_tb.v`](../../08_bootloader/boot_tb.v) plays the PC:

- **A. power-up, no upload:** the bootloader must announce itself, wait 1 s and
  start the program in RAM - step 7's greeting must arrive.
- **B. reset, upload with a wrong CRC:** must answer `ERROR ... CRC mismatch`.
- **C. the same upload with the right CRC**, sent at full line speed like
  `upload.py`: must answer `OK` and run it. The uploaded program is
  [`sw/04_hello.c`](../../sw/04_hello.c), which prints its results through the
  simulation-only console and ends with exit code 0 - so the test also proves
  every byte arrived intact and in the right place.

## Results

- `boot_tb`: **pass** (all three parts; about 6 minutes of simulation for 1.4 s of board
  time). In part C the uploaded program (1,228 bytes, sent without pauses) runs and
  prints `all checks passed`.
- Place-and-route: up to **56.2 MHz** (needs 25.2), 2,688 LUT4 (31%), 538
  flip-flops, **11 block RAMs** (the boot ROM is the new one), 34 LUT RAMs.
- The boot ROM's block RAM carries the bootloader (checked in the placed design).
- Bootloader: 288 of 512 ROM words (56%).
- Upload tool: `test_upload.py` passes 15 tests against a fake bootloader -
  good upload, exact packet bytes, upload only after the complete `[boot]` line,
  CRC error, no bootloader, cancel, file size limits, port choice with 0/1/2 boards.
  A copy of `upload.py` that sent too early failed 4 of them. The window was
  opened and clicked through against the same fake board: good upload, CRC
  error, and Cancel while no bootloader answers.
- All earlier testbenches still pass.

## Problems we hit

- The first testbench run failed in part C: the testbench sent the second upload
  as soon as it saw "CRC mismatch", while the board was still printing the rest of
  that line. The bytes arriving meanwhile overflowed the receive FIFO, and the
  bootloader correctly reported a timeout. Fixed in the testbench, which now -
  like `upload.py` - waits for the end of the board's line. The rule is now in
  the protocol description (here and in `08_boot.c`).
- Two C pitfalls were avoided up front: jumping to and writing at address 0
  (C's "null pointer") - see [Gotchas](../gotchas.md#c-address-0-is-the-null-pointer).
