// Video timing generator - 640x480 @ 60 Hz (VESA DMT, 25.175 MHz nominal;
// 25.2 MHz gives 60.06 Hz, which every monitor accepts)
//
// One line   = 640 visible + 16 front porch + 96 sync + 48 back porch = 800 pixels
// One frame  = 480 visible + 10 front porch +  2 sync + 33 back porch = 525 lines
// Both syncs are active LOW for this mode.
//
//   one line (800 clocks):
//   |<------- 640 visible ------->|<-16->|<---96--->|<--48-->|
//   de:    1111111111111111111111   0000   00000000   000000
//   hsync: 1111111111111111111111   1111   00000000   111111
//                                  front    sync      back porch
//
// The porches and sync pulse come from CRT monitors, which needed time to
// sweep the electron beam back to the left edge (and to the top, for vsync).
// Digital monitors still use the sync pulses to find where lines and frames
// start, and HDMI uses the blanking time to send control (and audio) data.
//
// x/y count from 0 at the top-left visible pixel; de is high in the visible area.
// All outputs are registered and aligned to each other.

module video_timing #(
    parameter H_VISIBLE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48,
    parameter V_VISIBLE = 480, V_FRONT = 10, V_SYNC = 2,  V_BACK = 33
) (
    input  wire       clk,      // pixel clock
    input  wire       rst,
    output reg        hsync = 1,
    output reg        vsync = 1,
    output reg        de    = 0,
    output reg  [9:0] x     = 0,
    output reg  [9:0] y     = 0,
    output wire       frame_start   // 1-cycle pulse when (x,y) = (0,0)
);

    localparam H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800
    localparam V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525

    // h = horizontal position (pixel within the line), v = line within the frame.
    // 10 bits each, since both totals are below 1024.
    reg [9:0] h = 0;
    reg [9:0] v = 0;

    // Two nested counters: h wraps every line, and each wrap advances v.
    always @(posedge clk) begin
        if (rst) begin
            h <= 0;
            v <= 0;
        end else if (h == H_TOTAL - 1) begin
            h <= 0;
            v <= (v == V_TOTAL - 1) ? 10'd0 : v + 1'b1;
        end else begin
            h <= h + 1'b1;
        end
    end

    // Register outputs so they all change on the same edge.
    // Decoding the regions straight from h/v would give combinational outputs
    // with glitches and different delays; registering them makes de, the
    // syncs and x/y describe the same pixel during the same clock cycle
    // (all one clock behind h/v, which doesn't matter).
    always @(posedge clk) begin
        de    <= (h < H_VISIBLE) && (v < V_VISIBLE);
        // Sync pulses are active low: 0 inside the sync region, 1 elsewhere
        hsync <= ~((h >= H_VISIBLE + H_FRONT) && (h < H_VISIBLE + H_FRONT + H_SYNC));
        vsync <= ~((v >= V_VISIBLE + V_FRONT) && (v < V_VISIBLE + V_FRONT + V_SYNC));
        x     <= h;
        y     <= v;
    end

    // Handy for logic that should update once per frame (e.g. animation)
    assign frame_start = de && (x == 0) && (y == 0);

endmodule
