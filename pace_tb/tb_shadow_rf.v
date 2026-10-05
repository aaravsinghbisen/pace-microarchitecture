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

module tb_shadow_rf;

    reg  clk = 0;
    reg  rst_n;

    reg  wr_en;
    reg  [63:0] wr_data;
    reg  wr_exception;
    wire wr_ready, wr_full;

    reg  rd_en;
    wire [63:0] rd_data;
    wire rd_exception, rd_valid, rd_empty;

    integer tests_run    = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;

    shadow_rf #(.DEPTH(8), .DATA_WIDTH(64)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .wr_exception(wr_exception),
        .wr_ready(wr_ready), .wr_full(wr_full),
        .rd_en(rd_en), .rd_data(rd_data), .rd_exception(rd_exception),
        .rd_valid(rd_valid), .rd_empty(rd_empty)
    );

    always #5 clk = ~clk;

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

    task push;
        input [63:0] data;
        input        exc;
        begin
            @(negedge clk);
            wr_en = 1; wr_data = data; wr_exception = exc;
            @(posedge clk);
            #1 wr_en = 0;
        end
    endtask

    task pop;
        begin
            @(negedge clk);
            rd_en = 1;
            @(posedge clk);
            #1 rd_en = 0;
        end
    endtask

    initial begin
        rst_n = 0;
        wr_en = 0; wr_data = 0; wr_exception = 0;
        rd_en = 0;

        #20 rst_n = 1;
        #10;

        $display("========================================");
        $display("  Shadow RF Testbench - Starting");
        $display("========================================");

        check(rd_empty === 1'b1, "empty after reset");
        check(wr_full  === 1'b0, "not full after reset");

        push(64'hDEADBEEF_CAFEBABE, 0);
        check(rd_empty === 1'b0, "not empty after push");
        check(rd_valid === 1'b1, "rd_valid high");
        check(rd_data === 64'hDEADBEEF_CAFEBABE, "rd_data matches");

        pop();
        check(rd_empty === 1'b1, "empty after pop");

        push(64'd100, 0);
        push(64'd200, 0);
        push(64'd300, 0);
        check(rd_data === 64'd100, "FIFO head = 100");
        pop();
        check(rd_data === 64'd200, "FIFO head = 200");
        pop();
        check(rd_data === 64'd300, "FIFO head = 300");
        pop();
        check(rd_empty === 1'b1, "empty after 3 pops");

        push(64'hBAD0BAD0, 1);
        check(rd_exception === 1'b1, "exception flag propagated");
        pop();

        push(64'd1, 0); push(64'd2, 0); push(64'd3, 0); push(64'd4, 0);
        push(64'd5, 0); push(64'd6, 0); push(64'd7, 0); push(64'd8, 0);
        check(wr_full  === 1'b1, "full after 8 pushes");
        check(wr_ready === 1'b0, "wr_ready low when full");
        check(rd_data === 64'd1, "head is 1 when full");

        pop(); pop(); pop(); pop();
        pop(); pop(); pop(); pop();
        check(rd_empty === 1'b1, "empty after draining");

        push(64'd11, 0);
        push(64'd22, 0);
        @(negedge clk);
        wr_en = 1; wr_data = 64'd33; wr_exception = 0;
        rd_en = 1;
        @(posedge clk);
        #1 wr_en = 0; rd_en = 0;
        check(rd_data === 64'd22, "simultaneous R/W: read 22");
        pop();
        check(rd_data === 64'd33, "simultaneous R/W: then 33");
        pop();
        check(rd_empty === 1'b1, "empty after simultaneous test");

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
