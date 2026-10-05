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
module tb_ao_multi;
    reg clk=0, rst_n=0;

    // Shadow RF
    reg [5:0] wr_en = 0;
    reg [6*72-1:0] wr_data = 0;
    reg [5:0] wr_exc = 0;
    wire [3:0] wr_ready;
    wire wr_full;

    wire [3:0] rd_en_from_ao;
    wire [4*72-1:0] shdw_rd_data;
    wire [3:0] shdw_rd_valid;
    wire shdw_rd_empty;
    wire [9:0] wr_ptr, rd_ptr;

    // Arch RF
    wire [3:0] rf_we;
    wire [3*5 + 5-1:0] rf_rd;
    wire [3*64 + 64-1:0] rf_wd;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_rd;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer i;

    shadow_rf_multi #(.DEPTH(32), .DATA_WIDTH(72), .N_READ(4), .N_WRITE(6)) u_shdw (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .wr_exception(wr_exc),
        .wr_ready(wr_ready), .wr_full(wr_full),
        .rd_en(rd_en_from_ao), .rd_data(shdw_rd_data),
        .rd_valid(shdw_rd_valid), .rd_empty(shdw_rd_empty),
        .dbg_wr_ptr(wr_ptr), .dbg_rd_ptr(rd_ptr)
    );

    ao_core_multi #(.N_AO(4)) u_ao (
        .clk(clk), .rst_n(rst_n),
        .shdw_data(shdw_rd_data), .shdw_valid(shdw_rd_valid),
        .shdw_rd_en(rd_en_from_ao),
        .rf_we(rf_we), .rf_rd(rf_rd), .rf_wd(rf_wd)
    );

    register_file_multi #(.N_WRITE(4)) u_rf (
        .clk(clk), .rst_n(rst_n),
        .we(rf_we), .rd(rf_rd), .wd(rf_wd),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
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

    task wr_entry;
        input integer k; input [4:0] rd; input [63:0] d;
        begin
            wr_data[k*72 +: 72] = {3'b0, rd, d};
            wr_en[k] = 1;
        end
    endtask

    initial begin
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  4 AO-Cores Testbench");
        $display("========================================");

        // Escreve 8 entradas: x1=10, x2=20, x3=30, x4=40, x5=50, x6=60, x7=70, x8=80
        wr_entry(0, 5'd1, 64'd10);
        wr_entry(1, 5'd2, 64'd20);
        wr_entry(2, 5'd3, 64'd30);
        wr_entry(3, 5'd4, 64'd40);
        wr_entry(4, 5'd5, 64'd50);
        wr_entry(5, 5'd6, 64'd60);
        @(negedge clk);
        wr_en = 0;
        @(negedge clk);
        wr_entry(0, 5'd7, 64'd70);
        wr_entry(1, 5'd8, 64'd80);
        @(negedge clk);
        wr_en = 0;
        @(negedge clk);

        // Espera 20 ciclos pro pipeline dos AO-Cores
        repeat(20) @(posedge clk);
        @(negedge clk);

        // Verifica os registradores commitados
        dbg_rs = 5'd1; #1; check(dbg_rd === 64'd10, "x1 = 10");
        dbg_rs = 5'd2; #1; check(dbg_rd === 64'd20, "x2 = 20");
        dbg_rs = 5'd3; #1; check(dbg_rd === 64'd30, "x3 = 30");
        dbg_rs = 5'd4; #1; check(dbg_rd === 64'd40, "x4 = 40");
        dbg_rs = 5'd5; #1; check(dbg_rd === 64'd50, "x5 = 50");
        dbg_rs = 5'd6; #1; check(dbg_rd === 64'd60, "x6 = 60");
        dbg_rs = 5'd7; #1; check(dbg_rd === 64'd70, "x7 = 70");
        dbg_rs = 5'd8; #1; check(dbg_rd === 64'd80, "x8 = 80");

        check(shdw_rd_empty === 1'b1, "shadow RF empty (all consumed)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
