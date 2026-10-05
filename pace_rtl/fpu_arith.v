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
// FPU aritmética combinacional usando CNRV-FPU (RISC-V native).
// Suporta: ADD.S/D, SUB.S/D, MUL.S/D
// DIV/SQRT ficam pra fase 2 (precisam de R5FP_int_div_sqrt)
module fpu_arith (
    input  wire [63:0] a, b,
    input  wire [3:0]  op,       // 0000=ADD.S 0010=SUB.S 0100=MUL.S
                                  // 0001=ADD.D 0011=SUB.D 0101=MUL.D
    output wire [63:0] result,
    output wire [7:0]  status_dbg
);
    wire is_d   = op[0];
    wire is_sub = op[1];
    wire is_mul = op[2];

    // SUB = ADD com sign flip de B
    wire [31:0] a_s = a[31:0];
    wire [31:0] b_s = b[31:0] ^ (is_sub ? 32'h8000_0000 : 32'h0);
    wire [63:0] a_d = a;
    wire [63:0] b_d = b ^ (is_sub ? 64'h8000_0000_0000_0000 : 64'h0);

    // ============ SINGLE ============
    wire [7:0]  s_a_zExp; wire [7:0] s_a_tzc; wire [5:0] s_a_zSt;
    wire [26:0] s_a_zSig; wire s_a_zSign;
    R5FP_add #(.EXP_W(8), .SIG_W(23)) u_s_add (
        .a(a_s), .b(b_s),
        .zExp(s_a_zExp), .tailZeroCnt(s_a_tzc),
        .zStatus(s_a_zSt), .zSig(s_a_zSig), .zSign(s_a_zSign)
    );
    wire [31:0] s_a_result; wire [7:0] s_a_post;
    R5FP_postproc #(.I_SIG_W(27), .SIG_W(23), .EXP_W(8)) u_s_add_post (
        .aExp(s_a_zExp), .aStatus(s_a_zSt), .aSig(s_a_zSig), .aSign(s_a_zSign),
        .specialTiny(1'b0), .zToInf(1'b0), .rnd(3'b0), .tailZeroCnt(s_a_tzc),
        .z(s_a_result), .zStatus(s_a_post)
    );

    wire [7:0]  s_m_zExp; wire [7:0] s_m_tzc; wire [5:0] s_m_zSt;
    wire [48:0] s_m_zSig; wire s_m_zSign, s_m_toInf;
    R5FP_mul #(.EXP_W(8), .SIG_W(23)) u_s_mul (
        .a(a_s), .b(b_s),
        .zExp(s_m_zExp), .tailZeroCnt(s_m_tzc),
        .zStatus(s_m_zSt), .zSig(s_m_zSig),
        .toInf(s_m_toInf), .zSign(s_m_zSign)
    );
    wire [31:0] s_m_result; wire [7:0] s_m_post;
    R5FP_postproc #(.I_SIG_W(49), .SIG_W(23), .EXP_W(8)) u_s_mul_post (
        .aExp(s_m_zExp), .aStatus(s_m_zSt), .aSig(s_m_zSig), .aSign(s_m_zSign),
        .specialTiny(1'b0), .zToInf(s_m_toInf), .rnd(3'b0), .tailZeroCnt(s_m_tzc),
        .z(s_m_result), .zStatus(s_m_post)
    );

    // ============ DOUBLE ============
    wire [10:0] d_a_zExp; wire [10:0] d_a_tzc; wire [5:0] d_a_zSt;
    wire [55:0] d_a_zSig; wire d_a_zSign;
    R5FP_add #(.EXP_W(11), .SIG_W(52)) u_d_add (
        .a(a_d), .b(b_d),
        .zExp(d_a_zExp), .tailZeroCnt(d_a_tzc),
        .zStatus(d_a_zSt), .zSig(d_a_zSig), .zSign(d_a_zSign)
    );
    wire [63:0] d_a_result; wire [7:0] d_a_post;
    R5FP_postproc #(.I_SIG_W(56), .SIG_W(52), .EXP_W(11)) u_d_add_post (
        .aExp(d_a_zExp), .aStatus(d_a_zSt), .aSig(d_a_zSig), .aSign(d_a_zSign),
        .specialTiny(1'b0), .zToInf(1'b0), .rnd(3'b0), .tailZeroCnt(d_a_tzc),
        .z(d_a_result), .zStatus(d_a_post)
    );

    wire [10:0]  d_m_zExp; wire [10:0] d_m_tzc; wire [5:0] d_m_zSt;
    wire [106:0] d_m_zSig; wire d_m_zSign, d_m_toInf;
    R5FP_mul #(.EXP_W(11), .SIG_W(52)) u_d_mul (
        .a(a_d), .b(b_d),
        .zExp(d_m_zExp), .tailZeroCnt(d_m_tzc),
        .zStatus(d_m_zSt), .zSig(d_m_zSig),
        .toInf(d_m_toInf), .zSign(d_m_zSign)
    );
    wire [63:0] d_m_result; wire [7:0] d_m_post;
    R5FP_postproc #(.I_SIG_W(107), .SIG_W(52), .EXP_W(11)) u_d_mul_post (
        .aExp(d_m_zExp), .aStatus(d_m_zSt), .aSig(d_m_zSig), .aSign(d_m_zSign),
        .specialTiny(1'b0), .zToInf(d_m_toInf), .rnd(3'b0), .tailZeroCnt(d_m_tzc),
        .z(d_m_result), .zStatus(d_m_post)
    );

    // ============ Output mux ============
    wire [31:0] s_out = is_mul ? s_m_result : s_a_result;
    wire [63:0] d_out = is_mul ? d_m_result : d_a_result;
    wire [7:0]  s_st  = is_mul ? s_m_post   : s_a_post;
    wire [7:0]  d_st  = is_mul ? d_m_post   : d_a_post;

    assign result    = is_d ? d_out : {32'b0, s_out};
    assign status_dbg= is_d ? d_st  : s_st;
endmodule
