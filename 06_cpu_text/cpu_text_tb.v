// Testbench for Step 6: runs sw/06_text.c on soc_text (CPU + text screen) and
// shows what ends up on the screen, two ways:
//   - as plain text in the simulation log (box characters drawn as + - |)
//   - as an image of one full video frame: cpu_text_tb.ppm
//
// It runs until the program has printed its "Running." line, which comes
// after the prime-counting benchmark (several million clock cycles, so this
// takes a few minutes). Then it presses S2, which prints 40 lines (one every
// 50 ms, another 2 s of board time) and makes the screen scroll. In total
// this simulates about 3 s of board time and takes 10-15 minutes.
// PASS if all the expected text is on screen, the screen scrolled, and the
// CPU did not trap.
// Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    reg clk = 0;
    reg rst = 1;
    reg [7:0] buttons = 0;
    always #19.841 clk = ~clk;           // 25.2 MHz

    wire [7:0]  leds;
    wire        trap, done;
    wire [31:0] exit_code;
    wire [23:0] rgb;
    wire        hsync, vsync, de;

    soc_text #(.PROGRAM("text.hex"), .FONT_FILE("../03_text/font.hex")) sys (
        .clk(clk), .rst(rst), .buttons(buttons), .leds(leds), .trap(trap),
        .uart_tx(), .uart_rx(1'b1),
        .rgb(rgb), .hsync(hsync), .vsync(vsync), .de(de),
        .done(done), .exit_code(exit_code)
    );

    // ---- Read the screen back from the character RAM ---------------------------
    // Hierarchical names (sys.text.char_ram.mem) let a testbench look inside
    // the design; real hardware can't do this, but it makes checking easy.
    function [7:0] screen_char(input integer row, input integer col);
        integer r;
        reg [7:0] c;
        begin
            r = row + sys.scroll;
            if (r >= 30) r = r - 30;
            c = sys.text.char_ram.mem[r * 80 + col][7:0];
            case (c)
                8'hC9, 8'hBB, 8'hC8, 8'hBC: screen_char = "+";
                8'hCD:                      screen_char = "-";
                8'hBA:                      screen_char = "|";
                8'hDB:                      screen_char = "#";
                default: screen_char = (c >= 8'h20 && c < 8'h7F) ? c : " ";
            endcase
        end
    endfunction

    // Does logical row `row` start (after leading spaces) with `text`?
    function row_contains(input integer row, input [8*16-1:0] text, input integer len);
        integer col, i, ok;
        begin
            row_contains = 0;
            for (col = 0; col <= 80 - len; col = col + 1) begin
                ok = 1;
                for (i = 0; i < len; i = i + 1)
                    // !== also counts unknown (X) values as a mismatch; plain != would
                    // give X there, which `if` treats as false, hiding the difference
                    if (screen_char(row, col + i) !== text[8*(len-1-i) +: 8]) ok = 0;
                if (ok) row_contains = 1;
            end
        end
    endfunction

    function screen_contains(input [8*16-1:0] text, input integer len);
        integer row;
        begin
            screen_contains = 0;
            for (row = 0; row < 30; row = row + 1)
                if (row_contains(row, text, len)) screen_contains = 1;
        end
    endfunction

    task print_screen;
        integer row, col;
        reg [8*80-1:0] line;
        begin
            $display("+--------------------------------------------------------------------------------+");
            for (row = 0; row < 30; row = row + 1) begin
                for (col = 0; col < 80; col = col + 1)
                    line[8*(79-col) +: 8] = screen_char(row, col);
                $display("|%s|", line);
            end
            $display("+--------------------------------------------------------------------------------+");
        end
    endtask

    // ---- Save one video frame as an image ---------------------------------------
    integer ppm;
    task save_frame;
        begin
            ppm = $fopen("cpu_text_tb.ppm", "w");
            $fwrite(ppm, "P3\n640 480\n255\n");
            @(negedge vsync);                      // wait for the end of a frame
            @(posedge vsync);
            while (!de) @(posedge clk);            // first visible pixel
            repeat (640 * 480) begin
                while (!de) @(posedge clk);
                $fwrite(ppm, "%0d %0d %0d\n", rgb[23:16], rgb[15:8], rgb[7:0]);
                @(posedge clk);
            end
            $fclose(ppm);
        end
    endtask

    // ---- Run ------------------------------------------------------------------------
    integer cycles = 0;
    integer errors = 0;
    always @(posedge clk) cycles <= cycles + 1;

    initial begin
        repeat (3) @(posedge clk);
        rst = 0;

        // Check every 200,000 clocks whether "Running." has appeared
        while (!trap && cycles < 40_000_000 && !screen_contains("Running.", 8))
            repeat (200_000) @(posedge clk);

        $display("Screen after %0d clock cycles (%0d ms of board time):", cycles, cycles / 25200);
        print_screen;

        if (trap)                                    begin errors = errors + 1; $display("FAIL: CPU trapped at pc=%h", sys.soc_i.cpu.pc); end
        if (!row_contains(0, "rv32i_core", 10))      begin errors = errors + 1; $display("FAIL: title bar missing"); end
        if (!screen_contains("Running.", 8))         begin errors = errors + 1; $display("FAIL: program did not reach the main loop"); end
        if (!screen_contains("669 found", 9))        begin errors = errors + 1; $display("FAIL: wrong prime count (expected 669)"); end

        // Press S2: the program prints 40 lines, more than fit, so the screen
        // must scroll (hardware SCROLL register). One line every 50 ms makes
        // the burst last 2 s of board time, so wait (checking every 1 million
        // clocks) until the last line has appeared.
        buttons = 8'd1;
        repeat (500_000) @(posedge clk);         // 20 ms
        buttons = 8'd0;
        while (!trap && cycles < 120_000_000 && !screen_contains("line 40 ", 8))
            repeat (1_000_000) @(posedge clk);
        $display("Screen after pressing S2 (scroll register = %0d):", sys.scroll);
        print_screen;
        if (!screen_contains("line 40 ", 8))       begin errors = errors + 1; $display("FAIL: 'line 40' never appeared"); end
        if (screen_contains("rv32i_core on", 13))  begin errors = errors + 1; $display("FAIL: title should have scrolled off the screen"); end
        if (sys.scroll == 0)                       begin errors = errors + 1; $display("FAIL: scroll register never changed"); end

        $display("Saving one frame as cpu_text_tb.ppm ...");
        save_frame;

        if (errors == 0) $display("PASS: the CPU wrote the expected text");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
