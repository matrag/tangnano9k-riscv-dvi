// Testbench for the UART modules alone (lib/uart_tx.v, lib/uart_rx.v)
//
//  1. loopback: uart_tx -> wire -> uart_rx, all 256 byte values
//  2. clock tolerance: the testbench sends with a bit time 2% too short and
//     2% too long (a PC whose clock differs from ours); every byte must
//     still arrive correctly
//  3. a short glitch on the line (shorter than half a bit) is ignored
//  4. a frame with a broken stop bit (0 instead of 1) is thrown away
//
// Takes a few seconds. Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    localparam CLK_HZ = 25_200_000;
    localparam BAUD   = 115_200;
    localparam real BIT_NS = 1.0e9 / BAUD;          // 8680.6 ns

    reg clk = 0;
    reg rst = 1;
    always #19.841 clk = ~clk;                      // 25.2 MHz

    // ---- 1. loopback: our transmitter into our receiver ------------------------
    reg  [7:0] tx_data  = 0;
    reg        tx_start = 0;
    wire       tx_busy, line;
    wire [7:0] lb_data;
    wire       lb_valid;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut_tx (
        .clk(clk), .rst(rst), .data(tx_data), .start(tx_start), .busy(tx_busy), .tx(line));
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut_rx (
        .clk(clk), .rst(rst), .rx(line), .data(lb_data), .valid(lb_valid));

    // ---- 2-4. a receiver fed by the testbench ----------------------------------
    reg        tb_line = 1;
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut_rx2 (
        .clk(clk), .rst(rst), .rx(tb_line), .data(rx_data), .valid(rx_valid));

    // Collect what the receivers output
    reg [7:0] got_lb [0:255];
    integer   n_lb = 0;
    always @(posedge clk) if (lb_valid) begin got_lb[n_lb % 256] = lb_data; n_lb = n_lb + 1; end

    reg [7:0] got_rx [0:1023];
    integer   n_rx = 0;
    always @(posedge clk) if (rx_valid) begin got_rx[n_rx % 1024] = rx_data; n_rx = n_rx + 1; end

    // Send one frame on tb_line with a given bit time and stop bit value
    task send_frame(input [7:0] b, input real bit_ns, input stop);
        integer i;
        begin
            tb_line = 0;                 #(bit_ns);          // start bit
            for (i = 0; i < 8; i = i + 1) begin
                tb_line = b[i];          #(bit_ns);          // data, LSB first
            end
            tb_line = stop;              #(bit_ns);          // stop bit
            tb_line = 1;                 #(bit_ns);          // a little idle time
        end
    endtask

    integer errors = 0;
    integer i, start_n;
    real    factor;

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, test);
        repeat (3) @(posedge clk);
        rst = 0;

        // 1. loopback, all byte values
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            while (tx_busy) @(negedge clk);
            tx_data = i; tx_start = 1;
            @(negedge clk);
            tx_start = 0;
        end
        while (tx_busy) @(negedge clk);
        repeat (300) @(posedge clk);
        if (n_lb != 256) begin errors = errors + 1; $display("FAIL: loopback received %0d of 256 bytes", n_lb); end
        for (i = 0; i < 256 && i < n_lb; i = i + 1)
            if (got_lb[i] !== i[7:0]) begin
                errors = errors + 1;
                if (errors < 10) $display("FAIL: loopback byte %0d received as %02h", i, got_lb[i]);
            end
        $display("1. loopback: %0d bytes", n_lb);

        // 2. sender clock 2% fast and 2% slow
        for (factor = 0.98; factor < 1.03; factor = factor + 0.04) begin
            start_n = n_rx;
            for (i = 0; i < 256; i = i + 1)
                send_frame(i, BIT_NS * factor, 1);
            if (n_rx - start_n != 256) begin
                errors = errors + 1;
                $display("FAIL: bit time x%0.2f: received %0d of 256 bytes", factor, n_rx - start_n);
            end
            for (i = 0; i < 256; i = i + 1)
                if (got_rx[(start_n + i) % 1024] !== i[7:0]) begin
                    errors = errors + 1;
                    if (errors < 10) $display("FAIL: bit time x%0.2f: byte %0d received as %02h",
                                              factor, i, got_rx[(start_n + i) % 1024]);
                end
            $display("2. bit time x%0.2f: %0d bytes", factor, n_rx - start_n);
        end

        // 3. a glitch of 1/4 bit must not start a frame
        start_n = n_rx;
        tb_line = 0; #(BIT_NS / 4); tb_line = 1; #(BIT_NS * 12);
        if (n_rx != start_n) begin errors = errors + 1; $display("FAIL: glitch produced a byte"); end
        else $display("3. glitch ignored");

        // 4. broken stop bit: dropped; the next good frame still arrives
        start_n = n_rx;
        send_frame(8'hA5, BIT_NS, 0);
        #(BIT_NS * 10);                    // let the line settle
        send_frame(8'h3C, BIT_NS, 1);
        if (n_rx - start_n != 1 || got_rx[start_n % 1024] !== 8'h3C) begin
            errors = errors + 1;
            $display("FAIL: framing error test: %0d bytes, first %02h", n_rx - start_n, got_rx[start_n % 1024]);
        end else
            $display("4. frame with bad stop bit dropped, next frame OK");

        if (errors == 0) $display("PASS: uart_tx / uart_rx");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
