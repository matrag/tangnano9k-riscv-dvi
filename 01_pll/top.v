// Step 1 - PLL clocking test for the Tang Nano 9K
//
// Three LEDs blink at 1 Hz, each from a different clock domain:
//   led[0] : 27 MHz board clock   (reference)
//   led[1] : 126 MHz PLL output
//   led[2] : 25.2 MHz divided pixel clock
//   led[5] : on while the PLL is locked
//
// If the PLL and divider produce the frequencies we expect, LEDs 0..2 blink
// together and stay in step. A wrong frequency shows up as one LED drifting
// away from the others (or blinking at a different rate).
// Hold S1 to reset; on release all three restart in phase.

module top (
    input  wire       clk,    // 27 MHz
    input  wire       btn1,   // S1, active low
    output wire [5:0] led     // active low
);

    wire clk_tmds, clk_pix, lock;

    clocks clocks_i (
        .clk_27  (clk),
        .clk_tmds(clk_tmds),
        .clk_pix (clk_pix),
        .lock    (lock)
    );

    // The PLL clocks are only valid once locked, so keep them in reset until then
    wire rst_async = !btn1 || !lock;

    wire [2:0] blink;

    blinker #(.HALF_PERIOD(27_000_000  / 2)) b27  (.clk(clk),      .rst_async(!btn1),    .out(blink[0]));
    blinker #(.HALF_PERIOD(126_000_000 / 2)) b126 (.clk(clk_tmds), .rst_async(rst_async), .out(blink[1]));
    blinker #(.HALF_PERIOD(25_200_000  / 2)) b25  (.clk(clk_pix),  .rst_async(rst_async), .out(blink[2]));

    // Active low LEDs
    assign led = ~{lock, 2'b00, blink};

endmodule

// Toggles `out` every HALF_PERIOD clock cycles.
// The asynchronous reset is synchronized into this clock domain first, so
// releasing it never happens close to a clock edge (avoids metastability).
module blinker #(
    parameter HALF_PERIOD = 1
) (
    input  wire clk,
    input  wire rst_async,
    output reg  out = 0
);

    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk or posedge rst_async)
        if (rst_async) rst_sync <= 2'b11;
        else           rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    reg [$clog2(HALF_PERIOD)-1:0] cnt = 0;

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 0;
            out <= 0;
        end else if (cnt == HALF_PERIOD - 1) begin
            cnt <= 0;
            out <= ~out;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule
