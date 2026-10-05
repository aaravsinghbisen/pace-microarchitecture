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
module tb_l2;
    reg clk = 0, rst_n;

    reg         p0_req;
    reg  [63:0] p0_addr;
    wire [511:0] p0_rdata;
    wire        p0_ready;

    reg         p1_req, p1_we;
    reg  [63:0] p1_addr, p1_wdata;
    wire [511:0] p1_rdata;
    wire        p1_ready;

    wire        mem_req, mem_we;
    wire [63:0] mem_addr;
    wire [511:0] mem_wdata;
    reg  [511:0] mem_rdata;
    reg         mem_ready;

    integer i;
    reg [511:0] dmem [0:511];
    reg [3:0] dram_delay;

    l2 dut (
        .clk(clk), .rst_n(rst_n),
        .p0_req(p0_req), .p0_addr(p0_addr), .p0_rdata(p0_rdata), .p0_ready(p0_ready),
        .p1_req(p1_req), .p1_we(p1_we), .p1_addr(p1_addr), .p1_wdata(p1_wdata),
        .p1_rdata(p1_rdata), .p1_ready(p1_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    // Debug trace (imprime só quando o estado muda, pra não poluir)
    reg [3:0] last_st = 15;
    always @(posedge clk) begin
        if (rst_n && dut.state !== last_st) begin
            $display("t=%0t ST %0d->%0d | cur_addr=%h | p1_rdy=%b p0_rdy=%b",
                $time, last_st, dut.state, dut.cur_addr, p1_ready, p0_ready);
            last_st <= dut.state;
        end
    end

    // DRAM ~8 cycles
    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_req && dram_delay == 0) dram_delay <= 8;
        else if (dram_delay > 0) begin
            dram_delay <= dram_delay - 1;
            if (dram_delay == 1) begin
                if (mem_we) dmem[mem_addr[15:6]][mem_addr[5:3]*64 +: 64] <= mem_wdata[63:0];
                else        mem_rdata <= dmem[mem_addr[15:6]];
                mem_ready <= 1;
            end
        end
    end

    // ===== Tasks with clean protocol =====
    task p0_read;
        input [63:0] a;
        begin
            @(negedge clk);
            p0_req = 1; p0_addr = a;
            @(negedge clk);              // let L2 sample
            while (!p0_ready) @(negedge clk);
            p0_req = 0;
            @(negedge clk);
        end
    endtask

    task p1_write;
        input [63:0] a, d;
        begin
            @(negedge clk);
            p1_req = 1; p1_we = 1; p1_addr = a; p1_wdata = d;
            @(negedge clk);
            while (!p1_ready) @(negedge clk);
            p1_req = 0;
            @(negedge clk);
        end
    endtask

    task p1_read;
        input [63:0] a;
        begin
            @(negedge clk);
            p1_req = 1; p1_we = 0; p1_addr = a;
            @(negedge clk);
            while (!p1_ready) @(negedge clk);
            p1_req = 0;
            @(negedge clk);
        end
    endtask

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;
    task check;
        input        cond;
        input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s", name);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    reg [511:0] saved_p0, saved_p1;

    initial begin
        for (i = 0; i < 512; i = i + 1) dmem[i] = 0;
        dmem[0][63:0]   = 64'hAAAA;
        dmem[0][127:64] = 64'hBBBB;
        dmem[1][63:0]   = 64'hCCCC;

        rst_n = 0;
        p0_req = 0; p0_addr = 0;
        p1_req = 0; p1_we = 0; p1_addr = 0; p1_wdata = 0;
        dram_delay = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  L2 Testbench");
        $display("========================================");

        // --- p0 miss on line 0 ---
        p0_read(64'd0);
        saved_p0 = p0_rdata;
        check(saved_p0[63:0] === 64'hAAAA, "p0 miss -> AAAA");

        // --- p0 hit on line 0 ---
        p0_read(64'd0);
        saved_p0 = p0_rdata;
        check(saved_p0[63:0] === 64'hAAAA, "p0 hit -> AAAA");

        // --- p1 write-through to line 0, word 0 ---
        p1_write(64'd0, 64'hDEAD);
        $display("       [INFO] dmem[0][63:0] = %h (expected AAAA, L2 handles cache side)", dmem[0][63:0]);

        // --- p1 read-back (hit) ---
        p1_read(64'd0);
        saved_p1 = p1_rdata;
        check(saved_p1[63:0] === 64'hDEAD, "p1 read back DEAD");

        // --- p1 miss on line 1 ---
        p1_read(64'd64);
        saved_p1 = p1_rdata;
        $display("       [INFO] p1_rdata[63:0] = %h (expected CCCC)", saved_p1[63:0]);
        check(saved_p1[63:0] === 64'hCCCC, "p1 miss on line1 -> CCCC");

        $display("========================================");
        $display("  Tests run:    %0d", tests_run);
        $display("  Tests passed: %0d", tests_passed);
        $display("  Tests failed: %0d", tests_failed);
        if (tests_failed == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: SOME TESTS FAILED");
        $display("========================================");
        $finish;
    end
endmodule
