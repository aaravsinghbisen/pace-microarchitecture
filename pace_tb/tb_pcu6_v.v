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
module tb_pcu6_v;
    reg clk=0, rst_n=0, stall=0, fetch_stall=0;
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
    wire [7:0] dbg_vl;
    wire [63:0] dbg_vtype;

    integer tests_run=0, tests_passed=0, tests_failed=0;

    pcu6_v dut (
        .clk(clk), .rst_n(rst_n),
        .stall(stall), .fetch_stall(fetch_stall),
        .shdw_wr_ready(shdw_ready),
        .instr_in(instr), .pc_out(pc_out),
        .shadow_we(shadow_we), .shadow_rd(shadow_rd),
        .shadow_data(shadow_data), .num_writes(num_writes),
        .br_valid(br_valid), .br_taken(br_taken), .br_target(br_target),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
        .ext_wr_en(ext_wr_en), .ext_wr_addr(ext_wr_addr), .ext_wr_data(ext_wr_data),
        .dbg_priv(dbg_priv), .dbg_vl(dbg_vl), .dbg_vtype(dbg_vtype)
    );

    always #5 clk = ~clk;

    function [31:0] addi; input [4:0] rd, rs1; input [11:0] imm;
        begin addi = {imm, rs1, 3'b000, rd, 7'b0010011}; end endfunction
    function [31:0] nop; begin nop = 32'h00000013; end endfunction

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    // vsetvli rd, rs1, vtypei (funct3=111, opcode=1010111, bit31=0)
    function [31:0] vsetvli; input [4:0] rd, rs1; input [10:0] vtypei;
        begin vsetvli = {1'b0, vtypei, rs1, 3'b111, rd, 7'b1010111}; end endfunction
    // vadd.vv vd, vs1, vs2 (funct6=000000, vm=1 (unmasked), opcode=1010111, funct3=000)
    function [31:0] vadd_vv; input [4:0] vd, vs1, vs2;
        begin vadd_vv = {6'b000000, 1'b1, vs2, vs1, 3'b000, vd, 7'b1010111}; end endfunction

    initial begin
        instr = 0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  PCU 6-wide + Vector Testbench");
        $display("========================================");

        // T1: 6 ALUs normais
        instr = { addi(5'd6,5'd0,12'd6), addi(5'd5,5'd0,12'd5),
                  addi(5'd4,5'd0,12'd4), addi(5'd3,5'd0,12'd3),
                  addi(5'd2,5'd0,12'd2), addi(5'd1,5'd0,12'd1) };
        #1;
        check(num_writes === 6, "T1: 6 ALU writes");

        // T2: vsetvli (1 instrução, sem writes ALU)
        instr = { nop(), nop(), nop(), nop(), nop(), vsetvli(5'd0, 5'd0, 11'b0) };
        #1;
        check(num_writes === 0, "T2: vsetvli doesn't write ALU");

        // T3: vadd (1 instr)
        instr = { nop(), nop(), nop(), nop(), nop(), vadd_vv(5'd1, 5'd2, 5'd3) };
        #1;
        check(num_writes === 0, "T3: vadd doesn't write ALU");

        $display("  VL = %0d, VType = %h", dbg_vl, dbg_vtype);

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
