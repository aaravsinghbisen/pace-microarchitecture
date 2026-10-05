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
module tb_top_pace_mem;

    reg clk = 0;
    reg rst_n_pcu, rst_n_ao;

    wire [63:0] pcu_pc, ao_pc;
    reg  [31:0] pcu_instr, ao_instr;
    wire [63:0] dbg_arch_rd, dbg_pcu_rd, dbg_mc_rd;
    reg  [4:0]  dbg_rs;

    wire        mc_mem_req, mc_mem_we;
    wire [63:0] mc_mem_addr, mc_mem_wdata;
    reg  [63:0] mc_mem_rdata;
    reg         mc_mem_ready;

    integer i;
    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:63];

    top_pace dut (
        .clk(clk),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao),
        .pcu_pc(pcu_pc), .pcu_instr(pcu_instr),
        .ao_pc(ao_pc), .ao_instr(ao_instr),
        .mc_mem_req(mc_mem_req), .mc_mem_we(mc_mem_we),
        .mc_mem_addr(mc_mem_addr), .mc_mem_wdata(mc_mem_wdata),
        .mc_mem_rdata(mc_mem_rdata), .mc_mem_ready(mc_mem_ready),
        .dbg_rs(dbg_rs),
        .dbg_arch_rd(dbg_arch_rd), .dbg_pcu_rd(dbg_pcu_rd), .dbg_mc_rd(dbg_mc_rd)
    );

    always @(*) pcu_instr = imem[pcu_pc[9:2]];
    always @(*) ao_instr  = imem[ao_pc[9:2]];
    always #5 clk = ~clk;

    // Simple data memory (1-cycle response)
    always @(posedge clk) begin
        mc_mem_ready <= 0;
        if (mc_mem_req) begin
            if (mc_mem_we) dmem[mc_mem_addr[8:3]] <= mc_mem_wdata;
            else           mc_mem_rdata <= dmem[mc_mem_addr[8:3]];
            mc_mem_ready <= 1;
        end
    end

    // ============ DEBUG ============
    `define DEBUG_ON
    `ifdef DEBUG_ON
        reg [1:0] last_st = 2'h3;
        always @(posedge clk) begin
            if (rst_n_pcu) begin
                if (dut.u_mc.state !== last_st ||
                    dut.u_pcu.shadow_we ||
                    dut.u_mc.shadow_we ||
                    dut.rf_wr_en) begin
                    $display("t=%0t | PCU pc=%h shdw_we=%b rd=x%0d d=%h | MC st=%0d busy=%b shdw_we=%b rd=x%0d d=%h | shdw_wr=%b | rf_we=%b x%0d=%h",
                        $time, pcu_pc, dut.pcu_shdw_we, dut.pcu_shdw_rd, dut.pcu_shdw_data,
                        dut.u_mc.state, dut.mc_busy, dut.mc_shdw_we, dut.mc_shdw_rd, dut.mc_shdw_data,
                        dut.shdw_we_final,
                        dut.rf_wr_en, dut.rf_wr_addr, dut.rf_wr_data);
                    last_st <= dut.u_mc.state;
                end
            end
        end
    `endif

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;
    task check_arch;
        input [4:0]   reg_num;
        input [63:0]  expected;
        input [255:0] name;
        begin
            dbg_rs = reg_num;
            #1;
            tests_run = tests_run + 1;
            if (dbg_arch_rd === expected) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s : x%0d = %0d", name, reg_num, dbg_arch_rd);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s : x%0d = %0d (expected %0d)",
                         name, reg_num, dbg_arch_rd, expected);
            end
        end
    endtask

    localparam NOP = 32'h00000013;

    initial begin
        // Program:
        //   0x00  addi x1, x0, 5
        //   0x04  addi x2, x0, 3
        //   0x08  add  x3, x1, x2    = 8
        //   0x0C  sub  x4, x1, x2    = 2
        //   0x10  lw   x5, 8(x0)     = dmem[1] = 0xDEAD
        //   0x14  xor  x6, x5, x1    = 0xDEAD ^ 5
        //   0x18  and  x7, x2, x1    = 1
        imem[0]  = 32'h00500093;
        imem[1]  = 32'h00300113;
        imem[2]  = 32'h002081B3;
        imem[3]  = 32'h40208233;
        imem[4]  = 32'h00802283;   // lw x5, 8(x0)
        imem[5]  = 32'h0012C333;   // xor x6, x5, x1
        imem[6]  = 32'h001173B3;   // and x7, x2, x1  (funct7=0000000, rs2=x1, rs1=x2, funct3=111, rd=x7)
        for (i = 7; i < 256; i = i + 1) imem[i] = NOP;

        // Fix x7: and x7, x2, x1 -> opcode 0110011, rd=00111, funct3=111, rs1=00010, rs2=00001
        // = 0000000_00001_00010_111_00111_0110011 = 0x001173B3
        // Hmm let me just verify: 7'b0_00001_00010_111_00111_0110011 → OK it's 0x001173B3

        for (i = 0; i < 64; i = i + 1) dmem[i] = 64'd0;
        dmem[1] = 64'hDEAD;   // word at address 8

        rst_n_pcu = 0;
        rst_n_ao  = 0;
        dbg_rs    = 0;

        $display("========================================");
        $display("  PACE with Memory - Top Integration");
        $display("========================================");

        #20 rst_n_pcu = 1;
        $display("[BOOT] PCU+M-Core enabled");

        repeat(80) @(posedge clk);
        @(negedge clk);

        rst_n_ao = 1;
        $display("[BOOT] AO-Core enabled");

        repeat(80) @(posedge clk);
        @(negedge clk);

        check_arch(5'd1, 64'd5,         "x1 = 5");
        check_arch(5'd2, 64'd3,         "x2 = 3");
        check_arch(5'd3, 64'd8,         "x3 = 8");
        check_arch(5'd4, 64'd2,         "x4 = 2");
        check_arch(5'd5, 64'hDEAD,      "x5 = 0xDEAD (load)");
        check_arch(5'd6, 64'hDEAD ^ 5,  "x6 = 0xDEAD ^ 5");
        check_arch(5'd7, 64'd1,         "x7 = 1");
        check_arch(5'd0, 64'd0,         "x0 = 0");

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
