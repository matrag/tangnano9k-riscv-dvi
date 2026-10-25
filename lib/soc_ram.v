// Program/data RAM for the CPU: 32-bit wide block RAM with byte write enables,
// speaking the rv32i_core bus handshake.
//
// The CPU raises `valid` (already qualified by the address decoder, so it
// means "this access is for me") and waits. One clock later the RAM has
// done the read or write and raises `ready` for exactly one clock:
//
//   clk     _/‾\_/‾\_/‾\_/‾\_
//   valid   _/‾‾‾‾‾‾‾\_______      (CPU drops valid when it sees ready)
//   ready   _____/‾‾‾\_______
//   rdata   -----< D >-------
//
// The `!ready` condition stops a second access from starting in the clock
// where ready is high (valid is still high in that clock).
//
// INIT_FILE preloads the program: one 32-bit hex word per line, word 0 first
// (made by tools/bin2hex.py from the compiled program).

module soc_ram #(
    parameter ADDR_BITS = 11,          // word address bits: 2^11 words = 8 KB
    parameter INIT_FILE = ""
) (
    input  wire                 clk,
    input  wire                 valid,
    input  wire [ADDR_BITS-1:0] addr,  // WORD address (byte address >> 2)
    input  wire [31:0]          wdata,
    input  wire [3:0]           wstrb,
    output reg  [31:0]          rdata = 0,
    output reg                  ready = 0
);

    reg [31:0] mem [0:(1 << ADDR_BITS) - 1];

    // Without a file the RAM starts as all zeros, like the real block RAM
    integer i;
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
        else
            for (i = 0; i < (1 << ADDR_BITS); i = i + 1) mem[i] = 0;
    end

    always @(posedge clk) begin
        ready <= 0;
        if (valid && !ready) begin
            // Each byte lane is written only if its strobe bit is set
            if (wstrb[0]) mem[addr][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[addr][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[addr][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[addr][31:24] <= wdata[31:24];
            rdata <= mem[addr];        // old contents on a write; ignored by the CPU
            ready <= 1;
        end
    end

endmodule
