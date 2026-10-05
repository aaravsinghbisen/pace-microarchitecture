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
module tb_mmu_top;
    reg clk=0, rst_n=0;
    reg         mc_req, mc_we;
    reg  [63:0] mc_addr_va, mc_wdata;
    wire [63:0] mc_rdata;
    wire        mc_ready;
    wire        mc_page_fault;
    wire [63:0] mc_fault_cause, mc_fault_va;
    wire        dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata;
    reg         dmem_ready;
    reg         flush_tlb;
    reg  [1:0]  priv;
    reg  [8:0]  asid;
    reg  [43:0] satp_ppn;
    reg         satp_enable;
    wire        pte_req;
    wire [63:0] pte_addr;
    reg  [63:0] pte_rdata;
    reg         pte_ready;

    reg [63:0] dmem [0:1023];
    reg [63:0] pmem [0:16383];
    reg [3:0]  dmem_delay;
    reg        pte_delay;
    integer i, tests_run=0, tests_passed=0, tests_failed=0, timeout;

    dmem_mmu_wrap dut (
        .clk(clk), .rst_n(rst_n),
        .mc_req(mc_req), .mc_we(mc_we), .mc_addr_va(mc_addr_va),
        .mc_wdata(mc_wdata), .mc_rdata(mc_rdata), .mc_ready(mc_ready),
        .mc_page_fault(mc_page_fault),
        .mc_fault_cause(mc_fault_cause), .mc_fault_va(mc_fault_va),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .flush_tlb(flush_tlb), .priv(priv), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        dmem_ready <= 0;
        if (dmem_req && dmem_delay == 0) dmem_delay <= 3;
        else if (dmem_delay > 0) begin
            dmem_delay <= dmem_delay - 1;
            if (dmem_delay == 1) begin
                if (dmem_we) dmem[dmem_addr[9:3]] <= dmem_wdata;
                else        dmem_rdata <= dmem[dmem_addr[9:3]];
                dmem_ready <= 1;
            end
        end
    end

    always @(posedge clk) begin
        pte_ready <= 0;
        if (pte_req && !pte_delay) pte_delay <= 1;
        else if (pte_delay) begin
            pte_delay <= 0;
            pte_rdata <= pmem[pte_addr[15:3]];
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

    // Captura resultado ANTES de derrubar mc_req
    reg [63:0] cap_rdata, cap_cause, cap_va;
    reg        cap_fault;

    task do_access;
        input we; input [63:0] va; input [63:0] wd;
        begin
            cap_rdata=0; cap_cause=0; cap_va=0; cap_fault=0;
            @(negedge clk);
            mc_req=1; mc_we=we; mc_addr_va=va; mc_wdata=wd;
            timeout = 0;
            // Fica checando DURANTE o request
            while (timeout < 200) begin
                if (mc_page_fault) begin
                    cap_fault = 1;
                    cap_cause = mc_fault_cause;
                    cap_va    = mc_fault_va;
                    timeout   = 200;
                end else if (mc_ready) begin
                    cap_rdata = mc_rdata;
                    timeout   = 200;
                end else begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
            end
            @(negedge clk);
            mc_req = 0;
            repeat(3) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && dut.state != 0)
            $display("t=%0t st=%0d mmu_req=%b mdone=%b mfault=%b phys=%h dmem_req=%b dmem_addr=%h dmem_ready=%b mc_ready=%b mc_rdata=%h",
                $time, dut.state, dut.mmu_req, dut.mdone, dut.mfault,
                dut.phys_addr, dmem_req, dmem_addr, dmem_ready, mc_ready, mc_rdata);
    end

    initial begin

        for (i=0;i<1024;i=i+1) dmem[i] = 0;
        for (i=0;i<16384;i=i+1) pmem[i] = 0;

        pmem[64'h1000/8 + 0] = pte_ptr(44'h2000 >> 12);
        pmem[64'h2000/8 + 0] = pte_ptr(44'h3000 >> 12);
        pmem[64'h3000/8 + 1] = pte_leaf(44'h0, 1'b1, 1'b1, 1'b1, 1'b1);

        dmem[1][63:0] = 64'hCAFE_BABE;

        rst_n = 0;
        flush_tlb = 0; priv = 2'b00; asid = 0;
        satp_ppn = 44'h1000 >> 12; satp_enable = 0;
        dmem_delay = 0; pte_delay = 0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  MMU + DMem wrapper test");
        $display("========================================");

        // T1: bare mode
        satp_enable = 0;
        do_access(0, 64'h40, 64'd0);
        check(cap_rdata === 64'hCAFE_BABE, "T1: bare mode read");

        // T2: com MMU
        satp_enable = 1;
        do_access(0, 64'h1040, 64'd0);
        check(cap_rdata === 64'hCAFE_BABE, "T2: MMU translated read");

        // T3: invalid VA → page fault
        do_access(0, 64'h4000, 64'd0);
        check(cap_fault === 1'b1, "T3: invalid VA -> page fault");
        $display("       cause=%0d va=%h", cap_cause, cap_va);

        // T4: escrita traduzida
        satp_enable = 1;
        do_access(1, 64'h1048, 64'hDEAD_1234);
        do_access(0, 64'h1048, 64'd0);
        check(cap_rdata === 64'hDEAD_1234, "T4: MMU translated write/read");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
