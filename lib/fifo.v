// Small first-in first-out buffer (FIFO)
//
// Used behind the UART receiver: bytes arrive whenever the PC sends them,
// and the CPU may be busy for a moment (e.g. scrolling the screen). The FIFO
// holds up to DEPTH bytes until the CPU reads them, so none are lost.
//
//   push side (writer)                       pop side (reader)
//   din, push --> [ ][ ][ ][ ][ ] ... --> dout (oldest entry), pop
//                  ^wptr          ^rptr
//
// The pointers are one bit wider than needed to address DEPTH entries. The
// extra bit tells "full" from "empty" when both pointers point at the same
// slot: same extra bit = empty, different = the writer has gone round once
// more than the reader = full.
//
// `dout` always shows the oldest entry (when not empty); `pop` removes it.
// Pushing when full is ignored (the byte is lost).

module fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH_BITS = 4              // DEPTH = 2^4 = 16 entries
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] din,
    input  wire             push,
    input  wire             pop,
    output wire [WIDTH-1:0] dout,
    output wire             empty,
    output wire             full
);

    reg [WIDTH-1:0]    mem [0:(1 << DEPTH_BITS) - 1];
    reg [DEPTH_BITS:0] wptr = 0;
    reg [DEPTH_BITS:0] rptr = 0;

    assign empty = (wptr == rptr);
    assign full  = (wptr[DEPTH_BITS-1:0] == rptr[DEPTH_BITS-1:0]) &&
                   (wptr[DEPTH_BITS] != rptr[DEPTH_BITS]);
    assign dout  = mem[rptr[DEPTH_BITS-1:0]];

    always @(posedge clk) begin
        if (rst) begin
            wptr <= 0;
            rptr <= 0;
        end else begin
            if (push && !full) begin
                mem[wptr[DEPTH_BITS-1:0]] <= din;
                wptr <= wptr + 1'b1;
            end
            if (pop && !empty)
                rptr <= rptr + 1'b1;
        end
    end

endmodule
