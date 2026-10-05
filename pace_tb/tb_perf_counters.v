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
module tb_perf_counters;
    reg clk=0, rst_n=0, enable=0, commit_en=0;
    reg shdw_wr_en=0, shdw_rd_en=0, shdw_empty=0, shdw_full=0;
    reg [5:0] shdw_count=0;
    reg sb_push=0, sb_hit=0, sb_miss=0;
    reg l1i_hit=0, l1i_miss=0, l1d_hit=0, l1d_miss=0, l2_hit=0, l2_miss=0;
    reg tlb_l1_hit=0, tlb_l1_miss=0, tlb_l2_hit=0, tlb_l2_miss=0;
    reg runahead_active=0, runahead_enter=0, runahead_exit=0;

    wire [63:0] cycles, instr_retired;
    wire [31:0] shdw_writes, shdw_reads, shdw_stall_cycles;
    wire [31:0] sb_pushes, sb_forward_hits;
    wire [31:0] l1i_hit_cnt, l1i_miss_cnt, l1d_hit_cnt, l1d_miss_cnt;
    wire [31:0] l2_hit_cnt, l2_miss_cnt;
    wire [31:0] tlb_l1_hit_cnt, tlb_l1_miss_cnt, tlb_l2_hit_cnt, tlb_l2_miss_cnt;
    wire [31:0] runahead_cycles, runahead_entries;
    wire [31:0] ipc_x1000, l1d_hit_rate_x1000, l1i_hit_rate_x1000;

    integer tests_run=0, tests_passed=0, tests_failed=0;

    perf_counters dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .commit_en(commit_en),
        .shdw_wr_en(shdw_wr_en), .shdw_rd_en(shdw_rd_en),
        .shdw_empty(shdw_empty), .shdw_full(shdw_full), .shdw_count(shdw_count),
        .sb_push(sb_push), .sb_hit(sb_hit), .sb_miss(sb_miss),
        .l1i_hit(l1i_hit), .l1i_miss(l1i_miss),
        .l1d_hit(l1d_hit), .l1d_miss(l1d_miss),
        .l2_hit(l2_hit), .l2_miss(l2_miss),
        .tlb_l1_hit(tlb_l1_hit), .tlb_l1_miss(tlb_l1_miss),
        .tlb_l2_hit(tlb_l2_hit), .tlb_l2_miss(tlb_l2_miss),
        .runahead_active(runahead_active),
        .runahead_enter(runahead_enter), .runahead_exit(runahead_exit),
        .cycles(cycles), .instr_retired(instr_retired),
        .shdw_writes(shdw_writes), .shdw_reads(shdw_reads),
        .shdw_stall_cycles(shdw_stall_cycles),
        .sb_pushes(sb_pushes), .sb_forward_hits(sb_forward_hits),
        .l1i_hit_cnt(l1i_hit_cnt), .l1i_miss_cnt(l1i_miss_cnt),
        .l1d_hit_cnt(l1d_hit_cnt), .l1d_miss_cnt(l1d_miss_cnt),
        .l2_hit_cnt(l2_hit_cnt), .l2_miss_cnt(l2_miss_cnt),
        .tlb_l1_hit_cnt(tlb_l1_hit_cnt), .tlb_l1_miss_cnt(tlb_l1_miss_cnt),
        .tlb_l2_hit_cnt(tlb_l2_hit_cnt), .tlb_l2_miss_cnt(tlb_l2_miss_cnt),
        .runahead_cycles(runahead_cycles), .runahead_entries(runahead_entries),
        .ipc_x1000(ipc_x1000),
        .l1d_hit_rate_x1000(l1d_hit_rate_x1000),
        .l1i_hit_rate_x1000(l1i_hit_rate_x1000)
    );

    always #5 clk = ~clk;

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    integer i;

    initial begin
        #20 rst_n = 1; #5;
        enable = 1;

        $display("========================================");
        $display("  Perf Counters Testbench");
        $display("========================================");

        // Simula 100 ciclos com padrão controlado
        for (i = 0; i < 100; i = i + 1) begin
            @(negedge clk);
            commit_en = (i % 3 == 0);      // 1/3 de commits
            shdw_wr_en = (i % 2 == 0);
            shdw_rd_en = 1; shdw_empty = (i < 20);
            sb_push    = (i % 5 == 0);
            sb_hit     = (i % 7 == 0);
            l1d_hit    = (i % 4 != 0);
            l1d_miss   = (i % 4 == 0);
            l1i_hit    = (i % 8 != 0);
            l1i_miss   = (i % 8 == 0);
        end
        @(negedge clk);
        commit_en = 0; shdw_wr_en = 0; shdw_rd_en = 0;
        shdw_empty = 0; sb_push = 0; sb_hit = 0;
        l1d_hit = 0; l1d_miss = 0; l1i_hit = 0; l1i_miss = 0;

        #5;
        $display("  cycles          = %0d", cycles);
        $display("  instr_retired   = %0d", instr_retired);
        $display("  IPC x1000       = %0d (=%0d.%03d)", ipc_x1000, ipc_x1000/1000, ipc_x1000%1000);
        $display("  L1d hit rate    = %0d.%03d%%", l1d_hit_rate_x1000/1000, l1d_hit_rate_x1000%1000);
        $display("  L1i hit rate    = %0d.%03d%%", l1i_hit_rate_x1000/1000, l1i_hit_rate_x1000%1000);

        check(cycles >= 100 && cycles <= 102, "cycles ~100");
        check(instr_retired > 30 && instr_retired < 40, "instr count ~33");
        check(l1d_hit_rate_x1000 > 700, "L1d hit rate > 70%");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
