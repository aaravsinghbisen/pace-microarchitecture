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
// Contadores de performance do PACE
module perf_counters (
    input  wire clk, rst_n, enable,

    // Contagem de instruções (commits do Arch RF)
    input  wire        commit_en,

    // Shadow RF
    input  wire        shdw_wr_en,
    input  wire        shdw_rd_en,
    input  wire        shdw_empty,
    input  wire        shdw_full,
    input  wire [5:0]  shdw_count,

    // Store buffer
    input  wire        sb_push,
    input  wire        sb_hit,
    input  wire        sb_miss,

    // Caches L1i / L1d
    input  wire        l1i_hit, l1i_miss,
    input  wire        l1d_hit, l1d_miss,
    input  wire        l2_hit, l2_miss,

    // MMU
    input  wire        tlb_l1_hit, tlb_l1_miss,
    input  wire        tlb_l2_hit, tlb_l2_miss,

    // Runahead
    input  wire        runahead_active,
    input  wire        runahead_enter,
    input  wire        runahead_exit,

    // Saídas
    output reg  [63:0] cycles,
    output reg  [63:0] instr_retired,
    output reg  [31:0] shdw_writes,
    output reg  [31:0] shdw_reads,
    output reg  [31:0] shdw_stall_cycles,
    output reg  [31:0] sb_pushes,
    output reg  [31:0] sb_forward_hits,
    output reg  [31:0] l1i_hit_cnt, l1i_miss_cnt,
    output reg  [31:0] l1d_hit_cnt, l1d_miss_cnt,
    output reg  [31:0] l2_hit_cnt,  l2_miss_cnt,
    output reg  [31:0] tlb_l1_hit_cnt, tlb_l1_miss_cnt,
    output reg  [31:0] tlb_l2_hit_cnt, tlb_l2_miss_cnt,
    output reg  [31:0] runahead_cycles,
    output reg  [31:0] runahead_entries,

    // Métricas calculadas (x1000 para precisão inteira)
    output wire [31:0] ipc_x1000,
    output wire [31:0] l1d_hit_rate_x1000,
    output wire [31:0] l1i_hit_rate_x1000
);
    wire go = enable && rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycles <= 0; instr_retired <= 0;
            shdw_writes <= 0; shdw_reads <= 0; shdw_stall_cycles <= 0;
            sb_pushes <= 0; sb_forward_hits <= 0;
            l1i_hit_cnt <= 0; l1i_miss_cnt <= 0;
            l1d_hit_cnt <= 0; l1d_miss_cnt <= 0;
            l2_hit_cnt <= 0;  l2_miss_cnt <= 0;
            tlb_l1_hit_cnt <= 0; tlb_l1_miss_cnt <= 0;
            tlb_l2_hit_cnt <= 0; tlb_l2_miss_cnt <= 0;
            runahead_cycles <= 0; runahead_entries <= 0;
        end else if (go) begin
            cycles          <= cycles + 1;
            if (commit_en)    instr_retired <= instr_retired + 1;

            if (shdw_wr_en)   shdw_writes <= shdw_writes + 1;
            if (shdw_rd_en && !shdw_empty) shdw_reads <= shdw_reads + 1;
            if (shdw_empty)   shdw_stall_cycles <= shdw_stall_cycles + 1;

            if (sb_push)      sb_pushes <= sb_pushes + 1;
            if (sb_hit)       sb_forward_hits <= sb_forward_hits + 1;

            if (l1i_hit)      l1i_hit_cnt <= l1i_hit_cnt + 1;
            if (l1i_miss)     l1i_miss_cnt <= l1i_miss_cnt + 1;
            if (l1d_hit)      l1d_hit_cnt <= l1d_hit_cnt + 1;
            if (l1d_miss)     l1d_miss_cnt <= l1d_miss_cnt + 1;
            if (l2_hit)       l2_hit_cnt <= l2_hit_cnt + 1;
            if (l2_miss)      l2_miss_cnt <= l2_miss_cnt + 1;
            if (tlb_l1_hit)   tlb_l1_hit_cnt <= tlb_l1_hit_cnt + 1;
            if (tlb_l1_miss)  tlb_l1_miss_cnt <= tlb_l1_miss_cnt + 1;
            if (tlb_l2_hit)   tlb_l2_hit_cnt <= tlb_l2_hit_cnt + 1;
            if (tlb_l2_miss)  tlb_l2_miss_cnt <= tlb_l2_miss_cnt + 1;

            if (runahead_active) runahead_cycles <= runahead_cycles + 1;
            if (runahead_enter)  runahead_entries <= runahead_entries + 1;
        end
    end

    // IPC x1000 = (instr * 1000) / cycles
    assign ipc_x1000 = (cycles == 0) ? 0 : (instr_retired * 1000) / cycles;
    assign l1d_hit_rate_x1000 = ((l1d_hit_cnt + l1d_miss_cnt) == 0) ? 0 :
        (l1d_hit_cnt * 1000) / (l1d_hit_cnt + l1d_miss_cnt);
    assign l1i_hit_rate_x1000 = ((l1i_hit_cnt + l1i_miss_cnt) == 0) ? 0 :
        (l1i_hit_cnt * 1000) / (l1i_hit_cnt + l1i_miss_cnt);
endmodule
