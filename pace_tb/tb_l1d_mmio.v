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
module tb_l1d_mmio;
    reg clk = 0, rst_n;

    reg         cpu_req, cpu_we;
    reg  [63:0] cpu_addr, cpu_wdata;
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

    integer i;
    reg [511:0] dmem [0:63];

    reg [63:0] mmio_reg = 64'hCAFE_1234_5678_9ABC;
    reg [3:0]  mmio_delay;
    reg        mmio_inflight;

    l1d dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .l2_req(l2_req), .l2_we(l2_we), .l2_addr(l2_addr), .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .snp_valid(1'b0), .snp_we(1'b0), .snp_addr(64'd0), .snp_wdata(64'd0)
    );

    always #5 clk = ~clk;

    // L2 model
    always @(posedge clk) begin
        l2_ready <= 0;
        if (l2_req) begin
            if (!l2_we) l2_rdata <= dmem[l2_addr[11:6]];
            else        dmem[l2_addr[11:6]][l2_addr[5:3]*64 +: 64] <= l2_wdata;
            l2_ready <= 1;
        end
    end

    // MMIO model with inflight flag (fixes double-trigger)
    always @(posedge clk) begin
        mmio_ready <= 0;
        if (!mmio_inflight && mmio_req) begin
            mmio_inflight <= 1;
            mmio_delay    <= 3;
        end else if (mmio_inflight) begin
            if (mmio_delay == 0) begin
                if (mmio_we) mmio_reg <= mmio_wdata;
                else         mmio_rdata <= mmio_reg;
                mmio_ready    <= 1;
                mmio_inflight <= 0;
            end else begin
                mmio_delay <= mmio_delay - 1;
            end
        end
    end

    // TRACE
    always @(posedge clk) begin
        if (rst_n && (mmio_req || mmio_ready))
            $display("t=%0t mmio_req=%b mmio_we=%b addr=%h wdata=%h ready=%b reg=%h delay=%0d inflight=%b",
                $time, mmio_req, mmio_we, mmio_addr, mmio_wdata, mmio_ready, mmio_reg, mmio_delay, mmio_inflight);
    end

    integer tests_run=0, tests_passed=0, tests_failed=0;
    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task cpu_op;
        input we; input [63:0] a; input [63:0] d;
        begin
            @(negedge clk);
            cpu_req=1; cpu_we=we; cpu_addr=a; cpu_wdata=d;
            @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            @(negedge clk);
            cpu_req=0;
        end
    endtask

    reg [63:0] rdata_saved;

    initial begin
        for (i=0;i<64;i=i+1) dmem[i] = 0;
        dmem[0][63:0] = 64'h1111;

        rst_n = 0;
        cpu_req=0; cpu_we=0; cpu_addr=0; cpu_wdata=0;
        mmio_delay = 0;
        mmio_inflight = 0;
        #20 rst_n=1; #5;

        $display("========================================");
        $display("  L1d + MMIO bypass test");
        $display("========================================");

        cpu_op(0, 64'h8000_0000, 64'd0);
        rdata_saved = cpu_rdata;
        check(rdata_saved === 64'h1111, "DRAM load via L1d/L2");

        cpu_op(0, 64'h1000_0000, 64'd0);
        rdata_saved = cpu_rdata;
        check(rdata_saved === 64'hCAFE_1234_5678_9ABC, "MMIO read bypasses L1d");

        cpu_op(1, 64'h1000_0000, 64'hDEAD_BEEF_0000_0000);
        #1;
        check(mmio_reg === 64'hDEAD_BEEF_0000_0000, "MMIO write reaches device");
        $display("       mmio_reg now = %h", mmio_reg);

        cpu_op(0, 64'h1000_0000, 64'd0);
        rdata_saved = cpu_rdata;
        check(rdata_saved === 64'hDEAD_BEEF_0000_0000, "MMIO read-back");

        cpu_op(0, 64'h8000_0000, 64'd0);
        rdata_saved = cpu_rdata;
        check(rdata_saved === 64'h1111, "DRAM still works after MMIO");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
