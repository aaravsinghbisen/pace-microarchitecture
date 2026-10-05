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

module ao_core (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory interface
    output wire [63:0] pc_out,
    input  wire [31:0] instr_in,

    // Commit interface
    output wire [63:0] out_pc,
    output wire [31:0] out_instr,
    output wire [63:0] out_result,
    output wire [4:0]  out_rd,
    output wire        out_we,
    output wire        out_valid,

    // Debug RF read
    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_rd
);

    // === PC ===
    reg [63:0] pc;
    assign pc_out = pc;

    // === Pipeline registers ===
    reg [63:0] s1_pc;
    reg [31:0] s1_instr;
    reg        s1_valid;

    reg [63:0] s2_pc;
    reg [31:0] s2_instr;
    reg [6:0]  s2_opcode;
    reg [2:0]  s2_funct3;
    reg [6:0]  s2_funct7;
    reg [4:0]  s2_rd;
    reg [63:0] s2_rs1_val;
    reg [63:0] s2_rs2_val;
    reg [63:0] s2_imm;
    reg        s2_we;
    reg        s2_valid;

    reg [63:0] s3_pc;
    reg [31:0] s3_instr;
    reg [4:0]  s3_rd;
    reg [63:0] s3_result;
    reg        s3_we;
    reg        s3_valid;

    reg [63:0] s4_pc;
    reg [31:0] s4_instr;
    reg [4:0]  s4_rd;
    reg [63:0] s4_result;
    reg        s4_we;
    reg        s4_valid;

    // === Decoder (on s1_instr, combinational) ===
    wire [6:0]  dec_opcode, dec_funct7;
    wire [2:0]  dec_funct3;
    wire [4:0]  dec_rd, dec_rs1, dec_rs2;
    wire [63:0] dec_imm;
    wire [2:0]  dec_format;

    decoder dec (
        .instr(s1_instr),
        .opcode(dec_opcode),
        .rd(dec_rd),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .funct3(dec_funct3),
        .funct7(dec_funct7),
        .imm(dec_imm),
        .format(dec_format)
    );

    // === Register File ===
    wire [63:0] rf_rd1, rf_rd2;
    wire        rf_we = s4_valid && s4_we && (s4_rd != 5'd0);

    register_file rf (
        .clk(clk), .rst_n(rst_n),
        .we(rf_we), .rd(s4_rd), .wd(s4_result),
        .rs1(dec_rs1), .rs2(dec_rs2),
        .rd1(rf_rd1), .rd2(rf_rd2),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
    );

    // === ALU control ===
    function [3:0] alu_ctrl;
        input [6:0] opcode;
        input [2:0] funct3;
        input [6:0] funct7;
        begin
            case (opcode)
                7'b0110011: begin // R-type
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
                7'b0010011: begin // I-type
                    case (funct3)
                        3'b000: alu_ctrl = 4'b0000;
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

    // === ALU ===
    wire [63:0] alu_in0 = s2_rs1_val;
    wire [63:0] alu_in1 = (s2_opcode == 7'b0010011) ? s2_imm : s2_rs2_val;
    wire [3:0]  alu_op  = alu_ctrl(s2_opcode, s2_funct3, s2_funct7);
    wire [63:0] alu_out;

    alu_rv64 alu (
        .in0_alu(alu_in0),
        .in1_alu(alu_in1),
        .opcd_alu(alu_op),
        .out_alu(alu_out)
    );

    // === Write-enable decode (only R-type and I-type for now) ===
    wire s2_we_comb = (dec_opcode == 7'b0110011) || (dec_opcode == 7'b0010011);

    // === Pipeline ===
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 64'd0;
            s1_pc <= 0; s1_instr <= 0; s1_valid <= 0;
            s2_pc <= 0; s2_instr <= 0; s2_opcode <= 0; s2_funct3 <= 0;
            s2_funct7 <= 0; s2_rd <= 0; s2_rs1_val <= 0; s2_rs2_val <= 0;
            s2_imm <= 0; s2_we <= 0; s2_valid <= 0;
            s3_pc <= 0; s3_instr <= 0; s3_rd <= 0; s3_result <= 0;
            s3_we <= 0; s3_valid <= 0;
            s4_pc <= 0; s4_instr <= 0; s4_rd <= 0; s4_result <= 0;
            s4_we <= 0; s4_valid <= 0;
        end else begin
            // IF
            pc <= pc + 4;
            s1_pc <= pc;
            s1_instr <= instr_in;
            s1_valid <= 1'b1;

            // ID
            s2_pc <= s1_pc;
            s2_instr <= s1_instr;
            s2_opcode <= dec_opcode;
            s2_funct3 <= dec_funct3;
            s2_funct7 <= dec_funct7;
            s2_rd <= dec_rd;
            s2_rs1_val <= rf_rd1;
            s2_rs2_val <= rf_rd2;
            s2_imm <= dec_imm;
            s2_we <= s2_we_comb;
            s2_valid <= s1_valid;

            // EX
            s3_pc <= s2_pc;
            s3_instr <= s2_instr;
            s3_rd <= s2_rd;
            s3_result <= alu_out;
            s3_we <= s2_we;
            s3_valid <= s2_valid;

            // MEM
            s4_pc <= s3_pc;
            s4_instr <= s3_instr;
            s4_rd <= s3_rd;
            s4_result <= s3_result;
            s4_we <= s3_we;
            s4_valid <= s3_valid;
        end
    end

    assign out_pc     = s4_pc;
    assign out_instr  = s4_instr;
    assign out_result = s4_result;
    assign out_rd     = s4_rd;
    assign out_we     = s4_we;
    assign out_valid  = s4_valid;

endmodule
