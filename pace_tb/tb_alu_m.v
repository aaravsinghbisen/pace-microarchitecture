// Copyright (c) 2026 uppmpt (https://github.com/uppmpt)
// Contact: pacesolodev@gmail.com
//
// This source describes Open Hardware and is licensed under the
// CERN-OHL-W v2.
//
// You may redistribute and modify this source and make products
// using it under the terms of the CERN-OHL-W v2
// (https://ohwr.org/cern_ohl_w_v2.txt).
//
// This source is distributed WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTY, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY,
// SATISFACTORY QUALITY AND FITNESS FOR A PARTICULAR PURPOSE.
// Please see the CERN-OHL-W v2 for applicable conditions.
//
// Source location: https://github.com/uppmpt/pace-microarchitecture
`timescale 1ns/1ps
module tb_alu_m;
    reg  [63:0] a, b;
    reg  [4:0]  op;
    wire [63:0] r;
    integer tests_run=0, tests_passed=0, tests_failed=0;

    alu_rv64 dut (.in0_alu(a), .in1_alu(b), .opcd_alu(op), .out_alu(r));

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        $display("========================================");
        $display("  M Extension Testbench");
        $display("========================================");

        // MUL: 7 * 6 = 42
        a=64'd7; b=64'd6; op=5'd10; #1;
        check(r === 64'd42, "MUL 7*6=42");

        // MUL negativo: -3 * 5 = -15
        a=-64'sd3; b=64'd5; op=5'd10; #1;
        check(r === -64'sd15, "MUL -3*5=-15");

        // MULH: (2^63) * 2 = 2^64 (overflow em 64bits, hi = 1)
        a=64'h8000_0000_0000_0000; b=64'd2; op=5'd11; #1;
        check(r === 64'hFFFF_FFFF_FFFF_FFFF, "MULH INT_MIN*2 hi=-1");

        // MULH signed: -2 * 2 = -4 (produto 128 = FFFF...FFFC)
        a=-64'sd2; b=64'd2; op=5'd11; #1;
        check(r === 64'hFFFF_FFFF_FFFF_FFFF, "MULH -2*2 hi=-1");

        // MULHU: (2^63) * 2 (unsigned) → hi = 1
        a=64'h8000_0000_0000_0000; b=64'd2; op=5'd13; #1;
        check(r === 64'd1, "MULHU unsigned 2^63*2 hi=1");

        // DIV: 42 / 6 = 7
        a=64'd42; b=64'd6; op=5'd14; #1;
        check(r === 64'd7, "DIV 42/6=7");

        // DIV signed: -42 / 6 = -7
        a=-64'sd42; b=64'd6; op=5'd14; #1;
        check(r === -64'sd7, "DIV -42/6=-7");

        // DIV by 0 → all ones
        a=64'd42; b=64'd0; op=5'd14; #1;
        check(r === 64'hFFFF_FFFF_FFFF_FFFF, "DIV by 0 = -1");

        // DIV overflow: INT_MIN / -1 → INT_MIN
        a=64'h8000_0000_0000_0000; b=64'hFFFF_FFFF_FFFF_FFFF; op=5'd14; #1;
        check(r === 64'h8000_0000_0000_0000, "DIV overflow = INT_MIN");

        // DIVU: 100 / 7 = 14
        a=64'd100; b=64'd7; op=5'd15; #1;
        check(r === 64'd14, "DIVU 100/7=14");

        // REM: 100 % 7 = 2
        a=64'd100; b=64'd7; op=5'd16; #1;
        check(r === 64'd2, "REM 100%7=2");

        // REM negative: -100 % 7 = -2
        a=-64'sd100; b=64'd7; op=5'd16; #1;
        check(r === -64'sd2, "REM -100%7=-2");

        // REMU: 100 % 7 = 2
        a=64'd100; b=64'd7; op=5'd17; #1;
        check(r === 64'd2, "REMU 100%7=2");

        // Base ops ainda funcionam
        a=64'd10; b=64'd3; op=5'd0; #1;
        check(r === 64'd13, "ADD 10+3=13");
        a=64'd10; b=64'd3; op=5'd2; #1;
        check(r === 64'd2, "AND 10&3=2");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
