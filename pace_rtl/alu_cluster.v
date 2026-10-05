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
module alu_cluster #(parameter N=6, parameter DATA_W=64) (
    input  wire clk, rst_n,
    input  wire [N-1:0]        in_valid,
    input  wire [N-1:0]        in_is_fpu,
    input  wire [N*7-1:0]      in_opcode,
    input  wire [N*3-1:0]      in_funct3,
    input  wire [N*7-1:0]      in_funct7,
    input  wire [N*5-1:0]      in_rs1, in_rs2, in_rd,
    input  wire [N*DATA_W-1:0] in_rs1_val, in_rs2_val, in_imm,
    output wire [N-1:0]        out_we,
    output wire [N*5-1:0]      out_rd,
    output wire [N*DATA_W-1:0] out_result
);
    wire [N*DATA_W-1:0] rs1_fwd, rs2_fwd;

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_fwd
            wire [DATA_W-1:0] r1_base = in_rs1_val[gi*DATA_W +: DATA_W];
            wire [DATA_W-1:0] r2_base = in_rs2_val[gi*DATA_W +: DATA_W];
            wire [4:0]        my_rs1  = in_rs1[gi*5 +: 5];
            wire [4:0]        my_rs2  = in_rs2[gi*5 +: 5];

            wire [DATA_W-1:0] r1_chain [0:N-1];
            wire [DATA_W-1:0] r2_chain [0:N-1];

            for (gj = 0; gj < N; gj = gj + 1) begin : g_chain
                // Valor anterior na cadeia (ou base, se gj==0)
                wire [DATA_W-1:0] prev1 = (gj == 0) ? r1_base : r1_chain[gj-1];
                wire [DATA_W-1:0] prev2 = (gj == 0) ? r2_base : r2_chain[gj-1];

                if (gj < gi) begin
                    // Slot gj é mais velho → pode forwardar
                    wire match1 = in_valid[gj] &&
                                  (in_rd[gj*5 +: 5] != 5'd0) &&
                                  (in_rd[gj*5 +: 5] == my_rs1) &&
                                  !in_is_fpu[gj];
                    wire match2 = in_valid[gj] &&
                                  (in_rd[gj*5 +: 5] != 5'd0) &&
                                  (in_rd[gj*5 +: 5] == my_rs2) &&
                                  !in_is_fpu[gj];
                    assign r1_chain[gj] = match1 ? out_result[gj*DATA_W +: DATA_W] : prev1;
                    assign r2_chain[gj] = match2 ? out_result[gj*DATA_W +: DATA_W] : prev2;
                end else begin
                    // Slot gj >= gi: não pode forwardar
                    assign r1_chain[gj] = prev1;
                    assign r2_chain[gj] = prev2;
                end
            end

            assign rs1_fwd[gi*DATA_W +: DATA_W] = r1_chain[N-1];
            assign rs2_fwd[gi*DATA_W +: DATA_W] = r2_chain[N-1];
        end
    endgenerate

    // ============ Lanes de execução ============
    genvar gk;
    generate
        for (gk = 0; gk < N; gk = gk + 1) begin : g_lane
            wire [63:0] r1 = rs1_fwd[gk*DATA_W +: DATA_W];
            wire [63:0] r2 = rs2_fwd[gk*DATA_W +: DATA_W];
            wire [63:0] im = in_imm[gk*DATA_W +: DATA_W];
            wire [6:0]  opc = in_opcode[gk*7 +: 7];
            wire [2:0]  f3  = in_funct3[gk*3 +: 3];
            wire [6:0]  f7  = in_funct7[gk*7 +: 7];
            wire        is_fpu = in_is_fpu[gk];

            reg [4:0] alu_op;
            always @(*) begin
                case (opc)
                    7'b0110011: begin
                        if (f7 == 7'b0000001) begin  // M extension
                            case (f3)
                                3'b000: alu_op = 5'd10;  // MUL
                                3'b001: alu_op = 5'd11;  // MULH
                                3'b010: alu_op = 5'd12;  // MULHSU
                                3'b011: alu_op = 5'd13;  // MULHU
                                3'b100: alu_op = 5'd14;  // DIV
                                3'b101: alu_op = 5'd15;  // DIVU
                                3'b110: alu_op = 5'd16;  // REM
                                3'b111: alu_op = 5'd17;  // REMU
                            endcase
                        end else begin
                            case (f3)
                                3'b000: alu_op = f7[5] ? 5'd1  : 5'd0;
                                3'b001: alu_op = 5'd5;
                                3'b010: alu_op = 5'd8;
                                3'b011: alu_op = 5'd9;
                                3'b100: alu_op = 5'd4;
                                3'b101: alu_op = f7[5] ? 5'd7  : 5'd6;
                                3'b110: alu_op = 5'd3;
                                3'b111: alu_op = 5'd2;
                            endcase
                        end
                    end
                    7'b0010011: case (f3)
                        3'b000: alu_op = 5'd0;
                        3'b001: alu_op = 5'd5;
                        3'b010: alu_op = 5'd8;
                        3'b011: alu_op = 5'd9;
                        3'b100: alu_op = 5'd4;
                        3'b101: alu_op = f7[5] ? 5'd7 : 5'd6;
                        3'b110: alu_op = 5'd3;
                        3'b111: alu_op = 5'd2;
                        default: alu_op = 5'd0;
                    endcase
                    default: alu_op = 5'd0;
                endcase
            end

            wire [63:0] alu_b = (opc == 7'b0010011) ? im : r2;
            wire [63:0] alu_r;
            alu_rv64 u_alu (.in0_alu(r1), .in1_alu(alu_b),
                            .opcd_alu(alu_op), .out_alu(alu_r));

            wire [3:0] fpu_op = {1'b0, f3[2], f3[1:0]};
            wire [63:0] fpu_r;
            fpu_arith u_fpu (.a(r1), .b(r2), .op(fpu_op),
                             .result(fpu_r), .status_dbg());

            assign out_result[gk*DATA_W +: DATA_W] = is_fpu ? fpu_r : alu_r;
        end
    endgenerate

    assign out_we = in_valid;
    assign out_rd = in_rd;
endmodule
