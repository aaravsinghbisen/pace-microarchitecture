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
module decoder (
    input  wire [31:0] instr,
    output wire [6:0]  opcode,
    output wire [4:0]  rd, rs1, rs2,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [63:0] imm,
    output wire [2:0]  format,
    // SYSTEM
    output wire        is_system,
    output wire        is_ecall,
    output wire        is_ebreak,
    output wire        is_mret,
    output wire        is_sret,
    output wire        is_csr,
    output wire [11:0] csr_addr,
    // Vector
    output wire        is_vsetvli,
    output wire        is_vsetivli,
    output wire        is_vsetvl,
    output wire        is_vector,       // any OP-V (arith, mask, load/store)
    output wire [5:0]  v_vm,            // [0] = vm bit (bit 25)
    output wire [5:0]  v_funct6
);
    localparam FMT_R=3'd0, FMT_I=3'd1, FMT_S=3'd2, FMT_B=3'd3, FMT_U=3'd4, FMT_J=3'd5, FMT_UNK=3'd7;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];
    assign csr_addr = instr[31:20];
    assign v_vm     = {5'b0, instr[25]};
    assign v_funct6 = instr[31:26];

    reg [2:0] fmt;
    always @(*) begin
        case (opcode)
            7'b0110011: fmt = FMT_R;
            7'b0010011, 7'b0000011, 7'b1100111, 7'b1110011: fmt = FMT_I;
            7'b0100011: fmt = FMT_S;
            7'b1100011: fmt = FMT_B;
            7'b0110111, 7'b0010111: fmt = FMT_U;
            7'b1101111: fmt = FMT_J;
            default:    fmt = FMT_UNK;
        endcase
    end
    assign format = fmt;

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    reg [31:0] imm32;
    always @(*) begin
        case (fmt)
            FMT_I: imm32 = imm_i;
            FMT_S: imm32 = imm_s;
            FMT_B: imm32 = imm_b;
            FMT_U: imm32 = imm_u;
            FMT_J: imm32 = imm_j;
            default: imm32 = 0;
        endcase
    end
    assign imm = {{32{imm32[31]}}, imm32};

    assign is_system = (opcode == 7'b1110011);
    assign is_ecall  = is_system && (funct3 == 3'b000) && (csr_addr == 12'h000);
    assign is_ebreak = is_system && (funct3 == 3'b000) && (csr_addr == 12'h001);
    assign is_sret   = is_system && (funct3 == 3'b000) && (csr_addr == 12'h102);
    assign is_mret   = is_system && (funct3 == 3'b000) && (csr_addr == 12'h302);
    assign is_csr    = is_system && (funct3 != 3'b000);

    // Vector
    assign is_vsetvli  = (opcode == 7'b1010111) && (funct3 == 3'b111) && (instr[31] == 1'b0);
    assign is_vsetivli = (opcode == 7'b1010111) && (funct3 == 3'b111) && (instr[31] == 1'b1) && (instr[30] == 1'b0);
    assign is_vsetvl   = (opcode == 7'b1010111) && (funct3 == 3'b111) && (instr[31] == 1'b1) && (instr[30] == 1'b1);
    assign is_vector   = (opcode == 7'b1010111) && (funct3 != 3'b111) && (funct3 != 3'b011);
endmodule
