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
// L2 unified: 1 MB, 8-way, 64B lines, ~14 cycle hit latency
// Write-through handled by L1d; L2 does local update only.
module l2 #(
    parameter ADDR_W = 64, parameter DATA_W = 64,
    parameter SETS = 2048, parameter WAYS = 8,
    parameter LINE_WORDS = 8, parameter HIT_LAT = 14
)(
    input  wire clk, rst_n,
    input  wire                    p0_req,
    input  wire [ADDR_W-1:0]       p0_addr,
    output reg  [LINE_WORDS*DATA_W-1:0] p0_rdata,
    output reg                     p0_ready,
    input  wire                    p1_req,
    input  wire                    p1_we,
    input  wire [ADDR_W-1:0]       p1_addr,
    input  wire [DATA_W-1:0]       p1_wdata,
    output reg  [LINE_WORDS*DATA_W-1:0] p1_rdata,
    output reg                     p1_ready,
    output reg                     mem_req,
    output reg                     mem_we,
    output reg  [ADDR_W-1:0]       mem_addr,
    output reg  [LINE_WORDS*DATA_W-1:0] mem_wdata,
    input  wire [LINE_WORDS*DATA_W-1:0] mem_rdata,
    input  wire                    mem_ready
);
    localparam LINE_BYTES = LINE_WORDS * (DATA_W/8);
    localparam OFF_W  = $clog2(LINE_BYTES);
    localparam IDX_W  = $clog2(SETS);
    localparam TAG_W  = ADDR_W - OFF_W - IDX_W;
    localparam LINE_W = LINE_WORDS * DATA_W;
    localparam WAY_W  = $clog2(WAYS);

    reg [LINE_W-1:0] data_arr [0:SETS-1][0:WAYS-1];
    reg [TAG_W-1:0]  tag_arr  [0:SETS-1][0:WAYS-1];
    reg              valid_arr[0:SETS-1][0:WAYS-1];
    reg [7:0]        age_arr  [0:SETS-1][0:WAYS-1];

    localparam S_IDLE      = 4'd0,
               S_LOOKUP    = 4'd1,
               S_HIT_WAIT  = 4'd2,
               S_HIT_RESP  = 4'd3,
               S_MEM_REQ   = 4'd5,
               S_MEM_WAIT  = 4'd6,
               S_FILL      = 4'd7;

    reg [3:0] state;
    reg [3:0] delay_cnt;
    reg [ADDR_W-1:0] cur_addr;
    reg              cur_we, cur_port;
    reg [DATA_W-1:0] cur_wdata;

    wire [OFF_W-1:0] off = cur_addr[OFF_W-1:0];
    wire [IDX_W-1:0] idx = cur_addr[OFF_W+IDX_W-1:OFF_W];
    wire [TAG_W-1:0] tg  = cur_addr[ADDR_W-1:OFF_W+IDX_W];

    wire [WAYS-1:0] hit_vec;
    genvar gw;
    generate
        for (gw = 0; gw < WAYS; gw = gw + 1) begin : g_hit
            assign hit_vec[gw] = valid_arr[idx][gw] && (tag_arr[idx][gw] == tg);
        end
    endgenerate
    wire hit = |hit_vec;

    reg [WAY_W-1:0] hit_way;
    integer hwi;
    always @(*) begin
        hit_way = 0;
        for (hwi = 0; hwi < WAYS; hwi = hwi + 1)
            if (hit_vec[hwi]) hit_way = hwi[WAY_W-1:0];
    end

    reg [WAY_W-1:0] victim_way;
    reg vi_found_inv;
    integer vk;
    always @(*) begin
        victim_way = 0;
        vi_found_inv = 0;
        for (vk = 0; vk < WAYS; vk = vk + 1) begin
            if (!valid_arr[idx][vk]) begin
                victim_way = vk[WAY_W-1:0];
                vi_found_inv = 1;
            end
        end
        if (!vi_found_inv) begin
            victim_way = 0;
            for (vk = 1; vk < WAYS; vk = vk + 1)
                if (age_arr[idx][vk] > age_arr[idx][victim_way])
                    victim_way = vk[WAY_W-1:0];
        end
    end

    integer s, w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            p0_ready <= 0; p1_ready <= 0;
            p0_rdata <= 0; p1_rdata <= 0;
            mem_req <= 0; mem_we <= 0; mem_addr <= 0; mem_wdata <= 0;
            cur_addr <= 0; cur_we <= 0; cur_port <= 0; cur_wdata <= 0;
            delay_cnt <= 0;
            for (s = 0; s < SETS; s = s + 1)
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid_arr[s][w] <= 0; tag_arr[s][w] <= 0;
                    age_arr[s][w] <= 0;   data_arr[s][w] <= 0;
                end
        end else begin
            p0_ready <= 0;
            p1_ready <= 0;
            mem_req  <= 0;

            case (state)
                S_IDLE: begin
                    delay_cnt <= 0;
                    if (p0_req) begin
                        cur_port <= 0; cur_addr <= p0_addr;
                        cur_we <= 0; cur_wdata <= 0;
                        state <= S_LOOKUP;
                    end else if (p1_req) begin
                        cur_port <= 1; cur_addr <= p1_addr;
                        cur_we <= p1_we; cur_wdata <= p1_wdata;
                        state <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    if (hit) begin
                        delay_cnt <= HIT_LAT - 2;
                        state <= S_HIT_WAIT;
                    end else begin
                        state <= S_MEM_REQ;
                    end
                end

                S_HIT_WAIT: begin
                    if (delay_cnt == 0) state <= S_HIT_RESP;
                    else                delay_cnt <= delay_cnt - 1;
                end

                S_HIT_RESP: begin
                    if (cur_port == 0) begin
                        p0_rdata <= data_arr[idx][hit_way];
                        p0_ready <= 1;
                    end else begin
                        p1_rdata <= data_arr[idx][hit_way];
                        p1_ready <= 1;
                        if (cur_we)
                            data_arr[idx][hit_way]
                              [off[OFF_W-1:3]*DATA_W +: DATA_W] <= cur_wdata;
                    end
                    age_arr[idx][hit_way] <= 0;
                    state <= S_IDLE;
                end

                S_MEM_REQ: begin
                    mem_req   <= 1;
                    mem_we    <= 0;
                    mem_addr  <= {cur_addr[ADDR_W-1:OFF_W], {OFF_W{1'b0}}};
                    mem_wdata <= 0;
                    state     <= S_MEM_WAIT;
                end

                S_MEM_WAIT: begin
                    if (mem_ready) begin
                        mem_req <= 0;
                        state   <= S_FILL;
                    end
                end

                S_FILL: begin
                    data_arr [idx][victim_way] <= mem_rdata;
                    tag_arr  [idx][victim_way] <= tg;
                    valid_arr[idx][victim_way] <= 1;
                    age_arr  [idx][victim_way] <= 0;

                    if (cur_we)
                        data_arr[idx][victim_way]
                          [off[OFF_W-1:3]*DATA_W +: DATA_W] <= cur_wdata;

                    if (cur_port == 0) begin
                        p0_rdata <= mem_rdata;
                        p0_ready <= 1;
                    end else begin
                        p1_rdata <= mem_rdata;
                        p1_ready <= 1;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
