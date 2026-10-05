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
module tb_l1d;
    reg clk = 0, rst_n;

    reg         cpu_req, cpu_we;
    reg  [63:0] cpu_addr, cpu_wdata;
    wire [63:0] cpu_rdata;
    wire        cpu_ready;

    wire        l2_req, l2_we;
    wire [63:0] l2_addr;
    wire [63:0] l2_wdata;
    reg  [511:0] l2_rdata;
    reg         l2_ready;

    reg         snp_valid, snp_we;
    reg  [63:0] snp_addr, snp_wdata;

    integer i;
    reg [511:0] dmem [0:63];

    l1d dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .l2_req(l2_req), .l2_we(l2_we), .l2_addr(l2_addr), .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready),
        .snp_valid(snp_valid), .snp_we(snp_we),
        .snp_addr(snp_addr), .snp_wdata(snp_wdata)
    );

    always #5 clk = ~clk;

    // L2 model: word-level write
    always @(posedge clk) begin
        if (l2_req) begin
            if (!l2_we) l2_rdata <= dmem[l2_addr[9:6]];
            else        dmem[l2_addr[9:6]][l2_addr[5:3]*64 +: 64] <= l2_wdata;
            l2_ready <= 1;
        end else l2_ready <= 0;
    end

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

    task cpu_op;
        input        we;
        input [63:0] a;
        input [63:0] d;
        begin
            @(negedge clk);
            cpu_req = 1; cpu_we = we; cpu_addr = a; cpu_wdata = d;
            @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            @(negedge clk);
            cpu_req = 0;
        end
    endtask

    initial begin
        for (i = 0; i < 64; i = i + 1) dmem[i] = 512'h0;
        dmem[0][63:0]   = 64'd1111;
        dmem[0][127:64] = 64'd2222;

        rst_n = 0;
        cpu_req = 0; cpu_we = 0; cpu_addr = 0; cpu_wdata = 0;
        snp_valid = 0; snp_we = 0; snp_addr = 0; snp_wdata = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  L1d Testbench");
        $display("========================================");

        cpu_op(0, 64'd0, 64'd0);
        check(cpu_rdata === 64'd1111, "miss -> load word0 = 1111");

        cpu_op(0, 64'd8, 64'd0);
        check(cpu_rdata === 64'd2222, "hit -> load word1 = 2222");

        dmem[2][63:0] = 64'd3333;
        cpu_op(0, 64'd128, 64'd0);
        check(cpu_rdata === 64'd3333, "miss line2 -> 3333");

        cpu_op(1, 64'd16, 64'hCAFEBABE);
        cpu_op(0, 64'd16, 64'd0);
        check(cpu_rdata === 64'hCAFEBABE, "write-through -> read back");

        check(dmem[0][191:128] === 64'hCAFEBABE, "L2 received write-through");

        @(negedge clk);
        snp_valid = 1; snp_we = 1;
        snp_addr = 64'd24; snp_wdata = 64'hDEADBEEF;
        @(posedge clk); @(negedge clk);
        snp_valid = 0;
        cpu_op(0, 64'd24, 64'd0);
        check(cpu_rdata === 64'hDEADBEEF, "snoop update visible");

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
