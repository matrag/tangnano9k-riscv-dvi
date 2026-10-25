// TMDS 8b/10b encoder (DVI 1.0 spec, section 3.2)
//
// During the active area (de=1) each 8-bit color value becomes a 10-bit word:
//   1. Transition minimization: XOR or XNOR chain over the bits, chosen to
//      produce fewer 0/1 transitions -> 9 bits (bit 8 says which was used).
//   2. DC balance: optionally invert the low 8 bits (bit 9 says so), keeping a
//      running count of ones-minus-zeros near 0 so the link has no DC offset.
// During blanking (de=0) one of four fixed control tokens is sent instead,
// selected by ctrl (channel 0 carries {vsync, hsync}; channels 1 and 2 send 00).
//
// Output word layout:
//   bit 9    : 1 = bits 7..0 were inverted (DC balance)
//   bit 8    : 1 = XOR chain used, 0 = XNOR chain used
//   bits 7..0: the (possibly inverted) chain output
//
// Why bother? Data words built this way never contain more than 5 bit
// transitions, while the control tokens contain 7 or more. During blanking
// the receiver looks for those many-transition tokens in the serial stream
// to find where each 10-bit word starts - that is how it aligns to the link
// without any separate "word start" signal.
//
// Worked example, sending 0x00 twice:
//   1st 0x00: no ones -> XOR chain -> q_m = 1_0000_0000, cnt = 0
//             -> send 01_0000_0000 (1 one, 9 zeros)   cnt becomes -8
//   2nd 0x00: cnt < 0 and the word is mostly zeros -> invert
//             -> send 11_1111_1111 (10 ones)          cnt becomes +2
//   So even a black screen alternates and never drifts away from balance.
//
// Latency: 1 clock.

module tmds_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire [1:0] ctrl,
    input  wire       de,
    output reg  [9:0] tmds = 0
);

    // Number of ones in a byte (synthesizes to a small adder tree)
    function [3:0] ones8(input [7:0] b);
        ones8 = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + b[7];
    endfunction

    // ---- Stage 1: transition minimization -------------------------------
    // Each output bit is the previous OUTPUT bit combined with the next INPUT
    // bit. With XOR, a 1 in the input means "toggle"; with XNOR a 1 means
    // "stay". For bytes with many ones, XNOR gives fewer toggles, so the spec
    // picks XNOR when there are more than 4 ones (or exactly 4 and bit 0 = 0,
    // a tie-break rule from the spec).
    wire [3:0] n1_data  = ones8(data);
    wire       use_xnor = (n1_data > 4) || (n1_data == 4 && data[0] == 1'b0);

    wire [8:0] q_m;          // "q_m" is the spec's name for the 9-bit intermediate word
    assign q_m[0] = data[0];
    genvar i;
    generate
        for (i = 1; i < 8; i = i + 1) begin : chain
            assign q_m[i] = use_xnor ? ~(q_m[i-1] ^ data[i]) : (q_m[i-1] ^ data[i]);
        end
    endgenerate
    assign q_m[8] = ~use_xnor;   // tells the receiver which chain to undo

    // ---- Stage 2: DC balance --------------------------------------------
    wire [3:0] n1_q = ones8(q_m[7:0]);
    wire [3:0] n0_q = 4'd8 - n1_q;

    // ones minus zeros of q_m[7:0], as a signed number (-8..+8)
    wire signed [5:0] diff = $signed({2'b00, n1_q}) - $signed({2'b00, n0_q});

    // Running disparity: total ones minus total zeros sent on this lane since
    // the last blanking period. Positive = we have sent too many ones.
    // The testbench checks it stays small (it never exceeds +-8 in practice).
    reg signed [5:0] cnt = 0;

    // The three branches below are the DVI spec flowchart (Figure 3-5).
    // In every branch the cnt update equals the actual ones-minus-zeros of
    // the 10-bit word being sent, including bits 9 and 8.
    always @(posedge clk) begin
        if (rst) begin
            cnt  <= 0;
            tmds <= 10'b1101010100;
        end else if (!de) begin
            // Blanking: send a control token. These are fixed, DC balanced
            // patterns, so the disparity counter restarts from 0.
            cnt <= 0;
            case (ctrl)
                2'b00: tmds <= 10'b1101010100;
                2'b01: tmds <= 10'b0010101011;
                2'b10: tmds <= 10'b0101010100;
                2'b11: tmds <= 10'b1010101011;
            endcase
        end else if (cnt == 0 || n1_q == n0_q) begin
            // No history to correct, or the word is already balanced:
            // use bit 8 to decide inversion (keeps bits 9/8 as opposites, so
            // they add zero disparity).
            tmds[9]   <= ~q_m[8];
            tmds[8]   <=  q_m[8];
            tmds[7:0] <=  q_m[8] ? q_m[7:0] : ~q_m[7:0];
            cnt       <=  q_m[8] ? cnt + diff : cnt - diff;
        end else if ((cnt > 0 && n1_q > n0_q) || (cnt < 0 && n0_q > n1_q)) begin
            // too many ones (or zeros) already: invert to pull back toward 0
            tmds <= {1'b1, q_m[8], ~q_m[7:0]};
            cnt  <= cnt + $signed({4'b0, q_m[8], 1'b0}) - diff;
        end else begin
            // the word already pushes the disparity back toward 0: send as is
            tmds <= {1'b0, q_m[8], q_m[7:0]};
            cnt  <= cnt - $signed({4'b0, ~q_m[8], 1'b0}) + diff;
        end
    end

endmodule
