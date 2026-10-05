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
// AO-Core for PACE:
//   - Primary path: read pre-computed value from Shadow RF
//   - Fallback path: if PCU stalls, compute locally with own ALU
//   - Commits result to architectural RF

module ao_core_pace (
    input  wire        clk,
    input  wire        rst_n,

    output wire [63:0] pc_out,
    input  wire [31:0] instr_in,

    // Shadow RF consumer
    input  wire [63:0] shadow_rd_data,
    input  wire        shadow_rd_valid,
    output wire        shadow_rd_en,

    // PCU status
    input  wire        pcu_stalled, input wire fetch_stall,

    // Architectural RF write
    output wire [4:0]  rf_wr_addr,
    output wire [63:0] rf_wr_data,
    output wire        rf_wr_en
);

    reg [63:0] pc;
    assign pc_out = pc;

    // === S1: fetch ===
    reg [63:0] s1_pc;
    reg [31:0] s1_instr;
    reg        s1_valid;

    // === Decoder ===
    wire [6:0]  d_opcode, d_funct7;
    wire [2:0]  d_funct3;
    wire [4:0]  d_rd, d_rs1, d_rs2;
    wire [63:0] d_imm;
    wire [2:0]  d_format;

    decoder dec (
        .instr(s1_instr),
        .opcode(d_opcode), .rd(d_rd), .rs1(d_rs1), .rs2(d_rs2),
        .funct3(d_funct3), .funct7(d_funct7),
        .imm(d_imm), .format(d_format)
    );

    wire writes_rd = ((d_opcode == 7'b0110011) || (d_opcode == 7'b0010011) || (d_opcode == 7'b0000011))
                     && (d_rd != 5'd0);

    // === Local register mirror (for fallback computation) ===
    reg [63:0] ao_regs [0:31];
    wire [63:0] local_rs1 = (d_rs1 == 5'd0) ? 64'd0 : ao_regs[d_rs1];
    wire [63:0] local_rs2 = (d_rs2 == 5'd0) ? 64'd0 : ao_regs[d_rs2];

    // === ALU control (same as PCU) ===
    function [3:0] alu_ctrl;
        input [6:0] opcode;
        input [2:0] funct3;
        input [6:0] funct7;
        begin
            case (opcode)
                7'b0110011, 7'b0010011: begin
                    case (funct3)
                        3'b000: alu_ctrl = funct7[5] ? 4'b0001 : 4'b0000;
                        3'b001: alu_ctrl = 4'b0101;
                        3'b010: alu_ctrl = 4'b1000;
                        3'b011: alu_ctrl = 4'b1001;
                        3'b100: alu_ctrl = 4'b0100;
                        3'b101: alu_ctrl = funct7[5] ? 4'b0111 : 4'b0110;
                        3'b110: alu_ctrl = 4'b0011;
                        3'b111: alu_ctrl = 4'b0010;
                        default: alu_ctrl = 4'b0000;
                    endcase
                end
                default: alu_ctrl = 4'b0000;
            endcase
        end
    endfunction

    wire [63:0] alu_in1 = (d_opcode == 7'b0010011) ? d_imm : local_rs2;
    wire [3:0]  alu_op  = alu_ctrl(d_opcode, d_funct3, d_funct7);
    wire [63:0] alu_out;

    alu_rv64 u_alu (
        .in0_alu(local_rs1), .in1_alu(alu_in1),
        .opcd_alu(alu_op), .out_alu(alu_out)
    );

    // === Choose source: shadow (primary) vs ALU (fallback) ===
    // If PCU is not stalled AND shadow has data, use shadow.
    wire use_shadow = !pcu_stalled && shadow_rd_valid;
    wire [63:0] s1_result = use_shadow ? shadow_rd_data : alu_out;

    // Pop shadow RF only when we're actually going to consume from it
    assign shadow_rd_en = writes_rd && s1_valid && use_shadow;

    // === S2 ===
    reg [4:0]  s2_rd;
    reg [63:0] s2_result;
    reg        s2_we;
    reg        s2_valid;

    // === S3 ===
    reg [4:0]  s3_rd;
    reg [63:0] s3_result;
    reg        s3_we;
    reg        s3_valid;

    // === S4 ===
    reg [4:0]  s4_rd;
    reg [63:0] s4_result;
    reg        s4_we;
    reg        s4_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 0;
            for (integer k = 0; k < 32; k = k + 1)
                ao_regs[k] <= 64'd0;
            s1_pc <= 0; s1_instr <= 0; s1_valid <= 0;
            s2_rd <= 0; s2_result <= 0; s2_we <= 0; s2_valid <= 0;
            s3_rd <= 0; s3_result <= 0; s3_we <= 0; s3_valid <= 0;
            s4_rd <= 0; s4_result <= 0; s4_we <= 0; s4_valid <= 0;
        end else begin
            if (!fetch_stall) pc <= pc + 4;
            if (!fetch_stall) begin s1_pc <= pc; s1_instr <= instr_in; s1_valid <= 1'b1; end

            s2_rd <= d_rd; s2_result <= s1_result;
            s2_we <= writes_rd && s1_valid; s2_valid <= s1_valid;

            s3_rd <= s2_rd; s3_result <= s2_result;
            s3_we <= s2_we; s3_valid <= s2_valid;

            s4_rd <= s3_rd; s4_result <= s3_result;
            s4_we <= s3_we; s4_valid <= s3_valid;

            // Update local mirror on commit (for fallback operands)
            if (s4_we && s4_valid && s4_rd != 5'd0)
                ao_regs[s4_rd] <= s4_result;
        end
    end

    assign rf_wr_addr = s4_rd;
    assign rf_wr_data = s4_result;
    assign rf_wr_en   = s4_we && s4_valid;

endmodule
