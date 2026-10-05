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
module tb_l1d_mmu;
    reg clk=0, rst_n=0, flush=0;
    reg  [1:0] priv=0;
    reg  [8:0] asid=0;
    reg  [43:0] satp_ppn=0;
    reg         satp_enable=0;
    reg         cpu_req=0, cpu_we=0;
    reg  [63:0] cpu_addr_va=0, cpu_wdata=0;
    wire [63:0] cpu_rdata;
    wire        cpu_ready;
    wire        l2_req, l2_we;
    wire [63:0] l2_addr, l2_wdata;
    reg  [511:0] l2_rdata;
    reg         l2_ready;
    wire        mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;
    wire        pte_req;
    wire [63:0] pte_addr;
    reg  [63:0] pte_rdata;
    reg         pte_ready;
    wire        page_fault;
    wire [63:0] fault_cause, fault_va;

    reg [511:0] dmem [0:1023];
    reg [63:0]  pmem [0:8191];
    reg [3:0]   l2_delay, mmio_delay;
    reg         mmio_inflight;
    integer i, tests_run=0, tests_passed=0, tests_failed=0, timeout;

    l1d_mmu dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we),
        .cpu_addr_va(cpu_addr_va), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .flush(flush), .priv(priv), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .l2_req(l2_req), .l2_we(l2_we),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .page_fault(page_fault),
        .fault_cause(fault_cause), .fault_va(fault_va)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        l2_ready <= 0;
        if (l2_req && l2_delay == 0) l2_delay <= 8;
        else if (l2_delay > 0) begin
            l2_delay <= l2_delay - 1;
            if (l2_delay == 1) begin
                if (l2_we) dmem[l2_addr[15:6]][l2_addr[5:3]*64 +: 64] <= l2_wdata;
                else       l2_rdata <= dmem[l2_addr[15:6]];
                l2_ready <= 1;
            end
        end
    end

    reg pte_delay;
    always @(posedge clk) begin
        pte_ready <= 0;
        if (pte_req && !pte_delay) pte_delay <= 1;
        else if (pte_delay) begin
            pte_delay <= 0;
            pte_rdata <= pmem[pte_addr[15:3]];
            pte_ready <= 1;
        end
    end

    always @(posedge clk) begin
        mmio_ready <= 0;
        if (!mmio_inflight && mmio_req) begin
            mmio_inflight <= 1; mmio_delay <= 2;
        end else if (mmio_inflight) begin
            if (mmio_delay == 0) begin
                mmio_rdata <= mmio_addr ^ 64'hA5A5_A5A5_0000_0000;
                mmio_ready <= 1; mmio_inflight <= 0;
            end else mmio_delay <= mmio_delay - 1;
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

    // Captura o resultado ENQUANTO o sinal está alto
    reg [63:0] cap_rdata;
    reg        cap_fault;
    reg [63:0] cap_cause, cap_va;

    task do_access;
        input we; input [63:0] a; input [63:0] d;
        begin
            cap_rdata = 0;
            cap_fault = 0;
            cap_cause = 0;
            cap_va    = 0;
            @(negedge clk);
            cpu_req=1; cpu_we=we; cpu_addr_va=a; cpu_wdata=d;
            timeout = 0;
            @(posedge clk);
            // Espera ready OU fault, captura no momento certo
            while (timeout < 300) begin
                if (cpu_ready) begin
                    cap_rdata = cpu_rdata;
                    timeout   = 300;
                end
                if (page_fault) begin
                    cap_fault = 1;
                    cap_cause = fault_cause;
                    cap_va    = fault_va;
                    timeout   = 300;
                end
                if (timeout < 300) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
            end
            @(negedge clk);
            cpu_req = 0;
            repeat(5) @(posedge clk);
        end
    endtask

    initial begin
        for (i=0;i<1024;i=i+1) dmem[i] = 0;
        for (i=0;i<8192;i=i+1) pmem[i] = 0;

        pmem[64'h1000/8 + 0] = pte_ptr(44'h2000 >> 12);
        pmem[64'h2000/8 + 0] = pte_ptr(44'h3000 >> 12);
        pmem[64'h3000/8 + 1] = pte_leaf(44'h0, 1'b1, 1'b1, 1'b1, 1'b1);

        dmem[1][63:0] = 64'hDEAD_BEEF;

        rst_n = 0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  L1d + MMU integration (capture)");
        $display("========================================");

        // T1: bare mode
        satp_enable = 0;
        do_access(0, 64'h40, 64'd0);
        check(cap_rdata === 64'hDEAD_BEEF, "T1: bare mode");

        // T2: MMU translated
        satp_enable = 1; satp_ppn = 44'h1000 >> 12;
        do_access(0, 64'h1040, 64'd0);
        check(cap_rdata === 64'hDEAD_BEEF, "T2: MMU translated load");
        $display("       rdata = %h", cap_rdata);

        // T3: L1 hit
        do_access(0, 64'h1040, 64'd0);
        check(cap_rdata === 64'hDEAD_BEEF, "T3: MMU hit + L1d hit");

        // T4: invalid VA -> fault (VPN0=4 missing)
        do_access(0, 64'h4000, 64'd0);
        $display("       T4: cap_fault=%b cause=%0d va=%h", cap_fault, cap_cause, cap_va);
        check(cap_fault, "T4: invalid VA -> fault");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
