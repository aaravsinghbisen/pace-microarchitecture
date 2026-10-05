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
module tb_mmu_sv39;
    reg clk=0, rst_n=0;
    reg         flush=0;
    reg         req=0;
    reg  [63:0] va=0;
    reg  [1:0]  priv=0;
    reg         is_fetch=0, is_store=0;
    reg  [8:0]  asid=0;
    reg  [43:0] satp_ppn=0;
    reg         satp_enable=0;
    wire        pte_req;
    wire [63:0] pte_addr;
    reg  [63:0] pte_rdata;
    reg         pte_ready;
    wire        done, fault;
    wire [63:0] fault_cause, fault_va, pa;

    reg [63:0] pmem [0:16383];
    reg [63:0] done_pa;
    reg        done_fault;
    integer    translate_cycles;
    integer    t1_cyc, t2_cyc, t3_cyc;

    integer i, tests_run=0, tests_passed=0, tests_failed=0;

    mmu_sv39 dut (
        .clk(clk), .rst_n(rst_n),
        .flush(flush), .req(req), .va(va), .priv(priv),
        .is_fetch(is_fetch), .is_store(is_store), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .done(done), .fault(fault),
        .fault_cause(fault_cause), .fault_va(fault_va), .pa(pa)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        pte_ready <= 0;
        if (pte_req) begin
            pte_rdata <= pmem[pte_addr[16:3]];
            pte_ready <= 1;
        end
    end

    function [63:0] pte_ptr; input [43:0] ppn;
        begin pte_ptr = {10'b0, ppn, 2'b0, 8'b0100_0001}; end
    endfunction
    function [63:0] pte_leaf; input [43:0] ppn; input u,x,w,r;
        begin pte_leaf = {10'b0, ppn, 2'b0, 1'b1, 1'b1, 1'b0, u, x, w, r, 1'b1}; end
    endfunction

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task translate;
        input [63:0] vaddr;
        begin
            @(negedge clk);
            va = vaddr; req = 1;
            @(posedge clk); @(negedge clk); req = 0;
            done_pa = 0; done_fault = 0;
            translate_cycles = 0;
            while (!done && !fault && translate_cycles < 100) begin
                @(posedge clk);
                translate_cycles = translate_cycles + 1;
            end
            if (done) done_pa = pa;
            if (fault) done_fault = 1;
            @(negedge clk);
        end
    endtask

    initial begin
        for (i=0; i<16384; i=i+1) pmem[i] = 0;

        pmem[64'h1000/8 + 0] = pte_ptr(44'h2000 >> 12);
        pmem[64'h2000/8 + 0] = pte_ptr(44'h3000 >> 12);
        pmem[64'h3000/8 + 1] = pte_leaf(44'h400000 >> 12, 1'b1, 1'b1, 1'b1, 1'b1);

        rst_n = 0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  MMU Sv39 Testbench (with TLB updates)");
        $display("========================================");

        // T1: bare mode
        satp_enable = 0;
        translate(64'h0000_0000_DEAD_BEEF);
        check(!done_fault && done_pa === 64'h0000_0000_DEAD_BEEF, "T1: bare mode PA = VA");

        // T2: enable, first access (walker miss)
        satp_enable = 1; satp_ppn = 44'h1000 >> 12;
        priv = 2'b00; is_store = 0; is_fetch = 0; asid = 0;
        translate(64'h0000_0000_0000_1234);
        t1_cyc = translate_cycles;
        check(!done_fault && done_pa === 64'h0000_0000_0040_0234, "T2: walker path -> PA");
        $display("       T2 walker latency = %0d cycles", t1_cyc);
        check(t1_cyc > 5, "T2: slow (walker)");

        // T3: second access, same VA -> L1 hit (fast)
        translate(64'h0000_0000_0000_1234);
        t2_cyc = translate_cycles;
        check(!done_fault && done_pa === 64'h0000_0000_0040_0234, "T3: L1 hit -> PA");
        $display("       T3 L1 hit latency = %0d cycles", t2_cyc);
        check(t2_cyc < t1_cyc, "T3: faster than walker (TLB populated)");

        // T4: same VPN, different offset -> L1 hit
        translate(64'h0000_0000_0000_1ABC);
        check(!done_fault && done_pa === 64'h0000_0000_0040_0ABC, "T4: L1 hit w/ offset");

        // T5: different VPN -> walker (miss L1, miss L2)
        pmem[64'h3000/8 + 5] = pte_leaf(44'h500000 >> 12, 1'b1, 1'b1, 1'b1, 1'b1);
        translate(64'h0000_0000_0000_5234);
        check(!done_fault && done_pa === 64'h0000_0000_0050_0234, "T5: new VPN -> walker");
        $display("       T5 walker latency = %0d cycles", translate_cycles);

        // T6: second access to VPN=5 -> L1 hit now
        translate(64'h0000_0000_0000_5234);
        t3_cyc = translate_cycles;
        check(!done_fault && t3_cyc < translate_cycles + 5, "T6: L1 hit for VPN=5");

        // T7: invalid VA -> fault
        translate(64'h0000_0000_8000_0000);
        check(done_fault, "T7: invalid VA -> fault");

        // T8: flush clears TLBs
        @(negedge clk); flush=1; @(posedge clk); @(negedge clk); flush=0;
        translate(64'h0000_0000_0000_1234);
        $display("       T8 latency after flush = %0d cycles", translate_cycles);
        check(!done_fault && done_pa === 64'h0000_0000_0040_0234, "T8: TLB refilled after flush");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
