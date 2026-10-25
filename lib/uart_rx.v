// UART receiver, 8N1 - the other half of uart_tx.v
//
// There is no clock wire, so the receiver times the bits itself:
//
//   rx    ‾‾‾‾\_____/‾‾‾‾\____/ ... /‾‾‾‾‾‾
//             ^  ^      ^      ^         ^
//             |  |      |      |         sample the stop bit (must be 1)
//             |  |      sample each data bit in its MIDDLE, 1 bit time apart
//             |  half a bit later: still 0? then it's a real start bit
//             falling edge = start of a frame
//
// Sampling in the middle of each bit gives the most margin: the sender's
// and receiver's clocks may differ by a few percent, and the error adds up
// over the 10 bits of a frame. Because every frame starts with its own start
// bit, the receiver re-synchronizes on every byte, so the error never grows
// beyond one frame. In practice about +-2% total error is safe.
//
// Output: `valid` is high for one clock with the received byte on `data`.
// A frame whose stop bit is 0 (a framing error) is thrown away.

module uart_rx #(
    parameter CLK_HZ = 25_200_000,
    parameter BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,              // straight from the pin
    output reg  [7:0] data  = 0,
    output reg        valid = 0
);

    localparam DIV = (CLK_HZ + BAUD / 2) / BAUD;

    // The pin can change at any moment: two flip-flops in a row before
    // using it (synchronizer, as for the buttons). Rests at 1.
    reg [1:0] rx_sync = 2'b11;
    always @(posedge clk) rx_sync <= {rx_sync[0], rx};
    wire rx_s = rx_sync[1];

    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]             state = S_IDLE;
    reg [$clog2(DIV)-1:0] cnt   = 0;
    reg [2:0]             bitn  = 0;       // which data bit, 0..7
    reg [7:0]             shift = 0;

    always @(posedge clk) begin
        valid <= 0;
        if (rst) begin
            state <= S_IDLE;
        end else case (state)
            S_IDLE:
                if (!rx_s) begin                       // falling edge: maybe a start bit
                    cnt   <= 0;
                    state <= S_START;
                end
            S_START:                                   // wait half a bit, check it again
                if (cnt == DIV / 2 - 1) begin
                    cnt   <= 0;
                    bitn  <= 0;
                    state <= rx_s ? S_IDLE : S_DATA;   // back to 1 = just a glitch
                end else
                    cnt <= cnt + 1'b1;
            S_DATA:                                    // one bit time later = middle of a data bit
                if (cnt == DIV - 1) begin
                    cnt   <= 0;
                    shift <= {rx_s, shift[7:1]};       // least significant bit comes first
                    bitn  <= bitn + 1'b1;
                    if (bitn == 7) state <= S_STOP;
                end else
                    cnt <= cnt + 1'b1;
            S_STOP:                                    // middle of the stop bit
                if (cnt == DIV - 1) begin
                    if (rx_s) begin                    // stop bit must be 1
                        data  <= shift;
                        valid <= 1;
                    end
                    state <= S_IDLE;
                end else
                    cnt <= cnt + 1'b1;
        endcase
    end

endmodule
