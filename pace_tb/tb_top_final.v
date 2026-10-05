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
module tb_top_final;
    reg clk=0, rst_n=0;
    reg  [4:0] dbg_rs=0;
    wire [63:0] dbg_pcu_pc, dbg_arch_rd;
    wire [1:0]  dbg_priv;
    wire        mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;
    wire        dram_req, dram_we;
    wire [63:0] dram_addr;
    wire [511:0] dram_wdata;
    reg  [511:0] dram_rdata;
    reg         dram_ready;

    reg [511:0] dmem [0:127];
    reg [3:0] dram_delay;
    integer i, tests_run=0, tests_passed=0, tests_failed=0;

    top_pace_final dut (
        .clk(clk), .rst_n_in(rst_n),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .dram_req(dram_req), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata),
        .dram_rdata(dram_rdata), .dram_ready(dram_ready),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_priv(dbg_priv),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        dram_ready <= 0;
        if (dram_req && dram_delay == 0) dram_delay <= 8;
        else if (dram_delay > 0) begin
            dram_delay <= dram_delay - 1;
            if (dram_delay == 1) begin
                if (dram_we) dmem[dram_addr[12:6]][dram_addr[5:3]*64 +: 64] <= dram_wdata[63:0];
                else        dram_rdata <= dmem[dram_addr[12:6]];
                dram_ready <= 1;
            end
        end
    end

    task check_arch;
        input [4:0] r; input [63:0] e; input [255:0] n;
        begin
            dbg_rs = r; #1; tests_run = tests_run + 1;
            if (dbg_arch_rd === e) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s : x%0d = %0d", n, r, dbg_arch_rd);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s : x%0d = %0d (exp %0d)", n, r, dbg_arch_rd, e);
            end
        end
    endtask

    reg [3:0] mmio_delay;
    reg       mmio_inflight;
    always @(posedge clk) begin
        mmio_ready <= 0;
        if (!mmio_inflight && mmio_req) begin
            mmio_inflight <= 1; mmio_delay <= 2;
        end else if (mmio_inflight) begin
            if (mmio_delay == 0) begin
                mmio_rdata <= 64'hCAFE_0000_0000_0000 | mmio_addr;
                mmio_ready <= 1; mmio_inflight <= 0;
            end else mmio_delay <= mmio_delay - 1;
        end
    end

    initial begin

        for (i=0;i<128;i=i+1) dmem[i] = 0;
        // Program at DRAM line 0
        dmem[0][31:0]   = 32'h00500093;  // addi x1, x0, 5
        dmem[0][63:32]  = 32'h00300113;  // addi x2, x0, 3
        dmem[0][95:64]  = 32'h002081B3;  // add  x3, x1, x2 = 8
        dmem[0][127:96] = 32'h40208233;  // sub  x4, x1, x2 = 2
        dmem[0][159:128]= 32'h00000013;
        dmem[0][191:160]= 32'h00000013;
        dmem[0][223:192]= 32'h00000013;
        dmem[0][255:224]= 32'h00000013;

        rst_n = 0;
        dram_delay = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  TOP PACE FINAL + Boot Sequencer");
        $display("========================================");

        // Wait: 5 reset + 64 scout-ahead + ~40 execution
        repeat(250) @(posedge clk);
        @(negedge clk);

        $display("  PCU pc=%h priv=%b", dbg_pcu_pc, dbg_priv);
        check_arch(5'd1, 64'd5, "x1 = 5");
        check_arch(5'd2, 64'd3, "x2 = 3");
        check_arch(5'd3, 64'd8, "x3 = 8");
        check_arch(5'd4, 64'd2, "x4 = 2");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
