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
// PACE II - B-Core (branch scout)
// PCU resolves; B-Core handles the redirect timing.
module b_core (
    input  wire        clk, rst_n,
    input  wire        br_valid,
    input  wire        br_taken,
    input  wire [63:0] br_target,
    input  wire [63:0] br_pc,
    output wire        redirect_valid,
    output wire [63:0] redirect_pc
);
    reg        r_valid, r_taken;
    reg [63:0] r_target, r_pc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_valid <= 0; r_taken <= 0; r_target <= 0; r_pc <= 0;
        end else begin
            r_valid <= br_valid; r_taken <= br_taken;
            r_target <= br_target; r_pc <= br_pc;
        end
    end
    // If taken -> target, else fall-through (pc+4)
    assign redirect_valid = r_valid;
    assign redirect_pc    = r_taken ? r_target : (r_pc + 64'd4);
endmodule
