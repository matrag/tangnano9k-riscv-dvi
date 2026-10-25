// Self-checking testbench for lib/text_mode.v (with lib/video_timing.v)
//
// The testbench loads its own copy of font.hex and screen.hex and computes
// the expected color of every visible pixel directly from (x, y), without
// any pipeline. It compares that with text_mode's output 3 clocks later.
// So it checks the memory contents, the address math, the bit order and -
// most importantly - that the pipeline delays line up (an off-by-one clock
// mistake would shift every character by a pixel and fail here).
//
// It also uses the write port: one cell is written before the first frame,
// another one between frames, and both must show up on screen.
//
// Simulates 2 full frames (840,000 pixel clocks, takes about 10 seconds).
// Prints PASS/FAIL, and saves frame 2 as text_mode_tb.ppm - an image of
// what the monitor should show. Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    reg clk = 0;
    reg rst = 1;
    always #20 clk = ~clk;

    // ---- DUT: timing + text mode ----------------------------------------
    wire       hsync, vsync, de, frame_start;
    wire [9:0] x, y;

    video_timing timing (
        .clk(clk), .rst(rst),
        .hsync(hsync), .vsync(vsync), .de(de),
        .x(x), .y(y), .frame_start(frame_start)
    );

    reg         wr_en   = 0;
    reg  [11:0] wr_addr = 0;
    reg  [15:0] wr_data = 0;
    wire [23:0] rgb;
    wire        de_o, hsync_o, vsync_o;

    text_mode #(.FONT_FILE("font.hex"), .SCREEN_FILE("screen.hex")) dut (
        .clk(clk),
        .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync),
        .wr_clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .scroll(6'd0),
        .rgb(rgb), .de_o(de_o), .hsync_o(hsync_o), .vsync_o(vsync_o)
    );

    // ---- Reference model --------------------------------------------------
    reg [7:0]  font_ref [0:4095];
    reg [15:0] scr_ref  [0:4095];
    reg [23:0] pal_ref  [0:15];

    initial begin
        $readmemh("font.hex",   font_ref);
        $readmemh("screen.hex", scr_ref);
        pal_ref[0]  = 24'h000000; pal_ref[1]  = 24'h0000AA; pal_ref[2]  = 24'h00AA00; pal_ref[3]  = 24'h00AAAA;
        pal_ref[4]  = 24'hAA0000; pal_ref[5]  = 24'hAA00AA; pal_ref[6]  = 24'hAA5500; pal_ref[7]  = 24'hAAAAAA;
        pal_ref[8]  = 24'h555555; pal_ref[9]  = 24'h5555FF; pal_ref[10] = 24'h55FF55; pal_ref[11] = 24'h55FFFF;
        pal_ref[12] = 24'hFF5555; pal_ref[13] = 24'hFF55FF; pal_ref[14] = 24'hFFFF55; pal_ref[15] = 24'hFFFFFF;
    end

    function [23:0] expected_rgb(input [9:0] px, input [9:0] py);
        reg [15:0] cell_data;
        reg [7:0]  bits;
        begin
            cell_data = scr_ref[(py / 16) * 80 + (px / 8)];
            bits = font_ref[cell_data[7:0] * 16 + (py % 16)];
            expected_rgb = bits[7 - (px % 8)] ? pal_ref[cell_data[11:8]] : pal_ref[cell_data[15:12]];
        end
    endfunction

    // Delay the timing outputs by the DUT's latency (3 clocks)
    reg [9:0] x_d [1:3];
    reg [9:0] y_d [1:3];
    reg       de_d [1:3], hs_d [1:3], vs_d [1:3];
    always @(posedge clk) begin
        x_d[1] <= x;      y_d[1] <= y;      de_d[1] <= de;      hs_d[1] <= hsync;   vs_d[1] <= vsync;
        x_d[2] <= x_d[1]; y_d[2] <= y_d[1]; de_d[2] <= de_d[1]; hs_d[2] <= hs_d[1]; vs_d[2] <= vs_d[1];
        x_d[3] <= x_d[2]; y_d[3] <= y_d[2]; de_d[3] <= de_d[2]; hs_d[3] <= hs_d[2]; vs_d[3] <= vs_d[2];
    end

    integer errors  = 0;
    integer checked = 0;
    integer frames  = 0;
    reg     checking = 0;     // start once the pipeline is filled after reset
    integer ppm;              // image file handle

    always @(posedge clk) begin
        if (checking) begin
            if (de_o !== de_d[3] || hsync_o !== hs_d[3] || vsync_o !== vs_d[3]) begin
                errors = errors + 1;
                if (errors <= 10) $display("FAIL: sync/de misaligned at x=%0d y=%0d", x_d[3], y_d[3]);
            end
            if (de_d[3]) begin
                checked = checked + 1;
                if (rgb !== expected_rgb(x_d[3], y_d[3])) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("FAIL: pixel x=%0d y=%0d is %06h, expected %06h",
                                 x_d[3], y_d[3], rgb, expected_rgb(x_d[3], y_d[3]));
                end
                // Save frame 2 as an image ("screenshot" of the simulation)
                if (frames == 1)
                    $fwrite(ppm, "%0d %0d %0d\n", rgb[23:16], rgb[15:8], rgb[7:0]);
            end
        end
    end

    // Plain-text PPM image: a header, then one "r g b" line per pixel in
    // raster order. Most image viewers open it (e.g. GIMP, IrfanView).
    initial begin
        ppm = $fopen("text_mode_tb.ppm", "w");
        $fwrite(ppm, "P3\n640 480\n255\n");
    end

    // Write one cell through the write port, in the DUT and in the model
    task write_cell(input [11:0] addr, input [15:0] data);
        begin
            @(negedge clk);
            wr_en = 1; wr_addr = addr; wr_data = data;
            @(negedge clk);
            wr_en = 0;
            scr_ref[addr] = data;
        end
    endtask

    initial begin
        $dumpfile("text_mode_tb.vcd");
        $dumpvars(1, test);       // top-level signals only, keeps the file small

        // While in reset: put a white-on-blue 'X' in the top-left cell
        write_cell(12'd0, 16'h1F58);
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;
        repeat (4) @(posedge clk);
        checking = 1;

        // Frame 1 starts right after reset. Its vsync pulse (line 490) comes
        // after all visible lines, so that's a safe moment to change the RAM.
        @(negedge vsync);
        frames = 1;
        // Between frames: red-on-yellow '@' at row 15, col 40
        write_cell(15 * 80 + 40, 16'hE440);
        // Frame 2
        @(negedge vsync);
        frames = 2;

        $display("Checked %0d visible pixels over %0d frames", checked, frames);
        if (checked < 2 * 640 * 480 - 8) begin
            errors = errors + 1;
            $display("FAIL: expected about %0d checked pixels", 2 * 640 * 480);
        end
        if (errors == 0) $display("PASS: text_mode");
        else             $display("FAIL: text_mode, %0d errors", errors);
        $display("Frame 2 saved as text_mode_tb.ppm");
        $fclose(ppm);
        $finish;
    end

endmodule
