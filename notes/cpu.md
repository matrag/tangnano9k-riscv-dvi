# The CPU core: `rv32i_core`

[Back to the notes index](README.md) · Source: [`lib/rv32i_core.v`](../lib/rv32i_core.v)

## In one sentence

A **32-bit, in-order, scalar, multi-cycle (non-pipelined) RISC-V core**
implementing the **RV32I** base integer instruction set, with a single shared
memory bus and no privileged architecture (no CSRs, interrupts or exceptions).

## What each of those words means

**RV32I (the instruction set)**
- **RV32** = 32-bit registers and addresses. **I** = the base integer set:
  37 instructions for arithmetic/logic, loads/stores, branches and jumps,
  plus FENCE, ECALL and EBREAK.
- No extensions: no **M** (multiply/divide - GCC calls libgcc helpers instead),
  no **C** (16-bit compressed instructions), no **A** (atomics), no **F/D**
  (floating point), no **Zicsr** (control/status registers).
- The smallest set GCC can target: `-march=rv32i -mabi=ilp32`.

**Multi-cycle (how it executes)**

One instruction at a time, stepped through by a state machine:

```
      FETCH (2 clocks) --> DECODE (1) --> EXECUTE (1) ------------------------> next FETCH
                                              \--> MEM (2, loads/stores only) --/
```

| State | What happens |
|---|---|
| FETCH | wait for the instruction word from memory, store it in `ir` |
| DECODE | read the two source registers (a clocked read, like a block RAM) |
| EXECUTE | ALU, branch decision, jump target; write the result register; start fetching the next instruction - or start a memory access |
| MEM | wait for load data (and write it to the register) or for the store to finish |

- **Clocks per instruction (CPI):** 4 for ALU, branch and jump instructions,
  6 for loads and stores. The C test program averaged **4.07**.
- At the 25.2 MHz pixel clock that is about **6 million instructions per second**.
  Place-and-route says the core could run at about 57-64 MHz.
- A **pipelined** CPU would overlap these steps (fetch the next instruction
  while executing this one) and get close to 1 clock per instruction, at the
  cost of hazard detection and forwarding logic. Multi-cycle keeps the design
  small and every step visible.

**In-order, scalar:** instructions complete in program order, one at a time.
No out-of-order execution, no branch prediction, no caches.

**One shared bus ("von Neumann" / Princeton):** instruction fetches and data
loads/stores use the same bus to the same RAM. Simple, but the two can never
overlap. A Harvard design has separate instruction and data paths.

**No privileged architecture:** real RISC-V cores implement at least
"machine mode" (CSRs such as `mstatus` and `mtvec`, exceptions, interrupts).
This core instead stops and raises `trap` on ECALL, EBREAK or an unknown
instruction. Fine for bare-metal programs, but **not a standards-compliant
RISC-V core**. Interrupts would be a future step.

## Instruction formats

All RISC-V instructions keep their fields in the same places, so decoding is
mostly wiring:

```
  31        25 24   20 19   15 14  12 11    7 6      0
 |  funct7    |  rs2  |  rs1  |funct3|  rd   | opcode |   R-type: register-register (add, sub, ...)
 |     imm[11:0]      |  rs1  |funct3|  rd   | opcode |   I-type: immediate, loads, jalr
 | imm[11:5]  |  rs2  |  rs1  |funct3|imm[4:0]| opcode|   S-type: stores
 |            imm[31:12]             |  rd   | opcode |   U-type: lui, auipc
```

B-type (branches) and J-type (jal) are S and U with the immediate bits
shuffled so that the sign bit is always bit 31.

## The bus

The core talks to memory with a valid/ready handshake (the same idea as
PicoRV32's "native" interface):

```
  clk        _/‾\_/‾\_/‾\_/‾\_
  mem_valid  _/‾‾‾‾‾‾‾\_______     CPU: "I want this address" (held until ready)
  mem_ready  _____/‾‾‾\_______     memory: "done" (one clock)
  mem_rdata  -----< D >-------     read data, valid while ready is high
```

| Signal | Meaning |
|---|---|
| `mem_addr` | byte address, always word aligned (`addr[1:0] = 0`) |
| `mem_wstrb` | which bytes to write: bit 0 = bits 7..0 ... bit 3 = bits 31..24. `0` = read |
| `mem_wdata` | write data; bytes and halfwords are repeated in every lane, `wstrb` picks the right one |

The CPU starts the next fetch already in the EXECUTE state, which saves one
clock per instruction.

## Inside the core

- **Register file:** 32 x 32 bits, x0 always reads 0 (never written).
  2 read ports + 1 write port; yosys maps it onto 32 small LUT RAMs
  (`RAM16SDP4`, two copies so both registers can be read at once). No block RAM.
- **ALU:** one adder/shifter/comparator block shared by register-register and
  register-immediate instructions; `funct3` picks the operation.
- **Loads:** the word is shifted down by the low address bits, then sign- or
  zero-extended for `lb`/`lh`/`lbu`/`lhu`.
- **Reset address:** parameter `RESET_PC` - `0` (the program in RAM, steps 4-7)
  or `0x3000_0000` (the bootloader in the boot ROM, step 8).
- **Not implemented on purpose:** misaligned loads/stores (undefined result;
  GCC doesn't generate them for normal C), CSRs, interrupts.

## How it compares

| Core | Type | Clocks/instruction | Size (approx.) |
|---|---|---|---|
| SERV | bit-serial: one bit per clock | ~32+ | ~200 LUTs |
| **rv32i_core** (ours) | multi-cycle, RV32I | 4-6 | ~2,000-2,800 LUT4 on the GW1N |
| PicoRV32 | multi-cycle, configurable (M, C, interrupts) | ~3-4 | 1,000-3,000 LUTs |
| Textbook 5-stage pipeline | pipelined, Harvard | ~1.2 | 2-3x ours |
| VexRiscv, CV32E40P, ... | pipelined, caches, full privileged spec | ~1 | much larger |

It is essentially the "multi-cycle datapath" of computer-architecture
textbooks (e.g. Patterson & Hennessy), applied to RISC-V.

## How it is tested

| Test | What it checks | Result |
|---|---|---|
| [`sw/04_rv32i_test.S`](../sw/04_rv32i_test.S) via [`04_cpu_sim/cpu_tests_tb.v`](../04_cpu_sim/cpu_tests_tb.v) | 60 self-checking tests covering every RV32I instruction except ECALL/EBREAK: edge cases (overflow, sign extension, shift counts, x0), all branches taken and not taken, all load/store widths and byte lanes | pass, 1,556 clock cycles |
| [`sw/04_hello.c`](../sw/04_hello.c) via [`04_cpu_sim/hello_tb.v`](../04_cpu_sim/hello_tb.v) | compiled C: loops, recursion, stack, globals, libgcc multiply/divide | pass, 30,735 instructions, CPI 4.07 |
| [`sw/05_leds.c`](../sw/05_leds.c), [`sw/06_text.c`](../sw/06_text.c), [`sw/07_terminal.c`](../sw/07_terminal.c) | real programs, in simulation and on the board | pass, work on the board |
| [`sw/08_boot.c`](../sw/08_boot.c) via [`08_bootloader/boot_tb.v`](../08_bootloader/boot_tb.v) | the bootloader running from the boot ROM, receiving and starting a program | see [Step 8](steps/08_bootloader.md#results) |
| official `riscv-arch-test` suite | standard compliance | **not run yet** |

The instruction test found one real bug (arithmetic shift right shifted in
zeros, see [Gotchas](gotchas.md#verilog-the--signedness-trap)).
