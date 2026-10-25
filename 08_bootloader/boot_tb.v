// Testbench for Step 8: the bootloader, with the testbench playing the PC.
//
//   A. Power-up, no upload: the bootloader announces itself, waits 1 s, and
//      starts the program already in RAM (step 7's terminal) - its greeting
//      must arrive.
//   B. Reset (like pressing S1), then an upload with a WRONG CRC: the
//      bootloader must answer ERROR and keep waiting.
//   C. The same upload with the right CRC, sent at full line speed like
//      tools/upload.py does: the bootloader must answer OK and start it. The
//      uploaded program is sw/04_hello.c (built for step 4); it prints through
//      the simulation-only CONSOLE register and ends with EXIT = 0.
//
// Simulates about 1.5 s of board time; takes a few minutes.
// Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    localparam real BIT_NS = 1.0e9 / 115_200;

    reg clk = 0;
    reg rst = 1;
    always #19.841 clk = ~clk;                       // 25.2 MHz

    reg         pc_tx = 1;                           // PC -> board
    wire        board_tx;                            // board -> PC
    wire [7:0]  leds;
    wire        trap, done;
    wire [31:0] exit_code;
    wire [23:0] rgb;
    wire        hsync, vsync, de;

    soc_text #(
        .PROGRAM("../07_uart/terminal.hex"), .FONT_FILE("../03_text/font.hex"), .RING_ROWS(51),
        .HAS_BOOT_ROM(1), .BOOT_PROGRAM("boot.hex"), .RESET_PC(32'h3000_0000)
    ) sys (
        .clk(clk), .rst(rst), .buttons(8'd0), .leds(leds), .trap(trap),
        .uart_tx(board_tx), .uart_rx(pc_tx),
        .rgb(rgb), .hsync(hsync), .vsync(vsync), .de(de),
        .done(done), .exit_code(exit_code)
    );

    // ---- The PC's receiver: decode and print everything the board sends -------------
    localparam BUF = 4000;
    reg [7:0] pc_text [0:BUF-1];
    integer   pc_n = 0;
    reg [7:0] b;
    integer   k;

    initial forever begin
        @(negedge board_tx);
        #(BIT_NS / 2);
        for (k = 0; k < 8; k = k + 1) begin
            #(BIT_NS);
            b[k] = board_tx;
        end
        #(BIT_NS);
        if (pc_n < BUF) pc_text[pc_n] = b;
        pc_n = pc_n + 1;
        if (b != 8'h0D) $write("%c", b);
    end

    // Has the PC received `s` at or after position `from`?
    function received_since(input integer from, input [8*40-1:0] s, input integer len);
        integer i, j, ok;
        begin
            received_since = 0;
            for (i = from; i + len <= pc_n && i + len <= BUF; i = i + 1) begin
                ok = 1;
                for (j = 0; j < len; j = j + 1)
                    if (pc_text[i + j] !== s[8*(len - 1 - j) +: 8]) ok = 0;
                if (ok) received_since = 1;
            end
        end
    endfunction

    // ---- The PC's transmitter, at full speed (no pauses), like upload.py ----------
    task pc_send(input [7:0] c);
        integer i;
        begin
            pc_tx = 0;          #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                pc_tx = c[i];   #(BIT_NS);
            end
            pc_tx = 1;          #(BIT_NS);           // stop bit, next byte right after
        end
    endtask

    task pc_send_u32(input [31:0] v);
        begin
            pc_send(v[7:0]); pc_send(v[15:8]); pc_send(v[23:16]); pc_send(v[31:24]);
        end
    endtask

    // ---- The program to upload: sw/04_hello.c, from its RAM image -----------------------
    reg [31:0] image [0:2047];
    integer    length;                               // bytes
    reg [31:0] crc;
    integer    i;

    function [31:0] crc32_byte(input [31:0] c, input [7:0] d);
        integer n;
        begin
            crc32_byte = c ^ d;
            for (n = 0; n < 8; n = n + 1)
                crc32_byte = crc32_byte[0] ? (crc32_byte >> 1) ^ 32'hEDB88320 : (crc32_byte >> 1);
        end
    endfunction

    function [7:0] image_byte(input integer a);      // little-endian bytes of the words
        image_byte = image[a / 4][8 * (a % 4) +: 8];
    endfunction

    task send_upload(input [31:0] crc_to_send);
        begin
            pc_send("U"); pc_send("P"); pc_send("L"); pc_send("D");
            pc_send_u32(length);
            for (i = 0; i < length; i = i + 1)
                pc_send(image_byte(i));
            pc_send_u32(crc_to_send);
        end
    endtask

    // Wait until `s` has been received since `from` (or a time limit in ms)
    task wait_for(input integer from, input [8*40-1:0] s, input integer len, input integer limit_ms);
        integer t;
        begin
            t = 0;
            while (!received_since(from, s, len) && t < limit_ms) begin
                #1_000_000;
                t = t + 1;
            end
        end
    endtask

    integer errors = 0;
    integer mark;

    initial begin
        // Length = up to the last non-zero word of the image (the rest is padding)
        $readmemh("../04_cpu_sim/hello.hex", image);
        length = 0;
        for (i = 0; i < 2048; i = i + 1)
            if (image[i] != 0) length = (i + 1) * 4;
        crc = 32'hFFFFFFFF;
        for (i = 0; i < length; i = i + 1)
            crc = crc32_byte(crc, image_byte(i));
        crc = ~crc;
        $display("Program to upload: 04_hello.c, %0d bytes, CRC-32 %08h", length, crc);

        // ---- A: power-up without an upload ----
        $display("\n=== A: power-up, no upload ===");
        repeat (3) @(posedge clk);
        rst = 0;
        wait_for(0, "starting the program in RAM", 27, 1500);
        wait_for(0, "Hello from the FPGA", 19, 100);
        if (!received_since(0, "Hello from the FPGA", 19))
            begin errors = errors + 1; $display("\nFAIL A: the program in RAM did not start after the wait"); end

        // ---- B: reset, upload with a wrong CRC ----
        $display("\n=== B: reset (S1), upload with a wrong CRC ===");
        rst = 1; repeat (3) @(posedge clk); rst = 0;
        mark = pc_n;
        // Like upload.py: wait for the END of the board's line before sending.
        // While the board is still printing it can't read, and bytes arriving
        // then would overflow the 16-byte receive FIFO.
        wait_for(mark, {"for an upload", 8'h0D, 8'h0A}, 15, 100);
        send_upload(crc ^ 32'h1);
        wait_for(mark, "CRC mismatch", 12, 300);
        if (!received_since(mark, "CRC mismatch", 12))
            begin errors = errors + 1; $display("\nFAIL B: no CRC error reported"); end

        // ---- C: the same upload, correct ----
        $display("\n=== C: upload with the right CRC ===");
        wait_for(mark, {"new upload", 8'h0D, 8'h0A}, 12, 300);          // end of the error line
        mark = pc_n;
        send_upload(crc);
        wait_for(mark, "OK - starting", 13, 300);
        if (!received_since(mark, "OK - starting", 13))
            begin errors = errors + 1; $display("\nFAIL C: no OK from the bootloader"); end
        t_wait_done;
        if (!done)               begin errors = errors + 1; $display("FAIL C: the uploaded program did not finish"); end
        else if (exit_code != 0) begin errors = errors + 1; $display("FAIL C: the uploaded program reported %0d errors", exit_code); end
        if (trap)                begin errors = errors + 1; $display("FAIL: CPU trapped at pc=%h", sys.soc_i.cpu.pc); end

        if (errors == 0) $display("PASS: bootloader - timeout, CRC error and upload all behave");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    // 04_hello.c ends by writing EXIT; give it up to 50 ms
    task t_wait_done;
        integer t;
        begin
            t = 0;
            while (!done && !trap && t < 50) begin #1_000_000; t = t + 1; end
        end
    endtask

endmodule
