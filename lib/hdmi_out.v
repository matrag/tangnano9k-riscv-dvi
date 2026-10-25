// DVI transmitter for the board's HDMI connector: RGB + syncs in, 4 differential TMDS pairs out
//
//   pixel domain (25.2 MHz)                          serial domain (126 MHz, both edges)
//   r,g,b,hsync,vsync,de --> 3x tmds_encoder --> 10 bits --> OSER10 --> ELVDS_OBUF --> pins
//
// Each pair runs at 10 bits x 25.2 MHz = 252 Mbit/s.
//
// OSER10 is a 10:1 serializer: it takes a 10-bit word every PCLK (pixel clock)
// and shifts it out on both edges of FCLK (5x pixel clock), LSB (D0) first,
// which is the bit order TMDS expects.
//
//   clk_pix  : |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|____________________|   one pixel = one 10-bit word
//   clk_tmds : |‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|              5 cycles, 2 bits each
//   Q        :  D0 D1 D2 D3 D4 D5 D6 D7 D8 D9
//
// The TMDS clock pair just carries the pixel clock, sent as the fixed
// pattern 0000011111 through the same kind of serializer so it stays aligned
// with the data pairs. Five 0s then five 1s per pixel = a 25.2 MHz square
// wave. The monitor multiplies it by 10 internally to sample the data lanes.
//
// This is plain DVI signaling, which every HDMI sink accepts. No audio or
// InfoFrames (those need HDMI data islands, not needed here).
//
// Where the syncs go: there are no hsync/vsync wires in HDMI. They travel on
// the blue lane as control tokens during blanking (see tmds_encoder.v).

module hdmi_out (
    input  wire       clk_pix,     // 25.2 MHz
    input  wire       clk_tmds,    // 126 MHz, phase aligned with clk_pix (from CLKDIV)
    input  wire       rst,         // synchronous to clk_pix
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    input  wire       hsync,
    input  wire       vsync,
    input  wire       de,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    // Four 10-bit words packed in one bus: [9:0] blue, [19:10] green, [29:20] red, [39:30] clock
    // (the lane order blue=0, green=1, red=2 is fixed by the DVI spec)
    wire [39:0] words;

    // All three encoders have the same 1-clock latency, so the three color
    // lanes and the syncs (carried by the blue encoder) stay aligned.

    tmds_encoder enc_b (.clk(clk_pix), .rst(rst), .data(b), .ctrl({vsync, hsync}), .de(de), .tmds(words[9:0]));
    tmds_encoder enc_g (.clk(clk_pix), .rst(rst), .data(g), .ctrl(2'b00),          .de(de), .tmds(words[19:10]));
    tmds_encoder enc_r (.clk(clk_pix), .rst(rst), .data(r), .ctrl(2'b00),          .de(de), .tmds(words[29:20]));
    assign words[39:30] = 10'b0000011111;

    // Single-ended serial bit streams, one per lane (0..2 data, 3 clock)
    wire [3:0] serial;

    // One OSER10 per lane. OSER10 is a hard block in the IO logic next to the
    // pin, not built from LUTs, which is what lets it run at 252 Mbit/s.
    // PCLK = parallel load clock, FCLK = fast shift clock (must be 5x PCLK).
    // `words[i*10 + k]` picks bit k of lane i out of the packed bus.
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : ser
            OSER10 oser (
                .Q    (serial[i]),
                .D0   (words[i*10 + 0]),
                .D1   (words[i*10 + 1]),
                .D2   (words[i*10 + 2]),
                .D3   (words[i*10 + 3]),
                .D4   (words[i*10 + 4]),
                .D5   (words[i*10 + 5]),
                .D6   (words[i*10 + 6]),
                .D7   (words[i*10 + 7]),
                .D8   (words[i*10 + 8]),
                .D9   (words[i*10 + 9]),
                .PCLK (clk_pix),
                .FCLK (clk_tmds),
                .RESET(rst)
            );
        end
    endgenerate

    // Emulated LVDS output buffers: drive the _p and _n pins in opposite phase.
    // "Emulated" = two ordinary 3.3 V outputs, one inverted (IO_TYPE=LVCMOS33D
    // in the .cst), instead of a true current-mode TMDS driver. The Tang Nano
    // 9K's HDMI connector is wired for this, and it works fine at 252 Mbit/s.
    // In the .cst both pins of each pair must be listed (e.g. 69,68 and 68)
    // or nextpnr reports the _n side as unconstrained.
    ELVDS_OBUF buf_clk (.I(serial[3]), .O(tmds_clk_p),  .OB(tmds_clk_n));
    ELVDS_OBUF buf_d0  (.I(serial[0]), .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
    ELVDS_OBUF buf_d1  (.I(serial[1]), .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
    ELVDS_OBUF buf_d2  (.I(serial[2]), .O(tmds_d_p[2]), .OB(tmds_d_n[2]));

endmodule
