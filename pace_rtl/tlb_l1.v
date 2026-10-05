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
// TLB L1: 64 entradas, fully-associative, 1-cycle lookup
module tlb_l1 (
    input  wire        clk, rst_n,
    input  wire        lookup_req,
    input  wire [63:0] lookup_va,
    input  wire [8:0]  lookup_asid,
    output reg         hit,
    output reg  [63:0] pa,
    output reg         perm_r, perm_w, perm_x, perm_u,
    input  wire        upd_en,
    input  wire [63:0] upd_va,
    input  wire [63:0] upd_pa,
    input  wire [8:0]  upd_asid,
    input  wire        upd_r, upd_w, upd_x, upd_u,
    input  wire        flush
);
    localparam ENTRIES = 64;
    localparam IDX_W   = 6;

    reg [26:0] tag_arr [0:ENTRIES-1];
    reg [8:0]  asid_arr[0:ENTRIES-1];
    reg [43:0] ppn_arr [0:ENTRIES-1];
    reg        r_arr   [0:ENTRIES-1];
    reg        w_arr   [0:ENTRIES-1];
    reg        x_arr   [0:ENTRIES-1];
    reg        u_arr   [0:ENTRIES-1];
    reg        v_arr   [0:ENTRIES-1];
    reg [5:0]  age_arr [0:ENTRIES-1];

    wire [26:0] lookup_tag = lookup_va[38:12];

    integer i;
    always @(*) begin
        hit   = 0;
        pa    = 0;
        perm_r = 0; perm_w = 0; perm_x = 0; perm_u = 0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (v_arr[i] &&
                tag_arr[i] == lookup_tag &&
                asid_arr[i] == lookup_asid) begin
                hit    = 1;
                pa     = {8'b0, ppn_arr[i], lookup_va[11:0]};
                perm_r = r_arr[i];
                perm_w = w_arr[i];
                perm_x = x_arr[i];
                perm_u = u_arr[i];
            end
        end
    end

    reg [IDX_W-1:0] victim;
    reg             found_invalid;
    integer vk;
    always @(*) begin
        victim = 0;
        found_invalid = 0;
        for (vk = 0; vk < ENTRIES; vk = vk + 1) begin
            if (!v_arr[vk]) begin
                victim = vk[IDX_W-1:0];
                found_invalid = 1;
            end
        end
        if (!found_invalid) begin
            victim = 0;
            for (vk = 1; vk < ENTRIES; vk = vk + 1)
                if (age_arr[vk] > age_arr[victim])
                    victim = vk[IDX_W-1:0];
        end
    end

    integer w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (w = 0; w < ENTRIES; w = w + 1) begin
                v_arr[w]   <= 0;
                tag_arr[w] <= 0;
                asid_arr[w]<= 0;
                ppn_arr[w] <= 0;
                r_arr[w]   <= 0;
                w_arr[w]   <= 0;
                x_arr[w]   <= 0;
                u_arr[w]   <= 0;
                age_arr[w] <= 0;
            end
        end else if (flush) begin
            for (w = 0; w < ENTRIES; w = w + 1)
                v_arr[w] <= 0;
        end else begin
            for (w = 0; w < ENTRIES; w = w + 1) begin
                if (lookup_req && v_arr[w] &&
                    tag_arr[w] == lookup_tag && asid_arr[w] == lookup_asid)
                    age_arr[w] <= 0;
                else if (v_arr[w])
                    age_arr[w] <= age_arr[w] + 1;
            end

            if (upd_en) begin
                tag_arr [victim] <= upd_va[38:12];
                asid_arr[victim] <= upd_asid;
                ppn_arr [victim] <= upd_pa[55:12];
                r_arr   [victim] <= upd_r;
                w_arr   [victim] <= upd_w;
                x_arr   [victim] <= upd_x;
                u_arr   [victim] <= upd_u;
                v_arr   [victim] <= 1;
                age_arr [victim] <= 0;
            end
        end
    end
endmodule
