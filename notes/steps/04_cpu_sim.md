# Step 4 - The CPU, in simulation

[Notes index](../README.md) · Previous: [Step 3](03_text.md) · Next: [Step 5 - CPU on the board](05_cpu_leds.md)

**Folder:** [`04_cpu_sim`](../../04_cpu_sim) · **Status:** simulation only (no bitstream for this step)

## Goal

Write our own RISC-V CPU and prove, in simulation, that it runs real
programs - including C compiled with GCC - before it touches the board.

## What's new

- [`lib/rv32i_core.v`](../../lib/rv32i_core.v): the CPU. Everything about it is in [The CPU core](../cpu.md).
- [`lib/soc_ram.v`](../../lib/soc_ram.v): 8 KB RAM with byte write enables, speaking the CPU's bus handshake.
- [`lib/soc.v`](../../lib/soc.v): CPU + RAM + IO registers. In this step it is
  used with the simulation-only registers: `CONSOLE` (print a character into
  the simulation log) and `EXIT` (end the simulation with an exit code).
- The **RISC-V compiler** (xPack GCC 15.2.0), set up by `framework_initialise.py`
  in `toolchain/riscv-gcc/` (see [SETUP.md](../../SETUP.md)).
- The **software** in [`sw/`](../../sw): startup code, linker script, Makefile.
  See [Tools and workflow](../toolchain.md#changing-the-software).

## The test programs

| Program | Testbench | What it checks |
|---|---|---|
| [`sw/04_rv32i_test.S`](../../sw/04_rv32i_test.S) | [`cpu_tests_tb.v`](../../04_cpu_sim/cpu_tests_tb.v) | 60 self-checking tests, one or more per instruction. On the first wrong result it reports the test number |
| [`sw/04_hello.c`](../../sw/04_hello.c) | [`hello_tb.v`](../../04_cpu_sim/hello_tb.v) | prints to the simulation log: Fibonacci numbers, primes, 10!, LED writes; checks its own answers |

Expected output of `hello_tb`:

```
Hello from rv32i_core!
fib(0..15): 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610
primes < 100: 2 3 5 7 ... 89 97
count = 25
10! = 3628800
all checks passed
30735 instructions in 125166 clock cycles (4.07 cycles per instruction)
PASS: 04_hello.c returned 0
```

## How a C program starts

1. The CPU starts at address 0, where the linker put [`start.S`](../../sw/start.S).
   (From step 8 the CPU starts in the bootloader, which then jumps to address 0.)
2. `start.S` sets the stack pointer to the top of RAM (0x2000), clears the
   zero-initialized globals (`.bss`), and calls `main()`.
3. Initialized globals need no copying: the whole program image, data
   included, is preloaded into RAM. This is only true for the first start:
   after S1 they keep their changed values (see [Gotchas](../gotchas.md#s1-doesnt-restore-initialized-global-variables)).
4. `main()`'s return value is written to `EXIT` (ends a simulation; ignored on the board).

There is no C library (no `printf`): the programs bring the few output
routines they need. Multiply and divide come from **libgcc** helper functions,
since RV32I has no such instructions.

## Results

- Instruction test: **pass**, 1,556 clock cycles.
- 04_hello.c: **pass**, CPI 4.07.
- The core alone: about 2,000 LUT4-equivalent cells; its register file maps
  to 32 small LUT RAMs, no block RAM.
