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
// AO-Core simplificado: consome {rd, data} do shadow RF e commita.
// Pipeline de 4 estágios, throughput 1/ciclo.
module ao_core_fifo (
    input  wire        clk, rst_n,
    input  wire [71:0] shdw_data,    // {3'b0, rd[4:0], data[63:0]}
    input  wire        shdw_valid,
    output wire        shdw_rd_en,
    output wire [4:0]  rf_wr_addr,
    output wire [63:0] rf_wr_data,
    output wire        rf_wr_en
);
    reg [71:0] s1, s2, s3, s4;
    reg v1, v2, v3, v4;

    assign shdw_rd_en = rst_n;  // shadow_rf gateia em !empty

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1<=72'b0; s2<=72'b0; s3<=72'b0; s4<=72'b0;
            v1<=0; v2<=0; v3<=0; v4<=0;
        end else begin
            s1 <= shdw_data;  v1 <= shdw_valid;
            s2 <= s1;         v2 <= v1;
            s3 <= s2;         v3 <= v2;
            s4 <= s3;         v4 <= v3;
        end
    end

    assign rf_wr_addr = s4[68:64];
    assign rf_wr_data = s4[63:0];
    assign rf_wr_en   = v4 && (s4[68:64] != 5'd0);
endmodule
