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
module tb_pcu_bcore;
    reg clk = 0, rst_n;

    wire [63:0] pcu_pc;
    reg  [31:0] instr;
    wire        shadow_we, shadow_exc;
    wire [63:0] shadow_data;
    wire        br_valid, br_taken;
    wire [63:0] br_target;
    wire        redirect_valid;
    wire [63:0] redirect_pc;
    wire [63:0] dbg_result;

    reg [31:0] imem [0:255];
    reg [63:0] shadow_log [0:15];
    reg [63:0] pc_trace   [0:255];
    integer shadow_count = 0, pc_trace_count = 0;
    integer reached_14 = 0, reached_24 = 0;
    integer i;

    pcu u_pcu (
        .clk(clk), .rst_n(rst_n),
        .pc_out(pcu_pc), .instr_in(instr),
        .shadow_we(shadow_we), .shadow_data(shadow_data), .shadow_exc(shadow_exc),
        .br_valid(br_valid), .br_taken(br_taken), .br_target(br_target),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
        .dbg_result(dbg_result)
    );

    b_core u_bcore (
        .clk(clk), .rst_n(rst_n),
        .br_valid(br_valid), .br_taken(br_taken),
        .br_target(br_target), .br_pc(pcu_pc),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc)
    );

    always @(*) instr = imem[pcu_pc[9:2]];
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            if (shadow_we) begin
                shadow_log[shadow_count] <= shadow_data;
                shadow_count <= shadow_count + 1;
            end
            pc_trace[pc_trace_count] <= pcu_pc;
            pc_trace_count <= pc_trace_count + 1;
            if (pcu_pc === 64'h14) reached_14 <= 1;
            if (pcu_pc === 64'h24) reached_24 <= 1;
        end
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

    initial begin
        // Program:
        //  0x00 addi x1, x0, 5
        //  0x04 addi x2, x0, 5
        //  0x08 beq  x1, x2, +12   (taken -> skip to 0x14)
        //  0x0C addi x3, x0, 99    (SKIPPED)
        //  0x10 addi x4, x0, 88    (SKIPPED)
        //  0x14 addi x5, x0, 7
        //  0x18 jal  x0, +12       (jump to 0x24)
        //  0x1C addi x6, x0, 66    (SKIPPED)
        //  0x20 addi x7, x0, 77    (SKIPPED)
        //  0x24 addi x8, x0, 8
        imem[0] = 32'h00500093;
        imem[1] = 32'h00500113;
        imem[2] = 32'h00208663;
        imem[3] = 32'h06300193;
        imem[4] = 32'h05800213;
        imem[5] = 32'h00700293;
        imem[6] = 32'h00C0006F;
        imem[7] = 32'h04200313;
        imem[8] = 32'h04D00393;
        imem[9] = 32'h00800413;
        for (i = 10; i < 256; i = i + 1) imem[i] = 32'h00000013;

        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  PCU + B-Core Testbench");
        $display("========================================");

        repeat(50) @(posedge clk);
        @(negedge clk);

        check(reached_14 === 1, "PC reached 0x14 (after BEQ taken)");
        check(reached_24 === 1, "PC reached 0x24 (after JAL)");

        check(shadow_count === 4, "shadow received 4 writes");
        check(shadow_log[0] === 64'd5, "shadow[0] = 5 (x1)");
        check(shadow_log[1] === 64'd5, "shadow[1] = 5 (x2)");
        check(shadow_log[2] === 64'd7, "shadow[2] = 7 (x5)");
        check(shadow_log[3] === 64'd8, "shadow[3] = 8 (x8)");

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
