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
module rvc_decompress (
    input  wire [15:0] instr16,
    output reg  [31:0] instr32,
    output wire        is_compressed,
    output wire        illegal
);
    wire [1:0] op  = instr16[1:0];
    wire [2:0] f3  = instr16[15:13];

    assign is_compressed = (op != 2'b11);
    assign illegal = 0;

    function [4:0] rvc_reg;
        input [2:0] c;
        begin rvc_reg = {2'b01, c}; end
    endfunction

    wire [4:0]  rd_c   = rvc_reg(instr16[4:2]);
    wire [4:0]  rs1_c  = rvc_reg(instr16[9:7]);
    wire [4:0]  rs2_c  = rvc_reg(instr16[4:2]);
    wire [4:0]  rd_full= instr16[11:7];
    wire [4:0]  rs2_full=instr16[6:2];

    wire [11:0] imm_ci  = {{6{instr16[12]}}, instr16[12], instr16[6:2]};
    wire [11:0] imm_cj  = {{4{instr16[12]}}, instr16[12], instr16[8],
                            instr16[10:9], instr16[6], instr16[7],
                            instr16[2], instr16[11], instr16[5:3], 1'b0};
    wire [11:0] imm_cb  = {{4{instr16[12]}}, instr16[12], instr16[6:5],
                            instr16[2], instr16[11:10], instr16[4:3], 1'b0};
    wire [11:0] imm_clw = {{7{1'b0}}, instr16[6], instr16[12:10], instr16[5], 2'b00};
    wire [11:0] imm_csw = imm_clw;
    wire [11:0] imm_lwsp= {{4{1'b0}}, instr16[3:2], instr16[12], instr16[6:4], 2'b00};
    wire [11:0] imm_swsp= {{4{1'b0}}, instr16[8:7], instr16[12:9], 2'b00};
    wire [11:0] imm_caddi16sp = {{3{instr16[12]}}, instr16[12], instr16[4:3],
                                  instr16[5], instr16[2], instr16[6], 4'b0};
    wire [11:0] imm_caddi4spn = {2'b0, instr16[10:7], instr16[12:11],
                                  instr16[5], instr16[6], 2'b0};

    always @(*) begin
        instr32 = 32'h00000013;

        case (op)
            2'b00: begin
                case (f3)
                    3'b000: instr32 = {imm_caddi4spn, 5'd2, 3'b000, rd_c, 7'b0010011};
                    3'b010: instr32 = {imm_clw, rs1_c, 3'b010, rd_c, 7'b0000011};
                    3'b110: instr32 = {imm_csw[11:5], rs2_c, rs1_c, 3'b010,
                                       imm_csw[4:0], 7'b0100011};
                    default: instr32 = 32'h00000013;
                endcase
            end
            2'b01: begin
                case (f3)
                    3'b000: instr32 = {imm_ci, rd_full, 3'b000, rd_full, 7'b0010011};
                    3'b001: instr32 = {imm_ci, rd_full, 3'b000, rd_full, 7'b0011011};
                    3'b010: instr32 = {imm_ci, 5'd0, 3'b000, rd_full, 7'b0010011};
                    3'b011: begin
                        if (rd_full == 5'd2)
                            instr32 = {imm_caddi16sp, 5'd2, 3'b000, 5'd2, 7'b0010011};
                        else
                            instr32 = {imm_ci, rd_full, 7'b0110111};
                    end
                    3'b100: begin
                        case (instr16[11:10])
                            2'b00: instr32 = {imm_ci, rd_c, 3'b101, rd_c, 7'b0010011};
                            2'b01: instr32 = {{6{instr16[12]}}, instr16[12], instr16[6:2],
                                              rd_c, 3'b101, rd_c, 7'b0010011};
                            2'b10: instr32 = {imm_ci, rd_c, 3'b111, rd_c, 7'b0010011};
                            default: instr32 = 32'h00000013;
                        endcase
                    end
                    3'b101: instr32 = {imm_cj[11], imm_cj[4:1], imm_cj[5], imm_cj[10:6],
                                       5'd0, 7'b1101111};
                    3'b110: instr32 = {imm_cb[11], imm_cb[4:1], imm_cb[5], imm_cb[10:6],
                                       rs1_c, 3'b000, imm_cb[3:0], 7'b1100011};
                    3'b111: instr32 = {imm_cb[11], imm_cb[4:1], imm_cb[5], imm_cb[10:6],
                                       rs1_c, 3'b001, imm_cb[3:0], 7'b1100011};
                endcase
            end
            2'b10: begin
                case (f3)
                    3'b000: instr32 = {imm_ci, rd_full, 3'b001, rd_full, 7'b0010011};
                    3'b010: instr32 = {imm_lwsp, 5'd2, 3'b010, rd_full, 7'b0000011};
                    3'b100: begin
                        if (instr16[12] == 0)
                            instr32 = {7'b0, rs2_full, 5'd0, 3'b000, rd_full, 7'b0110011};
                        else if (rd_full == 5'd0 && rs2_full == 5'd0)
                            instr32 = 32'h00100073;
                        else if (rs2_full == 5'd0)
                            instr32 = {12'b0, rd_full, 3'b000, 5'd0, 7'b1100111};
                        else
                            instr32 = {12'b0, rd_full, 3'b000, 5'd1, 7'b1100111};
                    end
                    3'b110: instr32 = {imm_swsp[11:5], rs2_full, 5'd2, 3'b010,
                                       imm_swsp[4:0], 7'b0100011};
                    default: instr32 = 32'h00000013;
                endcase
            end
            2'b11: instr32 = {instr16, 16'b0};
        endcase
    end
endmodule
