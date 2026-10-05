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
module tb_clint;
    reg clk = 0, rst_n;
    reg req, we;
    reg [63:0] addr, wdata;
    wire [63:0] rdata;
    wire ready;
    reg tick;
    wire mtip, msip_o;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    clint dut (
        .clk(clk), .rst_n(rst_n),
        .req(req), .we(we), .addr(addr), .wdata(wdata),
        .rdata(rdata), .ready(ready),
        .tick(tick), .mtip(mtip), .msip_o(msip_o)
    );

    always #5 clk = ~clk;

    task wr;
        input [63:0] a, d;
        begin @(negedge clk); addr=a; wdata=d; we=1; req=1; @(posedge clk); @(negedge clk); req=0; we=0; end
    endtask
    task rd;
        input [63:0] a;
        begin @(negedge clk); addr=a; we=0; req=1; @(posedge clk); #1; @(negedge clk); req=0; end
    endtask

    initial begin
        rst_n=0; req=0; we=0; addr=0; wdata=0; tick=0;
        #20 rst_n=1; #5;

        $display("========================================");
        $display("  CLINT Testbench");
        $display("========================================");

        // tick a few times
        repeat(10) begin tick=1; @(posedge clk); tick=0; @(posedge clk); end

        // Read mtime low
        rd(64'h0200_BFF8);
        check(rdata[31:0] > 0, "mtime advances with ticks");
        $display("       mtime low = %0d", rdata[31:0]);

        // Set mtimecmp slightly above mtime
        rd(64'h0200_BFF8);
        wr(64'h0200_4004, 64'd0); wr(64'h0200_4000, {32'b0, rdata[31:0] + 20});
        #1;
        check(mtip === 0, "mtip low (mtime < cmp)");

        // tick past mtimecmp
        repeat(30) begin tick=1; @(posedge clk); tick=0; @(posedge clk); end
        check(mtip === 1, "mtip fires (mtime >= cmp)");

        // msip
        wr(64'h0200_0000, 64'd1);
        #1;
        check(msip_o === 1, "msip set");
        wr(64'h0200_0000, 64'd0);
        #1;
        check(msip_o === 0, "msip clear");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
