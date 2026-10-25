// Step 2 - video test pattern, 640x480 @ 60 Hz, DVI through the HDMI connector
//
// Screen layout:
//   y   0..319 : 8 vertical color bars (white, yellow, cyan, green, magenta, red, blue, black)
//   y 320..399 : grayscale ramp, black on the left to white on the right
//   y 400..479 : dark blue band with a 32x32 orange square moving left/right, one
//                pixel per frame (shows the image is live, about 10 s per trip)
//   1-pixel white border around the whole frame (checks nothing is cropped)
//
// LEDs: led[5] = PLL locked, led[0] = blinks once per second from the frame rate
// S1 = reset
//
// Data flow (all in the 25.2 MHz pixel clock domain except the serializers):
//
//   video_timing --(x, y, de, syncs)--> pattern logic --(rgb)--> register --> hdmi_out
//                                          ^
//                    square position, updated once per frame
//
// The pattern is computed fresh for every pixel from (x, y): there is no
// frame buffer. That is how early video hardware worked too ("racing the
// beam"), and it needs almost no memory. Step 3 will add a small character
// buffer in block RAM for text.

module top (
    input  wire       clk,          // 27 MHz
    input  wire       btn1,         // S1, active low
    output wire [5:0] led,          // active low
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    // ---- Clocks and reset -----------------------------------------------
    wire clk_tmds, clk_pix, lock;

    clocks clocks_i (.clk_27(clk), .clk_tmds(clk_tmds), .clk_pix(clk_pix), .lock(lock));

    // Reset synchronized into the pixel clock domain.
    // The button and PLL lock are not related to clk_pix's timing. If reset
    // were released right at a clock edge, some flip-flops might leave reset
    // a cycle before others (or go metastable). So: assert immediately
    // (asynchronously), but release only after passing through two
    // flip-flops clocked by clk_pix. Also stay in reset until the PLL locks,
    // because its clocks are not reliable before that.
    wire rst_async = !btn1 || !lock;
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_pix or posedge rst_async)
        if (rst_async) rst_sync <= 2'b11;
        else           rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    // ---- Timing ---------------------------------------------------------
    wire       hsync, vsync, de, frame_start;
    wire [9:0] x, y;

    video_timing timing (
        .clk(clk_pix), .rst(rst),
        .hsync(hsync), .vsync(vsync), .de(de),
        .x(x), .y(y), .frame_start(frame_start)
    );

    // ---- Moving square position (updates once per frame) ----------------
    // Updating only on frame_start means the square never moves while a
    // frame is being drawn, so it can't tear (top half at the old position,
    // bottom half at the new one). It bounces between x = 1 and the right
    // border, staying inside the 1-pixel white frame.
    localparam SQ = 32;
    reg [9:0] sq_x   = 1;
    reg       sq_dir = 0;     // 0 = moving right

    always @(posedge clk_pix) begin
        if (rst) begin
            sq_x   <= 1;
            sq_dir <= 0;
        end else if (frame_start) begin
            if (!sq_dir) begin
                if (sq_x == 640 - SQ - 2) sq_dir <= 1;
                else                      sq_x   <= sq_x + 1'b1;
            end else begin
                if (sq_x == 1)            sq_dir <= 0;
                else                      sq_x   <= sq_x - 1'b1;
            end
        end
    end

    // ---- Pattern --------------------------------------------------------
    // Gray level 0..255 across 640 pixels: x * 409 / 1024 (639 * 409 / 1024 = 255).
    // Dividing by 1024 is free in hardware (just take the upper bits), so
    // "multiply by a constant, then shift" replaces the x * 256 / 640 division.
    // A multiply by a constant needs no real multiplier: synthesis turns it
    // into a few shifted additions (409 = 256 + 128 + 16 + 8 + 1).
    wire [18:0] gray_full = x * 9'd409;
    wire [7:0]  gray      = gray_full[17:10];

    // Bar index 0..7, each bar 80 pixels wide
    wire [2:0] bar = (x < 80)  ? 3'd0 : (x < 160) ? 3'd1 : (x < 240) ? 3'd2 : (x < 320) ? 3'd3 :
                     (x < 400) ? 3'd4 : (x < 480) ? 3'd5 : (x < 560) ? 3'd6 : 3'd7;

    // Combinational color lookup: rgb_next is the color of pixel (x, y).
    // Colors are 24-bit 0xRRGGBB. The if/else order is the priority: the
    // border wins over everything, then the bands from top to bottom.
    reg [23:0] rgb_next;
    always @(*) begin
        if (x == 0 || x == 639 || y == 0 || y == 479)
            rgb_next = 24'hFFFFFF;                                  // border
        else if (y < 320) begin
            case (bar)
                3'd0: rgb_next = 24'hFFFFFF;   // white
                3'd1: rgb_next = 24'hFFFF00;   // yellow
                3'd2: rgb_next = 24'h00FFFF;   // cyan
                3'd3: rgb_next = 24'h00FF00;   // green
                3'd4: rgb_next = 24'hFF00FF;   // magenta
                3'd5: rgb_next = 24'hFF0000;   // red
                3'd6: rgb_next = 24'h0000FF;   // blue
                3'd7: rgb_next = 24'h000000;   // black
            endcase
        end else if (y < 400)
            rgb_next = {gray, gray, gray};
        else if (x >= sq_x && x < sq_x + SQ && y >= 424 && y < 424 + SQ)
            rgb_next = 24'hFF8000;                                  // orange square
        else
            rgb_next = 24'h000040;                                  // dark blue
    end

    // Register the pixel, and delay the syncs by the same 1 clock to stay aligned.
    // Registering breaks the long combinational path (compare x/y -> mux ->
    // encoder) into two shorter ones, which helps timing. But it means the
    // color for pixel N comes out one clock after video_timing says "pixel N",
    // so hsync/vsync/de get one register too. If they didn't, every line
    // would be shifted by one pixel relative to the syncs.
    // Outside the visible area the color is forced to black; the encoder
    // ignores it there anyway (it sends control tokens when de=0).
    reg [23:0] rgb = 0;
    reg        hsync_d = 1, vsync_d = 1, de_d = 0;
    always @(posedge clk_pix) begin
        rgb     <= de ? rgb_next : 24'h000000;
        hsync_d <= hsync;
        vsync_d <= vsync;
        de_d    <= de;
    end

    // ---- HDMI output ----------------------------------------------------
    hdmi_out hdmi (
        .clk_pix(clk_pix), .clk_tmds(clk_tmds), .rst(rst),
        .r(rgb[23:16]), .g(rgb[15:8]), .b(rgb[7:0]),
        .hsync(hsync_d), .vsync(vsync_d), .de(de_d),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    // ---- LEDs -----------------------------------------------------------
    // Toggle led[0] every 30 frames: at 60 Hz that is on 0.5 s, off 0.5 s,
    // so a 1 Hz blink confirms the frame rate without any instrument.
    reg [5:0] frames = 0;
    reg       beat   = 0;
    always @(posedge clk_pix)
        if (frame_start) begin
            if (frames == 29) begin
                frames <= 0;
                beat   <= ~beat;
            end else
                frames <= frames + 1'b1;
        end

    // {led5, led4..led1, led0}, inverted because the LEDs are active low
    assign led = ~{lock, 4'b0000, beat};

endmodule
