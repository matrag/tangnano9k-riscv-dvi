// Step 8 - serial bootloader: load programs over USB without rebuilding the FPGA
//
// Step 7's system (CPU, text screen with scrollback, UART) plus a 2 KB boot
// ROM. The CPU now starts in the boot ROM (RESET_PC = 0x3000_0000):
//
//   reset (power-up or S1) --> bootloader (sw/08_boot.c, boot.hex) waits 1 s on the UART
//        |-- upload arrives and its CRC is right --> runs the uploaded program
//        '-- nothing arrives -----------------------> runs the program already in RAM
//
// The RAM is preloaded with step 7's terminal (../07_uart/terminal.hex), so
// without a PC the board behaves like step 7 - one second later.
// Upload from the PC:  make upload PROG=07_terminal   (in sw/), then press S1.
//
// LEDs: LED 0 on = bootloader running, LED 1 flickers while loading; then
//       whatever the program shows. All on = the CPU trapped.

module top (
    input  wire       clk,          // 27 MHz
    input  wire       btn1,         // S1, active low: reset
    input  wire       btn2,         // S2, active low: read by the program
    output wire [5:0] led,          // active low
    output wire       uart_tx,      // to the PC
    input  wire       uart_rx,      // from the PC
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    // ---- Clocks and reset (as in step 6) ----------------------------------------
    wire clk_tmds, clk_pix, lock;

    clocks clocks_i (.clk_27(clk), .clk_tmds(clk_tmds), .clk_pix(clk_pix), .lock(lock));

    wire rst_async = !btn1 || !lock;
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_pix or posedge rst_async)
        if (rst_async) rst_sync <= 2'b11;
        else           rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    reg [1:0] btn2_sync = 2'b00;
    always @(posedge clk_pix) btn2_sync <= {btn2_sync[0], !btn2};

    // ---- CPU system + text screen + UART + boot ROM --------------------------------
    wire [7:0]  leds;
    wire        trap;
    wire [23:0] rgb;
    wire        hsync, vsync, de;

    soc_text #(
        .PROGRAM("../07_uart/terminal.hex"),    // RAM contents at power-up
        .FONT_FILE("../03_text/font.hex"),
        .RING_ROWS(51),
        .HAS_BOOT_ROM(1),
        .BOOT_PROGRAM("boot.hex"),              // the bootloader
        .RESET_PC(32'h3000_0000)                // start in the boot ROM
    ) sys (
        .clk(clk_pix), .rst(rst),
        .buttons({7'b0, btn2_sync[1]}), .leds(leds), .trap(trap),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
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
