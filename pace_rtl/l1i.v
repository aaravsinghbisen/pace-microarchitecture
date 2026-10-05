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
module l1i #(
    parameter ADDR_W=64, parameter INSTR_W=32,
    parameter SETS=128, parameter WAYS=4,
    parameter LINE_INSTR=8
)(
    input  wire clk, rst_n,
    input  wire [ADDR_W-1:0] fetch_pc,
    output wire [INSTR_W-1:0] fetch_instr,
    output wire stall,                          // high when not ready
    output reg  l2_req,
    output reg  [ADDR_W-1:0] l2_addr,
    input  wire [LINE_INSTR*INSTR_W-1:0] l2_data,
    input  wire l2_ready
);
    localparam LINE_BYTES = LINE_INSTR*(INSTR_W/8);
    localparam OFF_W = $clog2(LINE_BYTES);
    localparam IDX_W = $clog2(SETS);
    localparam TAG_W = ADDR_W-OFF_W-IDX_W;
    localparam LINE_W= LINE_INSTR*INSTR_W;
    localparam WAY_W = $clog2(WAYS);

    reg [LINE_W-1:0] data_arr [0:1][0:SETS-1][0:WAYS-1];
    reg [TAG_W-1:0]  tag_arr  [0:1][0:SETS-1][0:WAYS-1];
    reg              valid_arr[0:1][0:SETS-1][0:WAYS-1];

    wire [IDX_W-1:0] fidx = fetch_pc[OFF_W+IDX_W-1:OFF_W];
    wire [TAG_W-1:0] ftag = fetch_pc[ADDR_W-1:OFF_W+IDX_W];
    wire [2:0]       iidx = fetch_pc[4:2];

    wire [WAYS-1:0] hv0, hv1;
    genvar g;
    generate for (g=0; g<WAYS; g=g+1) begin : gh
        assign hv0[g] = valid_arr[0][fidx][g] && (tag_arr[0][fidx][g]==ftag);
        assign hv1[g] = valid_arr[1][fidx][g] && (tag_arr[1][fidx][g]==ftag);
    end endgenerate
    wire hit0 = |hv0, hit1 = |hv1, hit = hit0|hit1;

    reg [WAY_W-1:0] hw0, hw1;
    integer h;
    always @(*) begin
        hw0=0; hw1=0;
        for (h=0; h<WAYS; h=h+1) begin
            if (hv0[h]) hw0 = h[WAY_W-1:0];
            if (hv1[h]) hw1 = h[WAY_W-1:0];
        end
    end

    // Combinational read on hit
    wire [LINE_W-1:0] cur_line = hit0 ? data_arr[0][fidx][hw0] :
                                 hit1 ? data_arr[1][fidx][hw1] : 0;
    assign fetch_instr = cur_line[iidx*INSTR_W +: INSTR_W];

    // FSM
    localparam S_IDLE=0, S_REQ=1, S_WAIT=2, S_FILL=3;
    reg [1:0] state;
    reg [IDX_W-1:0] miss_idx;
    reg [TAG_W-1:0] miss_tag;
    reg             miss_bank;
    reg [WAY_W-1:0] victim;

    integer vk; reg found_inv;
    always @(*) begin
        victim=0; found_inv=0;
        for (vk=0; vk<WAYS; vk=vk+1)
            if (!valid_arr[miss_bank][miss_idx][vk]) begin
                victim=vk[WAY_W-1:0]; found_inv=1;
            end
    end

    assign stall = !hit;

    integer r,s0,w0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; l2_req<=0; l2_addr<=0;
            miss_idx<=0; miss_tag<=0; miss_bank<=0;
            for (r=0;r<2;r=r+1) for (s0=0;s0<SETS;s0=s0+1) for (w0=0;w0<WAYS;w0=w0+1) begin
                valid_arr[r][s0][w0]<=0; tag_arr[r][s0][w0]<=0; data_arr[r][s0][w0]<=0;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    l2_req<=0;
                    if (!hit) begin
                        miss_idx<=fidx; miss_tag<=ftag;
                        miss_bank <= !hit1;   // prefetch direction
                        l2_req<=1;
                        l2_addr<={fetch_pc[ADDR_W-1:OFF_W],{OFF_W{1'b0}}};
                        state<=S_REQ;
                    end
                end
                S_REQ: state<=S_WAIT;
                S_WAIT: if (l2_ready) begin l2_req<=0; state<=S_FILL; end
                S_FILL: begin
                    data_arr [miss_bank][miss_idx][victim] <= l2_data;
                    tag_arr  [miss_bank][miss_idx][victim] <= miss_tag;
                    valid_arr[miss_bank][miss_idx][victim] <= 1;
                    state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
