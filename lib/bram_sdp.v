// Simple dual-port block RAM: one write port, one read port.
//
// Written in the style synthesis tools recognize ("inference"): yosys sees
// an array with a registered read and maps it onto the GW1NR-9's block RAM
// (BSRAM) instead of building it from flip-flops. The chip has 26 BSRAM
// blocks of 18 Kbit each (16 Kbit used when the width is a power of 2).
//
//   - The read is synchronous: rdata shows mem[raddr] one clock AFTER raddr
//     is presented. Block RAM can't do a same-cycle (combinational) read, so
//     any design using it must plan for this 1-clock latency.
//   - The two ports may use different clocks (e.g. CPU writes, video reads).
//   - INIT_FILE (optional) preloads the contents with $readmemh, both in
//     simulation and in the bitstream. A RAM that is never written is a ROM.

module bram_sdp #(
    parameter WIDTH     = 8,
    parameter ADDR_BITS = 12,           // depth = 2^ADDR_BITS words
    parameter INIT_FILE = ""
) (
    // write port
    input  wire                 wclk,
    input  wire                 we,
    input  wire [ADDR_BITS-1:0] waddr,
    input  wire [WIDTH-1:0]     wdata,
    // read port
    input  wire                 rclk,
    input  wire [ADDR_BITS-1:0] raddr,
    output reg  [WIDTH-1:0]     rdata
);

    reg [WIDTH-1:0] mem [0:(1 << ADDR_BITS) - 1];

    // Without a file the RAM starts as all zeros - as the real block RAM does.
    // (Without this, simulation would start with unknown 'X' values.)
    integer i;
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
        else
            for (i = 0; i < (1 << ADDR_BITS); i = i + 1) mem[i] = 0;
    end

    always @(posedge wclk)
        if (we)
            mem[waddr] <= wdata;

    always @(posedge rclk)
        rdata <= mem[raddr];

endmodule
