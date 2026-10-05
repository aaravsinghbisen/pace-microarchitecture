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
// Wrapper: PACE base + A extension (atomic_unit).
// Arbitragem de barramento entre MC e atomic_unit.
module pace_ext_a #(parameter HART_ID = 0) (
    input  wire clk, rst_n,
    input  wire [3:0] i_instr_count,
    output wire [63:0] imem_pc,
    input  wire [6*32-1:0] imem_instr,
    // DMem port (arbitrado: MC ou atomic_unit)
    output wire        dmem_req, dmem_we,
    output wire [63:0] dmem_addr, dmem_wdata,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_ready,
    // MMIO/PTE/etc
    output wire        mmio_req, mmio_we,
    output wire [63:0] mmio_addr, mmio_wdata,
    input  wire [63:0] mmio_rdata,
    input  wire        mmio_ready,
    output wire        pte_req,
    output wire [63:0] pte_addr,
    input  wire [63:0] pte_rdata,
    input  wire        pte_ready,
    output wire        dmmu_pf,
    output wire [63:0] dmmu_fc, dmmu_fv,
    input  wire i_mtip, i_msip, i_meip, i_seip, i_stip, i_ssip,
    input  wire [4:0] dbg_rs,
    output wire [63:0] dbg_arch_rd,
    output wire [63:0] dbg_pcu_pc, dbg_satp,
    output wire dbg_satp_en
);
    // Sinais do PACE
    wire        pace_dmem_req, pace_dmem_we;
    wire [63:0] pace_dmem_addr, pace_dmem_wdata;

    // Sinais da extensão A
    wire        amo_ext_req;
    wire [2:0]  amo_ext_op;
    wire [2:0]  amo_ext_funct3;
    wire [4:0]  amo_ext_funct5;
    wire [63:0] amo_ext_addr, amo_ext_rs2;
    wire [4:0]  amo_ext_rd;
    wire        amo_ext_ack;
    wire [63:0] amo_ext_result;
    // Atomic unit mem port
    wire        amo_mem_req, amo_mem_we;
    wire [63:0] amo_mem_addr, amo_mem_wdata;

    // ===== Arbitragem =====
    // Prioridade: atomic_unit (quando amo_ext_req ativo), senão MC.
    wire amo_active = amo_ext_req || amo_mem_req;
    assign dmem_req   = amo_active ? amo_mem_req : pace_dmem_req;
    assign dmem_we    = amo_active ? amo_mem_we  : pace_dmem_we;
    assign dmem_addr  = amo_active ? amo_mem_addr: pace_dmem_addr;
    assign dmem_wdata = amo_active ? amo_mem_wdata : pace_dmem_wdata;

    wire pace_dmem_ready = !amo_active && dmem_ready;
    wire amo_dmem_ready  =  amo_active && dmem_ready;

    // ===== PACE =====
    top_pace_imem #(.HART_ID(HART_ID)) u_pace (
        .clk(clk), .rst_n(rst_n), .i_instr_count(i_instr_count),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(pace_dmem_req), .dmem_we(pace_dmem_we),
        .dmem_addr(pace_dmem_addr), .dmem_wdata(pace_dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(pace_dmem_ready),
        .vmem_req(), .vmem_we(), .vmem_addr(), .vmem_wdata(),
        .vmem_rdata(64'd0), .vmem_ready(1'b0),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .dmmu_page_fault(dmmu_pf),
        .dmmu_fault_cause(dmmu_fc), .dmmu_fault_va(dmmu_fv),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .i_mtip(i_mtip), .i_msip(i_msip), .i_meip(i_meip),
        .i_seip(i_seip), .i_stip(i_stip), .i_ssip(i_ssip),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en),
        .amo_ext_req(amo_ext_req),
        .amo_ext_op(amo_ext_op),
        .amo_ext_funct3(amo_ext_funct3),
        .amo_ext_funct5(amo_ext_funct5),
        .amo_ext_addr(amo_ext_addr),
        .amo_ext_rs2(amo_ext_rs2),
        .amo_ext_rd(amo_ext_rd),
        .amo_ext_ack(amo_ext_ack),
        .amo_ext_result(amo_ext_result)
    );

    // ===== Extensão A =====
    atomic_unit u_amo (
        .clk(clk), .rst_n(rst_n),
        .req(amo_ext_req),
        .is_lr (amo_ext_op == 3'd2),
        .is_sc (amo_ext_op == 3'd3),
        .is_amo(amo_ext_op == 3'd4),
        .amo_op(amo_ext_funct5),
        .is_word(amo_ext_funct3 == 3'b010),
        .addr(amo_ext_addr),
        .rs2_val(amo_ext_rs2),
        .rd_val(amo_ext_result),
        .sc_success(),
        .done(amo_ext_ack),
        .mem_req(amo_mem_req), .mem_we(amo_mem_we),
        .mem_addr(amo_mem_addr), .mem_wdata(amo_mem_wdata),
        .mem_rdata(dmem_rdata),
        .mem_ready(amo_dmem_ready)
    );
endmodule
