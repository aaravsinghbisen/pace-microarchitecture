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
module tb_direct;
    reg clk=0, rst=1;
    reg [31:0] a, b;
    reg a_stb=0, b_stb=0, z_ack=0;
    wire a_ack, b_ack, z_stb;
    wire [31:0] z;
    integer cyc;

    adder uut (
        .clk(clk), .rst(rst),
        .input_a(a), .input_a_stb(a_stb), .input_a_ack(a_ack),
        .input_b(b), .input_b_stb(b_stb), .input_b_ack(b_ack),
        .output_z(z), .output_z_stb(z_stb), .output_z_ack(z_ack)
    );

    always #5 clk = ~clk;

    initial begin
        a = $shortrealtobits(1.5);
        b = $shortrealtobits(2.25);

        #20 rst = 0;
        #10;

        $display("=== Direct adder test ===");
        $display("t=%0t a_stb=1", $time);
        a_stb = 1;
        cyc = 0;
        while (!a_ack && cyc < 50) begin @(posedge clk); cyc = cyc + 1; end
        $display("  a_ack after %0d cycles", cyc);

        b_stb = 1;
        cyc = 0;
        while (!b_ack && cyc < 50) begin @(posedge clk); cyc = cyc + 1; end
        $display("  b_ack after %0d cycles", cyc);

        a_stb = 0; b_stb = 0;
        cyc = 0;
        while (!z_stb && cyc < 50) begin @(posedge clk); cyc = cyc + 1; end
        $display("  z_stb after %0d cycles", cyc);
        $display("  z = %f (expected 3.75)", $bitstoshortreal(z));

        z_ack = 1;
        @(posedge clk);
        z_ack = 0;
        #50 $finish;
    end
endmodule
