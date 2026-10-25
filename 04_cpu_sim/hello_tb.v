// Runs the C program ../sw/04_hello.c (hello.hex) on the CPU.
//
// Characters the program writes to CONSOLE are printed in the simulation
// log; LED writes are reported too. main()'s return value is the exit
// code: 0 means all of the program's own checks passed.
// Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    reg clk = 0;
    reg rst = 1;
    always #20 clk = ~clk;

    wire [7:0]  leds;
    wire        done, trap;
    wire [31:0] exit_code;

    soc #(.PROGRAM("hello.hex")) soc (
        .clk(clk), .rst(rst), .leds(leds), .buttons(8'd0), .uart_tx(), .uart_rx(1'b1),
        .ext_valid(), .ext_addr(), .ext_wdata(), .ext_wstrb(),
        .ext_ready(1'b0), .ext_rdata(32'd0),
        .done(done), .exit_code(exit_code), .trap(trap)
    );

    integer cycles = 0;
    integer instructions = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        // count instructions: one per entry into DECODE
        if (soc.cpu.state == 3'd1) instructions <= instructions + 1;
    end

    always @(leds)
        if (!rst) $display("[LEDS = %b]", leds);

    initial begin
        $dumpfile("hello_tb.vcd");
        $dumpvars(0, test);

        repeat (3) @(posedge clk);
        rst = 0;

        wait (done || trap || cycles > 2000000);
        @(posedge clk);

        $display("");
        $display("%0d instructions in %0d clock cycles (%0d.%02d cycles per instruction)",
                 instructions, cycles, cycles / instructions, (cycles * 100 / instructions) % 100);
        if (done && exit_code == 0)
            $display("PASS: 04_hello.c returned 0");
        else if (done)
            $display("FAIL: 04_hello.c returned %0d", exit_code);
        else if (trap)
            $display("FAIL: CPU trapped at pc=%h, instruction %h", soc.cpu.pc, soc.cpu.ir);
        else
            $display("FAIL: timeout, pc=%h", soc.cpu.pc);
        $finish;
    end

endmodule
