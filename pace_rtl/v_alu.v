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
// Vector ALU: 128 bits = 2 elementos de 64 bits (SEW=64)
// Também suporta SEW=32: 4 elementos de 32 bits
// Opcode (v_alu_op):
//   0000=VADD   0001=VSUB   0010=VAND   0011=VOR
//   0100=VXOR   0101=VSLL   0110=VSRL   0111=VSRA
//   1000=VMUL   1001=VMIN   1010=VMAX
module v_alu #(
    parameter VLE = 128,
    parameter SEW = 64
)(
    input  wire [VLE-1:0] a,
    input  wire [VLE-1:0] b,
    input  wire [3:0]     op,
    input  wire [VLE-1:0] mask,       // v0 (bit per element)
    input  wire           mask_en,    // usar masking
    output wire [VLE-1:0] result
);
    localparam NELEM = VLE / SEW;

    genvar gi;
    generate
        for (gi = 0; gi < NELEM; gi = gi + 1) begin : g_elem
            wire [SEW-1:0] ai = a[gi*SEW +: SEW];
            wire [SEW-1:0] bi = b[gi*SEW +: SEW];
            wire           mi = mask[gi];

            reg [SEW-1:0] ri;
            always @(*) begin
                case (op)
                    4'b0000: ri = ai + bi;
                    4'b0001: ri = ai - bi;
                    4'b0010: ri = ai & bi;
                    4'b0011: ri = ai | bi;
                    4'b0100: ri = ai ^ bi;
                    4'b0101: ri = ai << bi[5:0];               // shift logico esquerda
                    4'b0110: ri = ai >> bi[5:0];               // shift logico direita
                    4'b0111: ri = $signed(ai) >>> bi[5:0];     // shift aritmetico direita
                    4'b1000: ri = (ai * bi);                   // mul (baixos 64)
                    4'b1001: ri = ($signed(ai) < $signed(bi)) ? ai : bi;  // min signed
                    4'b1010: ri = ($signed(ai) > $signed(bi)) ? ai : bi;  // max signed
                    default: ri = 0;
                endcase
            end

            // Masking: se mi=0, mantém valor antigo (a)
            wire [SEW-1:0] final_r = (mask_en && !mi) ? ai : ri;

            assign result[gi*SEW +: SEW] = final_r;
        end
    endgenerate
endmodule
