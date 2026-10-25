# Results and measurements

[Back to the notes index](README.md)

All numbers come from our own runs (simulation with iverilog, synthesis with
yosys, place-and-route with nextpnr-himbaechel from OSS CAD Suite), October 2026.
"Fmax" is the highest clock frequency at which the logic would still meet
timing, as reported by nextpnr after routing.

## FPGA resources and speed per step

| Step | Clock needed | Fmax | LUT4 | Flip-flops | Block RAM (of 26) | LUT RAM |
|---|---|---|---|---|---|---|
| 2 HDMI pattern | 25.2 MHz | 42.6 MHz | - | - | 0 | 0 |
| 3 Text mode | 25.2 MHz | 105 MHz | 228 (2%) | 218 | 6 | 0 |
| 5 CPU + LEDs | 27 MHz | 60.2 MHz | 2,781 (32%) | 297 | 4 | 32 |
| 6 CPU + text | 25.2 MHz | 57.4 MHz | 2,357 (27%) | 473 | 10 | 32 |
| 7 UART (+ scrollback) | 25.2 MHz | 62.7 MHz | 2,451 (28%) | 537 | 10 | 34 |
| 8 Bootloader | 25.2 MHz | 56.2 MHz | 2,688 (31%) | 538 | 11 | 34 |

"-" = not recorded. Step 5 reports more LUTs than step 6 although it has less
logic; we haven't looked into why yet (a candidate: how yosys optimizes the
two designs differently).

## CPU performance

| Measurement | Value | Where |
|---|---|---|
| Clocks per instruction, ALU/branch/jump | 4 | by design |
| Clocks per instruction, load/store | 6 | by design |
| Average CPI, compiled C (`04_hello.c`) | **4.07** (30,735 instructions, 125,166 clocks) | step 4 |
| Instructions per second at 25.2 MHz | about 6 million | 25.2 / 4.07 |
| Primes below 5000 (trial division, software divide) | **669 in 940 ms** | step 6, on the CPU |

The prime benchmark is the baseline for a future hardware multiply/divide
(RISC-V "M" extension).

## Program sizes (8 KB RAM = 2048 words; uploads at most 7,936 bytes = 1,984 words)

| Program | Words | Used |
|---|---|---|
| `04_rv32i_test` | 364 | 17% |
| `04_hello` | 307 | 14% |
| `05_leds` | 119 | 5% |
| `06_text` (with the console library) | 969 | 47% |
| `07_terminal` (with the console library) | 460 | 22% |
| `08_boot` (bootloader, in the 2 KB boot ROM = 512 words) | 288 | 56% of the ROM |

## Testbenches

| Testbench | Result | Simulation time |
|---|---|---|
| `02_hdmi/tmds_encoder_tb` | pass, max running imbalance 8 | seconds |
| `03_text/text_mode_tb` | pass, 614,400 pixels over 2 frames | ~10 s |
| `04_cpu_sim/cpu_tests_tb` | pass, 60 tests, 1,556 clocks | seconds |
| `04_cpu_sim/hello_tb` | pass, CPI 4.07 | seconds |
| `05_cpu_leds/leds_tb` | pass, 80.02 ms per step | ~2.5 min |
| `06_cpu_text/cpu_text_tb` | pass, scroll wrapped to 2 | ~12 min |
| `07_uart/uart_tb` | pass: loopback, +-2% bit time, glitch, framing error | seconds |
| `07_uart/terminal_tb` | pass, both directions, screen, 58 scrolls round the 51-row ring | ~100 s |
| `08_bootloader/boot_tb` | pass: timeout -> program in RAM, CRC error, 1,228-byte upload runs | ~6 min |
| `tools/test_upload.py` (Python, the PC upload tool) | pass, 15 tests against a fake bootloader | < 1 s |

Simulation ran at about 100,000-200,000 clock cycles per second on the development PC, so
tests that cover seconds of board time take minutes.
