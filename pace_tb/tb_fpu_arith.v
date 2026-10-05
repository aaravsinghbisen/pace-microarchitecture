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
module tb_fpu_arith;
    reg  [63:0] a, b;
    reg  [3:0]  op;
    wire [63:0] result;
    wire [7:0]  status_dbg;

    integer tests_run=0, tests_passed=0, tests_failed=0;

    fpu_arith dut (.a(a), .b(b), .op(op), .result(result), .status_dbg(status_dbg));

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
        $display("  FPU Arith (CNRV-FPU) - hex verif");
        $display("========================================");

        // === DOUBLE ===
        // 3.5 + 1.25 = 4.75  -> 0x400E000000000000  (3.5=400C.., 1.25=3FF4.., 4.75=401300..)
        // Valores em hex double:
        //   3.5  = 0x400C000000000000
        //   1.25 = 0x3FF4000000000000
        //   4.75 = 0x4013000000000000
        //   10.0 = 0x4024000000000000
        //   0.5  = 0x3FE0000000000000
        //   9.5  = 0x4023000000000000
        //   2.5  = 0x4004000000000000
        //   4.0  = 0x4010000000000000
        //   1.5  = 0x3FF8000000000000
        //  -3.25 = 0xC00A000000000000
        //  -1.75 = 0xBFFC000000000000

        // ADD.D 3.5+1.25
        a = 64'h400C_0000_0000_0000; b = 64'h3FF4_0000_0000_0000; op = 4'b0001; #1;
        check(result === 64'h4013_0000_0000_0000, "ADD.D 3.5+1.25=4.75");

        // SUB.D 10-0.5
        a = 64'h4024_0000_0000_0000; b = 64'h3FE0_0000_0000_0000; op = 4'b0011; #1;
        check(result === 64'h4023_0000_0000_0000, "SUB.D 10-0.5=9.5");

        // MUL.D 2.5*4
        a = 64'h4004_0000_0000_0000; b = 64'h4010_0000_0000_0000; op = 4'b0101; #1;
        check(result === 64'h4024_0000_0000_0000, "MUL.D 2.5*4=10");

        // ADD.D 1.5+(-3.25)
        a = 64'h3FF8_0000_0000_0000; b = 64'hC00A_0000_0000_0000; op = 4'b0001; #1;
        check(result === 64'hBFFC_0000_0000_0000, "ADD.D 1.5+(-3.25)=-1.75");

        // === SINGLE ===
        // 3.5    = 0x40600000
        // 1.25   = 0x3FA00000
        // 4.75   = 0x40980000
        // 100.0  = 0x42C80000
        // 99.5   = 0x42C70000
        // 0.5    = 0x3F000000
        // 2.5    = 0x40200000
        // 4.0    = 0x40800000
        // 10.0   = 0x41200000

        a = {32'b0, 32'h4060_0000}; b = {32'b0, 32'h3FA0_0000}; op = 4'b0000; #1;
        check(result[31:0] === 32'h4098_0000, "ADD.S 3.5+1.25=4.75");

        a = {32'b0, 32'h42C8_0000}; b = {32'b0, 32'h42C7_0000}; op = 4'b0010; #1;
        check(result[31:0] === 32'h3F00_0000, "SUB.S 100-99.5=0.5");

        a = {32'b0, 32'h4020_0000}; b = {32'b0, 32'h4080_0000}; op = 4'b0100; #1;
        check(result[31:0] === 32'h4120_0000, "MUL.S 2.5*4=10");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
