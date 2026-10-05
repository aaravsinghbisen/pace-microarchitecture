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
module tb_addi_min;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs=0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire dbg_satp_en;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];
    integer i;
    // stubs
    wire dmem_req, dmem_we; wire [63:0] dmem_addr, dmem_wdata;
    reg [63:0] dmem_rdata; reg dmem_ready;
    wire vmem_req, vmem_we; wire [63:0] vmem_addr, vmem_wdata;
    reg [63:0] vmem_rdata; reg vmem_ready;
    wire pte_req; wire [63:0] pte_addr;
    reg [63:0] pte_rdata; reg pte_ready;
    wire dmmu_pf; wire [63:0] dmmu_fc, dmmu_fv;
    wire mmio_req, mmio_we; wire [63:0] mmio_addr, mmio_wdata;
    reg [63:0] mmio_rdata; reg mmio_ready;

    top_pace_imem #(.HART_ID(0)) dut (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .vmem_req(vmem_req), .vmem_we(vmem_we),
        .vmem_addr(vmem_addr), .vmem_wdata(vmem_wdata),
        .vmem_rdata(vmem_rdata), .vmem_ready(vmem_ready),
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
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en)
    );

    always #5 clk = ~clk;

    wire [31:0] i0 = imem[imem_pc[9:2] + 0];
    wire [31:0] i1 = imem[imem_pc[9:2] + 1];
    wire [31:0] i2 = imem[imem_pc[9:2] + 2];
    wire [31:0] i3 = imem[imem_pc[9:2] + 3];
    wire [31:0] i4 = imem[imem_pc[9:2] + 4];
    wire [31:0] i5 = imem[imem_pc[9:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    always @(posedge clk) begin
        dmem_ready <= 0;
        if (dmem_req) begin
            if (dmem_we) dmem[dmem_addr[8:3]] <= dmem_wdata;
            else dmem_rdata <= 0;
            dmem_ready <= 1;
        end
    end

    // Trace direto do PCU
    always @(posedge clk) begin
        if (rst_n)
            $display("t=%0t PC=%h op=%b rd=x%0d imm=%h x5=%h alu_out=%h",
                $time, dbg_pcu_pc,
                dut.u_pcu.d_opcode[0*7 +: 7],
                dut.u_pcu.d_rd[0*5 +: 5],
                dut.u_pcu.d_imm[0*64 +: 64],
                dut.u_pcu.pcu_regs[5],
                dut.u_pcu.cluster_result[0*64 +: 64]);
    end

    initial begin
        for (i=0; i<256; i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end
        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // Só uma coisa: addi x5, x0, 0x80
        imem[0] = 32'h08000293;
        imem[1] = 32'h0000006F;

        #20 rst_n = 1;
        repeat(15) @(posedge clk);
        $display("FINAL x5 = %0d (exp 128)", dut.u_pcu.pcu_regs[5]);
        $finish;
    end
endmodule
