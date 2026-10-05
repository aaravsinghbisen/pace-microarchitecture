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
module tb_top_pace;

    reg clk = 0;
    reg rst_n_pcu, rst_n_ao;

    wire [63:0] pcu_pc, ao_pc;
    reg  [31:0] pcu_instr, ao_instr;
    wire [63:0] dbg_arch_rd, dbg_pcu_rd;
    reg  [4:0]  dbg_rs;

    integer i;
    reg [31:0] imem [0:255];

    top_pace dut (
        .clk(clk),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao),
        .pcu_pc(pcu_pc), .pcu_instr(pcu_instr),
        .ao_pc(ao_pc), .ao_instr(ao_instr),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd), .dbg_pcu_rd(dbg_pcu_rd)
    );

    always @(*) pcu_instr = imem[pcu_pc[9:2]];
    always @(*) ao_instr  = imem[ao_pc[9:2]];
    always #5 clk = ~clk;

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;
    task check_arch;
        input [4:0]   reg_num;
        input [63:0]  expected;
        input [255:0] name;
        begin
            dbg_rs = reg_num;
            #1;
            tests_run = tests_run + 1;
            if (dbg_arch_rd === expected) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s : x%0d = %0d", name, reg_num, dbg_arch_rd);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s : x%0d = %0d (expected %0d)",
                         name, reg_num, dbg_arch_rd, expected);
            end
        end
    endtask

    localparam NOP = 32'h00000013;

    initial begin
        // Program: arithmetic only (no branches, no loads)
        //   0x00  addi x1, x0, 5
        //   0x04  addi x2, x0, 3
        //   0x08  add  x3, x1, x2
        //   0x0C  sub  x4, x1, x2
        //   0x10  and  x5, x1, x2
        //   0x14  xor  x6, x1, x2
        imem[0]  = 32'h00500093;
        imem[1]  = 32'h00300113;
        imem[2]  = 32'h002081B3;
        imem[3]  = 32'h40208233;
        imem[4]  = 32'h0020F2B3;
        imem[5]  = 32'h0020C333;
        for (i = 6; i < 256; i = i + 1) imem[i] = NOP;

        rst_n_pcu = 0;
        rst_n_ao  = 0;
        dbg_rs    = 0;

        $display("========================================");
        $display("  PACE Top-Level Testbench");
        $display("========================================");

        // Boot: PCU first
        #20 rst_n_pcu = 1;
        $display("[BOOT] PCU enabled");

        // Let PCU fill shadow RF (head start)
        repeat(50) @(posedge clk);
        @(negedge clk);

        // Enable AO-Core
        rst_n_ao = 1;
        $display("[BOOT] AO-Core enabled");

        // Let everything drain
        repeat(50) @(posedge clk);
        @(negedge clk);

        check_arch(5'd1, 64'd5,  "x1 = 5");
        check_arch(5'd2, 64'd3,  "x2 = 3");
        check_arch(5'd3, 64'd8,  "x3 = 5+3 = 8");
        check_arch(5'd4, 64'd2,  "x4 = 5-3 = 2");
        check_arch(5'd5, 64'd1,  "x5 = 5&3 = 1");
        check_arch(5'd6, 64'd6,  "x6 = 5^3 = 6");
        check_arch(5'd0, 64'd0,  "x0 = 0");

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
