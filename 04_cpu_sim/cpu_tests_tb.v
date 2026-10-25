// Runs ../sw/04_rv32i_test.S (rv32i_test.hex) on the CPU and reports the result.
//
// The program tests every RV32I instruction and writes the number of the
// first failing test to EXIT (0 = all passed). Look the number up in
// ../sw/04_rv32i_test.S to see which instruction is wrong; ../sw/build/04_rv32i_test.lst
// shows the matching addresses for the waveform (cpu_tests_tb.vcd).
// Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    reg clk = 0;
    reg rst = 1;
    always #20 clk = ~clk;                 // 25 MHz, like the pixel clock

    wire [7:0]  leds;
    wire        done, trap;
    wire [31:0] exit_code;

    soc #(.PROGRAM("rv32i_test.hex")) soc (
        .clk(clk), .rst(rst), .leds(leds), .buttons(8'd0), .uart_tx(), .uart_rx(1'b1),
        .ext_valid(), .ext_addr(), .ext_wdata(), .ext_wstrb(),
        .ext_ready(1'b0), .ext_rdata(32'd0),
        .done(done), .exit_code(exit_code), .trap(trap)
    );

    integer cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;

    initial begin
        $dumpfile("cpu_tests_tb.vcd");
        $dumpvars(0, test);

        repeat (3) @(posedge clk);
        rst = 0;

        wait (done || trap || cycles > 100000);
        @(posedge clk);

        if (done && exit_code == 0)
            $display("PASS: all RV32I instruction tests (%0d clock cycles)", cycles);
        else if (done)
            $display("FAIL: test %0d failed (see ../sw/04_rv32i_test.S)", exit_code);
        else if (trap)
            $display("FAIL: CPU trapped at pc=%h, instruction %h", soc.cpu.pc, soc.cpu.ir);
        else
            $display("FAIL: timeout, pc=%h", soc.cpu.pc);
        $finish;
    end

endmodule
