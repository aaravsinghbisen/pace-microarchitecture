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
module tlb_l2 (
    input  wire        clk, rst_n,
    input  wire        lookup_req,
    input  wire [63:0] lookup_va,
    input  wire [8:0]  lookup_asid,
    output reg         hit,
    output reg  [63:0] pa,
    output reg         perm_r, perm_w, perm_x, perm_u,
    output reg         ready,
    input  wire        upd_en,
    input  wire [63:0] upd_va,
    input  wire [63:0] upd_pa,
    input  wire [8:0]  upd_asid,
    input  wire        upd_r, upd_w, upd_x, upd_u,
    input  wire        flush
);
    localparam SETS = 64;
    localparam WAYS = 8;
    localparam IDX_W = 6;
    localparam WAY_W = 3;
    localparam LAT   = 6;

    reg [20:0] tag_arr [0:SETS-1][0:WAYS-1];
    reg [8:0]  asid_arr[0:SETS-1][0:WAYS-1];
    reg [43:0] ppn_arr [0:SETS-1][0:WAYS-1];
    reg        r_arr   [0:SETS-1][0:WAYS-1];
    reg        w_arr   [0:SETS-1][0:WAYS-1];
    reg        x_arr   [0:SETS-1][0:WAYS-1];
    reg        u_arr   [0:SETS-1][0:WAYS-1];
    reg        v_arr   [0:SETS-1][0:WAYS-1];
    reg [7:0]  age_arr [0:SETS-1][0:WAYS-1];

    // ==== Lookup index/tag (from lookup_va) ====
    wire [IDX_W-1:0] lk_idx = lookup_va[17:12];
    wire [20:0]      lk_tag = lookup_va[38:18];

    // ==== Update index/tag (from upd_va) ====
    wire [IDX_W-1:0] up_idx = upd_va[17:12];
    wire [20:0]      up_tag = upd_va[38:18];

    // Hit detection (combinational, lookup side)
    wire [WAYS-1:0] hit_vec;
    genvar g;
    generate
        for (g = 0; g < WAYS; g = g + 1) begin : ghit
            assign hit_vec[g] = v_arr[lk_idx][g] && tag_arr[lk_idx][g] == lk_tag &&
                                asid_arr[lk_idx][g] == lookup_asid;
        end
    endgenerate

    localparam S_IDLE=0, S_WAIT=1, S_RESP=2;
    reg [1:0] state;
    reg [3:0] cnt;
    reg       hit_r;
    reg [63:0] pa_r;
    reg       r_r, w_r, x_r, u_r;

    // Capture hit_way on req
    reg [WAY_W-1:0] hit_way_r;

    reg [WAY_W-1:0] hit_way;
    integer h;
    always @(*) begin
        hit_way = 0;
        for (h = 0; h < WAYS; h = h + 1)
            if (hit_vec[h]) hit_way = h[WAY_W-1:0];
    end

    // Victim selection uses up_idx (update side)
    reg [WAY_W-1:0] victim;
    reg             found_inv;
    integer vk;
    always @(*) begin
        victim = 0; found_inv = 0;
        for (vk = 0; vk < WAYS; vk = vk + 1)
            if (!v_arr[up_idx][vk]) begin
                victim = vk[WAY_W-1:0];
                found_inv = 1;
            end
        if (!found_inv) begin
            victim = 0;
            for (vk = 1; vk < WAYS; vk = vk + 1)
                if (age_arr[up_idx][vk] > age_arr[up_idx][victim])
                    victim = vk[WAY_W-1:0];
        end
    end

    integer s, w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            ready <= 0; hit <= 0; pa <= 0;
            perm_r <= 0; perm_w <= 0; perm_x <= 0; perm_u <= 0;
            cnt <= 0; hit_r <= 0; pa_r <= 0; r_r<=0; w_r<=0; x_r<=0; u_r<=0;
            hit_way_r <= 0;
            for (s = 0; s < SETS; s = s + 1)
                for (w = 0; w < WAYS; w = w + 1) begin
                    v_arr[s][w]   <= 0;
                    tag_arr[s][w] <= 0;
                    asid_arr[s][w]<= 0;
                    ppn_arr[s][w] <= 0;
                    r_arr[s][w]   <= 0;
                    w_arr[s][w]   <= 0;
                    x_arr[s][w]   <= 0;
                    u_arr[s][w]   <= 0;
                    age_arr[s][w] <= 0;
                end
        end else if (flush) begin
            for (s = 0; s < SETS; s = s + 1)
                for (w = 0; w < WAYS; w = w + 1)
                    v_arr[s][w] <= 0;
            state <= S_IDLE;
            ready <= 0;
        end else begin
            // Aging
            if (lookup_req && state == S_IDLE) begin
                for (w = 0; w < WAYS; w = w + 1) begin
                    if (hit_vec[w]) age_arr[lk_idx][w] <= 0;
                    else if (v_arr[lk_idx][w]) age_arr[lk_idx][w] <= age_arr[lk_idx][w] + 1;
                end
            end

            case (state)
                S_IDLE: begin
                    ready <= 0;
                    if (lookup_req) begin
                        hit_way_r <= hit_way;
                        cnt       <= LAT;
                        state     <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (cnt == 0) begin
                        if (|hit_vec) begin
                            hit_r <= 1;
                            pa_r  <= {8'b0, ppn_arr[lk_idx][hit_way], lookup_va[11:0]};
                            r_r   <= r_arr[lk_idx][hit_way];
                            w_r   <= w_arr[lk_idx][hit_way];
                            x_r   <= x_arr[lk_idx][hit_way];
                            u_r   <= u_arr[lk_idx][hit_way];
                        end else hit_r <= 0;
                        state <= S_RESP;
                    end else cnt <= cnt - 1;
                end
                S_RESP: begin
                    hit    <= hit_r;
                    pa     <= pa_r;
                    perm_r <= r_r;
                    perm_w <= w_r;
                    perm_x <= x_r;
                    perm_u <= u_r;
                    ready  <= 1;
                    state  <= S_IDLE;
                end
            endcase

            // ==== Update (uses up_idx/up_tag from upd_va) ====
            if (upd_en) begin
                tag_arr [up_idx][victim] <= up_tag;
                asid_arr[up_idx][victim] <= upd_asid;
                ppn_arr [up_idx][victim] <= upd_pa[55:12];
                r_arr   [up_idx][victim] <= upd_r;
                w_arr   [up_idx][victim] <= upd_w;
                x_arr   [up_idx][victim] <= upd_x;
                u_arr   [up_idx][victim] <= upd_u;
                v_arr   [up_idx][victim] <= 1;
                age_arr [up_idx][victim] <= 0;
            end
        end
    end
endmodule
