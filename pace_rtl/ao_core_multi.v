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
// 4 AO-Cores lendo em paralelo do Shadow RF.
// Cada head lê {3'b0, rd[4:0], data[63:0]} = 72 bits.
// Pipeline de 4 estágios por AO.
module ao_core_multi #(
    parameter N_AO = 4,
    parameter DATA_WIDTH = 72
)(
    input  wire clk, rst_n,
    // Shadow RF read
    input  wire [N_AO*DATA_WIDTH-1:0] shdw_data,
    input  wire [N_AO-1:0]            shdw_valid,
    output wire [N_AO-1:0]            shdw_rd_en,
    // Arch RF write
    output wire [N_AO-1:0]            rf_we,
    output wire [N_AO*5-1:0]          rf_rd,
    output wire [N_AO*64-1:0]         rf_wd
);
    genvar gi;
    generate
        for (gi = 0; gi < N_AO; gi = gi + 1) begin : g_ao
            wire [71:0] din = shdw_data[gi*DATA_WIDTH +: DATA_WIDTH];
            wire        vin = shdw_valid[gi];

            reg [71:0] s1, s2, s3, s4;
            reg        v1, v2, v3, v4;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1<=0; s2<=0; s3<=0; s4<=0;
                    v1<=0; v2<=0; v3<=0; v4<=0;
                end else begin
                    s1 <= din;  v1 <= vin;
                    s2 <= s1;   v2 <= v1;
                    s3 <= s2;   v3 <= v2;
                    s4 <= s3;   v4 <= v3;
                end
            end

            assign shdw_rd_en[gi] = rst_n;
            assign rf_we[gi] = v4 && (s4[68:64] != 5'd0);
            assign rf_rd[gi*5 +: 5] = s4[68:64];
            assign rf_wd[gi*64 +: 64] = s4[63:0];
        end
    endgenerate
endmodule
