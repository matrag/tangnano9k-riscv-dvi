# Video: DVI over the HDMI connector, and text mode

[Back to the notes index](README.md)

## The path of a pixel

```
video_timing --> (x, y, de, syncs) --> text_mode --> (r, g, b) --> 3 x TMDS encoder --> 4 x OSER10 --> ELVDS_OBUF --> HDMI
 "where are we"                     "what color here"           "8 bits -> 10 bits"   "10:1 serial"   "P/N pair"
```

An HDMI cable carries 4 differential pairs: 3 data lanes (blue, green, red)
and 1 clock lane. Every pixel period, each data lane sends one 10-bit word.

## 640 x 480 at 60 Hz: the timing

Source: [`lib/video_timing.v`](../lib/video_timing.v)

A frame is bigger than the visible picture:

```
 one line, 800 pixel clocks:
 |<------ 640 visible ------>|<16 front porch>|<96 sync>|<48 back porch>|

 one frame, 525 lines:  480 visible | 10 front porch | 2 sync | 33 back porch
```

- 800 x 525 x 60 = **25.2 million pixels per second** -> the pixel clock.
  (The standard says 25.175 MHz; 25.2 MHz gives 60.06 Hz, accepted by every monitor.)
- The porches and sync pulses come from CRT monitors, which needed time to
  move the electron beam back. Digital monitors still use the syncs to find
  where lines and frames start; HDMI also uses the blanking time to send
  control words.
- Both syncs are active low in this mode.
- `de` ("data enable") is high only in the visible 640 x 480 area.

## Clocks for the video link

- Each lane sends 10 bits per pixel: 10 x 25.2 = **252 Mbit/s**.
- The `OSER10` serializer sends on both clock edges, so it needs 252 / 2 = **126 MHz**.
- The PLL makes 126 MHz (27 x 14 / 3); the dedicated `CLKDIV` block divides
  it by 5 to get 25.2 MHz. `CLKDIV` (rather than a counter in logic) keeps the
  two clocks phase-aligned, which the serializer needs.
- Source: [`lib/clocks.v`](../lib/clocks.v)

## TMDS encoding: 8 bits -> 10 bits

Source: [`lib/tmds_encoder.v`](../lib/tmds_encoder.v)

Two extra bits per byte, for two reasons:

1. **Transition minimization (bit 8).** The bits are chained with XOR or XNOR,
   whichever gives fewer 0/1 changes. Data words then never have more than 5
   transitions, while the 4 control words have 7 or more. The monitor finds
   where each 10-bit word starts by spotting control words during blanking.
2. **DC balance (bit 9).** A running count of ones-minus-zeros is kept; when
   it drifts, the low 8 bits are sent inverted. This keeps the average signal
   level in the middle.

Worked example, sending `0x00` twice:
- 1st: sent as `01_0000_0000` (1 one, 9 zeros) -> balance -8
- 2nd: sent inverted as `11_1111_1111` (10 ones) -> balance +2

During blanking (`de = 0`) one of 4 control words is sent instead. The blue
lane carries `{vsync, hsync}` this way: **HDMI has no sync wires**.

The testbench saw a maximum running imbalance of 8.

## Serializers and differential outputs

Source: [`lib/hdmi_out.v`](../lib/hdmi_out.v)

- `OSER10`: loads 10 bits per pixel clock, shifts them out over 5 cycles of
  126 MHz, 2 bits per cycle, **bit 0 first** (TMDS order).
- Clock lane: a 4th serializer sending the fixed word `0000011111` = a 25.2 MHz
  square wave, aligned with the data because it goes through the same path.
- `ELVDS_OBUF`: "emulated LVDS" - two ordinary 3.3 V outputs, one inverted
  (`IO_TYPE=LVCMOS33D`). The Tang Nano 9K is wired for this.
- This is plain **DVI** signaling (HDMI without audio and InfoFrames); every
  HDMI monitor accepts it. It is not an HDMI implementation and not an
  HDMI-certified product; "HDMI" in this project names the board's connector
  (and, for history, the folder `02_hdmi` and the module `hdmi_out`).

## Text mode: 80 x 30 characters

Source: [`lib/text_mode.v`](../lib/text_mode.v)

The screen is a grid of 80 x 30 cells, each 8 x 16 pixels. Instead of storing
every pixel, it stores **which character** is in each cell and looks up its
pixels in a font while the line is drawn - the way the IBM PC's VGA text mode
worked.

| Approach | Memory | Fits in 468 Kbit of block RAM? |
|---|---|---|
| Framebuffer, 640 x 480, 24-bit color | 7,372 Kbit | no |
| Framebuffer, 640 x 480, 1 bit per pixel | 307 Kbit | barely |
| **Text mode** (2,400 cells x 16 bit + 4 KB font) | **70 Kbit** | yes, ~15% |

### Two memories

| Memory | Size | Changes? | Contents |
|---|---|---|---|
| Character RAM | 4096 x 16 bit (2,400 for the screen; up to 4,080 with scrollback) | yes - written by the CPU | per cell: character code (bits 7..0), foreground color (11..8), background color (15..12) |
| Font ROM | 4096 x 8 bit | never | 256 characters x 16 rows; bit 7 = leftmost pixel |

The font is **Spleen 8x16** (BSD-2-Clause, by Frederic Cambus), converted by
[`tools/bdf2hex.py`](../tools/bdf2hex.py) to the IBM PC character set (code
page 437), so box-drawing, shading and symbol characters are available. Its
license is in [`tools/font/LICENSE-spleen`](../tools/font/LICENSE-spleen).
Three code page 437 symbols (0x10, 0x11, 0x1C) don't exist in Spleen and are blank.

### The pipeline

Each block RAM read takes one clock, so the color for pixel (x, y) is worked
out in stages:

```
stage 0: (x, y)  -> which cell? address = row*80 + col  -> character RAM read starts
stage 1: cell    -> font address = char*16 + (y mod 16)   -> font ROM read starts
stage 2: font row-> pick bit (7 - x mod 8) -> foreground or background color
stage 3: rgb out (registered)
```

Everything a later stage needs about (x, y) - the low bits of x and y, `de`,
the syncs - is carried along in registers, so it arrives together with the
memory data. Total delay: 3 clocks. If one of these delays were wrong by a
clock, every character would shift by a pixel; the step 3 testbench checks
exactly this.

### Colors

The 16-color CGA palette: black, blue, green, cyan, red, magenta, brown,
light gray, then the bright versions of each (dark gray ... white).

### Hardware scrolling

The character RAM is used as a **ring of rows** - 30 in step 6, 51 in step 7.
The `scroll` input says which RAM row is shown at the top of the screen:
screen row r shows RAM row (r + scroll) mod ring size.

To scroll the whole screen up by one line, software adds 1 to `scroll` and
clears the row that just appeared at the bottom: **80 writes instead of moving
all 2,400 cells**. See [`sw/console.c`](../sw/console.c).

The ring size is a parameter (`RING_ROWS`). With 30 (step 6) the ring is just
the screen. With up to 51 (step 7: 51 x 80 = 4,080 of the 4,096 cells) the extra
rows keep the lines that scrolled off the top - a **scrollback** - and `scroll - 1`
brings them back. See [Step 7 - Scrollback](steps/07_uart.md#scrollback).
