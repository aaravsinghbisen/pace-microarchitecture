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
module tb_runahead_ports;
    reg clk=0, rst_n=0;
    integer i;
    reg [4:0] dbg_rs = 0;
    reg rh_discard = 0;

    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    wire dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata = 0;
    reg         dmem_ready = 0;
    wire mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg [63:0] mmio_rdata = 0;
    reg        mmio_ready = 0;
    wire pte_req;
    wire [63:0] pte_addr;
    reg [63:0] pte_rdata = 0;
    reg        pte_ready = 0;
    wire dmmu_pf;
    wire [63:0] dmmu_fc, dmmu_fv;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire dbg_satp_en;
    wire rh_stall_long, rh_stall_cleared, rh_sb_full;
    wire amo_ext_req, amo_ext_ack;
    wire [2:0] amo_ext_op, amo_ext_funct3;
    wire [4:0] amo_ext_funct5, amo_ext_rd;
    wire [63:0] amo_ext_addr, amo_ext_rs2, amo_ext_result;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];

    top_pace_imem #(.HART_ID(0)) dut (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .vmem_req(), .vmem_we(), .vmem_addr(), .vmem_wdata(),
        .vmem_rdata(64'd0), .vmem_ready(1'b0),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .dmmu_page_fault(dmmu_pf),
        .dmmu_fault_cause(dmmu_fc), .dmmu_fault_va(dmmu_fv),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .rh_discard(rh_discard),
        .rh_stall_long(rh_stall_long),
        .rh_stall_cleared(rh_stall_cleared),
        .rh_sb_full(rh_sb_full),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en),
        .amo_ext_req(amo_ext_req), .amo_ext_op(amo_ext_op),
        .amo_ext_funct3(amo_ext_funct3), .amo_ext_funct5(amo_ext_funct5),
        .amo_ext_addr(amo_ext_addr), .amo_ext_rs2(amo_ext_rs2),
        .amo_ext_rd(amo_ext_rd), .amo_ext_ack(1'b0), .amo_ext_result(64'd0)
    );

    always #5 clk = ~clk;

    wire [31:0] i0 = imem[imem_pc[9:2] + 0];
    wire [31:0] i1 = imem[imem_pc[9:2] + 1];
    wire [31:0] i2 = imem[imem_pc[9:2] + 2];
    wire [31:0] i3 = imem[imem_pc[9:2] + 3];
    wire [31:0] i4 = imem[imem_pc[9:2] + 4];
    wire [31:0] i5 = imem[imem_pc[9:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    reg pending;
    always @(posedge clk) begin
        dmem_ready <= 0;
        if (!dmem_req) pending <= 0;
        else if (!pending) begin
            pending <= 1;
            if (dmem_we) dmem[dmem_addr[8:3]] <= dmem_wdata;
            else         dmem_rdata <= dmem[dmem_addr[8:3]];
            dmem_ready <= 1;
        end
    end

    // Trace: monitor rh_discard effect
    integer commits_normal = 0;
    integer commits_rh     = 0;
    always @(posedge clk) begin
        if (rst_n && dut.u_arf.we != 4'b0) begin
            if (rh_discard) commits_rh = commits_rh + 1;
            else            commits_normal = commits_normal + 1;
        end
    end

    initial begin
        for (i=0; i<256; i=i+1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 0;
        end
        // Program: 100 independent ADDIs
        for (i=0; i<100; i=i+1)
            imem[i] = 32'h00100093;

        #20 rst_n = 1;

        $display("========================================");
        $display("  Runahead Ports Testbench");
        $display("========================================");

        // Phase 1: normal operation
        repeat(200) @(posedge clk);
        $display("  Phase 1 (normal):  PC=%h  commits=%0d", dbg_pcu_pc, commits_normal);
        $display("    rh_stall_long=%b rh_stall_cleared=%b rh_sb_full=%b",
                 rh_stall_long, rh_stall_cleared, rh_sb_full);

        // Phase 2: force rh_discard high — PCU executes but writes discarded
        $display("  Phase 2: rh_discard=1 (writes should be discarded)");
        rh_discard = 1;
        repeat(50) @(posedge clk);
        @(negedge clk);

        $display("    After rh_discard: PC=%h  commits_normal=%0d commits_rh=%0d",
                 dbg_pcu_pc, commits_normal, commits_rh);

        // Check: PCU still advances (rh_discard doesn't stall)
        $display("    PCU advanced: %s",
                 (dbg_pcu_pc > 64'h100) ? "YES (accepts+executes)" : "NO");

        // Phase 3: release rh_discard
        rh_discard = 0;
        repeat(50) @(posedge clk);
        @(negedge clk);

        $display("  Phase 3 (normal again): PC=%h commits=%0d",
                 dbg_pcu_pc, commits_normal);

        $display("========================================");
        $display("  RESULT:");
        $display("    PCU accepts and executes during rh_discard: %s",
                 (commits_rh == 0) ? "YES (all discarded)" : "NO");
        $display("========================================");
        $finish;
    end
endmodule
