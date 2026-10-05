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
module shadow_rf #(
    parameter DEPTH = 512,
    parameter DATA_WIDTH = 64,
    parameter PORTS = 6
)(
    input  wire clk, rst_n,
    // Porta única de leitura
    input  wire rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire rd_exception, rd_valid, rd_empty,
    // Portas de escrita paralelas
    input  wire [PORTS-1:0]              wr_en,
    input  wire [PORTS*DATA_WIDTH-1:0]   wr_data,
    input  wire [PORTS-1:0]              wr_exception,
    output wire [3:0]                    wr_ready,   // quantas escritas cabem
    output wire                          wr_full,
    // Debug
    output wire [$clog2(DEPTH):0] dbg_wr_ptr,
    output wire [$clog2(DEPTH):0] dbg_rd_ptr
);
    localparam PTR_W  = $clog2(DEPTH) + 1;
    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem_data [0:DEPTH-1];
    reg                  mem_exc  [0:DEPTH-1];
    reg [PTR_W-1:0]      wr_ptr, rd_ptr;

    wire [PTR_W-1:0] count = wr_ptr - rd_ptr;
    assign wr_full  = (count == DEPTH[PTR_W-1:0]);
    assign wr_ready = DEPTH[PTR_W-1:0] - count;   // espaços livres
    assign rd_empty = (wr_ptr == rd_ptr);
    assign rd_valid = ~rd_empty;
    assign rd_data  = mem_data[rd_ptr[ADDR_W-1:0]];
    assign rd_exception = mem_exc[rd_ptr[ADDR_W-1:0]];
    assign dbg_wr_ptr = wr_ptr;
    assign dbg_rd_ptr = rd_ptr;

    // Conta escritas válidas neste ciclo
    wire [PORTS-1:0] wr_accept;
    assign wr_accept[0] = wr_en[0] && (count     < DEPTH[PTR_W-1:0]);
    assign wr_accept[1] = wr_en[1] && (count + 1 < DEPTH[PTR_W-1:0]);
    assign wr_accept[2] = wr_en[2] && (count + 2 < DEPTH[PTR_W-1:0]);
    assign wr_accept[3] = wr_en[3] && (count + 3 < DEPTH[PTR_W-1:0]);
    assign wr_accept[4] = wr_en[4] && (count + 4 < DEPTH[PTR_W-1:0]);
    assign wr_accept[5] = wr_en[5] && (count + 5 < DEPTH[PTR_W-1:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else begin
            for (integer i = 0; i < PORTS; i = i + 1) begin
                if (wr_accept[i]) begin
                    mem_data[wr_ptr[ADDR_W-1:0] + i[ADDR_W-1:0]] <=
                        wr_data[i*DATA_WIDTH +: DATA_WIDTH];
                    mem_exc [wr_ptr[ADDR_W-1:0] + i[ADDR_W-1:0]] <=
                        wr_exception[i];
                end
            end
            if (wr_accept[0])      wr_ptr <= wr_ptr + 1;
            if (wr_accept[5])      wr_ptr <= wr_ptr + 6;
            else if (wr_accept[4]) wr_ptr <= wr_ptr + 5;
            else if (wr_accept[3]) wr_ptr <= wr_ptr + 4;
            else if (wr_accept[2]) wr_ptr <= wr_ptr + 3;
            else if (wr_accept[1]) wr_ptr <= wr_ptr + 2;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_ptr <= 0;
        else if (rd_en && !rd_empty) rd_ptr <= rd_ptr + 1;
    end
endmodule
