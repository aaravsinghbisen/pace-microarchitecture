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
module tb_csr_pcu;
    reg clk = 0, rst_n;
    wire [63:0] pc_out, dbg_result;
    reg  [31:0] instr;
    wire shadow_we, shadow_exc, pcu_valid;
    wire [4:0] shadow_rd;
    wire [63:0] shadow_data;
    wire br_valid, br_taken;
    wire [63:0] br_target;
    wire [1:0] dbg_priv;

    reg [63:0] shadow_log [0:31];
    reg [4:0]  shadow_rd_log [0:31];
    integer shadow_count = 0;
    reg [63:0] pc_prev;

    reg [31:0] imem [0:31];
    integer i;

    pcu dut (
        .clk(clk), .rst_n(rst_n),
        .stall(1'b0), .fetch_stall(1'b0), .shdw_wr_ready(1'b1),
        .pcu_valid(pcu_valid),
        .pc_out(pc_out), .instr_in(instr),
        .shadow_we(shadow_we), .shadow_rd(shadow_rd),
        .shadow_data(shadow_data), .shadow_exc(shadow_exc),
        .ext_wr_en(1'b0), .ext_wr_addr(5'd0), .ext_wr_data(64'd0),
        .br_valid(br_valid), .br_taken(br_taken), .br_target(br_target),
        .redirect_valid(1'b0), .redirect_pc(64'd0),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_result(dbg_result), .dbg_priv(dbg_priv)
    );

    always @(*) instr = imem[pc_out[6:2]];

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && pc_out !== pc_prev)
            $display("t=%0t pc=%h instr=%h priv=%b", $time, pc_out, instr, dbg_priv);
        pc_prev <= pc_out;
    end

    always @(posedge clk) begin
        if (shadow_we) begin
            shadow_log[shadow_count]    <= shadow_data;
            shadow_rd_log[shadow_count] <= shadow_rd;
            shadow_count <= shadow_count + 1;
            $display("t=%0t WRITE rd=x%0d data=%h cnt=%0d", $time, shadow_rd, shadow_data, shadow_count);
        end
    end

    integer tests_run=0, tests_passed=0, tests_failed=0;
    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    function [63:0] find_rd;
        input [4:0] r;
        integer k;
        begin
            find_rd = 64'hDEAD_BEEF_DEAD_BEEF;
            for (k = 0; k < shadow_count; k = k + 1)
                if (shadow_rd_log[k] == r) find_rd = shadow_log[k];
        end
    endfunction

    localparam NOP = 32'h00000013;

    initial begin
        // Program:
        //   0x00  addi x1, x0, 0x40     ; handler at 0x40
        //   0x04  csrrw x0, mtvec, x1   ; mtvec = 0x40
        //   0x08  ecall                 ; trap → 0x40, mepc = 0x08
        //   0x0C  addi x3, x0, 99       ; runs after mret
        //   0x10  jal x0, 0             ; infinite loop
        //   ...
        //   0x40  csrrs x5, mepc, x0    ; x5 = 0x08
        //   0x44  addi x5, x5, 4        ; x5 = 0x0C
        //   0x48  csrrw x0, mepc, x5    ; mepc = 0x0C
        //   0x4C  mret                  ; return to 0x0C
        imem[0]  = 32'h04000093;   // addi x1, x0, 0x40
        imem[1]  = 32'h30509073;   // csrrw x0, mtvec, x1
        imem[2]  = 32'h00000073;   // ecall
        imem[3]  = 32'h06300193;   // addi x3, x0, 99
        imem[4]  = 32'h0000006F;   // jal x0, 0 (infinite loop at 0x10)
        for (i=5; i<16; i=i+1) imem[i] = NOP;
        imem[16] = 32'h341022F3;   // 0x40 csrrs x5, mepc, x0
        imem[17] = 32'h00428293;   // 0x44 addi x5, x5, 4
        imem[18] = 32'h34129073;   // 0x48 csrrw x0, mepc, x5
        imem[19] = 32'h30200073;   // 0x4C mret
        imem[20] = 32'h0000006F;   // 0x50 jal x0, 0
        for (i=21; i<32; i=i+1) imem[i] = NOP;

        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  Trap end-to-end test");
        $display("========================================");

        check(dbg_priv === 2'b11, "reset in M-mode");

        // Let it run
        repeat(120) @(posedge clk);
        @(negedge clk);

        $display("--- captured shadow writes ---");
        for (i = 0; i < 10 && i < shadow_count; i = i + 1)
            $display("  [%0d] rd=x%0d data=%h", i, shadow_rd_log[i], shadow_log[i]);

        // Expected: x1=0x40, x5=0x08, x5=0x0C, x3=99
        check(shadow_count >= 4, "at least 4 writes (x1, x5, x5, x3)");
        check(find_rd(5'd1) === 64'h40, "x1 = 0x40 (handler addr)");
        check(find_rd(5'd3) === 64'd99, "x3 = 99 (ran after mret)");
        check(dbg_priv === 2'b11, "still M-mode after trap+mret");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
