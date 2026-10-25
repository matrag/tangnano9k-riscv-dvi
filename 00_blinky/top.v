// Step 0 - Blinky for the Tang Nano 9K
//
// Shows a 6-bit binary counter on the 6 onboard LEDs, advancing ~4 times/s.
// Hold button S1 to reset the counter to 0.
//
// Board facts used here:
//   - clk   : 27 MHz crystal oscillator
//   - led   : active LOW (driving 0 turns the LED on)
//   - btn1  : S1, active LOW (pressed = 0), has a pull-up in the .cst

module top (
    input  wire       clk,    // 27 MHz
    input  wire       btn1,   // S1, active low -> reset
    output wire [5:0] led     // active low
);

    localparam CLK_HZ  = 27_000_000;
    localparam TICK_HZ = 4;                       // LED counter steps per second
    localparam DIV     = CLK_HZ / TICK_HZ;        // 6_750_000 clocks per step

    // 23 bits is enough to count to 6_750_000 (2^23 = 8_388_608)
    reg [22:0] div_cnt = 0;
    reg [5:0]  count   = 0;

    always @(posedge clk) begin
        if (!btn1) begin
            div_cnt <= 0;
            count   <= 0;
        end else if (div_cnt == DIV - 1) begin
            div_cnt <= 0;
            count   <= count + 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    // Invert because the LEDs are active low: a '1' bit in count = LED on
    assign led = ~count;

endmodule
