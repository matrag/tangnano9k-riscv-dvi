// soc_text - the CPU system with an 80x30 text screen
//
//   +-----+  ext bus 0x2xxx_xxxx  +-------------+  wr_*   +-----------+  rgb, syncs
//   | soc |--------------------->| text device |-------->| text_mode |------------> (hdmi_out)
//   +-----+                      +-------------+  scroll +-----------+
//                                                             ^
//                                          video_timing ------+
//
// Everything runs on ONE clock, the 25.2 MHz pixel clock: the CPU writes
// the character RAM through its write port while the video side reads it
// through the other port. No clock-domain crossing needed.
//
// Memory map of the text device (also in sw/soc.h):
//   0x2000_0000 + 4*cell   TEXT    w  one character cell per 32-bit word,
//                                     cell = ram_row*80 + col (ram_row 0..RING_ROWS-1),
//                                     value = bg<<12 | fg<<8 | character
//                                     (use 32-bit stores; the upper 16 bits are ignored)
//   0x2001_0000            SCROLL  rw char RAM row shown at the top of the screen
//                                     (0..RING_ROWS-1; larger values are taken as 0)
//   0x2001_0004            RING    r  RING_ROWS: how many rows the RAM ring has, so
//                                     software can adapt (30 = no scrollback)
//
// The character RAM is write-only for the CPU. A second CPU read port would
// cost more block RAM, and a console never needs to read the screen back:
// software knows what it wrote.

module soc_text #(
    parameter PROGRAM   = "",          // e.g. "text.hex"
    parameter FONT_FILE = "",          // e.g. "../03_text/font.hex"
    parameter RING_ROWS = 30,          // 30..51; above 30 the extra rows keep scrolled-off lines
    // boot ROM and start address, passed on to soc (step 8)
    parameter HAS_BOOT_ROM = 0,
    parameter BOOT_PROGRAM = "",
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input  wire        clk,             // 25.2 MHz pixel clock
    input  wire        rst,
    input  wire [7:0]  buttons,
    output wire [7:0]  leds,
    output wire        trap,
    // serial port (tie uart_rx to 1 if unused)
    output wire        uart_tx,
    input  wire        uart_rx,
    // video out, to hdmi_out
    output wire [23:0] rgb,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    // simulation helpers
    output wire        done,
    output wire [31:0] exit_code
);

    // ---- CPU system -----------------------------------------------------------
    wire        ext_valid;
    wire [31:0] ext_addr, ext_wdata;
    wire [3:0]  ext_wstrb;
    reg         ext_ready = 0;
    reg  [5:0]  scroll    = 0;

    // Register reads: ext_addr[2] picks SCROLL (0) or RING (1)
    wire [31:0] ext_rdata = ext_addr[2] ? RING_ROWS : {26'b0, scroll};

    soc #(.PROGRAM(PROGRAM), .CLK_HZ(25_200_000), .BAUD(115_200),
          .HAS_BOOT_ROM(HAS_BOOT_ROM), .BOOT_PROGRAM(BOOT_PROGRAM), .RESET_PC(RESET_PC)) soc_i (
        .clk(clk), .rst(rst),
        .leds(leds), .buttons(buttons), .trap(trap),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .ext_valid(ext_valid), .ext_addr(ext_addr), .ext_wdata(ext_wdata),
        .ext_wstrb(ext_wstrb), .ext_ready(ext_ready), .ext_rdata(ext_rdata),
        .done(done), .exit_code(exit_code)
    );

    // ---- Text device: bus -> character RAM write port / scroll register ---------
    // ext_addr[16] = 0: a character cell, 1: a register
    wire is_reg = ext_addr[16];
    wire access = ext_valid && !ext_ready;         // first clock of a request

    // The write goes straight into the RAM's write port in the first clock
    wire        wr_en   = access && (ext_wstrb != 0) && !is_reg;
    wire [11:0] wr_addr = ext_addr[13:2];          // byte address / 4 = cell number
    wire [15:0] wr_data = ext_wdata[15:0];

    always @(posedge clk) begin
        ext_ready <= 0;
        if (rst) begin
            scroll <= 0;
        end else if (access) begin
            ext_ready <= 1;                        // answer after one clock, like the RAM
            if (ext_wstrb != 0 && is_reg && !ext_addr[2])
                scroll <= (ext_wdata[5:0] < RING_ROWS) ? ext_wdata[5:0] : 6'd0;
        end
    end

    // ---- Video ------------------------------------------------------------------
    wire       t_hsync, t_vsync, t_de, frame_start;
    wire [9:0] x, y;

    video_timing timing (
        .clk(clk), .rst(rst),
        .hsync(t_hsync), .vsync(t_vsync), .de(t_de),
        .x(x), .y(y), .frame_start(frame_start)
    );

    // SCREEN_FILE "" = the RAM starts all zero: character 0 (blank) in black
    // on black, so the screen is black until the program writes to it.
    text_mode #(.FONT_FILE(FONT_FILE), .SCREEN_FILE(""), .RING_ROWS(RING_ROWS)) text (
        .clk(clk),
        .x(x), .y(y), .de(t_de), .hsync(t_hsync), .vsync(t_vsync),
        .wr_clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .scroll(scroll),
        .rgb(rgb), .de_o(de), .hsync_o(hsync), .vsync_o(vsync)
    );

endmodule
