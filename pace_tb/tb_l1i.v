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
module tb_l1i;
    reg clk = 0, rst_n;

    reg         fetch_req;
    reg  [63:0] fetch_pc;
    wire [127:0] fetch_data;
    wire        fetch_ready;

    wire         l2_req;
    wire [63:0]  l2_addr;
    reg  [255:0] l2_data;
    reg          l2_ready;

    integer i;
    // Backing instr memory: 4KB = 128 lines of 32B
    reg [255:0] imem [0:127];

    l1i dut (
        .clk(clk), .rst_n(rst_n),
        .fetch_req(fetch_req), .fetch_pc(fetch_pc),
        .fetch_data(fetch_data), .fetch_ready(fetch_ready),
        .l2_req(l2_req), .l2_addr(l2_addr), .l2_data(l2_data), .l2_ready(l2_ready)
    );

    always #5 clk = ~clk;

    // L2 model
    always @(posedge clk) begin
        if (l2_req) begin
            l2_data  <= imem[l2_addr[9:5]];
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

    task fetch;
        input [63:0] pc;
        begin
            @(negedge clk);
            fetch_req = 1; fetch_pc = pc;
            @(posedge clk);
            while (!fetch_ready) @(posedge clk);
            @(negedge clk);
            fetch_req = 0;
        end
    endtask

    initial begin
        // Fill imem with pattern: line N word K = (N<<4) | K
        for (i = 0; i < 128; i = i + 1) begin
            imem[i][31:0] = i*8 + 0;
            imem[i][63:32] = i*8 + 1;
            imem[i][95:64] = i*8 + 2;
            imem[i][127:96] = i*8 + 3;
            imem[i][159:128] = i*8 + 4;
            imem[i][191:160] = i*8 + 5;
            imem[i][223:192] = i*8 + 6;
            imem[i][255:224] = i*8 + 7;
        end

        rst_n = 0;
        fetch_req = 0; fetch_pc = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  L1i Testbench");
        $display("========================================");

        // Miss: fetch PC=0, expect first 4 instrs of line 0 = 0,1,2,3
        fetch(64'd0);
        check(fetch_data[31:0]   === 32'd0, "line0 word0 = 0");
        check(fetch_data[63:32]  === 32'd1, "line0 word1 = 1");
        check(fetch_data[95:64]  === 32'd2, "line0 word2 = 2");
        check(fetch_data[127:96] === 32'd3, "line0 word3 = 3");

        // Hit: same line, PC=16 -> second half = 4,5,6,7
        fetch(64'd16);
        check(fetch_data[31:0]   === 32'd4, "line0 word4 = 4");
        check(fetch_data[127:96] === 32'd7, "line0 word7 = 7");

        // Next line (PC=32) should already be prefetched by now
        fetch(64'd32);
        check(fetch_data[31:0]  === 32'd8, "line1 word0 = 8 (prefetched)");
        check(fetch_data[63:32] === 32'd9, "line1 word1 = 9");

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
