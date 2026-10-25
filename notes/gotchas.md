# Gotchas and lessons learned

[Back to the notes index](README.md)

Every trap we fell into, what it looked like, and the fix. Grouped by where
the problem was.

## Verilog

### Verilog: the `?:` signedness trap

**Symptom:** the CPU's arithmetic shift right (`sra`) shifted in zeros instead
of copies of the sign bit. Found by test 13 of the instruction test (step 4).

**Cause:** in `alt ? $signed(a) >>> n : a >> n`, the second branch is
unsigned, and Verilog then treats the **whole** `?:` expression as unsigned -
which silently turns `>>>` into a logical shift.

**Fix:** compute the signed shift as its own signal, then select:

```verilog
wire signed [31:0] alu_sra = $signed(alu_a) >>> shamt;
...
alu_out = alt ? alu_sra : alu_a >> shamt;
```

**Lesson:** signedness in Verilog depends on the whole expression, not just one operand.

### Verilog: `cell` is a reserved word

**Symptom:** a cascade of "syntax error" messages from iverilog (step 3).
**Cause:** `cell` is a keyword in Verilog-2001 (used for library configurations).
**Fix:** renamed the signal to `cell_data`. Other surprising keywords: `config`, `design`, `library`, `instance`, `use`, `liblist`.

### Verilog: integers inside `{}` are 32 bits wide

In a concatenation every part keeps its width. `{"L", 8'h30 + n / 10}` with an
`integer n` gives a 32-bit second part, not one character. Compute such values
into an 8-bit `reg` first (step 7 testbench).

### Verilog: declare before use

A `reg` used in an expression before its declaration is an error (step 4,
`mem_addr_lo`; again in step 7, `io_ready`). iverilog says "Unable to bind
wire/reg". Declare signals at the top of the block that uses them - and when
adding code above existing code, check what it uses.

## Simulation

### Simulation: `!=` with X hides failures

**Symptom:** the step 6 testbench printed PASS after 2 clock cycles, without
anything on the screen.

**Cause:** a memory without an init file holds unknown `X` values in
simulation. `X != 'R'` is neither true nor false (it is `X`), and `if (X)`
counts as false - so no mismatch was ever detected.

**Fix, two parts:**
- Memories without an init file now start at zero in simulation, which is
  also what the real block RAM does ([`bram_sdp.v`](../lib/bram_sdp.v), [`soc_ram.v`](../lib/soc_ram.v)).
- Testbench comparisons use `!==` / `===`, which treat `X` as a real value
  and so count it as a mismatch.

**Lesson:** a testbench that can't fail is worse than none. Check that a new
testbench fails when it should - we did this on purpose in step 3 by breaking
the pipeline (37,618 errors reported).

### Simulation: `$readmemh` paths are relative to where the simulator runs

Lushay runs iverilog and yosys in the **project folder**, so `"font.hex"`
means a file next to the `.lushay.json`. Step 6 loads `"../03_text/font.hex"`
to share the font instead of copying it.

## Yosys / nextpnr

### Yosys: default parameter values get elaborated too

**Symptom:** "Can not open file `program.hex` for `$readmemh`" (step 5), later
the same with `font.hex` (step 6), although every instance passed a different file name.

**Cause:** yosys may elaborate a module once with its **default** parameter
values, and a default file name that doesn't exist stops the build.

**Fix:** file-name parameters default to `""`, and an empty name means "no
init file" (the memory starts at zero).

### Yosys: `CLKDIV` has no `GSREN` here

The yosys cell library has three definitions of `CLKDIV`; the one used for the
GW1NR-9 has only `DIV_MODE`. Passing `GSREN` gives "does not have a parameter
named 'GSREN'" (step 1).

### HDMI pins: list the `_n` pins in the .cst

**Symptom:** first Lushay ("Ports are missing from CST file: tmds_clk_n ...")
and then, with that check off, nextpnr ("Unconstrained IO: tmds_d_n_OBUF_O_2").

**Cause:** yosys puts an output buffer on every port, including the `_n` side
of each differential pair. nextpnr checks every buffer has a pin before it
merges the P and N buffers into one differential output.

**Fix:** constrain both sides:

```
IO_LOC  "tmds_clk_p" 69,68;
IO_PORT "tmds_clk_p" IO_TYPE=LVCMOS33D PULL_MODE=NONE DRIVE=8;
IO_LOC  "tmds_clk_n" 68;
```

The result was checked in the place-and-route output: each pair is packed as
`DIFF_TYPE=ELVDS_OBUF` with P and N on the same IO tile.

## Lushay Code

### Lushay: the project file key is `includedFiles`

The file list in a `*.lushay.json` is `includedFiles` (paths relative to the
project file). `includedFilePaths` is used internally and gets overwritten.
Without `includedFiles`, Lushay falls back to "all `.v` files", using a file
search that can find nothing on Windows - "No files to synthesize".
**Always list the files explicitly.** Other keys: [Tools and workflow](toolchain.md#lushay-project-files).

### Lushay: a new submodule must be added to every project that uses it

When the UART went into `lib/soc.v` (step 7), steps 4, 5 and 6 also use
`soc.v`, but their `*.lushay.json` didn't list the new `uart_tx.v`,
`uart_rx.v` and `fifo.v`. In Lushay they would have failed with "Unknown
module type: uart_tx". Hand-run simulations didn't notice, because they were
given the files directly; a regression that reads the project files did. Rule:
when a shared module instantiates a new module, add its file to the
`includedFiles` of every step that uses the shared module.

### Lushay: workspace settings override user settings

The OSS CAD Suite path (`lushay.OssCadSuite.path`) was set correctly in the
user settings, but a **workspace** setting still pointed at `C:\oss-cad-suite`.
Check all tabs (User / Workspace / Folder) in VS Code's settings.

### Lushay: testbenches must be named `test`

Lushay compiles a testbench with `iverilog -s test`, so the testbench module
must be called `test`.

## Software

### Python's `cp437` codec has no symbols for 0x01-0x1F

It maps those codes to control characters, while on the PC screen they were
smileys, card suits, arrows... [`bdf2hex.py`](../tools/bdf2hex.py) and
[`gen_screen.py`](../tools/gen_screen.py) carry their own table for them.

### C: address 0 is the null pointer

In C, a pointer with the value 0 is the *null pointer*, and the compiler may
assume a program never uses it: it can delete such accesses or replace a call
through it with a trap. On our system address 0 is simply the start of the RAM,
where the bootloader stores programs and then jumps. So [`sw/08_boot.c`](../sw/08_boot.c)
jumps with inline assembly (`jr zero`) and is compiled with
`-fno-delete-null-pointer-checks` for its stores to address 0 (step 8).

### objcopy: a RAM and a ROM far apart make a huge .bin

`objcopy -O binary` writes one image from the lowest to the highest address of
all loaded sections. The bootloader's code is at `0x3000_0000` and its (empty)
RAM sections at `0x1F00`, so the image would be ~768 MB of zeros. The Makefile
uses `objcopy -j .text` for the bootloader: only code and constants (step 8).

### S1 doesn't restore initialized global variables

S1 resets the CPU, not the RAM (block RAM has no reset). Globals with a starting
value (`int lives = 3;`, section `.data`) get it only when the program image is
loaded - from the bitstream or by an upload. After the program has changed them,
S1 re-runs `main()` with the changed values. `.bss` globals (no starting value)
are cleared by `start.S` at every start, and locals are always fresh. Not fixed
on purpose: set state in code at the start of `main()`. A fix would keep a copy of
the starting values and let `start.S` copy them back. See [Step 8](steps/08_bootloader.md#known-limitation-s1-doesnt-restore-initialized-globals).

### A serial echo can't keep up with pasted text

Echoing sends more bytes than arrive (Enter -> `\r\n`), so with text arriving at
full line speed the CPU falls behind and the receive FIFO overflows. Testbenches
should type like a person (pauses between keys) - and wait until the board has
finished sending before typing. See [Step 7](steps/07_uart.md#known-limitation-pasting-text).

### Keep screen lines shorter than 80 characters

A line of 80+ characters wraps onto the next row, which also moves everything
printed after it. The step 6 burst line was 83 characters at first.

## Makefile and tools

### make: spaces before a `#` comment belong to the value

`PORT ?=   # comment` makes `PORT` three spaces, not empty, so a test like
`$(if $(PORT),...)` sees a value. Put such comments on their own line (step 8).

### Tk windows on a scaled Windows display

Without "DPI awareness", Windows stretches a Tk window as a bitmap on a
scaled display (e.g. 125%): blurry text, and window sizes that don't match the
screen. `upload_gui.py` calls `ctypes.windll.shcore.SetProcessDpiAwareness(1)`
before creating the window.

### Shell strings: `$` means something in PowerShell

In a double-quoted PowerShell string, `$(...)` runs as code and `$name` is a
variable - text containing make's `$(if ...)` breaks the whole command. Use
single quotes, or edit files with a script language where `$` is plain text.

## The board

- **S1 = pin 4, S2 = pin 3**, both active low (pressed = 0).
- LEDs are **active low**.
- The LED/button bank runs at 1.8 V (`LVCMOS18`), the clock pin at 3.3 V (`LVCMOS33`).
