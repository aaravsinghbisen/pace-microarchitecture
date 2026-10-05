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
module tb_runahead;
    reg clk=0, rst_n=0;
    reg enable=0, stall_long=0, stall_cleared=0, sb_full=0;
    wire runahead_active, discard_writes;
    wire [31:0] rh_steps;
    wire enter_pulse, exit_pulse;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer i;

    runahead_ctrl dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .stall_long(stall_long), .stall_cleared(stall_cleared),
        .sb_full(sb_full),
        .runahead_active(runahead_active), .discard_writes(discard_writes),
        .rh_steps(rh_steps), .enter_pulse(enter_pulse), .exit_pulse(exit_pulse)
    );

    always #5 clk = ~clk;

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        #20 rst_n = 1; #5;
        enable = 1;

        $display("========================================");
        $display("  Runahead Control Testbench");
        $display("========================================");

        check(runahead_active === 0, "reset: not active");

        // T1: entra em runahead
        stall_long = 1;
        @(posedge clk); @(posedge clk);
        check(runahead_active === 1, "T1: entered runahead");
        check(discard_writes  === 1, "T1: discarding writes");

        // T2: roda alguns ciclos
        repeat(20) @(posedge clk);
        check(rh_steps > 15, "T2: runahead ran some steps");
        $display("       rh_steps = %0d", rh_steps);

        // T3: sai quando memória chega
        stall_long = 0; stall_cleared = 1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        check(runahead_active === 0, "T3: exited runahead");
        check(discard_writes  === 0, "T3: writes no longer discarded");

        // T4: não entra se SB cheio
        stall_cleared = 0; sb_full = 1;
        stall_long = 1;
        repeat(3) @(posedge clk);
        check(runahead_active === 0, "T4: no runahead when SB full");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
