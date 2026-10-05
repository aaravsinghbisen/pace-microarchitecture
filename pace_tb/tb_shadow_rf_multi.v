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
module tb_shadow_rf_multi;
    reg clk=0, rst_n=0;
    reg [5:0] wr_en = 0;
    reg [6*72-1:0] wr_data = 0;
    reg [5:0] wr_exc = 0;
    wire [3:0] wr_ready;
    wire wr_full;
    reg [3:0] rd_en = 0;
    wire [4*72-1:0] rd_data;
    wire [3:0] rd_valid;
    wire rd_empty;
    wire [9:0] wr_ptr, rd_ptr;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer i;

    shadow_rf_multi #(.DEPTH(32), .DATA_WIDTH(72), .N_READ(4), .N_WRITE(6)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .wr_exception(wr_exc),
        .wr_ready(wr_ready), .wr_full(wr_full),
        .rd_en(rd_en), .rd_data(rd_data),
        .rd_valid(rd_valid), .rd_empty(rd_empty),
        .dbg_wr_ptr(wr_ptr), .dbg_rd_ptr(rd_ptr)
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

    // Escreve uma entrada {rd,data} no slot k
    task wr_entry;
        input integer k;
        input [4:0] rd;
        input [63:0] d;
        begin
            wr_data[k*72 +: 72] = {3'b0, rd, d};
            wr_en[k] = 1;
        end
    endtask

    initial begin
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  Shadow RF multi-read Testbench");
        $display("========================================");

        // Escreve 4 entradas: x1=10, x2=20, x3=30, x4=40
        wr_entry(0, 5'd1, 64'd10);
        wr_entry(1, 5'd2, 64'd20);
        wr_entry(2, 5'd3, 64'd30);
        wr_entry(3, 5'd4, 64'd40);
        @(negedge clk);
        wr_en = 0;
        @(negedge clk);
        #1;

        check(wr_ptr === 10'd4, "wr_ptr = 4 after 4 writes");
        check(rd_empty === 0, "not empty");
        check(rd_valid === 4'b1111, "all 4 heads valid");

        $display("       head0 rd=x%0d data=%0d", rd_data[0*72+68:0*72+64], rd_data[0*72+63:0*72]);
        $display("       head1 rd=x%0d data=%0d", rd_data[1*72+68:1*72+64], rd_data[1*72+63:1*72]);
        $display("       head2 rd=x%0d data=%0d", rd_data[2*72+68:2*72+64], rd_data[2*72+63:2*72]);
        $display("       head3 rd=x%0d data=%0d", rd_data[3*72+68:3*72+64], rd_data[3*72+63:3*72]);

        check(rd_data[0*72+63:0*72] === 64'd10, "head0 = x1=10");
        check(rd_data[1*72+63:1*72] === 64'd20, "head1 = x2=20");
        check(rd_data[2*72+63:2*72] === 64'd30, "head2 = x3=30");
        check(rd_data[3*72+63:3*72] === 64'd40, "head3 = x4=40");

        // Todos os 4 heads consomem → advance=4
        @(negedge clk);
        rd_en = 4'b1111;
        @(negedge clk);
        rd_en = 0;
        #1;
        check(rd_ptr === 10'd4, "rd_ptr advances to 4");
        check(rd_empty === 1, "empty after consuming all 4");

        // Escrita de 6 + leitura de 4 em paralelo
        wr_entry(0, 5'd5, 64'd50);
        wr_entry(1, 5'd6, 64'd60);
        wr_entry(2, 5'd7, 64'd70);
        wr_entry(3, 5'd8, 64'd80);
        wr_entry(4, 5'd9, 64'd90);
        wr_entry(5, 5'd10, 64'd100);
        @(negedge clk);
        wr_en = 0;
        @(negedge clk);
        #1;
        check(wr_ptr === 10'd10, "wr_ptr = 10 after 6 more");

        // Consome 4
        @(negedge clk);
        rd_en = 4'b1111;
        @(negedge clk);
        rd_en = 0;
        #1;
        check(rd_ptr === 10'd8, "rd_ptr = 8");
        check(rd_valid === 4'b0011, "only 2 heads valid (2 entries left)");

        // Consome os últimos 2
        @(negedge clk);
        rd_en = 4'b0011;   // só heads 0-1
        @(negedge clk);
        rd_en = 0;
        #1;
        check(rd_ptr === 10'd10, "rd_ptr = 10, all consumed");
        check(rd_empty === 1, "empty");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
