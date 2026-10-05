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

module tb_pcu;

    reg  clk = 0;
    reg  rst_n;
    wire [63:0] pc_out;
    reg  [31:0] instr_in;
    wire        shadow_we;
    wire [63:0] shadow_data;
    wire        shadow_exc;
    wire [63:0] dbg_result;

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;
    integer i;
    reg [31:0] imem [0:255];

    // Shadow RF in testbench (simple model)
    reg [63:0] shadow_q [0:63];
    integer    shadow_wr_ptr = 0;

    pcu dut (
        .clk(clk), .rst_n(rst_n),
        .pc_out(pc_out), .instr_in(instr_in),
        .shadow_we(shadow_we), .shadow_data(shadow_data), .shadow_exc(shadow_exc),
        .dbg_result(dbg_result)
    );

    always @(*) instr_in = imem[pc_out[9:2]];
    always #5 clk = ~clk;

    // Model the shadow RF filling
    always @(posedge clk) begin
        if (shadow_we && rst_n) begin
            shadow_q[shadow_wr_ptr] <= shadow_data;
            shadow_wr_ptr <= shadow_wr_ptr + 1;
        end
    end

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

    initial begin
        // Same program as before, with NOPs to avoid internal RAW
        imem[0]  = 32'h00500093; // addi x1, x0, 5
        imem[1]  = 32'h00000013;
        imem[2]  = 32'h00000013;
        imem[3]  = 32'h00000013;
        imem[4]  = 32'h00300113; // addi x2, x0, 3
        imem[5]  = 32'h00000013;
        imem[6]  = 32'h00000013;
        imem[7]  = 32'h00000013;
        imem[8]  = 32'h002081B3; // add x3, x1, x2 = 8
        imem[9]  = 32'h00000013;
        imem[10] = 32'h00000013;
        imem[11] = 32'h00000013;
        imem[12] = 32'h40208233; // sub x4, x1, x2 = 2
        for (i = 13; i < 256; i = i + 1) imem[i] = 32'h00000013;

        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  PCU Testbench - Starting");
        $display("========================================");

        repeat(20) @(posedge clk);
        @(negedge clk);

        // Shadow RF should have captured the computed values
        check(shadow_wr_ptr === 4, "shadow RF got 4 entries");
        check(shadow_q[0] === 64'd5, "shadow[0] = 5");
        check(shadow_q[1] === 64'd3, "shadow[1] = 3");
        check(shadow_q[2] === 64'd8, "shadow[2] = 8");
        check(shadow_q[3] === 64'd2, "shadow[3] = 2");

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
