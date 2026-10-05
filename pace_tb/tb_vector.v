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
module tb_vector;
    reg clk=0, rst_n=0;

    // Vector RF
    reg  [4:0] rs1 = 0, rs2 = 0;
    wire [127:0] rf_rd1, rf_rd2;
    reg        we = 0;
    reg  [4:0] rd = 0;
    reg  [127:0] wd = 0;
    reg  [4:0] dbg_rs = 0;
    wire [127:0] dbg_rd;

    // ALU
    reg  [127:0] alu_a, alu_b;
    reg  [3:0]  alu_op;
    reg  [127:0] mask;
    reg  mask_en;
    wire [127:0] alu_result;

    // CSRs
    reg         csr_access = 0, csr_we = 0;
    reg  [11:0] csr_addr = 0;
    reg  [63:0] csr_wdata = 0;
    reg  [1:0]  csr_op = 0;
    wire [63:0] csr_rdata;
    wire [7:0]  vl;
    wire [63:0] vtype;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer k;

    vector_rf u_rf (
        .clk(clk), .rst_n(rst_n),
        .rs1(rs1), .rs2(rs2), .rd1(rf_rd1), .rd2(rf_rd2),
        .we(we), .rd(rd), .wd(wd),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
    );

    v_alu u_alu (
        .a(alu_a), .b(alu_b), .op(alu_op),
        .mask(mask), .mask_en(mask_en),
        .result(alu_result)
    );

    v_csr u_csr (
        .clk(clk), .rst_n(rst_n),
        .csr_access(csr_access), .csr_we(csr_we),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata),
        .csr_op(csr_op), .csr_rdata(csr_rdata),
        .vl(vl), .vtype(vtype)
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

    task tick; begin @(posedge clk); @(negedge clk); end endtask

    initial begin
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  Vector VLE=128 Testbench");
        $display("========================================");

        // ===== Vector RF =====
        // v1 = [10, 20] (2 elementos de 64 bits)
        we = 1; rd = 5'd1; wd = {64'd20, 64'd10}; tick();
        // v2 = [3, 4]
        we = 1; rd = 5'd2; wd = {64'd4, 64'd3}; tick();
        we = 0;

        rs1 = 5'd1; rs2 = 5'd2; tick();
        $display("        v1 = {%0d, %0d}", rf_rd1[127:64], rf_rd1[63:0]);
        $display("        v2 = {%0d, %0d}", rf_rd2[127:64], rf_rd2[63:0]);
        check(rf_rd1 === {64'd20, 64'd10}, "RF: v1 = [10,20]");
        check(rf_rd2 === {64'd4, 64'd3},   "RF: v2 = [3,4]");

        // ===== VADD =====
        alu_a = {64'd20, 64'd10};
        alu_b = {64'd4,  64'd3};
        alu_op = 4'b0000;
        mask_en = 0;
        #1;
        $display("        vadd = {%0d, %0d} (exp {24, 13})",
                 alu_result[127:64], alu_result[63:0]);
        check(alu_result === {64'd24, 64'd13}, "VADD: [10,20]+[3,4]=[13,24]");

        // ===== VSUB =====
        alu_op = 4'b0001; #1;
        check(alu_result === {64'd16, 64'd7}, "VSUB: [10,20]-[3,4]=[7,16]");

        // ===== VMUL =====
        alu_op = 4'b1000; #1;
        check(alu_result === {64'd80, 64'd30}, "VMUL: [10,20]*[3,4]=[30,80]");

        // ===== VAND =====
        alu_a = {64'hFF00_FF00_FF00_FF00, 64'hAAAA_AAAA_AAAA_AAAA};
        alu_b = {64'h0F0F_0F0F_0F0F_0F0F, 64'hFFFF_FFFF_FFFF_FFFF};
        alu_op = 4'b0010; #1;
        check(alu_result === {64'h0F00_0F00_0F00_0F00, 64'hAAAA_AAAA_AAAA_AAAA},
              "VAND bit a bit");

        // ===== VSLL (shift logico esquerda por 4) =====
        alu_a = {64'd20, 64'd10};
        alu_b = {64'd4,  64'd4};
        alu_op = 4'b0101; #1;
        check(alu_result === {64'd320, 64'd160}, "VSLL: <<4");

        // ===== VSRA (shift aritmetico direita) =====
        alu_a = {64'hFFFF_FFFF_FFFF_FFF0, 64'h8000_0000_0000_0000};
        alu_b = {64'd4, 64'd4};
        alu_op = 4'b0111; #1;
        check(alu_result[63:0]  === 64'hF800_0000_0000_0000, "VSRA sign-extend");
        check(alu_result[127:64] === 64'hFFFF_FFFF_FFFF_FFFF, "VSRA -16>>4 = -1");

        // ===== Masking =====
        alu_a = {64'd20, 64'd10};
        alu_b = {64'd4,  64'd3};
        alu_op = 4'b0000;
        mask = 128'h1;    // só elemento 0 ativo
        mask_en = 1; #1;
        $display("        masked vadd = {%0d, %0d} (exp {20, 13})",
                 alu_result[127:64], alu_result[63:0]);
        check(alu_result === {64'd20, 64'd13}, "Masked VADD: só elem 0 muda");

        // ===== CSRs =====
        csr_access = 1; csr_we = 1; csr_op = 2'b01;
        csr_addr = 12'hC20; csr_wdata = 64'd8; tick();
        check(vl === 8'd8, "CSR: vl = 8");

        csr_addr = 12'hC21; csr_wdata = 64'h3; tick();
        check(vtype === 64'h3, "CSR: vtype = 3 (SEW=64, LMUL=1)");

        csr_addr = 12'h008; csr_wdata = 64'd2; tick();
        csr_access = 0; csr_we = 0;
        csr_addr = 12'h008; #1;
        check(csr_rdata[5:0] === 6'd2, "CSR: vstart = 2");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
