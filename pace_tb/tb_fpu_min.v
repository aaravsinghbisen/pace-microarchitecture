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
module tb_fpu_min;
    reg clk=0, rst_n=0, start=0;
    reg [63:0] a, b;
    reg [3:0]  op;
    wire [63:0] result;
    wire done, busy;

    fpu_arith dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .a(a), .b(b), .op(op),
        .result(result), .done(done), .busy(busy)
    );

    always #5 clk = ~clk;

    integer cyc;

    initial begin
        #20 rst_n = 1; #5;
        $display("=== FPU minimal test ===");
        $display("Testing ADD.D only");

        a = $realtobits(3.5); b = $realtobits(1.25); op = 4'b0001;
        @(negedge clk); start = 1;
        @(posedge clk); @(negedge clk); start = 0;

        cyc = 0;
        while (!done && cyc < 100) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        $display("done=%b after %0d cycles", done, cyc);
        $display("result = %f (expected 4.75)", $bitstoreal(result));
        $display("busy = %b", busy);
        $finish;
    end
endmodule
