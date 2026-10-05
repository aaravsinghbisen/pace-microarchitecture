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
module tb_boot_seq;
    reg clk=0, rst_n=0;
    wire rst_n_pcu, rst_n_ao, boot_done;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer pcu_on_t, ao_on_t, done_t;

    boot_sequencer #(.SHADOW_DEPTH(32), .SCOUT_AHEAD_CYCLES(64)) dut (
        .clk(clk), .rst_n(rst_n),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao), .boot_done(boot_done)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n_pcu && pcu_on_t == 0) pcu_on_t = $time;
        if (rst_n_ao  && ao_on_t  == 0) ao_on_t  = $time;
        if (boot_done && done_t   == 0) done_t   = $time;
    end

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        pcu_on_t = 0; ao_on_t = 0; done_t = 0;
        #20 rst_n = 1;
        repeat(150) @(posedge clk);

        $display("========================================");
        $display("  Boot Sequencer Testbench");
        $display("========================================");
        check(pcu_on_t > 0, "PCU enabled");
        check(ao_on_t  > 0, "AO-Core enabled");
        check(boot_done === 1, "boot_done asserted");
        check(ao_on_t > pcu_on_t, "AO enabled after PCU (scout-ahead first)");
        $display("  PCU enabled at t=%0d", pcu_on_t);
        $display("  AO  enabled at t=%0d", ao_on_t);
        $display("  Delta = %0d ns (expected ~640ns = 64 cycles)", ao_on_t - pcu_on_t);
        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        $display("========================================");
        $finish;
    end
endmodule
