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

module register_file #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 5
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    we,
    input  wire [ADDR_WIDTH-1:0]   rd,
    input  wire [DATA_WIDTH-1:0]   wd,
    input  wire [ADDR_WIDTH-1:0]   rs1,
    input  wire [ADDR_WIDTH-1:0]   rs2,
    output wire [DATA_WIDTH-1:0]   rd1,
    output wire [DATA_WIDTH-1:0]   rd2,
    // Debug read port (for testbench peek)
    input  wire [ADDR_WIDTH-1:0]   dbg_rs,
    output wire [DATA_WIDTH-1:0]   dbg_rd
);

    reg [DATA_WIDTH-1:0] regs [0:31];

    assign rd1    = (rs1    == 5'd0) ? {DATA_WIDTH{1'b0}} : regs[rs1];
    assign rd2    = (rs2    == 5'd0) ? {DATA_WIDTH{1'b0}} : regs[rs2];
    assign dbg_rd = (dbg_rs == 5'd0) ? {DATA_WIDTH{1'b0}} : regs[dbg_rs];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {DATA_WIDTH{1'b0}};
        end else if (we && rd != 5'd0) begin
            regs[rd] <= wd;
        end
    end

endmodule
