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
module tb_pace_lite;

    reg clk = 0;
    reg rst_n_pcu, rst_n_ao;

    wire [63:0] pcu_pc;
    reg  [31:0] pcu_instr;
    wire        pcu_shadow_we;
    wire [63:0] pcu_shadow_data;
    wire        pcu_shadow_exc;
    wire [63:0] pcu_dbg;

    wire [63:0] shadow_rd_data;
    wire        shadow_rd_valid, shadow_rd_en;
    wire        shadow_rd_exc, shadow_rd_empty;
    wire        shadow_wr_ready, shadow_wr_full;

    wire [63:0] ao_pc;
    reg  [31:0] ao_instr;
    wire [4:0]  rf_wr_addr;
    wire [63:0] rf_wr_data;
    wire        rf_wr_en;

    reg  [4:0]  dbg_rs;
    wire [63:0] dbg_rd;
    reg pcu_stalled;

    reg [31:0] imem [0:255];
    integer i;

    pcu u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .pc_out(pcu_pc), .instr_in(pcu_instr),
        .shadow_we(pcu_shadow_we), .shadow_data(pcu_shadow_data),
        .shadow_exc(pcu_shadow_exc), .dbg_result(pcu_dbg)
    );

    shadow_rf #(.DEPTH(16), .DATA_WIDTH(64)) u_shadow (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(pcu_shadow_we), .wr_data(pcu_shadow_data),
        .wr_exception(pcu_shadow_exc),
        .wr_ready(shadow_wr_ready), .wr_full(shadow_wr_full),
        .rd_en(shadow_rd_en), .rd_data(shadow_rd_data),
        .rd_exception(shadow_rd_exc), .rd_valid(shadow_rd_valid),
        .rd_empty(shadow_rd_empty)
    );

    ao_core_pace u_ao (
        .clk(clk), .rst_n(rst_n_ao),
        .pc_out(ao_pc), .instr_in(ao_instr),
        .shadow_rd_data(shadow_rd_data),
        .shadow_rd_valid(shadow_rd_valid),
        .shadow_rd_en(shadow_rd_en),
        .pcu_stalled(pcu_stalled),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en)
    );

    register_file #(.DATA_WIDTH(64), .ADDR_WIDTH(5)) u_arf (
        .clk(clk), .rst_n(rst_n_ao),
        .we(rf_wr_en), .rd(rf_wr_addr), .wd(rf_wr_data),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
    );

    always @(*) pcu_instr = imem[pcu_pc[9:2]];
    always @(*) ao_instr  = imem[ao_pc[9:2]];
    always #5 clk = ~clk;

    // === DEBUG: print one line per cycle after both are running ===
    always @(posedge clk) begin
        if (rst_n_pcu && rst_n_ao) begin
            $display("t=%0t | PCU pc=%0d wr=%b data=%0d | SHDW rd_en=%b val=%b data=%0d empty=%b | AO pc=%0d | RF we=%b x%0d=%0d",
                $time, pcu_pc, pcu_shadow_we, pcu_shadow_data,
                shadow_rd_en, shadow_rd_valid, shadow_rd_data, shadow_rd_empty,
                ao_pc, rf_wr_en, rf_wr_addr, rf_wr_data);
        end
    end

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;

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
        imem[0]  = 32'h00500093;
        imem[1]  = NOP;
        imem[2]  = NOP;
        imem[3]  = NOP;
        imem[4]  = 32'h00300113;
        imem[5]  = NOP;
        imem[6]  = NOP;
        imem[7]  = NOP;
        imem[8]  = 32'h002081B3;
        imem[9]  = NOP;
        imem[10] = NOP;
        imem[11] = NOP;
        imem[12] = 32'h40208233;
        for (i = 13; i < 256; i = i + 1) imem[i] = NOP;

        rst_n_pcu = 0;
        rst_n_ao  = 0;
        dbg_rs = 0;
        pcu_stalled = 0;

        $display("========================================");
        $display("  PACE Lite - Debug Run");
        $display("========================================");

        #20 rst_n_pcu = 1;

        // Let PCU fill the shadow RF well
        repeat(50) @(posedge clk);
        @(negedge clk);

        $display("[BOOT] Shadow should be populated. Enabling AO-Core.");
        $display("[BOOT] writing started. Now enabling AO-Core.");

        rst_n_ao = 1;

        // Let AO-Core drain the shadow RF
        repeat(30) @(posedge clk);
        @(negedge clk);

        check_rf(5'd1, 64'd5, "x1 = 5");
        check_rf(5'd2, 64'd3, "x2 = 3");
        check_rf(5'd3, 64'd8, "x3 = 8");
        check_rf(5'd4, 64'd2, "x4 = 2");

        $display("========================================");
        $display("  Tests run:    %0d", tests_run);
        $display("  Tests passed: %0d", tests_passed);
        $display("  Tests failed: %0d", tests_failed);
        $display("========================================");

        $finish;
    end

endmodule
