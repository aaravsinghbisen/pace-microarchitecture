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
module shadow_rf_multi #(
    parameter DEPTH = 512, parameter DATA_WIDTH = 72,
    parameter N_READ = 4, parameter N_WRITE = 6
)(
    input  wire clk, rst_n,
    input  wire [N_WRITE-1:0]              wr_en,
    input  wire [N_WRITE*DATA_WIDTH-1:0]   wr_data,
    input  wire [N_WRITE-1:0]              wr_exception,
    output wire [3:0]                      wr_ready,
    output wire                            wr_full,
    input  wire [N_READ-1:0]               rd_en,
    output wire [N_READ*DATA_WIDTH-1:0]    rd_data,
    output wire [N_READ-1:0]               rd_valid,
    output wire                            rd_empty,
    output wire [$clog2(DEPTH):0] dbg_wr_ptr,
    output wire [$clog2(DEPTH):0] dbg_rd_ptr
);
    localparam PTR_W  = $clog2(DEPTH) + 1;
    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem_data [0:DEPTH-1];
    reg                  mem_exc  [0:DEPTH-1];
    reg [PTR_W-1:0]      wr_ptr, rd_ptr;

    wire [PTR_W-1:0] count = wr_ptr - rd_ptr;
    assign wr_full  = (count >= DEPTH[PTR_W-1:0] - N_WRITE[PTR_W-1:0]);
    wire [PTR_W-1:0] free_slots = DEPTH[PTR_W-1:0] - count;
    assign wr_ready = (free_slots >= 6) ? 4'd6 : free_slots[3:0];
    assign rd_empty = (count == 0);

    // ===== Read ports (validade baseada em count) =====
    genvar gr;
    generate
        for (gr = 0; gr < N_READ; gr = gr + 1) begin : g_rd
            wire [PTR_W-1:0] my_ptr = rd_ptr + gr[PTR_W-1:0];
            assign rd_data [gr*DATA_WIDTH +: DATA_WIDTH] = mem_data[my_ptr[ADDR_W-1:0]];
            assign rd_valid[gr] = (count > gr[PTR_W-1:0]);
        end
    endgenerate

    // ===== Advance: apenas os heads "líderes" contíguos =====
    // Se AO0 não consome, nada avança (preserva entrada 0).
    // Se AO0 consome mas AO1 não, avança 1.
    // Se AO0 e AO1 consomem e há >= 2, avança 2. Etc.
    reg [2:0] advance;
    always @(*) begin
        if      (!rd_en[0] || count < 1) advance = 0;
        else if (!rd_en[1] || count < 2) advance = 1;
        else if (!rd_en[2] || count < 3) advance = 2;
        else if (!rd_en[3] || count < 4) advance = 3;
        else                              advance = 4;
    end

    // ===== Write side =====
    wire [N_WRITE-1:0] wr_accept;
    assign wr_accept[0] = wr_en[0] && (count             < DEPTH[PTR_W-1:0]);
    assign wr_accept[1] = wr_en[1] && (count + 1'b1      < DEPTH[PTR_W-1:0]);
    assign wr_accept[2] = wr_en[2] && (count + 2'd2      < DEPTH[PTR_W-1:0]);
    assign wr_accept[3] = wr_en[3] && (count + 2'd3      < DEPTH[PTR_W-1:0]);
    assign wr_accept[4] = wr_en[4] && (count + 2'd4      < DEPTH[PTR_W-1:0]);
    assign wr_accept[5] = wr_en[5] && (count + 2'd5      < DEPTH[PTR_W-1:0]);

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_ptr <= 0;
        else begin
            for (k = 0; k < N_WRITE; k = k + 1) begin
                if (wr_accept[k]) begin
                    mem_data[wr_ptr[ADDR_W-1:0] + k[ADDR_W-1:0]] <=
                        wr_data[k*DATA_WIDTH +: DATA_WIDTH];
                    mem_exc [wr_ptr[ADDR_W-1:0] + k[ADDR_W-1:0]] <= wr_exception[k];
                end
            end
            if      (wr_accept[5]) wr_ptr <= wr_ptr + 6;
            else if (wr_accept[4]) wr_ptr <= wr_ptr + 5;
            else if (wr_accept[3]) wr_ptr <= wr_ptr + 4;
            else if (wr_accept[2]) wr_ptr <= wr_ptr + 3;
            else if (wr_accept[1]) wr_ptr <= wr_ptr + 2;
            else if (wr_accept[0]) wr_ptr <= wr_ptr + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_ptr <= 0;
        else if (advance > 0) rd_ptr <= rd_ptr + advance;
    end

    assign dbg_wr_ptr = wr_ptr;
    assign dbg_rd_ptr = rd_ptr;
endmodule
