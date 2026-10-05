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
module tb_fpu_dbg;
    reg  [63:0] a, b;
    reg  [3:0]  op;
    wire [63:0] result;
    wire [7:0]  status_dbg;

    fpu_arith dut (.a(a), .b(b), .op(op), .result(result), .status_dbg(status_dbg));

    initial begin
        $display("=== FPU single debug (hex inputs) ===");

        // 3.5 = 0x40600000, 1.25 = 0x3FA00000 -> 4.75 = 0x40980000
        a = {32'b0, 32'h4060_0000}; b = {32'b0, 32'h3FA0_0000}; op = 4'b0000; #1;
        $display("ADD.S 3.5+1.25:  a=%h b=%h -> r=%h (expected 40980000, %f)",
                 a[31:0], b[31:0], result[31:0], $bitstoshortreal(result[31:0]));

        // 2.5 * 4 = 10.0  (0x40200000 * 0x40800000 = 0x41200000)
        a = {32'b0, 32'h4020_0000}; b = {32'b0, 32'h4080_0000}; op = 4'b0100; #1;
        $display("MUL.S 2.5*4:     r=%h (expected 41200000, %f)",
                 result[31:0], $bitstoshortreal(result[31:0]));

        // 1.0 + 1.0 = 2.0  (0x3F800000 + 0x3F800000 = 0x40000000)
        a = {32'b0, 32'h3F80_0000}; b = {32'b0, 32'h3F80_0000}; op = 4'b0000; #1;
        $display("ADD.S 1+1:       r=%h (expected 40000000, %f)",
                 result[31:0], $bitstoshortreal(result[31:0]));

        // 100.0 - 99.5 = 0.5  (0x42C80000 - 0x42C70000 = 0x3F000000)
        a = {32'b0, 32'h42C8_0000}; b = {32'b0, 32'h42C7_0000}; op = 4'b0010; #1;
        $display("SUB.S 100-99.5:  r=%h (expected 3F000000, %f)",
                 result[31:0], $bitstoshortreal(result[31:0]));

        // 1.0 + 0.0
        a = {32'b0, 32'h3F80_0000}; b = 64'd0; op = 4'b0000; #1;
        $display("ADD.S 1+0:       r=%h (expected 3F800000)",
                 result[31:0]);

        $finish;
    end
endmodule
