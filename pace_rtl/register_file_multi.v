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
module register_file_multi #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 5,
    parameter N_WRITE = 4
)(
    input  wire clk, rst_n,
    // Write ports
    input  wire [N_WRITE-1:0]              we,
    input  wire [N_WRITE*ADDR_WIDTH-1:0]   rd,
    input  wire [N_WRITE*DATA_WIDTH-1:0]   wd,
    // Read ports (1 pra PCU, 1 pra debug)
    input  wire [ADDR_WIDTH-1:0]           rs1, rs2,
    output wire [DATA_WIDTH-1:0]           rd1, rd2,
    input  wire [ADDR_WIDTH-1:0]           dbg_rs,
    output wire [DATA_WIDTH-1:0]           dbg_rd
);
    reg [DATA_WIDTH-1:0] regs [0:31];
    integer k;

    assign rd1 = (rs1 == 5'd0) ? 0 : regs[rs1];
    assign rd2 = (rs2 == 5'd0) ? 0 : regs[rs2];
    assign dbg_rd = (dbg_rs == 5'd0) ? 0 : regs[dbg_rs];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 32; k = k + 1) regs[k] <= 0;
        end else begin
            for (k = 0; k < N_WRITE; k = k + 1) begin
                if (we[k] && (rd[k*ADDR_WIDTH +: ADDR_WIDTH] != 5'd0))
                    regs[rd[k*ADDR_WIDTH +: ADDR_WIDTH]] <=
                        wd[k*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end
endmodule
