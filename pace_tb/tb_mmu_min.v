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
module tb_mmu_min;
    reg clk=0, rst_n=0;
    reg mc_req=0, mc_we=0;
    reg [63:0] mc_addr_va=0, mc_wdata=0;
    wire [63:0] mc_rdata;
    wire mc_ready, mc_page_fault;
    wire [63:0] mc_fault_cause, mc_fault_va;
    wire dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg [63:0] dmem_rdata=0;
    reg dmem_ready=0;
    reg flush_tlb=0;
    reg [1:0] priv=2'b00;
    reg [8:0] asid=0;
    reg [43:0] satp_ppn=0;
    reg satp_enable=0;
    wire pte_req;
    wire [63:0] pte_addr;
    reg [63:0] pte_rdata=0;
    reg pte_ready=0;

    reg [63:0] dmem [0:255];
    reg [63:0] pmem [0:8191];
    reg [2:0] dmem_delay=0;
    reg pte_delay=0;
    reg [63:0] cap_rd=0;
    reg cap_fault=0;
    integer i, t_run=0, t_pass=0, t_fail=0;
    integer timeout;

    dmem_mmu_wrap dut (
        .clk(clk), .rst_n(rst_n),
        .mc_req(mc_req), .mc_we(mc_we),
        .mc_addr_va(mc_addr_va), .mc_wdata(mc_wdata),
        .mc_rdata(mc_rdata), .mc_ready(mc_ready),
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

    // DMem 3 ciclos
    always @(posedge clk) begin
        dmem_ready <= 0;
        if (dmem_req && dmem_delay == 0) dmem_delay <= 3;
        else if (dmem_delay > 0) begin
            dmem_delay <= dmem_delay - 1;
            if (dmem_delay == 1) begin
                if (dmem_we) dmem[dmem_addr[8:3]] <= dmem_wdata;
                else        dmem_rdata <= dmem[dmem_addr[8:3]];
                dmem_ready <= 1;
            end
        end
    end

    // PTE 1 ciclo
    always @(posedge clk) begin
        pte_ready <= 0;
        if (pte_req && !pte_delay) pte_delay <= 1;
        else if (pte_delay) begin
            pte_delay <= 0;
            pte_rdata <= pmem[pte_addr[14:3]];
            pte_ready <= 1;
        end
    end

    function [63:0] pte_ptr; input [43:0] ppn;
        begin pte_ptr = {10'b0, ppn, 2'b0, 8'b0100_0001}; end
    endfunction
    function [63:0] pte_leaf; input [43:0] ppn;
        begin pte_leaf = {10'b0, ppn, 2'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1}; end
    endfunction

    task check;
        input cond; input [255:0] name;
        begin
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    // Do access: espera ready/fault, captura, derruba req
    task do_access;
        input we; input [63:0] va; input [63:0] wd;
        begin
            cap_rd = 0; cap_fault = 0;
            @(negedge clk);
            mc_req = 1; mc_we = we; mc_addr_va = va; mc_wdata = wd;
            timeout = 0;
            while (timeout < 100 && !mc_ready && !mc_page_fault) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            // Captura antes de derrubar
            if (mc_page_fault) cap_fault = 1;
            else               cap_rd = mc_rdata;
            @(negedge clk);
            mc_req = 0;
            repeat(3) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && mc_req && dut.state != 0)
            $display("t=%0t st=%0d mmu_req=%b mdone=%b mfault=%b ready=%b fault=%b",
                $time, dut.state, dut.mmu_req, dut.mdone, dut.mfault, mc_ready, mc_page_fault);
    end

    initial begin

        for (i=0;i<256;i=i+1) dmem[i] = 0;
        for (i=0;i<8192;i=i+1) pmem[i] = 0;

        // Página: root @ 0x1000, PT1 @ 0x2000, PT0 @ 0x3000
        pmem[64'h1000/8] = pte_ptr(44'h2000 >> 12);
        pmem[64'h2000/8] = pte_ptr(44'h3000 >> 12);
        // VA 0x1000 → PA 0x40
        pmem[64'h3000/8 + 1] = pte_leaf(44'h0);

        // Dado em PA 0x40 (linha 8)
        dmem[8] = 64'hCAFEBABE;

        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  MMU minimal test");
        $display("========================================");

        // T1: bare mode lê PA 0x40
        satp_enable = 0;
        do_access(0, 64'h40, 64'd0);
        $display("       T1: cap_rd = %h, fault = %b", cap_rd, cap_fault);
        check(cap_rd === 64'hCAFEBABE, "T1: bare mode read PA=0x40");

        // T2: com MMU, VA 0x1000 → PA 0x40
        satp_enable = 1; satp_ppn = 44'h1000 >> 12;
        do_access(0, 64'h1040, 64'd0);
        $display("       T2: cap_rd = %h, fault = %b", cap_rd, cap_fault);
        check(cap_rd === 64'hCAFEBABE, "T2: MMU VA=0x1040→PA=0x40");

        // T3: VA sem PTE → page fault
        do_access(0, 64'h2000, 64'd0);
        $display("       T3: fault = %b", cap_fault);
        check(cap_fault === 1'b1, "T3: invalid VA → fault");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
