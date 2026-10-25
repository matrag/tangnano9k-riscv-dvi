// Testbench for Step 5: simulates the whole board design (top.v) running
// sw/05_leds.c, and checks what the LEDs do and when.
//
// Expected:
//   - all 6 LEDs on for 300 ms (start-up flash)
//   - Knight Rider: 1 light moving 0,1,2,3,4,5,4,... one step every 80 ms
//   - after S2 is pressed: binary counter 0,1,2,3,...
//
// This simulates about 1.1 s of real time = 30 million clock cycles, so it
// takes a while (2-3 minutes). Every LED change is printed with its time.
// Lushay Code requires the module name `test`.

`timescale 1ns/1ps

module test;

    reg  clk  = 0;
    reg  btn1 = 0;           // S1 held = reset at start
    reg  btn2 = 1;           // S2 released
    wire [5:0] led;

    always #18.5185 clk = ~clk;          // 27 MHz

    top dut (.clk(clk), .btn1(btn1), .btn2(btn2), .led(led));

    wire [5:0] lit = ~led;               // 1 = LED on

    // ---- Record every change ------------------------------------------------
    integer changes = 0;
    integer errors  = 0;
    real    t_ms, last_ms = 0;
    reg [5:0] seq [0:31];
    real      at  [0:31];

    always @(lit) if (btn1) begin
        t_ms = $realtime / 1.0e6;
        $display("%8.2f ms  LEDs %b  (+%0.2f ms)", t_ms, lit, t_ms - last_ms);
        if (changes < 32) begin
            seq[changes] = lit;
            at[changes]  = t_ms;
        end
        changes = changes + 1;
        last_ms = t_ms;
    end

    task expect_step(input integer i, input [5:0] value, input real gap_ms);
        begin
            if (seq[i] !== value) begin
                errors = errors + 1;
                $display("FAIL: change %0d is %b, expected %b", i, seq[i], value);
            end
            if (i > 0 && (at[i] - at[i-1] < gap_ms * 0.99 || at[i] - at[i-1] > gap_ms * 1.01)) begin
                errors = errors + 1;
                $display("FAIL: change %0d came after %0.2f ms, expected %0.2f ms",
                         i, at[i] - at[i-1], gap_ms);
            end
        end
    endtask

    initial begin
        #1000 btn1 = 1;                   // release reset after 1 us

        // start-up flash + 7 Knight Rider steps
        wait (changes == 8);
        expect_step(0, 6'b111111, 0);
        expect_step(1, 6'b000001, 300);
        expect_step(2, 6'b000010, 80);
        expect_step(3, 6'b000100, 80);
        expect_step(4, 6'b001000, 80);
        expect_step(5, 6'b010000, 80);
        expect_step(6, 6'b100000, 80);
        expect_step(7, 6'b010000, 80);    // bounces back

        // press S2 for 30 ms: the program should switch to the counter
        #20_000_000;                      // 20 ms into the current step
        btn2 = 0;
        #30_000_000;
        btn2 = 1;
        wait (changes == 12);
        // counter shows 0 (all off), 1, 2, 3 ...
        if (seq[8] !== 6'b000000 || seq[9] !== 6'b000001 || seq[10] !== 6'b000010 || seq[11] !== 6'b000011) begin
            errors = errors + 1;
            $display("FAIL: after S2 expected counter 0,1,2,3 got %b %b %b %b",
                     seq[8], seq[9], seq[10], seq[11]);
        end

        if (dut.trap) begin
            errors = errors + 1;
            $display("FAIL: CPU trapped");
        end
        if (errors == 0) $display("PASS: LED program behaves as expected");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
