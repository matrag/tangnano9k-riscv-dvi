// soc - the system on chip: CPU + RAM + IO registers, used both on the
// board and in simulation.
//
//                 +-----------+   mem bus    +-----------------+
//                 | rv32i_core|------------->| address decoder |
//                 +-----------+              +-----------------+
//                                              |             |
//                       addr[31:28]=0     addr[31:28]=1     addr[31:28]=2     addr[31:28]=3
//                                 v             v                 v                 v
//                           +----------+  +--------------+  ext_* port:     +-------------+
//                           | RAM 8 KB |  | IO registers |  devices outside | boot ROM 2K |
//                           +----------+  +--------------+  this module     | (optional)  |
//                                                                           +-------------+
//
// Memory map (also in sw/soc.h for C programs):
//   0x0000_0000 - 0x0000_1FFF  RAM, 8 KB: program, data, stack
//   0x1000_0000  LEDS     rw  LED register (the board top decides how it is shown)
//   0x1000_0004  CONSOLE  w   print a character - simulation only
//   0x1000_0008  EXIT     w   end the simulation, value = exit code - simulation only
//   0x1000_000C  TIMER    r   free-running count of clock cycles
//   0x1000_0010  BUTTONS  r   button inputs (bit 0 = S2)
//   0x1000_0014  UART_DATA    w: send a byte (only when UART_STATUS bit 0 = 1)
//                             r: bit 8 = 1 if a byte was received, bits 7..0 = that byte
//                                (reading takes it out of the receive FIFO)
//   0x1000_0018  UART_STATUS  r: bit 0 = transmitter ready, bit 1 = received byte waiting
//                The receive FIFO holds 16 bytes; more arriving before the CPU reads
//                them are lost. Writing UART_DATA while the transmitter is busy is ignored.
//   0x2000_0000 - 0x2FFF_FFFF  external bus (ext_*): e.g. the text screen in step 6
//   0x3000_0000 - 0x3000_07FF  boot ROM, 2 KB, read-only (only if HAS_BOOT_ROM = 1, step 8)
//
// The CPU starts at RESET_PC: 0 = straight into the program in RAM (steps 4-7),
// 0x3000_0000 = into the bootloader in the boot ROM (step 8).
//
// The external bus is the same handshake as the CPU's: ext_valid is held
// until the outside device answers with ext_ready for one clock. A design
// with nothing there should tie ext_ready to ext_valid (answer at once) so
// a stray access can't hang the CPU.
//
// The "simulation only" behaviour is inside `ifndef SYNTHESIS: yosys defines
// SYNTHESIS while reading the files, so that code never becomes hardware.
// iverilog doesn't define it, so the simulation sees it.

module soc #(
    parameter PROGRAM       = "",               // RAM init file, e.g. "leds.hex"
    parameter RAM_ADDR_BITS = 11,               // 2^11 words = 8 KB
    parameter CLK_HZ        = 25_200_000,       // clock frequency, for the UART bit timing
    parameter BAUD          = 115_200,          // UART speed (format fixed: 8N1)
    parameter HAS_BOOT_ROM  = 0,                // 1 = boot ROM at 0x3000_0000
    parameter BOOT_PROGRAM  = "",               // boot ROM contents, e.g. "boot.hex"
    parameter [31:0] RESET_PC = 32'h0000_0000   // where the CPU starts
) (
    input  wire        clk,
    input  wire        rst,
    output reg  [7:0]  leds      = 0,
    input  wire [7:0]  buttons,                // already synchronized to clk
    output wire        trap,
    // serial port (idle level 1; tie uart_rx to 1 if unused)
    output wire        uart_tx,
    input  wire        uart_rx,
    // external bus, addresses 0x2xxx_xxxx
    output wire        ext_valid,
    output wire [31:0] ext_addr,
    output wire [31:0] ext_wdata,
    output wire [3:0]  ext_wstrb,
    input  wire        ext_ready,
    input  wire [31:0] ext_rdata,
    // simulation helpers (unused on the board)
    output reg         done      = 0,
    output reg  [31:0] exit_code = 0
);

    wire        mem_valid, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;

    rv32i_core #(.RESET_PC(RESET_PC)) cpu (
        .clk(clk), .rst(rst),
        .mem_valid(mem_valid), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .trap(trap)
    );

    // ---- Address decoder --------------------------------------------------
    wire sel_ram = mem_addr[31:28] == 4'h0;
    wire sel_io  = mem_addr[31:28] == 4'h1;
    wire sel_ext = mem_addr[31:28] == 4'h2;
    wire sel_rom = mem_addr[31:28] == 4'h3;
    // (an access anywhere else gets no answer and stalls the CPU - a
    // program bug, easy to spot in simulation)

    // ---- External bus: just pass the CPU's request through ------------------
    assign ext_valid = mem_valid && sel_ext;
    assign ext_addr  = mem_addr;
    assign ext_wdata = mem_wdata;
    assign ext_wstrb = mem_wstrb;

    // ---- RAM ----------------------------------------------------------------
    wire [31:0] ram_rdata;
    wire        ram_ready;

    soc_ram #(.ADDR_BITS(RAM_ADDR_BITS), .INIT_FILE(PROGRAM)) ram (
        .clk(clk), .valid(mem_valid && sel_ram), .addr(mem_addr[RAM_ADDR_BITS+1:2]),
        .wdata(mem_wdata), .wstrb(mem_wstrb),
        .rdata(ram_rdata), .ready(ram_ready)
    );

    // ---- Boot ROM (optional) ---------------------------------------------------
    // The same RAM module, with its write strobes forced to 0: a store to the
    // ROM is answered (so the CPU doesn't hang) but changes nothing.
    wire [31:0] rom_rdata;
    wire        rom_ready;

    generate
        if (HAS_BOOT_ROM) begin : boot_rom
            soc_ram #(.ADDR_BITS(9), .INIT_FILE(BOOT_PROGRAM)) rom (        // 2^9 words = 2 KB
                .clk(clk), .valid(mem_valid && sel_rom), .addr(mem_addr[10:2]),
                .wdata(32'd0), .wstrb(4'b0000),
                .rdata(rom_rdata), .ready(rom_ready)
            );
        end else begin : no_boot_rom
            assign rom_rdata = 32'd0;
            assign rom_ready = 1'b0;
        end
    endgenerate

    // ---- Timer: counts every clock, never stops -----------------------------
    reg [31:0] timer = 0;
    always @(posedge clk) timer <= timer + 1;

    // ---- UART: transmitter, receiver, receive FIFO ---------------------------
    reg  [31:0] io_rdata = 0;                                   // IO register read data / handshake,
    reg         io_ready = 0;                                   // driven in the IO block below
    wire       io_access = mem_valid && sel_io && !io_ready;   // first clock of an IO access
    wire       io_write  = io_access && (mem_wstrb != 0);
    wire       io_read   = io_access && (mem_wstrb == 0);

    wire       tx_busy;
    wire [7:0] rx_byte, rx_head;
    wire       rx_valid, rx_empty, rx_full;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) utx (
        .clk(clk), .rst(rst),
        .data(mem_wdata[7:0]), .start(io_write && mem_addr[4:2] == 3'd5),
        .busy(tx_busy), .tx(uart_tx)
    );

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) urx (
        .clk(clk), .rst(rst), .rx(uart_rx),
        .data(rx_byte), .valid(rx_valid)
    );

    // Received bytes wait here until the CPU reads UART_DATA
    fifo #(.WIDTH(8), .DEPTH_BITS(4)) rx_fifo (
        .clk(clk), .rst(rst),
        .din(rx_byte), .push(rx_valid),
        .pop(io_read && mem_addr[4:2] == 3'd5),
        .dout(rx_head), .empty(rx_empty), .full(rx_full)
    );

    // ---- IO registers -----------------------------------------------------
    // Same handshake as the RAM: answer one clock after valid.
    // mem_addr[4:2] picks the register (each register is 4 bytes apart).
    always @(posedge clk) begin
        io_ready <= 0;
        if (rst) begin
            leds <= 0;
        end else if (io_access) begin
            io_ready <= 1;
            case (mem_addr[4:2])
                3'd0:    io_rdata <= {24'b0, leds};
                3'd3:    io_rdata <= timer;
                3'd4:    io_rdata <= {24'b0, buttons};
                3'd5:    io_rdata <= {23'b0, !rx_empty, rx_head};     // bit 8 = byte valid
                3'd6:    io_rdata <= {30'b0, !rx_empty, !tx_busy};
                default: io_rdata <= 0;
            endcase
            if (mem_wstrb != 0) begin
                case (mem_addr[4:2])
                    3'd0: leds <= mem_wdata[7:0];
                    // 3'd5 (UART_DATA): handled by uart_tx's `start` above
`ifndef SYNTHESIS
                    3'd1: $write("%c", mem_wdata[7:0]);
                    3'd2: begin done <= 1; exit_code <= mem_wdata; end
`endif
                    default: ;
                endcase
            end
        end
    end

    // ---- Read data back to the CPU ------------------------------------------
    // Only the selected device raises ready, so the readys can be OR-ed and
    // ready tells us whose data to pass on.
    assign mem_ready = ram_ready | io_ready | ext_ready | rom_ready;
    assign mem_rdata = ram_ready ? ram_rdata :
                       io_ready  ? io_rdata  :
                       rom_ready ? rom_rdata : ext_rdata;

endmodule
