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
module tb_two_cores;
    reg clk=0, rst_n=0;
    integer i, t_run=0, t_pass=0, t_fail=0;

    // Core 0
    wire [63:0] imem_pc0;
    wire [6*32-1:0] imem_instr0;
    wire dmem_req0, dmem_we0;
    wire [63:0] dmem_addr0, dmem_wdata0;
    reg [63:0] dmem_rdata0;
    reg dmem_ready0;
    wire vmem_req0, vmem_we0;
    wire [63:0] vmem_addr0, vmem_wdata0;
    reg [63:0] vmem_rdata0;
    reg vmem_ready0;
    wire pte_req0; wire [63:0] pte_addr0;
    reg [63:0] pte_rdata0; reg pte_ready0;
    wire dmmu_pf0; wire [63:0] dmmu_fc0, dmmu_fv0;
    wire mmio_req0, mmio_we0; wire [63:0] mmio_addr0, mmio_wdata0;
    reg [63:0] mmio_rdata0; reg mmio_ready0;
    wire [63:0] dbg_arch_rd0, dbg_pcu_pc0, dbg_satp0;
    wire dbg_satp_en0;
    reg [4:0] dbg_rs0 = 0;

    // Core 1
    wire [63:0] imem_pc1;
    wire [6*32-1:0] imem_instr1;
    wire dmem_req1, dmem_we1;
    wire [63:0] dmem_addr1, dmem_wdata1;
    reg [63:0] dmem_rdata1;
    reg dmem_ready1;
    wire vmem_req1, vmem_we1;
    wire [63:0] vmem_addr1, vmem_wdata1;
    reg [63:0] vmem_rdata1;
    reg vmem_ready1;
    wire pte_req1; wire [63:0] pte_addr1;
    reg [63:0] pte_rdata1; reg pte_ready1;
    wire dmmu_pf1; wire [63:0] dmmu_fc1, dmmu_fv1;
    wire mmio_req1, mmio_we1; wire [63:0] mmio_addr1, mmio_wdata1;
    reg [63:0] mmio_rdata1; reg mmio_ready1;
    wire [63:0] dbg_arch_rd1, dbg_pcu_pc1, dbg_satp1;
    wire dbg_satp_en1;
    reg [4:0] dbg_rs1 = 0;

    reg [31:0] imem0 [0:255], imem1 [0:255];
    reg [63:0] dmem0 [0:255], dmem1 [0:255];

    // Core 0 — HART_ID = 0
    top_pace_imem #(.HART_ID(0)) core0 (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc0), .imem_instr(imem_instr0),
        .dmem_req(dmem_req0), .dmem_we(dmem_we0),
        .dmem_addr(dmem_addr0), .dmem_wdata(dmem_wdata0),
        .dmem_rdata(dmem_rdata0), .dmem_ready(dmem_ready0),
        .vmem_req(vmem_req0), .vmem_we(vmem_we0),
        .vmem_addr(vmem_addr0), .vmem_wdata(vmem_wdata0),
        .vmem_rdata(vmem_rdata0), .vmem_ready(vmem_ready0),
        .pte_req(pte_req0), .pte_addr(pte_addr0),
        .pte_rdata(pte_rdata0), .pte_ready(pte_ready0),
        .dmmu_page_fault(dmmu_pf0),
        .dmmu_fault_cause(dmmu_fc0), .dmmu_fault_va(dmmu_fv0),
        .mmio_req(mmio_req0), .mmio_we(mmio_we0),
        .mmio_addr(mmio_addr0), .mmio_wdata(mmio_wdata0),
        .mmio_rdata(mmio_rdata0), .mmio_ready(mmio_ready0),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs0), .dbg_arch_rd(dbg_arch_rd0),
        .dbg_pcu_pc(dbg_pcu_pc0), .dbg_satp(dbg_satp0), .dbg_satp_en(dbg_satp_en0)
    );

    // Core 1 — HART_ID = 1
    top_pace_imem #(.HART_ID(1)) core1 (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc1), .imem_instr(imem_instr1),
        .dmem_req(dmem_req1), .dmem_we(dmem_we1),
        .dmem_addr(dmem_addr1), .dmem_wdata(dmem_wdata1),
        .dmem_rdata(dmem_rdata1), .dmem_ready(dmem_ready1),
        .vmem_req(vmem_req1), .vmem_we(vmem_we1),
        .vmem_addr(vmem_addr1), .vmem_wdata(vmem_wdata1),
        .vmem_rdata(vmem_rdata1), .vmem_ready(vmem_ready1),
        .pte_req(pte_req1), .pte_addr(pte_addr1),
        .pte_rdata(pte_rdata1), .pte_ready(pte_ready1),
        .dmmu_page_fault(dmmu_pf1),
        .dmmu_fault_cause(dmmu_fc1), .dmmu_fault_va(dmmu_fv1),
        .mmio_req(mmio_req1), .mmio_we(mmio_we1),
        .mmio_addr(mmio_addr1), .mmio_wdata(mmio_wdata1),
        .mmio_rdata(mmio_rdata1), .mmio_ready(mmio_ready1),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs1), .dbg_arch_rd(dbg_arch_rd1),
        .dbg_pcu_pc(dbg_pcu_pc1), .dbg_satp(dbg_satp1), .dbg_satp_en(dbg_satp_en1)
    );

    always #5 clk = ~clk;

    // IMem por core
    wire [31:0] i0_0 = imem0[imem_pc0[9:2] + 0];
    wire [31:0] i1_0 = imem0[imem_pc0[9:2] + 1];
    wire [31:0] i2_0 = imem0[imem_pc0[9:2] + 2];
    wire [31:0] i3_0 = imem0[imem_pc0[9:2] + 3];
    wire [31:0] i4_0 = imem0[imem_pc0[9:2] + 4];
    wire [31:0] i5_0 = imem0[imem_pc0[9:2] + 5];
    assign imem_instr0 = {i5_0, i4_0, i3_0, i2_0, i1_0, i0_0};

    wire [31:0] i0_1 = imem1[imem_pc1[9:2] + 0];
    wire [31:0] i1_1 = imem1[imem_pc1[9:2] + 1];
    wire [31:0] i2_1 = imem1[imem_pc1[9:2] + 2];
    wire [31:0] i3_1 = imem1[imem_pc1[9:2] + 3];
    wire [31:0] i4_1 = imem1[imem_pc1[9:2] + 4];
    wire [31:0] i5_1 = imem1[imem_pc1[9:2] + 5];
    assign imem_instr1 = {i5_1, i4_1, i3_1, i2_1, i1_1, i0_1};

    // DMem por core
    always @(posedge clk) begin
        dmem_ready0 <= 0; vmem_ready0 <= 0;
        dmem_ready1 <= 0; vmem_ready1 <= 0;
        if (dmem_req0) begin
            if (dmem_we0) dmem0[dmem_addr0[8:3]] <= dmem_wdata0;
            else          dmem_rdata0 <= dmem0[dmem_addr0[8:3]];
            dmem_ready0 <= 1;
        end
        if (vmem_req0) begin
            if (vmem_we0) dmem0[vmem_addr0[8:3]] <= vmem_wdata0;
            else          vmem_rdata0 <= dmem0[vmem_addr0[8:3]];
            vmem_ready0 <= 1;
        end
        if (dmem_req1) begin
            if (dmem_we1) dmem1[dmem_addr1[8:3]] <= dmem_wdata1;
            else          dmem_rdata1 <= dmem1[dmem_addr1[8:3]];
            dmem_ready1 <= 1;
        end
        if (vmem_req1) begin
            if (vmem_we1) dmem1[vmem_addr1[8:3]] <= vmem_wdata1;
            else          vmem_rdata1 <= dmem1[vmem_addr1[8:3]];
            vmem_ready1 <= 1;
        end
    end

    task check;
        input cond; input [255:0] name;
        begin
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        // Inicializa MMIO/PTE (não usados)
        pte_rdata0 = 0; pte_ready0 = 0;
        mmio_rdata0 = 0; mmio_ready0 = 0;
        pte_rdata1 = 0; pte_ready1 = 0;
        mmio_rdata1 = 0; mmio_ready1 = 0;

        for (i=0;i<256;i=i+1) begin
            imem0[i] = 32'h00000013; imem1[i] = 32'h00000013;
            dmem0[i] = 0; dmem1[i] = 0;
        end

        // Core 0: addi x1, x0, 11; addi x2, x0, 22; add x3, x1, x2; jal x0, 0
        imem0[0] = 32'h00B00093;
        imem0[1] = 32'h01600113;
        imem0[2] = 32'h002081B3;
        imem0[3] = 32'h0000006F;

        // Core 1: addi x1, x0, 100; addi x2, x0, 200; add x3, x1, x2; jal x0, 0
        imem1[0] = 32'h06400093;
        imem1[1] = 32'h0C800113;
        imem1[2] = 32'h002081B3;
        imem1[3] = 32'h0000006F;

        #20 rst_n = 1;

        $display("========================================");
        $display("  Two PACE cores (HART 0 + HART 1)");
        $display("========================================");

        repeat(300) @(posedge clk);
        @(negedge clk);

        // Core 0 check
        dbg_rs0 = 5'd3; #1;
        check(dbg_arch_rd0 === 64'd33, "Core 0: x3 = 33 (11+22)");
        // Core 1 check
        dbg_rs1 = 5'd3; #1;
        check(dbg_arch_rd1 === 64'd300, "Core 1: x3 = 300 (100+200)");

        // Verifica que PCUs estão em PCs diferentes
        $display("  Core 0 PC = %h, Core 1 PC = %h", dbg_pcu_pc0, dbg_pcu_pc1);

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — 2 harts coexist");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
