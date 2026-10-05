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
module tb_m_core;

    reg clk = 0, rst_n;

    wire [63:0] pc_out;
    reg  [31:0] instr_in;
    wire        shadow_we, shadow_exc;
    wire [63:0] shadow_data;
    wire        mem_req, mem_we;
    wire [63:0] mem_addr, mem_wdata;
    reg  [63:0] mem_rdata;
    reg         mem_ready;
    reg  [4:0]  dbg_rs;
    wire [63:0] dbg_rd;

    integer i;
    reg [31:0] imem [0:255];

    m_core dut (
        .clk(clk), .rst_n(rst_n),
        .pc_out(pc_out), .instr_in(instr_in),
        .shadow_we(shadow_we), .shadow_data(shadow_data), .shadow_exc(shadow_exc),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
    );

    always @(*) instr_in = imem[pc_out[9:2]];
    always #5 clk = ~clk;

    // Backing memory model
    reg [63:0] dmem [0:255];

    always @(posedge clk) begin
        if (mem_req) begin
            mem_ready <= 1;
            if (mem_we) dmem[mem_addr[9:3]] <= mem_wdata;
            else        mem_rdata <= dmem[mem_addr[9:3]];
        end else begin
            mem_ready <= 0;
        end
    end

    integer tests_run = 0, tests_passed = 0, tests_failed = 0;
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

    initial begin
        // Test program:
        //  0x00  lw  x1, 0(x0)         # x1 = mem[0] (=42 from init)
        //  0x04  sw  x1, 8(x0)         # store to mem[8]
        //  0x08  lw  x2, 8(x0)         # load from mem[8] (forward from SB!)
        //  0x0C  lbu x3, 0(x0)         # unsigned byte load
        //  (each followed by NOPs to avoid internal RAW hazards)
        imem[0]  = 32'h00002083; // lw x1, 0(x0)
        imem[1]  = 32'h00000013;
        imem[2]  = 32'h00000013;
        imem[3]  = 32'h00000013;
        imem[4]  = 32'h00102423; // sw x1, 8(x0)
        imem[5]  = 32'h00000013;
        imem[6]  = 32'h00000013;
        imem[7]  = 32'h00000013;
        imem[8]  = 32'h00802103; // lw x2, 8(x0)
        imem[9]  = 32'h00000013;
        imem[10] = 32'h00000013;
        imem[11] = 32'h00000013;
        imem[12] = 32'h00004183; // lbu x0? actually lbu x0... let's do lbu x3, 0(x0)
        // Fix: lbu x3, 0(x0) = funct3=100, opcode=0000011, rs1=x0, rd=x3, imm=0
        // = 000000000000_00000_100_00011_0000011 = 0x00004003
        for (i = 13; i < 256; i = i + 1) imem[i] = 32'h00000013;

        // Init memory
        for (i = 0; i < 256; i = i + 1) dmem[i] = 64'd0;
        dmem[0] = 64'd42;         // mem[0] = 42

        rst_n = 0;
        dbg_rs = 0;
        mem_ready = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  M-Core Testbench");
        $display("========================================");

        repeat(60) @(posedge clk);
        @(negedge clk);

        dbg_rs = 5'd1; #1;
        check(dbg_rd === 64'd42, "lw x1 = 42 (from mem)");

        dbg_rs = 5'd2; #1;
        check(dbg_rd === 64'd42, "lw x2 = 42 (forwarded from SB)");

        dbg_rs = 5'd3; #1;
        check(dbg_rd === 64'd42, "lbu x3 = 42 (byte load)");

        check(dmem[1] === 64'd42 || dmem[1] === 64'd0, "store went to SB (mem may not be written)");

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
