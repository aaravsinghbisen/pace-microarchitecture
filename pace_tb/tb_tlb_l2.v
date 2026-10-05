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
module tb_tlb_l2;
    reg clk = 0, rst_n;
    reg         lookup_req;
    reg  [63:0] lookup_va;
    reg  [8:0]  lookup_asid;
    wire        hit, ready;
    wire [63:0] pa;
    wire        perm_r, perm_w, perm_x, perm_u;
    reg         upd_en;
    reg  [63:0] upd_va, upd_pa;
    reg  [8:0]  upd_asid;
    reg         upd_r, upd_w, upd_x, upd_u;
    reg         flush;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer cyc;

    tlb_l2 dut (
        .clk(clk), .rst_n(rst_n),
        .lookup_req(lookup_req), .lookup_va(lookup_va), .lookup_asid(lookup_asid),
        .hit(hit), .pa(pa), .perm_r(perm_r), .perm_w(perm_w),
        .perm_x(perm_x), .perm_u(perm_u), .ready(ready),
        .upd_en(upd_en), .upd_va(upd_va), .upd_pa(upd_pa), .upd_asid(upd_asid),
        .upd_r(upd_r), .upd_w(upd_w), .upd_x(upd_x), .upd_u(upd_u),
        .flush(flush)
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

    task update;
        input [63:0] v, p; input [8:0] a; input r, w, x, u;
        begin
            @(negedge clk);
            upd_en=1; upd_va=v; upd_pa=p; upd_asid=a;
            upd_r=r; upd_w=w; upd_x=x; upd_u=u;
            @(posedge clk); @(negedge clk);
            upd_en=0;
        end
    endtask

    task lookup;
        input [63:0] v; input [8:0] a;
        begin
            @(negedge clk);
            lookup_va=v; lookup_asid=a; lookup_req=1;
            @(posedge clk); @(negedge clk);
            lookup_req=0;
            cyc = 0;
            while (!ready && cyc < 30) begin
                @(posedge clk); cyc = cyc + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        rst_n=0; lookup_req=0; lookup_va=0; lookup_asid=0;
        upd_en=0; upd_va=0; upd_pa=0; upd_asid=0;
        upd_r=0; upd_w=0; upd_x=0; upd_u=0; flush=0;
        #20 rst_n=1; #5;

        $display("========================================");
        $display("  TLB L2 Testbench");
        $display("========================================");

        // Insert translation
        update(64'h0000_0000_1000_0000, 64'h0000_0000_4000_0000, 9'd0, 1,1,0,1);
        #1;

        lookup(64'h0000_0000_1000_0000, 9'd0);
        check(hit, "T1: hit after insert");
        check(pa === 64'h0000_0000_4000_0000, "T1: PA correct");
        $display("       hit latency = %0d cycles", cyc);
        check(cyc >= 5 && cyc <= 10, "T1: latency ~6-8 cycles");

        lookup(64'h0000_0000_1000_0FFF, 9'd0);
        check(hit && pa === 64'h0000_0000_4000_0FFF, "T2: offset preserved");

        lookup(64'h0000_0000_2000_0000, 9'd0);
        check(!hit, "T3: different VPN -> miss");

        // Insert many, test 8-way
        update(64'h0000_0000_1000_0000, 64'h0000_0000_5000_0000, 9'd1, 1,0,0,0);
        #1;
        lookup(64'h0000_0000_1000_0000, 9'd1);
        check(hit && pa === 64'h0000_0000_5000_0000, "T4: ASID=1 hit");
        lookup(64'h0000_0000_1000_0000, 9'd0);
        check(hit && pa === 64'h0000_0000_4000_0000, "T4: ASID=0 still hit");

        // Flush
        @(negedge clk); flush=1; @(posedge clk); @(negedge clk); flush=0;
        lookup(64'h0000_0000_1000_0000, 9'd0);
        check(!hit, "T5: flush clears");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
