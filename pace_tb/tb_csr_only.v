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
module tb_csr_only;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_vtype, dbg_instr_count, dbg_satp;
    wire [7:0]  dbg_vl;
    wire [31:0] dbg_ipc_x1000;
    wire        dbg_satp_en, dbg_flush_tlb, dbg_trap_taken;
    wire [2:0]  dbg_advance;
    wire [63:0] dbg_new_pc;

    reg  [6*32-1:0] instr_bus;
    reg  [63:0] pc_in;
    wire [63:0] pc_out;
    wire [5:0]  shdw_we;
    wire [6*5-1:0] shdw_rd;
    wire [6*64-1:0] shdw_data;

    integer tests_run=0, tests_passed=0, tests_failed=0;

    pcu6_v dut (
        .clk(clk), .rst_n(rst_n),
        .stall(1'b0), .fetch_stall(1'b0), .shdw_wr_ready(4'd6),
        .instr_count(4'd1),   // só lane 0 válida neste tb
        .instr_in(instr_bus),
        .pc_out(pc_out),
        .shadow_we(shdw_we), .shadow_rd(shdw_rd), .shadow_data(shdw_data),
        .num_writes(),
        .br_valid(), .br_taken(), .br_target(),
        .redirect_valid(1'b0), .redirect_pc(64'd0),
        .ext_wr_en(1'b0), .ext_wr_addr(5'd0), .ext_wr_data(64'd0),
        .dbg_priv(), .dbg_satp(dbg_satp), .dbg_satp_enable(dbg_satp_en),
        .dbg_flush_tlb(dbg_flush_tlb), .dbg_trap_taken(dbg_trap_taken),
        .dbg_advance(dbg_advance), .dbg_flush_fetch(), .dbg_new_pc(dbg_new_pc),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_vl(dbg_vl), .dbg_vtype(dbg_vtype),
        .dbg_vrs(5'd0), .dbg_vrd()
    );

    always #5 clk = ~clk;

    // IMem simples (combinacional)
    reg [31:0] imem [0:255];
    always @(*) begin
        instr_bus = {32'h00000013, 32'h00000013, 32'h00000013, 32'h00000013, 32'h00000013, imem[pc_out[9:2]]};
    end

    integer i;
    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    // Trace
    reg [63:0] last_pc;
    always @(posedge clk) begin
        if (rst_n && pc_out !== last_pc) begin
            $display("t=%0t PCU pc=%h instr=%h", $time, pc_out, imem[pc_out[9:2]]);
            last_pc <= pc_out;
        end
    end

    initial begin
        for (i=0;i<256;i=i+1) imem[i] = 32'h00000013;
        // 0x00: addi x1, x0, 0x40
        // 0x04: csrrw x0, mtvec, x1
        // 0x08: ecall
        // 0x0C: addi x3, x0, 99
        // 0x10: addi x8, x0, 100
        // 0x14: jal x0, 0
        // 0x40: csrrs x5, mepc, x0
        // 0x44: addi x5, x5, 4
        // 0x48: csrrw x0, mepc, x5
        // 0x4C: mret
        imem[0]  = 32'h04000093;
        imem[1]  = 32'h30509073;
        imem[2]  = 32'h00000073;
        imem[3]  = 32'h06300193;
        imem[4]  = 32'h06400413;
        imem[5]  = 32'h0000006F;
        imem[16] = 32'h341022F3;   // 0x40
        imem[17] = 32'h00428293;   // 0x44
        imem[18] = 32'h34129073;   // 0x48
        imem[19] = 32'h30200073;   // 0x4C

        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  CSR/Trap no PCU (isolado)");
        $display("========================================");

        repeat(100) @(posedge clk);
        @(negedge clk);

        $display("  Final PCU pc = %h", pc_out);

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        $display("========================================");
        $finish;
    end
endmodule
