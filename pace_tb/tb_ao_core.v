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

module tb_ao_core;

    reg  clk = 0;
    reg  rst_n;
    wire [63:0] pc_out;
    reg  [31:0] instr_in;
    wire [63:0] out_pc, out_result;
    wire [31:0] out_instr;
    wire [4:0]  out_rd;
    wire        out_we, out_valid;
    reg  [4:0]  dbg_rs;
    wire [63:0] dbg_rd;

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;
    integer i;
    reg [31:0] imem [0:255];

    ao_core dut (
        .clk(clk), .rst_n(rst_n),
        .pc_out(pc_out), .instr_in(instr_in),
        .out_pc(out_pc), .out_instr(out_instr), .out_result(out_result),
        .out_rd(out_rd), .out_we(out_we), .out_valid(out_valid),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
    );

    always @(*) instr_in = imem[pc_out[9:2]];
    always #5 clk = ~clk;

    // Force use of out_* signals (avoid UNUSEDSIGNAL warning)
    wire _unused = &{1'b0, out_pc, out_instr, out_result, out_rd, out_we, out_valid};

    task check_rf;
        input [4:0]   reg_num;
        input [63:0]  expected;
        input [255:0] name;
        begin
            dbg_rs = reg_num;
            #1;
            tests_run = tests_run + 1;
            if (dbg_rd === expected) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s : x%0d = %0d", name, reg_num, dbg_rd);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s : x%0d = %0d (expected %0d)",
                         name, reg_num, dbg_rd, expected);
            end
        end
    endtask

    localparam NOP = 32'h00000013;

    initial begin
        imem[0]  = 32'h00500093;  // addi x1, x0, 5
        imem[1]  = NOP;
        imem[2]  = NOP;
        imem[3]  = NOP;
        imem[4]  = 32'h00300113;  // addi x2, x0, 3
        imem[5]  = NOP;
        imem[6]  = NOP;
        imem[7]  = NOP;
        imem[8]  = 32'h002081B3;  // add x3, x1, x2
        imem[9]  = NOP;
        imem[10] = NOP;
        imem[11] = NOP;
        imem[12] = 32'h40208233;  // sub x4, x1, x2
        imem[13] = NOP;
        imem[14] = NOP;
        imem[15] = NOP;
        imem[16] = 32'h0020F2B3;  // and x5, x1, x2
        imem[17] = NOP;
        imem[18] = NOP;
        imem[19] = NOP;
        imem[20] = 32'h0020E333;  // or  x6, x1, x2
        imem[21] = NOP;
        imem[22] = NOP;
        imem[23] = NOP;
        imem[24] = 32'h0020C3B3;  // xor x7, x1, x2

        for (i = 25; i < 256; i = i + 1)
            imem[i] = NOP;

        rst_n = 0;
        dbg_rs = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  AO-Core Full Testbench - Starting");
        $display("========================================");

        repeat(40) @(posedge clk);
        @(negedge clk);

        check_rf(5'd1, 64'd5, "addi x1 = 5");
        check_rf(5'd2, 64'd3, "addi x2 = 3");
        check_rf(5'd3, 64'd8, "add  x3 = 8");
        check_rf(5'd4, 64'd2, "sub  x4 = 2");
        check_rf(5'd5, 64'd1, "and  x5 = 1");
        check_rf(5'd6, 64'd7, "or   x6 = 7");
        check_rf(5'd7, 64'd6, "xor  x7 = 6");
        check_rf(5'd0, 64'd0, "x0 = 0 (immutable)");

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
