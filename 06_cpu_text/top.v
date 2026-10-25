// Step 6 - the CPU writes text to the HDMI screen
//
//   27 MHz -> clocks -> 25.2 MHz pixel clock --> soc_text (CPU + RAM + IO + text screen)
//                    \-> 126 MHz -----------.          | rgb, syncs
//                                            v          v
//                                          hdmi_out ---------> HDMI connector
//
// The CPU now runs on the pixel clock (25.2 MHz instead of 27 MHz), so it
// shares one clock with the video and can write the character RAM directly.
// The program is sw/06_text.c (text.hex); the font comes from step 3.
//
// LEDs: show the LEDS register (the program counts seconds on them);
//       all on = the CPU trapped.
// S1 = reset (CPU and video), S2 = read by the program.

module top (
    input  wire       clk,          // 27 MHz
    input  wire       btn1,         // S1, active low: reset
    input  wire       btn2,         // S2, active low: read by the program
    output wire [5:0] led,          // active low
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    // ---- Clocks and reset ---------------------------------------------------
    wire clk_tmds, clk_pix, lock;

    clocks clocks_i (.clk_27(clk), .clk_tmds(clk_tmds), .clk_pix(clk_pix), .lock(lock));

    wire rst_async = !btn1 || !lock;
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_pix or posedge rst_async)
        if (rst_async) rst_sync <= 2'b11;
        else           rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    // S2 into the pixel clock domain (two flip-flops against metastability)
    reg [1:0] btn2_sync = 2'b00;
    always @(posedge clk_pix) btn2_sync <= {btn2_sync[0], !btn2};

    // ---- CPU system + text screen ---------------------------------------------
    wire [7:0]  leds;
    wire        trap;
    wire [23:0] rgb;
    wire        hsync, vsync, de;

    soc_text #(.PROGRAM("text.hex"), .FONT_FILE("../03_text/font.hex")) sys (
        .clk(clk_pix), .rst(rst),
        .buttons({7'b0, btn2_sync[1]}), .leds(leds), .trap(trap),
        .uart_tx(), .uart_rx(1'b1),          // serial port not used in this step
        .rgb(rgb), .hsync(hsync), .vsync(vsync), .de(de),
        .done(), .exit_code()
    );

    // ---- HDMI output ------------------------------------------------------------
    hdmi_out hdmi (
        .clk_pix(clk_pix), .clk_tmds(clk_tmds), .rst(rst),
        .r(rgb[23:16]), .g(rgb[15:8]), .b(rgb[7:0]),
        .hsync(hsync), .vsync(vsync), .de(de),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    assign led = trap ? 6'b000000 : ~leds[5:0];

endmodule
