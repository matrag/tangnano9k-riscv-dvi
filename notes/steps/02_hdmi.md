# Step 2 - Video test pattern (DVI)

[Notes index](../README.md) · Previous: [Step 1](01_pll.md) · Next: [Step 3 - Text mode](03_text.md)

**Folder:** [`02_hdmi`](../../02_hdmi) · **Status:** works on the board

## Goal

Get a picture on a monitor through the board's HDMI connector: 640 x 480 at
60 Hz, DVI signaling, generated entirely in logic.

## What it does

- Top two thirds: 8 vertical color bars (white, yellow, cyan, green, magenta, red, blue, black)
- Middle band: a grayscale ramp, black to white
- Bottom band: dark blue with an orange 32 x 32 square moving left and right, one pixel per frame
- A 1-pixel white border, to check the monitor doesn't crop the picture
- LED 5 = PLL locked, LED 0 blinks once per second (counted in frames)

There is **no memory**: every pixel's color is computed from its (x, y)
position while it is being sent ("racing the beam").

## What's new

See [Video](../video.md) for the full explanation.

- [`lib/video_timing.v`](../../lib/video_timing.v): the 800 x 525 counters, syncs, `de`, x/y
- [`lib/tmds_encoder.v`](../../lib/tmds_encoder.v): TMDS 8b/10b encoding (transition minimization + DC balance)
- [`lib/hdmi_out.v`](../../lib/hdmi_out.v): 3 encoders, 4 `OSER10` serializers, `ELVDS_OBUF` differential outputs
- The colors are registered one clock after being computed, so the syncs are
  delayed by the same clock to stay aligned with them.
- The square moves only at the start of a frame, so it never tears.

## Files

| File | Contents |
|---|---|
| [`top.v`](../../02_hdmi/top.v) | the test pattern |
| [`tangnano9k.cst`](../../02_hdmi/tangnano9k.cst) | HDMI pairs: clock 69/68, blue 71/70, green 73/72, red 75/74 |
| [`tmds_encoder_tb.v`](../../02_hdmi/tmds_encoder_tb.v) | encoder testbench: control words, every byte value decodes back, worst-case patterns, 5,000 random bytes, DC balance |
| [`hdmi.lushay.json`](../../02_hdmi/hdmi.lushay.json) | project, with the testbench listed |

## Results

- Encoder testbench: **pass**, maximum running imbalance 8.
- Place-and-route: pixel-clock logic up to **42.6 MHz** (needs 25.2). Each pair is
  placed as a real differential output (`DIFF_TYPE=ELVDS_OBUF`).

## Problems we hit

- Lushay: "Ports are missing from CST file: tmds_clk_n, ...". Then nextpnr:
  "Unconstrained IO: tmds_d_n_OBUF_O_2". Fix: list the `_n` pins in the `.cst`
  too. See [Gotchas](../gotchas.md#hdmi-pins-list-the-_n-pins-in-the-cst).
