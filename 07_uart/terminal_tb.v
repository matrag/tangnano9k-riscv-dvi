// Testbench for Step 7: runs sw/07_terminal.c on soc_text, with the testbench
// playing the PC on the other end of the serial line.
//
//   - a "PC receiver" decodes everything the board sends and prints it
//   - the "PC" types "Hi FPGA!", Enter, "abx", Backspace, "c"
//   - checks: the greeting arrived, the typed text was echoed back, and the
//     HDMI screen (read from the character RAM) shows "Hi FPGA!" and "abc"
//   - scrolling: types 80 numbered lines so the screen scrolls 58 times and
//     goes once round the 51-row character RAM ring; the expected lines must
//     be at the top and bottom (the screen is printed in the log)
//
// Simulates about 0.4 s of board time; takes about 2 minutes.
// Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    localparam real BIT_NS = 1.0e9 / 115_200;

    reg clk = 0;
    reg rst = 1;
    always #19.841 clk = ~clk;                       // 25.2 MHz

    reg         pc_tx = 1;                           // PC -> board (board's uart_rx)
    wire        board_tx;                            // board -> PC
    wire [7:0]  leds;
    wire        trap, done;
    wire [31:0] exit_code;
    wire [23:0] rgb;
    wire        hsync, vsync, de;

    soc_text #(.PROGRAM("terminal.hex"), .FONT_FILE("../03_text/font.hex"), .RING_ROWS(51)) sys (
        .clk(clk), .rst(rst), .buttons(8'd0), .leds(leds), .trap(trap),
        .uart_tx(board_tx), .uart_rx(pc_tx),
        .rgb(rgb), .hsync(hsync), .vsync(vsync), .de(de),
        .done(done), .exit_code(exit_code)
    );

    // ---- The PC's receiver: decode frames from board_tx ---------------------------
    reg [8*400-1:0] pc_text = 0;                     // everything received, as a string
    integer         pc_n    = 0;
    reg [7:0]       b;
    integer         k;

    initial forever begin
        @(negedge board_tx);                         // start bit begins
        #(BIT_NS / 2);                               // middle of the start bit
        for (k = 0; k < 8; k = k + 1) begin
            #(BIT_NS);
            b[k] = board_tx;
        end
        #(BIT_NS);                                   // middle of the stop bit
        pc_text = {pc_text[8*399-1:0], b};
        pc_n = pc_n + 1;
        if (b != 8'h0D) $write("%c", b);             // print it (skip \r)
    end

    // ---- The PC's transmitter ---------------------------------------------------------
    task pc_send(input [7:0] c);
        integer i;
        begin
            pc_tx = 0;                   #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                pc_tx = c[i];            #(BIT_NS);
            end
            pc_tx = 1;                   #(BIT_NS);       // stop bit
            // Pause like a (fast) typist: 1 ms between keys. Sending at full line
            // speed would be like pasting text: the echo sends more bytes back
            // than arrive (Enter -> "\r\n"), the CPU falls behind and once the
            // 16-byte receive FIFO is full, bytes are lost.
            #1_000_000;
        end
    endtask

    task pc_type(input [8*16-1:0] s, input integer len);
        integer i;
        for (i = len - 1; i >= 0; i = i - 1)
            pc_send(s[8*i +: 8]);
    endtask

    // Did the PC receive `s` (anywhere)?
    function pc_received(input [8*16-1:0] s, input integer len);
        integer i, j, ok;
        begin
            pc_received = 0;
            for (i = 0; i + len <= pc_n && i + len <= 400; i = i + 1) begin
                ok = 1;
                for (j = 0; j < len; j = j + 1)
                    if (pc_text[8*(i + len - 1 - j) +: 8] !== s[8*(len - 1 - j) +: 8]) ok = 0;
                if (ok) pc_received = 1;
            end
        end
    endfunction

    // ---- Reading the HDMI screen out of the character RAM ----------------------------
    localparam RING = 51;                            // must match RING_ROWS above

    // Character at a screen (logical) row/column, as the monitor shows it
    function [7:0] screen_char(input integer row, input integer col);
        integer r;
        begin
            r = row + sys.scroll;
            if (r >= RING) r = r - RING;
            screen_char = sys.text.char_ram.mem[r * 80 + col][7:0];
        end
    endfunction

    // Does screen row `row` start with `s`?
    function row_starts(input integer row, input [8*16-1:0] s, input integer len);
        integer i;
        begin
            row_starts = 1;
            for (i = 0; i < len; i = i + 1)
                if (screen_char(row, i) !== s[8*(len - 1 - i) +: 8]) row_starts = 0;
        end
    endfunction

    // Does the HDMI screen contain `s` (anywhere)?
    function screen_contains(input [8*16-1:0] s, input integer len);
        integer row, col, i, ok;
        begin
            screen_contains = 0;
            for (row = 0; row < 30; row = row + 1)
                for (col = 0; col + len <= 80; col = col + 1) begin
                    ok = 1;
                    for (i = 0; i < len; i = i + 1)
                        if (screen_char(row, col + i) !== s[8*(len - 1 - i) +: 8]) ok = 0;
                    if (ok) screen_contains = 1;
                end
        end
    endfunction

    task print_screen;
        integer row, col;
        reg [8*80-1:0] line;
        reg [7:0] c;
        begin
            for (row = 0; row < 30; row = row + 1) begin
                for (col = 0; col < 80; col = col + 1) begin
                    c = screen_char(row, col);
                    line[8*(79-col) +: 8] = (c >= 8'h20 && c < 8'h7F) ? c : " ";
                end
                $display("%2d|%s|", row, line);
            end
        end
    endtask

    integer errors = 0;
    integer n;
    reg [7:0] tens, ones;

    initial begin
        repeat (3) @(posedge clk);
        rst = 0;

        // Wait until the whole greeting has arrived (~100 characters, ~9 ms at
        // 115200 baud): while the board is busy sending it, it can't echo.
        while (!pc_received("HDMI screen.", 12)) #1_000_000;
        $display("\n--- the PC types ---");
        pc_type("Hi FPGA!", 8);
        pc_send(8'h0D);                               // Enter
        pc_type("abx", 3);
        pc_send(8'h08);                               // Backspace
        pc_type("c", 1);
        #3_000_000;                                   // let the echo finish
        $display("\n-------------------");

        if (trap)                              begin errors = errors + 1; $display("FAIL: CPU trapped"); end
        if (!pc_received("Hello from the", 14)) begin errors = errors + 1; $display("FAIL: greeting not received by the PC"); end
        if (!pc_received("Hi FPGA!", 8))       begin errors = errors + 1; $display("FAIL: typed text not echoed"); end
        if (!screen_contains("Hi FPGA!", 8))   begin errors = errors + 1; $display("FAIL: typed text not on the screen"); end
        if (!screen_contains("abc", 3))        begin errors = errors + 1; $display("FAIL: backspace: 'abc' not on the screen"); end
        if (leds !== "c")                      begin errors = errors + 1; $display("FAIL: LEDs show %02h, expected the code of 'c'", leds); end

        // ---- Scrolling through the 51-row ring ----------------------------------
        // Type 80 numbered lines L01..L80. L01 starts on screen row 7, so L80 lands
        // on row 86 and the cursor on 87: 87 - 29 = 58 scrolls, which is once round
        // the 51-row ring (58 - 51 = 7). The cursor ends on an empty line below L80.
        pc_send(8'h0D);
        for (n = 1; n <= 80; n = n + 1) begin
            // 8-bit digits: inside {} an integer expression would be 32 bits wide
            tens = 8'h30 + n / 10;
            ones = 8'h30 + n % 10;
            pc_type({"L", tens, ones}, 3);
            pc_send(8'h0D);
        end
        #3_000_000;
        $display("\n--- screen after 80 lines (scroll register = %0d) ---", sys.scroll);
        print_screen;
        if (!row_starts(0, "L52", 3) || !row_starts(28, "L80", 3))
            begin errors = errors + 1; $display("FAIL: expected L52 on the top row and L80 on row 28"); end
        if (sys.scroll != 7)
            begin errors = errors + 1; $display("FAIL: scroll register is %0d, expected 7 (wrapped round the ring)", sys.scroll); end

        if (errors == 0) $display("PASS: terminal works in both directions");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
