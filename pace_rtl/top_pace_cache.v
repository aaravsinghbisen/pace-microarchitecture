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
module top_pace_cache (
    input  wire clk, rst_n_pcu, rst_n_ao,
    output wire [63:0] dbg_pcu_pc, dbg_ao_pc,
    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_arch_rd,
    output wire        dram_req, dram_we,
    output wire [63:0] dram_addr,
    output wire [511:0] dram_wdata,
    input  wire [511:0] dram_rdata,
    input  wire        dram_ready,
    // MMIO port (uncached, para o SoC)
    output wire        mmio_req,
    output wire        mmio_we,
    output wire [63:0] mmio_addr,
    output wire [63:0] mmio_wdata,
    input  wire [63:0] mmio_rdata,
    input  wire        mmio_ready,
    output wire [5:0]  dbg_shdw_wr_ptr,
    output wire [5:0]  dbg_shdw_rd_ptr,
    output wire        dbg_shdw_empty, dbg_shdw_full,
    output wire        dbg_pcu_shdw_we, dbg_mc_shdw_we,
    output wire [4:0]  dbg_pcu_shdw_rd, dbg_mc_shdw_rd,
    output wire [63:0] dbg_pcu_shdw_data, dbg_mc_shdw_data,
    output wire        dbg_rf_wr_en, dbg_redir_v
);
    assign dbg_ao_pc = 64'd0;

    wire [63:0] pcu_pc;
    wire [31:0] pcu_instr;
    wire        pcu_stall_i;
    wire        pcu_l2_req;
    wire [63:0] pcu_l2_addr;
    wire [255:0] pcu_l2_data;
    wire        pcu_l2_ready;

    wire        mc_req, mc_we;
    wire [63:0] mc_addr, mc_wdata, mc_rdata;
    wire        mc_ready;
    wire        l1d_l2_req, l1d_l2_we;
    wire [63:0] l1d_l2_addr, l1d_l2_wdata;
    wire [511:0] l1d_l2_rdata;
    wire        l1d_l2_ready;

    wire [511:0] l2_p0_rdata, l2_p1_rdata;
    wire        l2_p0_ready, l2_p1_ready;

    l1i u_l1i_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .fetch_pc(pcu_pc), .fetch_instr(pcu_instr), .stall(pcu_stall_i),
        .l2_req(pcu_l2_req), .l2_addr(pcu_l2_addr),
        .l2_data(pcu_l2_data), .l2_ready(pcu_l2_ready)
    );

    wire        pcu_shdw_we, pcu_shdw_exc, mc_shdw_we, mc_shdw_exc;
    wire [4:0]  pcu_shdw_rd, mc_shdw_rd;
    wire [63:0] pcu_shdw_data, mc_shdw_data;
    wire        mc_busy;

    wire        pcu_valid;
    wire        pcu_br_v, pcu_br_t;
    wire [63:0] pcu_br_tgt;
    wire        redir_v;
    wire [63:0] redir_pc;

    wire        shdw_wr_ready, shdw_wr_full;
    wire [71:0] shdw_rd_data;
    wire        shdw_rd_valid, shdw_rd_en, shdw_rd_exc, shdw_rd_empty;
    wire [5:0]  shdw_wr_ptr_w, shdw_rd_ptr_w;

    wire        shdw_we_final = pcu_shdw_we | mc_shdw_we;
    wire [4:0]  shdw_rd_final = mc_shdw_we ? mc_shdw_rd : pcu_shdw_rd;
    wire [63:0] shdw_data_final = mc_shdw_we ? mc_shdw_data : pcu_shdw_data;
    wire [71:0] shdw_pack = {3'b0, shdw_rd_final, shdw_data_final};

    wire [4:0]  rf_wr_addr;
    wire [63:0] rf_wr_data;
    wire        rf_wr_en;

    wire        i_mtip_w = 1'b0, i_msip_w = 1'b0, i_meip_w = 1'b0;
    wire        i_seip_w = 1'b0, i_stip_w = 1'b0, i_ssip_w = 1'b0;
    wire [1:0]  dbg_priv_w;

    pcu u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .stall(mc_busy), .fetch_stall(pcu_stall_i),
        .shdw_wr_ready(shdw_wr_ready),
        .pcu_valid(pcu_valid),
        .pc_out(pcu_pc), .instr_in(pcu_instr),
        .shadow_we(pcu_shdw_we), .shadow_rd(pcu_shdw_rd),
        .shadow_data(pcu_shdw_data), .shadow_exc(pcu_shdw_exc),
        .ext_wr_en(mc_shdw_we), .ext_wr_addr(mc_shdw_rd), .ext_wr_data(mc_shdw_data),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t), .br_target(pcu_br_tgt),
        .redirect_valid(redir_v), .redirect_pc(redir_pc),
        .i_mtip(i_mtip_w), .i_msip(i_msip_w), .i_meip(i_meip_w),
        .i_seip(i_seip_w), .i_stip(i_stip_w), .i_ssip(i_ssip_w),
        .dbg_priv(dbg_priv_w),
        .dbg_result()
    );

    m_core u_mc (
        .clk(clk), .rst_n(rst_n_pcu),
        .pcu_valid(pcu_valid),
        .instr_in(pcu_instr),
        .shdw_wr_ready(shdw_wr_ready),
        .stall_pcu(mc_busy),
        .shadow_we(mc_shdw_we), .shadow_rd(mc_shdw_rd),
        .shadow_data(mc_shdw_data), .shadow_exc(mc_shdw_exc),
        .ext_wr_en(pcu_shdw_we), .ext_wr_addr(pcu_shdw_rd), .ext_wr_data(pcu_shdw_data),
        .mem_req(mc_req), .mem_we(mc_we),
        .mem_addr(mc_addr), .mem_wdata(mc_wdata),
        .mem_rdata(mc_rdata), .mem_ready(mc_ready),
        .dbg_rs(5'd0), .dbg_rd()
    );

    shadow_rf #(.DEPTH(32), .DATA_WIDTH(72)) u_shadow (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(shdw_we_final), .wr_data(shdw_pack), .wr_exception(1'b0),
        .wr_ready(shdw_wr_ready), .wr_full(shdw_wr_full),
        .rd_en(shdw_rd_en), .rd_data(shdw_rd_data),
        .rd_exception(shdw_rd_exc), .rd_valid(shdw_rd_valid),
        .rd_empty(shdw_rd_empty),
        .dbg_wr_ptr(shdw_wr_ptr_w), .dbg_rd_ptr(shdw_rd_ptr_w)
    );

    b_core u_bc (
        .clk(clk), .rst_n(rst_n_pcu),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t),
        .br_target(pcu_br_tgt), .br_pc(pcu_pc),
        .redirect_valid(redir_v), .redirect_pc(redir_pc)
    );

    ao_core_fifo u_ao (
        .clk(clk), .rst_n(rst_n_ao),
        .shdw_data(shdw_rd_data), .shdw_valid(shdw_rd_valid),
        .shdw_rd_en(shdw_rd_en),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en)
    );

    register_file #(.DATA_WIDTH(64), .ADDR_WIDTH(5)) u_arf (
        .clk(clk), .rst_n(rst_n_ao),
        .we(rf_wr_en), .rd(rf_wr_addr), .wd(rf_wr_data),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_arch_rd)
    );

    assign dbg_pcu_pc = pcu_pc;

    l1d u_l1d (
        .clk(clk), .rst_n(rst_n_pcu),
        .cpu_req(mc_req), .cpu_we(mc_we),
        .cpu_addr(mc_addr), .cpu_wdata(mc_wdata),
        .cpu_rdata(mc_rdata), .cpu_ready(mc_ready),
        .l2_req(l1d_l2_req), .l2_we(l1d_l2_we),
        .l2_addr(l1d_l2_addr), .l2_wdata(l1d_l2_wdata),
        .l2_rdata(l1d_l2_rdata), .l2_ready(l1d_l2_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .snp_valid(1'b0), .snp_we(1'b0), .snp_addr(64'd0), .snp_wdata(64'd0)
    );

    l2 u_l2 (
        .clk(clk), .rst_n(rst_n_pcu),
        .p0_req(pcu_l2_req), .p0_addr(pcu_l2_addr),
        .p0_rdata(l2_p0_rdata), .p0_ready(l2_p0_ready),
        .p1_req(l1d_l2_req), .p1_we(l1d_l2_we),
        .p1_addr(l1d_l2_addr), .p1_wdata({448'b0, l1d_l2_wdata[63:0]}),
        .p1_rdata(l2_p1_rdata), .p1_ready(l2_p1_ready),
        .mem_req(dram_req), .mem_we(dram_we),
        .mem_addr(dram_addr), .mem_wdata(dram_wdata),
        .mem_rdata(dram_rdata), .mem_ready(dram_ready)
    );

    assign pcu_l2_data  = l2_p0_rdata[255:0];
    assign pcu_l2_ready = l2_p0_ready;
    assign l1d_l2_rdata = l2_p1_rdata;
    assign l1d_l2_ready = l2_p1_ready;

    assign dbg_shdw_wr_ptr    = shdw_wr_ptr_w;
    assign dbg_shdw_rd_ptr    = shdw_rd_ptr_w;
    assign dbg_shdw_empty     = shdw_rd_empty;
    assign dbg_shdw_full      = shdw_wr_full;
    assign dbg_pcu_shdw_we    = pcu_shdw_we;
    assign dbg_mc_shdw_we     = mc_shdw_we;
    assign dbg_pcu_shdw_rd    = pcu_shdw_rd;
    assign dbg_mc_shdw_rd     = mc_shdw_rd;
    assign dbg_pcu_shdw_data  = pcu_shdw_data;
    assign dbg_mc_shdw_data   = mc_shdw_data;
    assign dbg_rf_wr_en       = rf_wr_en;
    assign dbg_redir_v        = redir_v;
endmodule
