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
module top_pace_final (
    input  wire clk,
    input  wire rst_n_in,
    // MMIO (uncached, para o SoC)
    output wire        mmio_req, mmio_we,
    output wire [63:0] mmio_addr, mmio_wdata,
    input  wire [63:0] mmio_rdata,
    input  wire        mmio_ready,
    // DRAM (cacheable)
    output wire        dram_req, dram_we,
    output wire [63:0] dram_addr,
    output wire [511:0] dram_wdata,
    input  wire [511:0] dram_rdata,
    input  wire        dram_ready,
    // Interrupts
    input  wire        i_mtip, i_msip, i_meip, i_seip, i_stip, i_ssip,
    // Debug
    output wire [63:0] dbg_pcu_pc,
    output wire [1:0]  dbg_priv,
    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_arch_rd
);
    // ==== Boot sequencer ====
    wire rst_n_pcu, rst_n_ao, boot_done;
    boot_sequencer #(.SCOUT_AHEAD_CYCLES(64)) u_boot (
        .clk(clk), .rst_n(rst_n_in),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao), .boot_done(boot_done)
    );

    // ==== MMU config (TODO: hook to CSRs once integrated) ====
    wire        satp_enable = 1'b0;   // bare mode for now
    wire [43:0] satp_ppn    = 44'd0;
    wire [8:0]  asid        = 9'd0;
    wire        flush_tlb   = 1'b0;

    // ==== PCU ====
    wire [63:0] pcu_pc;
    wire [31:0] pcu_instr;
    wire        pcu_fetch_stall;
    wire        pcu_valid, pcu_shdw_we, pcu_shdw_exc;
    wire [4:0]  pcu_shdw_rd;
    wire [63:0] pcu_shdw_data;
    wire        pcu_br_v, pcu_br_t;
    wire [63:0] pcu_br_tgt;
    wire        redir_v;
    wire [63:0] redir_pc;

    // ==== Shadow RF ====
    wire        shdw_wr_ready, shdw_wr_full;
    wire [71:0] shdw_rd_data;
    wire        shdw_rd_valid, shdw_rd_en, shdw_rd_exc, shdw_rd_empty;
    wire [5:0]  shdw_wr_ptr, shdw_rd_ptr;

    // ==== M-Core ====
    wire        mc_shdw_we, mc_shdw_exc;
    wire [4:0]  mc_shdw_rd;
    wire [63:0] mc_shdw_data;
    wire        mc_busy;
    wire        mc_req, mc_we;
    wire [63:0] mc_addr, mc_wdata, mc_rdata;
    wire        mc_ready;

    // ==== AO-Core ====
    wire [4:0]  rf_wr_addr;
    wire [63:0] rf_wr_data;
    wire        rf_wr_en;

    // ==== L1d (with MMU) ====
    wire        l1d_l2_req, l1d_l2_we;
    wire [63:0] l1d_l2_addr, l1d_l2_wdata;
    wire [511:0] l1d_l2_rdata;
    wire        l1d_l2_ready;
    wire        l1d_pte_req;
    wire [63:0] l1d_pte_addr;
    wire [63:0] l1d_pte_rdata;
    wire        l1d_pte_ready;
    wire        l1d_page_fault;
    wire [63:0] l1d_fault_cause, l1d_fault_va;

    // ==== L1i (with MMU) ====
    wire        l1i_l2_req;
    wire [63:0] l1i_l2_addr;
    wire [255:0] l1i_l2_data;
    wire        l1i_l2_ready;
    wire        l1i_pte_req;
    wire [63:0] l1i_pte_addr;
    wire [63:0] l1i_pte_rdata;
    wire        l1i_pte_ready;
    wire        l1i_page_fault;
    wire [63:0] l1i_fault_cause, l1i_fault_va;

    // ==== L2 ====
    wire [511:0] l2_p1_rdata;
    wire        l2_p1_ready;
    wire        l2_p0_ready;
    wire [511:0] l2_p0_rdata;

    // Mux PTE requests (L1i + L1d) into L2 p0
    // Priority: L1d first (data), then L1i (fetch) — simple round-robin enough
    wire pte_arb_req = l1d_pte_req | l1i_pte_req;
    wire pte_arb_sel = l1d_pte_req;   // 0=instr, 1=data
    wire [63:0] pte_arb_addr = l1d_pte_req ? l1d_pte_addr : l1i_pte_addr;

    assign l1d_pte_rdata = pte_arb_sel ? l2_p0_rdata[63:0] : 64'd0;
    assign l1d_pte_ready = pte_arb_sel ? l2_p0_ready : 1'b0;
    assign l1i_pte_rdata = (!pte_arb_sel) ? l2_p0_rdata[63:0] : 64'd0;
    assign l1i_pte_ready = (!pte_arb_sel) ? l2_p0_ready : 1'b0;

    // ==== PCU ====
    pcu u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .stall(mc_busy), .fetch_stall(pcu_fetch_stall),
        .shdw_wr_ready(shdw_wr_ready),
        .pcu_valid(pcu_valid),
        .pc_out(pcu_pc), .instr_in(pcu_instr),
        .shadow_we(pcu_shdw_we), .shadow_rd(pcu_shdw_rd),
        .shadow_data(pcu_shdw_data), .shadow_exc(pcu_shdw_exc),
        .ext_wr_en(mc_shdw_we), .ext_wr_addr(mc_shdw_rd), .ext_wr_data(mc_shdw_data),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t), .br_target(pcu_br_tgt),
        .redirect_valid(redir_v), .redirect_pc(redir_pc),
        .i_mtip(i_mtip), .i_msip(i_msip), .i_meip(i_meip),
        .i_seip(i_seip), .i_stip(i_stip), .i_ssip(i_ssip),
        .dbg_result(), .dbg_priv(dbg_priv)
    );

    // ==== M-Core ====
    m_core u_mc (
        .clk(clk), .rst_n(rst_n_pcu),
        .pcu_valid(pcu_valid),
        .shdw_wr_ready(shdw_wr_ready),
        .instr_in(pcu_instr),
        .shadow_we(mc_shdw_we), .shadow_rd(mc_shdw_rd),
        .shadow_data(mc_shdw_data), .shadow_exc(mc_shdw_exc),
        .stall_pcu(mc_busy),
        .ext_wr_en(pcu_shdw_we), .ext_wr_addr(pcu_shdw_rd), .ext_wr_data(pcu_shdw_data),
        .mem_req(mc_req), .mem_we(mc_we),
        .mem_addr(mc_addr), .mem_wdata(mc_wdata),
        .mem_rdata(mc_rdata), .mem_ready(mc_ready),
        .dbg_rs(5'd0), .dbg_rd()
    );

    // ==== Shadow RF ====
    wire        shdw_we_final   = pcu_shdw_we | mc_shdw_we;
    wire [4:0]  shdw_rd_final   = mc_shdw_we ? mc_shdw_rd : pcu_shdw_rd;
    wire [63:0] shdw_data_final = mc_shdw_we ? mc_shdw_data : pcu_shdw_data;
    wire [71:0] shdw_pack       = {3'b0, shdw_rd_final, shdw_data_final};

    shadow_rf #(.DEPTH(32), .DATA_WIDTH(72)) u_shadow (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(shdw_we_final), .wr_data(shdw_pack), .wr_exception(1'b0),
        .wr_ready(shdw_wr_ready), .wr_full(shdw_wr_full),
        .rd_en(shdw_rd_en), .rd_data(shdw_rd_data),
        .rd_exception(shdw_rd_exc), .rd_valid(shdw_rd_valid),
        .rd_empty(shdw_rd_empty),
        .dbg_wr_ptr(shdw_wr_ptr), .dbg_rd_ptr(shdw_rd_ptr)
    );

    // ==== B-Core ====
    b_core u_bc (
        .clk(clk), .rst_n(rst_n_pcu),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t),
        .br_target(pcu_br_tgt), .br_pc(pcu_pc),
        .redirect_valid(redir_v), .redirect_pc(redir_pc)
    );

    // ==== AO-Core ====
    ao_core_fifo u_ao (
        .clk(clk), .rst_n(rst_n_ao),
        .shdw_data(shdw_rd_data), .shdw_valid(shdw_rd_valid),
        .shdw_rd_en(shdw_rd_en),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en)
    );

    // ==== Arch RF ====
    register_file #(.DATA_WIDTH(64), .ADDR_WIDTH(5)) u_arf (
        .clk(clk), .rst_n(rst_n_ao),
        .we(rf_wr_en), .rd(rf_wr_addr), .wd(rf_wr_data),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_arch_rd)
    );

    // ==== L1i with MMU ====
    l1i_mmu u_l1i (
        .clk(clk), .rst_n(rst_n_pcu),
        .fetch_pc_va(pcu_pc),
        .fetch_instr(pcu_instr),
        .stall(pcu_fetch_stall),
        .flush(flush_tlb),
        .priv(dbg_priv), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .l2_req(l1i_l2_req), .l2_addr(l1i_l2_addr),
        .l2_data(l1i_l2_data), .l2_ready(l1i_l2_ready),
        .pte_req(l1i_pte_req), .pte_addr(l1i_pte_addr),
        .pte_rdata(l1i_pte_rdata), .pte_ready(l1i_pte_ready),
        .page_fault(l1i_page_fault),
        .fault_cause(l1i_fault_cause), .fault_va(l1i_fault_va)
    );

    // ==== L1d with MMU ====
    l1d_mmu u_l1d (
        .clk(clk), .rst_n(rst_n_pcu),
        .cpu_req(mc_req), .cpu_we(mc_we),
        .cpu_addr_va(mc_addr), .cpu_wdata(mc_wdata),
        .cpu_rdata(mc_rdata), .cpu_ready(mc_ready),
        .flush(flush_tlb),
        .priv(dbg_priv), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .l2_req(l1d_l2_req), .l2_we(l1d_l2_we),
        .l2_addr(l1d_l2_addr), .l2_wdata(l1d_l2_wdata),
        .l2_rdata(l1d_l2_rdata), .l2_ready(l1d_l2_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .pte_req(l1d_pte_req), .pte_addr(l1d_pte_addr),
        .pte_rdata(l1d_pte_rdata), .pte_ready(l1d_pte_ready),
        .page_fault(l1d_page_fault),
        .fault_cause(l1d_fault_cause), .fault_va(l1d_fault_va)
    );

    // ==== L2 (single port shared: p0 for L1i+PTE, p1 for L1d) ====
    // p0 arbiter: L1i lines OR PTE fetches (L1d PTE priority)
    wire p0_req_any = l1i_l2_req | pte_arb_req;
    wire p0_sel_pte = pte_arb_req;
    wire [63:0] p0_addr_mux = p0_sel_pte ? pte_arb_addr : l1i_l2_addr;
    wire p0_req_mux = p0_sel_pte ? pte_arb_req : l1i_l2_req;

    l2 u_l2 (
        .clk(clk), .rst_n(rst_n_pcu),
        .p0_req(p0_req_mux), .p0_addr(p0_addr_mux),
        .p0_rdata(l2_p0_rdata), .p0_ready(l2_p0_ready),
        .p1_req(l1d_l2_req), .p1_we(l1d_l2_we),
        .p1_addr(l1d_l2_addr), .p1_wdata({448'b0, l1d_l2_wdata[63:0]}),
        .p1_rdata(l2_p1_rdata), .p1_ready(l2_p1_ready),
        .mem_req(dram_req), .mem_we(dram_we),
        .mem_addr(dram_addr), .mem_wdata(dram_wdata),
        .mem_rdata(dram_rdata), .mem_ready(dram_ready)
    );

    assign l1i_l2_data  = l2_p0_rdata[255:0];
    assign l1i_l2_ready = (!p0_sel_pte) ? l2_p0_ready : 1'b0;
    assign l1d_l2_rdata = l2_p1_rdata;
    assign l1d_l2_ready = l2_p1_ready;

    assign dbg_pcu_pc = pcu_pc;
endmodule
