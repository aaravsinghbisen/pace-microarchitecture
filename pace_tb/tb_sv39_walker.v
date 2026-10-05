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
module tb_sv39_walker;
    reg clk = 0, rst_n;
    reg         req;
    reg  [63:0] va;
    reg  [1:0]  priv;
    reg         is_fetch, is_store;
    reg  [43:0] satp_ppn;
    wire        mem_req;
    wire [63:0] mem_addr;
    reg  [63:0] mem_rdata;
    reg         mem_ready;
    wire        done, fault;
    wire [63:0] fault_cause, fault_va, pa;

    reg [63:0] pmem [0:16383];

    integer i, tests_run=0, tests_passed=0, tests_failed=0;

    // Latched results
    reg        done_r, fault_r;
    reg [63:0] cause_r, pa_r;

    sv39_walker dut (
        .clk(clk), .rst_n(rst_n),
        .req(req), .va(va), .priv(priv),
        .is_fetch(is_fetch), .is_store(is_store),
        .satp_ppn(satp_ppn),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .done(done), .fault(fault),
        .fault_cause(fault_cause), .fault_va(fault_va), .pa(pa)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_req) begin
            mem_rdata <= pmem[mem_addr[16:3]];
            mem_ready <= 1;
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

    task walk;
        input [63:0] vaddr;
        begin
            @(negedge clk);
            va = vaddr; req = 1;
            @(posedge clk); @(negedge clk); req = 0;

            // Wait for done OR fault, latch them the instant they pulse
            done_r = 0; fault_r = 0; pa_r = 0; cause_r = 0;
            fork
                begin : wait_done
                    while (!done_r && !fault_r) begin
                        @(posedge clk);
                        if (done && !done_r) begin
                            done_r = 1; pa_r = pa;
                        end
                        if (fault && !fault_r) begin
                            fault_r = 1; cause_r = fault_cause;
                        end
                    end
                end
                begin : timeout
                    repeat(50) @(posedge clk);
                end
            join_any
            disable fork;
            @(negedge clk);
        end
    endtask

    initial begin
        for (i=0; i<16384; i=i+1) pmem[i] = 0;

        // Root PT @ 0x1000
        pmem[64'h1000/8 + 0] = pte_ptr(44'h2000 >> 12);
        // PT1 @ 0x2000
        pmem[64'h2000/8 + 0] = pte_ptr(44'h3000 >> 12);
        // PT0 @ 0x3000
        pmem[64'h3000/8 + 1] = pte_leaf(44'h400000 >> 12, 1'b1, 1'b1, 1'b1, 1'b1);
        pmem[64'h3000/8 + 2] = pte_leaf(44'h500000 >> 12, 1'b0, 1'b0, 1'b1, 1'b0);
        pmem[64'h3000/8 + 3] = pte_leaf(44'h600000 >> 12, 1'b0, 1'b1, 1'b1, 1'b1);
        pmem[64'h3000/8 + 4] = 64'd0;

        rst_n = 0;
        req = 0; va = 0; priv = 2'b00;
        is_fetch = 0; is_store = 0;
        satp_ppn = 44'h1000 >> 12;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  Sv39 Walker Testbench");
        $display("========================================");

        priv = 2'b00; is_fetch = 0; is_store = 0;
        walk(64'h0000_0000_0000_1234);
        check(done_r && !fault_r, "T1: done");
        check(pa_r === 64'h0000_0000_0040_0234, "T1: PA = 0x400234");

        priv = 2'b00; is_store = 1; is_fetch = 0;
        walk(64'h0000_0000_0000_1234);
        check(done_r && !fault_r, "T2: store allowed");

        priv = 2'b00; is_store = 1; is_fetch = 0;
        walk(64'h0000_0000_0000_2234);
        check(fault_r && !done_r, "T3: store on R-only -> fault");
        check(cause_r === 64'd15, "T3: cause=15");

        priv = 2'b01; is_fetch = 0; is_store = 0;
        walk(64'h0000_0000_0000_3234);
        check(done_r && !fault_r, "T4: S-mode on U=0 -> OK");

        priv = 2'b00; is_fetch = 0; is_store = 0;
        walk(64'h0000_0000_0000_3234);
        check(fault_r && !done_r, "T5: U-mode on S-page -> fault");

        priv = 2'b00; is_fetch = 0; is_store = 0;
        walk(64'h0000_0000_0000_4234);
        check(fault_r && !done_r, "T6: invalid PTE -> fault");

        priv = 2'b00;
        walk(64'h0000_0000_8000_1234);
        check(fault_r && !done_r, "T7: bad VA sign -> fault");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
