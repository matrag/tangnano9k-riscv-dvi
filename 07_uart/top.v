// Step 7 - UART: talk to the PC over the board's USB connector
//
// Same system as step 6, plus the serial port. The board's USB chip (a
// BL702) appears on the PC as a COM port and is wired to two FPGA pins:
//
//   PC terminal <--USB--> BL702 <--- uart_tx (pin 17) --- soc_text (UART in lib/soc.v)
//                               ---- uart_rx (pin 18) --->
//
// The program is sw/07_terminal.c (terminal.hex): typed characters appear on
// the HDMI screen and are echoed back to the PC.
//
// LEDs: code of the last character received; all on = the CPU trapped.
// S1 = reset, S2 = sends a message.

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

    // ---- CPU system + text screen + UART ----------------------------------------
    // (uart_rx is synchronized inside the UART receiver)
    wire [7:0]  leds;
    wire        trap;
    wire [23:0] rgb;
    wire        hsync, vsync, de;

    // RING_ROWS 51: the character RAM keeps 21 lines that scrolled off the top,
    // so the terminal can scroll back (Backspace at the start of a line)
    soc_text #(.PROGRAM("terminal.hex"), .FONT_FILE("../03_text/font.hex"), .RING_ROWS(51)) sys (
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
