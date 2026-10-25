// Self-checking testbench for lib/tmds_encoder.v
//
// Checks:
//   1. the four control tokens during blanking (de=0)
//   2. every encoded word decodes back to the original byte (all 256 values,
//      then fixed worst-case patterns, then random data)
//   3. the running DC disparity (ones minus zeros sent) stays bounded
//
// Prints PASS/FAIL at the end. Waveforms go to tmds_encoder_tb.vcd.
// Lushay Code requires the testbench module to be named `test`.

`timescale 1ns/1ps

module test;

    reg        clk = 0;
    reg        rst = 1;
    reg  [7:0] data = 0;
    reg  [1:0] ctrl = 0;
    reg        de = 0;
    wire [9:0] tmds;

    tmds_encoder dut (.clk(clk), .rst(rst), .data(data), .ctrl(ctrl), .de(de), .tmds(tmds));

    always #20 clk = ~clk;   // 25 MHz

    integer errors   = 0;
    integer disp     = 0;    // running disparity, should match the encoder's cnt
    integer max_disp = 0;
    integer i;

    // Reference TMDS decoder (what the monitor does)
    function [7:0] decode(input [9:0] w);
        reg [7:0] d;
        integer k;
        begin
            d = w[9] ? ~w[7:0] : w[7:0];
            decode[0] = d[0];
            for (k = 1; k < 8; k = k + 1)
                decode[k] = w[8] ? (d[k] ^ d[k-1]) : ~(d[k] ^ d[k-1]);
        end
    endfunction

    function integer ones10(input [9:0] w);
        integer k;
        begin
            ones10 = 0;
            for (k = 0; k < 10; k = k + 1) ones10 = ones10 + w[k];
        end
    endfunction

    // Send one active pixel and check the result (encoder latency = 1 clock)
    task send_pixel(input [7:0] value);
        begin
            data = value;
            de   = 1;
            @(posedge clk); #1;
            if (decode(tmds) !== value) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL: data %02h encoded as %b decodes to %02h", value, tmds, decode(tmds));
            end
            disp = disp + 2 * ones10(tmds) - 10;
            if (disp > max_disp)  max_disp = disp;
            if (-disp > max_disp) max_disp = -disp;
        end
    endtask

    task check_ctrl(input [1:0] c, input [9:0] expected);
        begin
            ctrl = c;
            de   = 0;
            @(posedge clk); #1;
            disp = 0;   // the encoder resets its counter during blanking
            if (tmds !== expected) begin
                errors = errors + 1;
                $display("FAIL: ctrl %b gave %b, expected %b", c, tmds, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("tmds_encoder_tb.vcd");
        $dumpvars(0, test);

        repeat (3) @(posedge clk);
        #1 rst = 0;

        // 1. control tokens
        check_ctrl(2'b00, 10'b1101010100);
        check_ctrl(2'b01, 10'b0010101011);
        check_ctrl(2'b10, 10'b0101010100);
        check_ctrl(2'b11, 10'b1010101011);

        // 2a. every byte value
        for (i = 0; i < 256; i = i + 1)
            send_pixel(i[7:0]);

        // 2b. worst-case patterns for DC balance
        for (i = 0; i < 200; i = i + 1) send_pixel(8'h00);
        for (i = 0; i < 200; i = i + 1) send_pixel(8'hFF);
        for (i = 0; i < 200; i = i + 1) send_pixel(i[0] ? 8'h55 : 8'hAA);
        for (i = 0; i < 200; i = i + 1) send_pixel(8'h0F);

        // 2c. random data
        for (i = 0; i < 5000; i = i + 1)
            send_pixel($random);

        check_ctrl(2'b00, 10'b1101010100);

        // 3. disparity: the encoder keeps it in a 6-bit signed counter
        $display("Max running disparity seen: %0d", max_disp);
        if (max_disp > 31) begin
            errors = errors + 1;
            $display("FAIL: disparity out of range");
        end

        if (errors == 0) $display("PASS: tmds_encoder");
        else             $display("FAIL: tmds_encoder, %0d errors", errors);
        $finish;
    end

endmodule
