// Step 5 - the rv32i_core on the board, running sw/05_leds.c
//
//   27 MHz --> soc (CPU + 8 KB RAM + IO) --> LEDS register --> 6 LEDs
//                 ^
//   S2 -----------+ BUTTONS register        S1 = reset
//
// The CPU runs directly on the 27 MHz board clock; no PLL is needed yet
// (Step 6 will move it to the 25.2 MHz pixel clock, to share the text RAM).
// The program is baked into the bitstream: leds.hex preloads the RAM, so
// after a rebuild of the software (make in sw/) the FPGA must be rebuilt too.
//
// If the CPU ever traps (illegal instruction, ECALL, EBREAK), all six LEDs
// light up, so a crashed program is easy to tell apart from a running one.

module top (
    input  wire       clk,          // 27 MHz
    input  wire       btn1,         // S1, active low: reset
    input  wire       btn2,         // S2, active low: read by the program
    output wire [5:0] led           // active low
);

    // ---- Reset: same synchronizer as before ----------------------------------
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk or negedge btn1)
        if (!btn1) rst_sync <= 2'b11;
        else       rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    // ---- Button S2 into the clock domain -----------------------------------
    // The button can change at any moment; two flip-flops in a row give the
    // first one a whole clock to settle if it samples during a change
    // (metastability), before the CPU sees the value.
    reg [1:0] btn2_sync = 2'b00;
    always @(posedge clk) btn2_sync <= {btn2_sync[0], !btn2};   // 1 = pressed

    // ---- The SoC --------------------------------------------------------------
    wire [7:0] leds;
    wire       trap;
    wire       ext_valid;

    soc #(.PROGRAM("leds.hex"), .RAM_ADDR_BITS(11), .CLK_HZ(27_000_000)) soc_i (
        .clk(clk), .rst(rst),
        .leds(leds), .buttons({7'b0, btn2_sync[1]}),
        .trap(trap),
        .uart_tx(), .uart_rx(1'b1),          // serial port not used in this step
        // nothing on the external bus: answer at once so a stray access can't hang
        .ext_valid(ext_valid), .ext_addr(), .ext_wdata(), .ext_wstrb(),
        .ext_ready(ext_valid), .ext_rdata(32'd0),
        .done(), .exit_code()
    );

    // Active low LEDs; all on if the CPU has stopped
    assign led = trap ? 6'b000000 : ~leds[5:0];

endmodule
