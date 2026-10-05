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
// Vector register file: 32 × VLE bits (default VLE=128)
// 2 read ports (vs1, vs2) + 1 write port (vd)
// v0 é máscara (não hardwired, só convenção)
module vector_rf #(
    parameter VLE = 128,
    parameter NREGS = 32
)(
    input  wire clk, rst_n,
    // Read ports
    input  wire [4:0] rs1, rs2,
    output wire [VLE-1:0] rd1, rd2,
    // Write port
    input  wire        we,
    input  wire [4:0]  rd,
    input  wire [VLE-1:0] wd,
    // Debug
    input  wire [4:0]  dbg_rs,
    output wire [VLE-1:0] dbg_rd
);
    reg [VLE-1:0] regs [0:NREGS-1];
    integer k;

    assign rd1    = regs[rs1];
    assign rd2    = regs[rs2];
    assign dbg_rd = regs[dbg_rs];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < NREGS; k = k + 1) regs[k] <= 0;
        end else if (we) begin
            regs[rd] <= wd;
        end
    end
endmodule
