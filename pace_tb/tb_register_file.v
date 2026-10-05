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

module tb_register_file;

    reg  clk = 0;
    reg  rst_n;
    reg         we;
    reg  [4:0]  rd, rs1, rs2;
    reg  [63:0] wd;
    wire [63:0] rd1, rd2;

    integer tests_run    = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;

    register_file #(.DATA_WIDTH(64), .ADDR_WIDTH(5)) dut (
        .clk(clk), .rst_n(rst_n),
        .we(we), .rd(rd), .wd(wd),
        .rs1(rs1), .rs2(rs2), .rd1(rd1), .rd2(rd2)
    );

    always #5 clk = ~clk;

    task check;
        input         cond;
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

    task write_reg;
        input [4:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            we = 1; rd = addr; wd = data;
            @(posedge clk);
            @(negedge clk);
            we = 0;
        end
    endtask

    // 64-bit counters to avoid width warnings
    integer i;
    reg [63:0] k64;
    reg        all_ok;

    initial begin
        rst_n = 0;
        we = 0; rd = 0; rs1 = 0; rs2 = 0; wd = 0;
        #20 rst_n = 1;
        #5;

        $display("========================================");
        $display("  Register File Testbench - Starting");
        $display("========================================");

        // === After reset: all zero ===
        rs1 = 5'd1; rs2 = 5'd2; #1;
        check(rd1 === 64'd0, "reset: r1 = 0");
        check(rd2 === 64'd0, "reset: r2 = 0");

        // === x0 always reads 0 ===
        write_reg(5'd0, 64'hDEADBEEF);
        rs1 = 5'd0; #1;
        check(rd1 === 64'd0, "x0 reads 0 after write attempt");

        // === Write / read basic ===
        write_reg(5'd1, 64'd100);
        write_reg(5'd2, 64'd200);
        write_reg(5'd3, 64'hDEADBEEFCAFEBABE);

        rs1 = 5'd1; rs2 = 5'd2; #1;
        check(rd1 === 64'd100, "r1 = 100");
        check(rd2 === 64'd200, "r2 = 200");

        rs1 = 5'd3; #1;
        check(rd1 === 64'hDEADBEEFCAFEBABE, "r3 = pattern");

        // === Dual read ===
        rs1 = 5'd1; rs2 = 5'd3; #1;
        check(rd1 === 64'd100,               "dual read: r1");
        check(rd2 === 64'hDEADBEEFCAFEBABE, "dual read: r3");

        // === Overwrite ===
        write_reg(5'd1, 64'd999);
        rs1 = 5'd1; #1;
        check(rd1 === 64'd999, "r1 overwritten to 999");

        // === we=0 means no write ===
        @(negedge clk);
        we = 0; rd = 5'd5; wd = 64'hFFFFFFFFFFFFFFFF;
        @(posedge clk);
        @(negedge clk);
        rs1 = 5'd5; #1;
        check(rd1 === 64'd0, "we=0: r5 not written");

        // === Write to all 32 regs, read back ===
        for (i = 1; i < 32; i = i + 1) begin
            write_reg(i[4:0], 64'd1000 + {{32{1'b0}}, i[31:0]});
        end

        all_ok = 1;
        for (i = 1; i < 32; i = i + 1) begin
            rs1 = i[4:0]; #1;
            k64 = 64'd1000 + {{32{1'b0}}, i[31:0]};
            if (rd1 !== k64) all_ok = 0;
        end
        check(all_ok == 1'b1, "all 32 regs written+read");

        // === x0 still 0 ===
        rs1 = 5'd0; #1;
        check(rd1 === 64'd0, "x0 still 0 after mass write");

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
