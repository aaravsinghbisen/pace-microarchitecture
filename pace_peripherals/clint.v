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
module clint (
    input  wire        clk, rst_n,
    input  wire        req, we,
    input  wire [63:0] addr, wdata,
    output reg  [63:0] rdata,
    output reg         ready,
    input  wire        tick,
    output wire        mtip,
    output wire        msip_o
);
    localparam BASE = 32'h0200_0000;

    reg [63:0] mtime;
    reg [63:0] mtimecmp;
    reg        msip;

    wire [31:0] off = addr[31:0] - BASE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime    <= 64'd0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
            msip     <= 1'b0;
        end else begin
            if (tick) mtime <= mtime + 1;
            if (req && we) begin
                case (off)
                    32'h0000: msip            <= wdata[0];
                    32'h4000: mtimecmp[31:0]  <= wdata[31:0];
                    32'h4004: mtimecmp[63:32] <= wdata[31:0];
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        ready = 1'b1;
        case (off)
            32'h0000: rdata = {63'b0, msip};
            32'h4000: rdata = {32'b0, mtimecmp[31:0]};
            32'h4004: rdata = {32'b0, mtimecmp[63:32]};
            32'hBFF8: rdata = {32'b0, mtime[31:0]};
            32'hBFFC: rdata = {32'b0, mtime[63:32]};
            default:  rdata = 64'd0;
        endcase
    end

    assign mtip   = (mtime >= mtimecmp);
    assign msip_o = msip;
endmodule
