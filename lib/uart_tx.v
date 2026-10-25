// UART transmitter, 8N1 (8 data bits, no parity, 1 stop bit)
//
// A UART sends each byte as a "frame" on one wire, with no clock wire:
//
//   idle  start  bit0 bit1 bit2 bit3 bit4 bit5 bit6 bit7  stop  idle
//   ‾‾‾‾‾\_____/‾‾‾‾\____/ ...                        /‾‾‾‾‾‾‾‾‾‾‾‾
//          0     data bits, least significant first      1
//
// Every bit lasts exactly 1/BAUD seconds = DIV clock cycles. The line rests
// at 1; the 0 start bit tells the receiver "a byte begins now".
//
// Usage: when `busy` is low, pulse `start` for one clock with the byte on
// `data`. `busy` stays high for the 10 bit times of the frame.

module uart_tx #(
    parameter CLK_HZ = 25_200_000,
    parameter BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       start,
    output wire       busy,
    output wire       tx
);

    // Clock cycles per bit, rounded to the nearest whole number
    // (25.2 MHz / 115200 = 218.75 -> 219, an error of 0.1%)
    localparam DIV = (CLK_HZ + BAUD / 2) / BAUD;

    // The frame is loaded into a shift register and sent from bit 0 upwards.
    // When idle the register holds all ones, so `tx` (= bit 0) rests at 1.
    // It comes straight from a flip-flop, so the line never glitches.
    reg [9:0]               shift     = 10'h3FF;
    reg [3:0]               bits_left = 0;      // bits of the frame still to send
    reg [$clog2(DIV)-1:0]   cnt       = 0;      // clock cycles within the current bit

    assign busy = (bits_left != 0);
    assign tx   = shift[0];

    always @(posedge clk) begin
        if (rst) begin
            shift     <= 10'h3FF;
            bits_left <= 0;
        end else if (!busy) begin
            if (start) begin
                shift     <= {1'b1, data, 1'b0};    // stop bit, data, start bit
                bits_left <= 10;
                cnt       <= 0;
            end
        end else if (cnt == DIV - 1) begin
            cnt       <= 0;
            shift     <= {1'b1, shift[9:1]};        // next bit; shift in idle ones
            bits_left <= bits_left - 1'b1;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule
