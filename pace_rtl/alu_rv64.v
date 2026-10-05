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
module alu_rv64 (
    input  wire [63:0] in0_alu,
    input  wire [63:0] in1_alu,
    input  wire [4:0]  opcd_alu,
    output reg  [63:0] out_alu
);
    localparam OP_ADD    = 5'd0;
    localparam OP_SUB    = 5'd1;
    localparam OP_AND    = 5'd2;
    localparam OP_OR     = 5'd3;
    localparam OP_XOR    = 5'd4;
    localparam OP_SLL    = 5'd5;
    localparam OP_SRL    = 5'd6;
    localparam OP_SRA    = 5'd7;
    localparam OP_SLT    = 5'd8;
    localparam OP_SLTU   = 5'd9;
    localparam OP_MUL    = 5'd10;
    localparam OP_MULH   = 5'd11;
    localparam OP_MULHSU = 5'd12;
    localparam OP_MULHU  = 5'd13;
    localparam OP_DIV    = 5'd14;
    localparam OP_DIVU   = 5'd15;
    localparam OP_REM    = 5'd16;
    localparam OP_REMU   = 5'd17;

    wire signed [63:0]  sa = $signed(in0_alu);
    wire signed [63:0]  sb = $signed(in1_alu);
    wire signed [127:0] prod_ss = sa * sb;
    wire        [127:0] prod_uu = in0_alu * in1_alu;
    wire signed [127:0] prod_su = sa * $signed({1'b0, in1_alu});

    wire div_ovf = (in0_alu == 64'h8000_0000_0000_0000) && (in1_alu == 64'hFFFF_FFFF_FFFF_FFFF);

    always @(*) begin
        case (opcd_alu)
            OP_ADD:    out_alu = in0_alu + in1_alu;
            OP_SUB:    out_alu = in0_alu - in1_alu;
            OP_AND:    out_alu = in0_alu & in1_alu;
            OP_OR:     out_alu = in0_alu | in1_alu;
            OP_XOR:    out_alu = in0_alu ^ in1_alu;
            OP_SLL:    out_alu = in0_alu << in1_alu[5:0];
            OP_SRL:    out_alu = in0_alu >> in1_alu[5:0];
            OP_SRA:    out_alu = $signed(in0_alu) >>> in1_alu[5:0];
            OP_SLT:    out_alu = (sa < sb) ? 64'd1 : 64'd0;
            OP_SLTU:   out_alu = (in0_alu < in1_alu) ? 64'd1 : 64'd0;
            OP_MUL:    out_alu = in0_alu * in1_alu;
            OP_MULH:   out_alu = prod_ss[127:64];
            OP_MULHSU: out_alu = prod_su[127:64];
            OP_MULHU:  out_alu = prod_uu[127:64];
            OP_DIV:    out_alu = (in1_alu == 0)         ? 64'hFFFF_FFFF_FFFF_FFFF :
                                 (div_ovf)              ? 64'h8000_0000_0000_0000 :
                                                          $signed(sa / sb);
            OP_DIVU:   out_alu = (in1_alu == 0)         ? 64'hFFFF_FFFF_FFFF_FFFF :
                                                          in0_alu / in1_alu;
            OP_REM:    out_alu = (in1_alu == 0)         ? in0_alu :
                                 (div_ovf)              ? 64'd0 : $signed(sa % sb);
            OP_REMU:   out_alu = (in1_alu == 0)         ? in0_alu :
                                                          in0_alu % in1_alu;
            default:   out_alu = 0;
        endcase
    end
endmodule
