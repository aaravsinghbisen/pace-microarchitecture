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
module tb_ipc;
    reg clk=0, rst_n=0;
    integer i;
    integer cycles  = 0;
    integer commits = 0;
    reg     counting = 0;
    reg [4:0] dbg_rs = 0;

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

    reg [31:0] imem [0:4095];
    reg [63:0] dmem [0:255];

    top_pace_imem #(.HART_ID(0)) dut (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd6),
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
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en),
        .amo_ext_req(), .amo_ext_op(), .amo_ext_funct3(),
        .amo_ext_funct5(), .amo_ext_addr(), .amo_ext_rs2(),
        .amo_ext_rd(), .amo_ext_ack(1'b0), .amo_ext_result(64'd0)
    );

    always #5 clk = ~clk;

    // IMem: 6-wide fetch (12-bit index because 4096 words)
    wire [31:0] i0 = imem[imem_pc[13:2] + 0];
    wire [31:0] i1 = imem[imem_pc[13:2] + 1];
    wire [31:0] i2 = imem[imem_pc[13:2] + 2];
    wire [31:0] i3 = imem[imem_pc[13:2] + 3];
    wire [31:0] i4 = imem[imem_pc[13:2] + 4];
    wire [31:0] i5 = imem[imem_pc[13:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    // DMem: 1-cycle response
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

    // ===== Commit counter (from AO-Cores to Arch RF) =====
    wire [3:0] rf_we_w = dut.u_arf.we;
    always @(posedge clk) begin
        if (counting) begin
            cycles  = cycles + 1;
            commits = commits + rf_we_w[0] + rf_we_w[1] + rf_we_w[2] + rf_we_w[3];
        end
    end

    integer wr_start;

    initial begin
        for (i=0; i<4096; i=i+1)
            imem[i] = 32'h00000013;   // NOP
        for (i=0; i<256; i=i+1) dmem[i] = 0;

        // ========================================
        // Program: 3500 independent ADDIs, no branches
        // ========================================
        for (i=0; i<3500; i=i+1) begin
            if (i[0] == 1'b0)
                imem[i] = 32'h00100093;   // addi x1, x0, 1
            else
                imem[i] = 32'h00200113;   // addi x2, x0, 2
        end

        #20 rst_n = 1;

        $display("========================================");
        $display("  PACE IPC Testbench");
        $display("========================================");
        $display("  Program:   3500 x addi (no branches)");
        $display("  Fetch:     1 instr/cycle");
        $display("  AO-Cores:  4");
        $display("  Note:      AO-Cores enable ~500 cycles after boot");
        $display("========================================");

        // Warm-up: boot + scout-ahead + AO enable + pipeline fill
        repeat(800) @(posedge clk);
        @(negedge clk);

        $display("  After warm-up: PC=%h  (AO should be running)", dbg_pcu_pc);

        // Measure for 2000 cycles
        counting = 1;
        wr_start = dut.u_shdw.wr_ptr;
        repeat(2000) @(posedge clk);
        counting = 0;
        @(negedge clk);

        $display("");
        $display("  Cycles measured:  %0d", cycles);
        $display("  Commits:          %0d", commits);
        $display("  IPC:              %0d.%03d",
                 (commits*1000/cycles)/1000, (commits*1000/cycles)%1000);
        $display("  Shadow writes:    %0d", dut.u_shdw.wr_ptr - wr_start);
        $display("");
        $display("  Final PC:         %h", dbg_pcu_pc);
        $display("========================================");
        $finish;
    end
endmodule
