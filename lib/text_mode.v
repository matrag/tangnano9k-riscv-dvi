// 80x30 color text mode for 640x480
//
// The screen is a grid of 80 x 30 character cells, each 8 x 16 pixels
// (80 * 8 = 640, 30 * 16 = 480). Instead of storing 640x480 pixels
// (300 K pixels - far more than the 58 KB of block RAM on the chip), we
// store only WHICH character is in each cell, and look up its pixels in a
// font ROM while the screen is drawn. This is how the IBM PC's VGA text mode
// worked.
//
// Memories (both block RAM):
//   char RAM : 4096 x 16 bit: RING_ROWS rows of 80 cells (2400 cells with the default 30,
//              up to 4080 with 51). One word per cell, address = ram_row*80 + col
//                bits  7..0  character code (CP437)
//                bits 11..8  foreground color (0..15)
//                bits 15..12 background color (0..15)
//              It has a write port, so other logic (later: the CPU) can change the text.
//   font ROM : 4096 x 8 bit. address = char_code*16 + pixel row; bit 7 = leftmost pixel.
//
// Pipeline (one stage per clock, every stage busy every clock):
//
//   stage 0  x,y in    -> compute cell address        -> char RAM read starts
//   stage 1  char+attr -> compute font address        -> font ROM read starts
//   stage 2  font byte -> pick the pixel bit, palette -> color
//   stage 3  rgb out (registered)
//
// Because each block RAM read takes 1 clock, the character code for pixel
// (x, y) only arrives in stage 1, its font row in stage 2, and the final
// color leaves in stage 3. Everything the later stages need about (x, y)
// - the low bits of x and y, de, the syncs - is carried along in pipeline
// registers so it reaches each stage at the same time as the memory data.
// Total latency from the inputs to rgb/de_o/hsync_o/vsync_o: 3 clocks.

module text_mode #(
    // Init files, relative to the project folder. The defaults are empty on
    // purpose: yosys may elaborate a module once with its defaults, and a
    // default file name that doesn't exist there would stop the build.
    parameter FONT_FILE   = "",
    parameter SCREEN_FILE = "",
    // Rows in the character RAM ring (see "Hardware scroll" below). 30 = just
    // the screen. Up to 51 fit in the 4096-cell RAM (51 * 80 = 4080): the
    // extra 21 rows keep lines that scrolled off the top (scrollback).
    parameter RING_ROWS   = 30
) (
    input  wire        clk,         // pixel clock
    // from video_timing
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    // char RAM write port (may be in another clock domain)
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [11:0] wr_addr,
    input  wire [15:0] wr_data,
    // hardware scroll: char RAM row shown at the top of the screen (0..RING_ROWS-1)
    input  wire [5:0]  scroll,
    // to hdmi_out, delayed 3 clocks
    output reg  [23:0] rgb     = 0,
    output reg         de_o    = 0,
    output reg         hsync_o = 1,
    output reg         vsync_o = 1
);

    // ---- Stage 0: which cell is (x, y) in? ------------------------------
    // col = x / 8 and row = y / 16 are just the upper bits (powers of 2).
    // row * 80 = row * 64 + row * 16: two shifts and an add, no multiplier.
    wire [6:0]  col       = x[9:3];
    wire [4:0]  screen_row = y[8:4];

    // Hardware scroll: screen row r shows char RAM row (r + scroll) mod RING_ROWS.
    // The RAM is used as a ring of rows; to scroll the whole screen up by
    // one line, software just adds 1 to `scroll` and clears the row that
    // appears at the bottom - 80 writes instead of moving all 2400 cells.
    // With a ring bigger than the screen, rows that scrolled off the top
    // stay in the RAM, so scrolling back (scroll - 1) brings them back.
    // (During blanking screen_row can reach 32; those rows are never shown,
    // and the address still stays inside the RAM.)
    wire [6:0]  row_sum   = screen_row + scroll;
    wire [5:0]  row       = (row_sum >= RING_ROWS) ? row_sum - RING_ROWS : row_sum[5:0];
    wire [11:0] char_addr = {row, 6'b0} + {row, 4'b0} + col;

    // valid in stage 1 (not named `cell`: that's a reserved word in Verilog-2001)
    wire [15:0] cell_data;

    bram_sdp #(.WIDTH(16), .ADDR_BITS(12), .INIT_FILE(SCREEN_FILE)) char_ram (
        .wclk(wr_clk), .we(wr_en), .waddr(wr_addr), .wdata(wr_data),
        .rclk(clk), .raddr(char_addr), .rdata(cell_data)
    );

    // Carry what later stages need
    reg [2:0] px1 = 0;      // pixel column inside the cell (x mod 8)
    reg [3:0] py1 = 0;      // pixel row inside the cell    (y mod 16)
    reg       de1 = 0, hs1 = 1, vs1 = 1;
    always @(posedge clk) begin
        px1 <= x[2:0];
        py1 <= y[3:0];
        de1 <= de;
        hs1 <= hsync;
        vs1 <= vsync;
    end

    // ---- Stage 1: which font row do we need? ----------------------------
    // char_code * 16 + row  =  {char_code, row}  (concatenation = shift + add)
    wire [11:0] font_addr = {cell_data[7:0], py1};

    wire [7:0] font_bits;   // valid in stage 2

    bram_sdp #(.WIDTH(8), .ADDR_BITS(12), .INIT_FILE(FONT_FILE)) font_rom (
        .wclk(clk), .we(1'b0), .waddr(12'd0), .wdata(8'd0),   // never written = ROM
        .rclk(clk), .raddr(font_addr), .rdata(font_bits)
    );

    reg [2:0] px2  = 0;
    reg [7:0] attr2 = 0;    // {bg, fg} of this cell
    reg       de2 = 0, hs2 = 1, vs2 = 1;
    always @(posedge clk) begin
        px2   <= px1;
        attr2 <= cell_data[15:8];
        de2   <= de1;
        hs2   <= hs1;
        vs2   <= vs1;
    end

    // ---- Stage 2: pixel on or off, then color ----------------------------
    // bit 7 is the leftmost pixel, so pixel column px is bit (7 - px)
    wire pixel_on = font_bits[3'd7 - px2];

    // The 16-color CGA/VGA text palette
    function [23:0] palette(input [3:0] idx);
        case (idx)
            4'h0: palette = 24'h000000;  // black
            4'h1: palette = 24'h0000AA;  // blue
            4'h2: palette = 24'h00AA00;  // green
            4'h3: palette = 24'h00AAAA;  // cyan
            4'h4: palette = 24'hAA0000;  // red
            4'h5: palette = 24'hAA00AA;  // magenta
            4'h6: palette = 24'hAA5500;  // brown (dark yellow with green halved)
            4'h7: palette = 24'hAAAAAA;  // light gray
            4'h8: palette = 24'h555555;  // dark gray
            4'h9: palette = 24'h5555FF;  // light blue
            4'hA: palette = 24'h55FF55;  // light green
            4'hB: palette = 24'h55FFFF;  // light cyan
            4'hC: palette = 24'hFF5555;  // light red
            4'hD: palette = 24'hFF55FF;  // light magenta
            4'hE: palette = 24'hFFFF55;  // yellow
            4'hF: palette = 24'hFFFFFF;  // white
        endcase
    endfunction

    wire [3:0] color_idx = pixel_on ? attr2[3:0] : attr2[7:4];

    // ---- Stage 3: registered outputs ------------------------------------
    always @(posedge clk) begin
        rgb     <= de2 ? palette(color_idx) : 24'h000000;
        de_o    <= de2;
        hsync_o <= hs2;
        vsync_o <= vs2;
    end

endmodule
