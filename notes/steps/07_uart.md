# Step 7 - UART: talking to the PC

[Notes index](../README.md) · Previous: [Step 6](06_cpu_text.md) · Next: [Step 8 - Bootloader](08_bootloader.md)

**Folder:** [`07_uart`](../../07_uart) · **Status:** works on the board

## Goal

A serial port to the PC over the board's USB connector: the PC keyboard
becomes an input for the CPU, and the CPU can send text to a terminal on the
PC. It is also the basis for a future bootloader (loading programs without
rebuilding the FPGA).

## What it does

Program [`sw/07_terminal.c`](../../sw/07_terminal.c):

1. Shows a title bar on the HDMI screen and sends a greeting to the PC.
2. Every character typed in the PC's serial terminal appears on the HDMI
   screen (yellow) and is sent back to the PC ("echo").
3. The LEDs show the code of the last character received.
4. S2 sends "[S2 pressed]" to both the screen and the PC.

| Key | Effect |
|---|---|
| Enter | new line (CR, LF or CR+LF all work) |
| Backspace | deletes the character before the cursor, within the current line |

The terminal is deliberately simple. A version with line deletion (Backspace
at the start of a line, Ctrl+U) was built and tested, then removed again to
keep the step lean: the console library still has the functions for it (see
[Scrollback](#scrollback)).

**Settings for the PC terminal:** the board's COM port, **115200 baud, 8N1**.

- **Lushay Code:** FPGA Toolchain button -> **Serial Console**. It finds the
  board automatically (the board's USB chip presents itself as an FTDI-style
  dual serial device; the UART is the second one, "USB Serial Converter B"
  in Windows' device manager). Lushay's console shows what you type *and*
  the board echoes it, so **each character appears twice** there.
- **PuTTY**, **Tera Term**, or pyserial's `python -m serial.tools.miniterm <port> 115200`:
  every key goes straight to the board, no local echo.
- **HTerm** (line-based: type into a box, then send): set the newline to CR.
  Control codes are sent as hex bytes, e.g. `08` for Backspace.
- To find the board's port: `make ports` in `sw/` (step 8), or look for the
  *USB Serial Port* with USB ID `0403:6010` (Windows: Device Manager; Linux: `/dev/ttyUSBn`).

## How a UART works

One wire per direction and **no clock wire**. Each byte travels as a frame:

```
 idle  start  bit0 bit1 bit2 bit3 bit4 bit5 bit6 bit7  stop  idle
 ‾‾‾‾‾\_____/‾‾‾‾\____/ ...                        /‾‾‾‾‾‾‾‾‾‾‾‾
        0     8 data bits, least significant first    1
```

- Every bit lasts 1/115200 s = 8.68 us = 219 clock cycles at 25.2 MHz
  (exactly 218.75: the 0.1% rounding error is harmless).
- The line rests at 1; the 0 start bit says "a byte begins now".
- The **receiver** times the bits itself: after the falling edge of the start
  bit it waits half a bit (and checks the line is still 0, otherwise it was a
  glitch), then samples each bit in its **middle**. It re-synchronizes on
  every start bit, so small clock differences between PC and FPGA never add
  up beyond one frame. About +-2% total error is safe.
- A frame whose stop bit is 0 ("framing error") is thrown away.
- The receive pin goes through a two-flip-flop **synchronizer** first, like the buttons.

## Design choices

- **8N1 fixed, baud rate a build-time parameter** (`BAUD = 115200`, with
  `CLK_HZ` so the same module works at 27 or 25.2 MHz). No runtime
  configuration: nothing for a program to get wrong, and a bootloader needs
  a known speed anyway.
- **16-byte receive FIFO** ([`lib/fifo.v`](../../lib/fifo.v)): bytes may
  arrive while the CPU is busy (e.g. scrolling the screen). More than 16
  waiting bytes are lost.
- **No transmit FIFO**: software waits for "ready" before each byte
  (`uart_putc` in [`sw/soc.h`](../../sw/soc.h)). One byte takes 87 us.
- Reading `UART_DATA` returns the byte **and** a valid flag (bit 8) in one
  read, so `uart_getc()` needs a single bus access.

## Scrollback

When the screen scrolls, the line leaving the top used to be overwritten
immediately: its RAM row was reused for the new bottom line. The character
RAM, however, has room for 4,096 cells and the screen uses only 2,400 - so
in step 7 the ring of rows is **51 rows** instead of 30 (`RING_ROWS` parameter of
[`lib/text_mode.v`](../../lib/text_mode.v) and [`lib/soc_text.v`](../../lib/soc_text.v)):

- the screen still shows 30 rows;
- the 21 most recent lines that scrolled off stay in the RAM;
- scrolling back (`TEXT_SCROLL - 1`) brings them back with their text.

No extra block RAM: the space was already there. Step 6 keeps 30 rows.
Software reads the ring size from a new register (`TEXT_RING`, `0x2001_0004`),
so the same console library works on both.

The console library ([`sw/console.c`](../../sw/console.c)) counts how many
lines above the screen are still valid, and remembers where each line ended
(the screen itself doesn't know), so the cursor can go back to the end of the
previous line. Functions: `con_clear_line()`, `con_delete_row()` (removes
the cursor's line and scrolls back), `con_cursor_col()`.

`07_terminal.c` doesn't use them any more. They were tested (Backspace at a line
start brought back a scrolled-off line, Ctrl+U cleared a line) while the
terminal used them; the current testbench only checks scrolling through the
ring. Programs that don't call them don't carry their code (`--gc-sections`).

## Registers

Added to [`lib/soc.v`](../../lib/soc.v), so every step's SoC has them (the
earlier steps tie the receive pin to 1 and leave the transmit pin open):

| Address | Name | Access | Meaning |
|---|---|---|---|
| `0x1000_0014` | `UART_DATA` | write | send a byte (only when `UART_STATUS` bit 0 = 1; otherwise ignored) |
| | | read | bit 8 = 1 if a byte was received, bits 7..0 = the byte; the read removes it from the FIFO |
| `0x1000_0018` | `UART_STATUS` | read | bit 0 = transmitter ready, bit 1 = a received byte is waiting |

C helpers in [`sw/soc.h`](../../sw/soc.h): `uart_putc`, `uart_puts`,
`uart_getc` (returns -1 if nothing arrived). The console library got
Backspace support (`'\b'`).

## Files

| File | Contents |
|---|---|
| [`lib/uart_tx.v`](../../lib/uart_tx.v) | transmitter: a 10-bit shift register (start, data, stop), one bit every 219 clocks |
| [`lib/uart_rx.v`](../../lib/uart_rx.v) | receiver: synchronizer, start-bit check, mid-bit sampling, stop-bit check |
| [`lib/fifo.v`](../../lib/fifo.v) | 16-entry FIFO |
| [`07_uart/top.v`](../../07_uart/top.v) | step 6's system plus the UART pins |
| [`07_uart/tangnano9k.cst`](../../07_uart/tangnano9k.cst) | `uart_tx` = pin 17, `uart_rx` = pin 18 (`LVCMOS33`) |
| [`07_uart/uart_tb.v`](../../07_uart/uart_tb.v) | UART alone, see below |
| [`07_uart/terminal_tb.v`](../../07_uart/terminal_tb.v) | whole system, see below |
| [`07_uart/uart.lushay.json`](../../07_uart/uart.lushay.json) | project; `baudRate` sets Lushay's serial console speed |

## The testbenches

**[`uart_tb.v`](../../07_uart/uart_tb.v)** - the UART modules alone (a few seconds):

1. loopback, transmitter -> receiver: all 256 byte values
2. a sender whose bit time is 2% too short, and 2% too long: all 256 bytes each
3. a glitch of a quarter bit on the line: ignored
4. a frame with a broken stop bit: dropped, and the next frame still arrives

**[`terminal_tb.v`](../../07_uart/terminal_tb.v)** - the whole system running
`07_terminal.c`, with the testbench playing the PC (about 100 s): it decodes
everything the board sends, types `Hi FPGA!`, Enter, `abx`, Backspace, `c`,
and checks the greeting arrived, the text was echoed, the HDMI screen shows
`Hi FPGA!` and `abc`, and the LEDs show the code of `c`. Then it types 80
numbered lines (L01..L80), one key per millisecond: the screen scrolls 58
times, once round the 51-row ring, and must end with L52 at the top, L80 at
the bottom and the scroll register at 7. The screen is printed in the log.

## Results

- `uart_tb`: **pass**. `terminal_tb`: **pass**.
- All earlier testbenches still pass after the SoC changes.
- Place-and-route (with scrollback): up to **62.7 MHz** (needs 25.2), 2,451 LUT4 (28%),
  537 flip-flops, 10 block RAMs, 34 LUT RAMs (2 more than step 6: the FIFO).

## Known limitation: pasting text

The echo sends more bytes back than arrive (Enter is echoed as `\r\n`,
Backspace as three bytes), and the CPU waits for each byte to be sent. When
text arrives at full line speed - pasted, not typed - the CPU falls behind,
the 16-byte receive FIFO fills up and characters are lost. Typing by hand is
far slower and never hits this. A fix would be a transmit FIFO plus a bigger
receive FIFO, or (later) interrupts.
