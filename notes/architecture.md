# Architecture

[Back to the notes index](README.md)

This page describes the complete system as it is in step 8
([`08_bootloader`](steps/08_bootloader.md)): step 6 plus the serial port (step 7)
and a boot ROM with a serial bootloader (step 8).

## Block diagram

```
                 27 MHz crystal
                       |
                 +-----v------+
                 |   clocks   |  rPLL: 27 -> 126 MHz,  CLKDIV: 126 / 5 = 25.2 MHz
                 +--+------+--+
          126 MHz   |      |  25.2 MHz (everything else runs on this clock)
                    |      v
                    |  +------------------------------------- soc_text ------------------------------------+
                    |  |                                                                                   |
                    |  |  +--------------------------- soc ---------------------------+                    |
                    |  |  |                                                           |                    |
                    |  |  |  rv32i_core <--bus--> address decoder                     |                    |
                    |  |  |                       |         |         |         |     |                    |
                    |  |  |                   RAM 8 KB   IO regs  boot ROM   ext bus--+--> text device     |
                    |  |  |                   (program,  (LEDs,   2 KB, the           |    (cell writes,   |
                    |  |  |                    data,     buttons, bootloader          |     scroll reg)    |
                    |  |  |                    stack)    timer,   (step 8)            |         |          |
                    |  |  |                              UART)                        |         |          |
                    |  |  +-----------------------------------------------------------+         v          |
                    |  |                                                                char RAM (write)   |
                    |  |     video_timing --(x, y, syncs)--> text_mode <-- font ROM                        |
                    |  |                                         |       char RAM (read)                   |
                    |  +-----------------------------------------+-----------------------------------------+
                    |                                            | rgb, hsync, vsync, de
                    v                                            v
                 +------------------------------------------------------+
                 | hdmi_out: 3 x TMDS encoder, 4 x OSER10, ELVDS        |----> HDMI connector
                 +------------------------------------------------------+
```

## Clocks

| Clock | Frequency | Made by | Used for |
|---|---|---|---|
| `clk` | 27 MHz | crystal on the board | input to the PLL (and the CPU in step 5) |
| `clk_tmds` | 126 MHz | rPLL: 27 x 14 / 3 | the serializers: 10 bits per pixel, sent on both clock edges |
| `clk_pix` | 25.2 MHz | CLKDIV: 126 / 5 | video timing, text mode, encoders, **and the CPU** |

Running the CPU on the pixel clock means the CPU and the video share one clock,
so the CPU can write the character RAM directly, with no clock-domain
crossing. Why 25.2 MHz: 640 x 480 at 60 Hz needs 800 x 525 x 60 = 25.2 million
pixel clocks per second (see [Video](video.md)).

## Memory map

What the CPU sees at each address. The top 4 address bits choose the device.
The same table is in [`sw/soc.h`](../sw/soc.h) for C programs.

| Address | Name | Access | What it does |
|---|---|---|---|
| `0x0000_0000` - `0x0000_1FFF` | RAM | read/write | 8 KB: program, data, stack. Steps 4-7 start here (`RESET_PC = 0`) |
| `0x1000_0000` | `LEDS` | read/write | bit n = 1 lights LED n (6 LEDs) |
| `0x1000_0004` | `CONSOLE` | write | prints a character - **simulation only** |
| `0x1000_0008` | `EXIT` | write | ends the simulation with an exit code - **simulation only** |
| `0x1000_000C` | `TIMER` | read | counts clock cycles since power-up, wraps after 2^32 |
| `0x1000_0010` | `BUTTONS` | read | bit 0 = S2 pressed |
| `0x1000_0014` | `UART_DATA` | read/write | write: send a byte; read: bit 8 = byte received, bits 7..0 = the byte (step 7) |
| `0x1000_0018` | `UART_STATUS` | read | bit 0 = ready to send, bit 1 = byte waiting (step 7) |
| `0x2000_0000 + 4 x cell` | `TEXT` | write | one character cell per 32-bit word, `cell = ram_row x 80 + col`, value `bg<<12 \| fg<<8 \| character` |
| `0x2001_0000` | `TEXT_SCROLL` | read/write | which character RAM row is shown at the top of the screen (0..ring-1) |
| `0x2001_0004` | `TEXT_RING` | read | rows in the character RAM ring: 30, or 51 with scrollback (step 7) |
| `0x3000_0000` - `0x3000_07FF` | boot ROM | read | 2 KB, the bootloader; step 8 starts here (`RESET_PC = 0x3000_0000`) and then jumps to 0 |

An access to any other address gets no answer and stalls the CPU (a program
bug, easy to see in simulation).

"Simulation only" registers are inside `` `ifndef SYNTHESIS `` in
[`lib/soc.v`](../lib/soc.v): yosys skips that code, so it never becomes hardware.

## Shared modules (`lib/`)

| Module | File | Used from step | Purpose |
|---|---|---|---|
| `clocks` | [`clocks.v`](../lib/clocks.v) | 2 | PLL + divider |
| `video_timing` | [`video_timing.v`](../lib/video_timing.v) | 2 | 640 x 480 counters, syncs, `de`, x/y |
| `tmds_encoder` | [`tmds_encoder.v`](../lib/tmds_encoder.v) | 2 | 8b/10b TMDS encoding |
| `hdmi_out` | [`hdmi_out.v`](../lib/hdmi_out.v) | 2 | 3 encoders, 4 serializers, differential outputs |
| `bram_sdp` | [`bram_sdp.v`](../lib/bram_sdp.v) | 3 | generic block RAM, one write port + one read port |
| `text_mode` | [`text_mode.v`](../lib/text_mode.v) | 3 | 80 x 30 text renderer, 3-stage pipeline, hardware scroll |
| `rv32i_core` | [`rv32i_core.v`](../lib/rv32i_core.v) | 4 | the CPU |
| `soc_ram` | [`soc_ram.v`](../lib/soc_ram.v) | 4 | 32-bit CPU RAM with byte enables and bus handshake |
| `soc` | [`soc.v`](../lib/soc.v) | 4 | CPU + RAM + IO registers + external bus; UART (7); optional boot ROM and reset address (8) |
| `soc_text` | [`soc_text.v`](../lib/soc_text.v) | 6 | `soc` + text device + video timing + text mode |
| `uart_tx` | [`uart_tx.v`](../lib/uart_tx.v) | 7 | serial transmitter, 8N1 |
| `uart_rx` | [`uart_rx.v`](../lib/uart_rx.v) | 7 | serial receiver, 8N1, mid-bit sampling |
| `fifo` | [`fifo.v`](../lib/fifo.v) | 7 | small first-in first-out buffer (UART receive) |

## Resource use (step 8)

From place-and-route; details in [Results](results.md).

| Resource | Used | Available |
|---|---|---|
| LUT4 (logic) | 2,688 | 8,640 (31%) |
| Flip-flops | 538 | 6,480 (8%) |
| Block RAM (18 Kbit) | 11 | 26 (42%): 4 CPU RAM, 4 character RAM, 2 font, 1 boot ROM |
| LUT RAM (RAM16SDP4) | 34 | 270: the CPU's register file (32) and the UART receive FIFO (2) |
