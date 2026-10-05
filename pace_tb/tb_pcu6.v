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
module tb_pcu6;
    reg clk=0, rst_n=0;
    reg stall=0, fetch_stall=0;
    reg [3:0] shdw_ready=6;
    reg [6*32-1:0] instr;
    wire [63:0] pc_out;
    wire [5:0] shadow_we;
    wire [6*5-1:0] shadow_rd;
    wire [6*64-1:0] shadow_data;
    wire [5:0] num_writes;
    wire br_valid, br_taken;
    wire [63:0] br_target;
    reg redirect_valid=0;
    reg [63:0] redirect_pc=0;
    reg ext_wr_en=0;
    reg [4:0] ext_wr_addr=0;
    reg [63:0] ext_wr_data=0;
    wire [1:0] dbg_priv;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer i;

    pcu6 dut (
        .clk(clk), .rst_n(rst_n),
        .stall(stall), .fetch_stall(fetch_stall),
        .shdw_wr_ready(shdw_ready),
        .instr_in(instr), .pc_out(pc_out),
        .shadow_we(shadow_we), .shadow_rd(shadow_rd),
        .shadow_data(shadow_data), .num_writes(num_writes),
        .br_valid(br_valid), .br_taken(br_taken), .br_target(br_target),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
        .ext_wr_en(ext_wr_en), .ext_wr_addr(ext_wr_addr), .ext_wr_data(ext_wr_data),
        .dbg_priv(dbg_priv)
    );

    always #5 clk = ~clk;

    function [31:0] addi; input [4:0] rd, rs1; input [11:0] imm;
        begin addi = {imm, rs1, 3'b000, rd, 7'b0010011}; end
    endfunction
    function [31:0] add; input [4:0] rd, rs1, rs2;
        begin add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; end
    endfunction
    function [31:0] nop; begin nop = 32'h00000013; end endfunction

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        instr = 0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  PCU 6-wide Testbench");
        $display("========================================");

        // 6 addi em paralelo: x1=1, x2=2, x3=3, x4=4, x5=5, x6=6
        instr = { addi(5'd6, 5'd0, 12'd6),
                  addi(5'd5, 5'd0, 12'd5),
                  addi(5'd4, 5'd0, 12'd4),
                  addi(5'd3, 5'd0, 12'd3),
                  addi(5'd2, 5'd0, 12'd2),
                  addi(5'd1, 5'd0, 12'd1) };
        #1;
        $display("       num_writes = %0d (expected 6)", num_writes);
        $display("       lane0 rd = %0d data = %0d", shadow_rd[0*5 +: 5], shadow_data[0*64 +: 64]);
        $display("       lane5 rd = %0d data = %0d", shadow_rd[5*5 +: 5], shadow_data[5*64 +: 64]);
        check(num_writes === 6, "6 writes issued in 1 cycle");
        check(shadow_we === 6'b111111, "all 6 lanes valid");
        check(shadow_data[0*64 +: 64] === 64'd1, "x1 = 1");
        check(shadow_data[5*64 +: 64] === 64'd6, "x6 = 6");

        // Teste de RAW chain dentro do grupo
        // x1=10 (lane0), x2=x1+1 (lane1, forward), x3=x2+1 (lane2, forward)
        // x4=x3+1, x5=x4+1, x6=x5+1
        instr = { addi(5'd6, 5'd5, 12'd1),   // x6 = x5 + 1
                  addi(5'd5, 5'd4, 12'd1),   // x5 = x4 + 1
                  addi(5'd4, 5'd3, 12'd1),   // x4 = x3 + 1
                  addi(5'd3, 5'd2, 12'd1),   // x3 = x2 + 1
                  addi(5'd2, 5'd1, 12'd1),   // x2 = x1 + 1
                  addi(5'd1, 5'd0, 12'd10) };// x1 = 10
        #1;
        $display("       chain: x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d (exp 10,11,12,13,14,15)",
                 shadow_data[0*64 +: 64], shadow_data[1*64 +: 64],
                 shadow_data[2*64 +: 64], shadow_data[3*64 +: 64],
                 shadow_data[4*64 +: 64], shadow_data[5*64 +: 64]);
        check(shadow_data[0*64 +: 64] === 64'd10, "chain x1=10");
        check(shadow_data[1*64 +: 64] === 64'd11, "chain x2=11 (fwd)");
        check(shadow_data[5*64 +: 64] === 64'd15, "chain x6=15 (fwd)");

        // Stall porque shdw_ready = 2 (só cabe 2)
        shdw_ready = 4'd2;
        instr = { addi(5'd6, 5'd0, 12'd6), addi(5'd5, 5'd0, 12'd5),
                  addi(5'd4, 5'd0, 12'd4), addi(5'd3, 5'd0, 12'd3),
                  addi(5'd2, 5'd0, 12'd2), addi(5'd1, 5'd0, 12'd1) };
        #1;
        check(dut.pcu_stall_now === 1'b1, "stall when shadow full");
        shdw_ready = 4'd6;

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
