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
module tb_top_simple;
    reg clk=0, rst_n=0;
    reg  [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc;
    wire [63:0] imem_addr;
    reg  [31:0] imem_rdata;

    reg [31:0] imem [0:255];
    integer i, tests_run=0, tests_passed=0, tests_failed=0;

    top_simple dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc)
    );

    always @(*) imem_rdata = imem[imem_addr[9:2]];
    always #5 clk = ~clk;

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

    initial begin
        for (i=0;i<256;i=i+1) imem[i] = 32'h00000013;
        // Programa com M extension:
        //  addi x1, x0, 7           0x00700093
        //  addi x2, x0, 6           0x00600113
        //  mul  x3, x1, x2  = 42    0x022081B3
        //  div  x4, x1, x2  = 1     0x0220C233
        //  rem  x5, x1, x2  = 1     0x0220E2B3
        //  mulh x6, x1, x2  = 0     0x02209333
        imem[0] = 32'h00700093;
        imem[1] = 32'h00600113;
        imem[2] = 32'h022081B3;
        imem[3] = 32'h0220C233;
        imem[4] = 32'h0220E2B3;
        imem[5] = 32'h02209333;

        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  TOP SIMPLE + M extension");
        $display("========================================");

        repeat(100) @(posedge clk);
        @(negedge clk);

        check_arch(5'd1, 64'd7, "x1 = 7");
        check_arch(5'd2, 64'd6, "x2 = 6");
        check_arch(5'd3, 64'd42, "x3 = MUL 7*6 = 42");
        check_arch(5'd4, 64'd1, "x4 = DIV 7/6 = 1");
        check_arch(5'd5, 64'd1, "x5 = REM 7%6 = 1");
        check_arch(5'd6, 64'd0, "x6 = MULH 7*6 hi = 0");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
