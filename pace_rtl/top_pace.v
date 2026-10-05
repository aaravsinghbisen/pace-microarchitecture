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
module top_pace (
    input  wire clk,
    input  wire rst_n_pcu,
    input  wire rst_n_ao,

    output wire [63:0] pcu_pc,
    input  wire [31:0] pcu_instr,
    output wire [63:0] ao_pc,
    input  wire [31:0] ao_instr,

    // Memory interface (M-Core -> L1d -> L2)
    output wire        mc_mem_req, mc_mem_we,
    output wire [63:0] mc_mem_addr, mc_mem_wdata,
    input  wire [63:0] mc_mem_rdata,
    input  wire        mc_mem_ready,

    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_arch_rd,
    output wire [63:0] dbg_pcu_rd,
    output wire [63:0] dbg_mc_rd
);

    // PCU signals
    wire        pcu_shdw_we, pcu_shdw_exc;
    wire [4:0]  pcu_shdw_rd;
    wire [63:0] pcu_shdw_data;
    wire        pcu_br_v, pcu_br_t;
    wire [63:0] pcu_br_tgt;
    wire        redir_v;
    wire [63:0] redir_pc;

    // M-Core signals
    wire        mc_shdw_we, mc_shdw_exc;
    wire [4:0]  mc_shdw_rd;
    wire [63:0] mc_shdw_data;
    wire        mc_busy;

    // Shadow RF signals
    wire        shdw_wr_ready, shdw_wr_full;
    wire [63:0] shdw_rd_data;
    wire        shdw_rd_valid, shdw_rd_en, shdw_rd_exc, shdw_rd_empty;

    // AO-Core signals
    wire [4:0]  rf_wr_addr;
    wire [63:0] rf_wr_data;
    wire        rf_wr_en;

    // Shadow RF write mux (only one writes per instruction)
    wire        shdw_we_final   = pcu_shdw_we | mc_shdw_we;
    wire [4:0]  shdw_rd_final   = mc_shdw_we ? mc_shdw_rd : pcu_shdw_rd;
    wire [63:0] shdw_data_final = mc_shdw_we ? mc_shdw_data : pcu_shdw_data;
    wire        shdw_exc_final  = 1'b0;

    // === PCU ===
    pcu u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .stall(mc_busy),
        .pc_out(pcu_pc), .instr_in(pcu_instr),
        .shadow_we(pcu_shdw_we), .shadow_rd(pcu_shdw_rd),
        .shadow_data(pcu_shdw_data), .shadow_exc(pcu_shdw_exc),
        .ext_wr_en(mc_shdw_we), .ext_wr_addr(mc_shdw_rd),
        .ext_wr_data(mc_shdw_data),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t), .br_target(pcu_br_tgt),
        .redirect_valid(redir_v), .redirect_pc(redir_pc),
        .dbg_result(dbg_pcu_rd)
    );

    // === M-Core ===
    m_core u_mc (
        .clk(clk), .rst_n(rst_n_pcu),
        .pc_out(), .instr_in(pcu_instr),   // ← shared PC (PCU's)
        .shadow_we(mc_shdw_we), .shadow_rd(mc_shdw_rd),
        .shadow_data(mc_shdw_data), .shadow_exc(mc_shdw_exc),
        .busy(mc_busy),
        .ext_wr_en(pcu_shdw_we), .ext_wr_addr(pcu_shdw_rd),
        .ext_wr_data(pcu_shdw_data),
        .mem_req(mc_mem_req), .mem_we(mc_mem_we),
        .mem_addr(mc_mem_addr), .mem_wdata(mc_mem_wdata),
        .mem_rdata(mc_mem_rdata), .mem_ready(mc_mem_ready),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_mc_rd)
    );

    // === Shadow RF ===
    shadow_rf #(.DEPTH(32), .DATA_WIDTH(64)) u_shadow (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(shdw_we_final), .wr_data(shdw_data_final),
        .wr_exception(shdw_exc_final),  // simplified
        .wr_ready(shdw_wr_ready), .wr_full(shdw_wr_full),
        .rd_en(shdw_rd_en), .rd_data(shdw_rd_data),
        .rd_exception(shdw_rd_exc), .rd_valid(shdw_rd_valid),
        .rd_empty(shdw_rd_empty)
    );

    // === B-Core ===
    b_core u_bc (
        .clk(clk), .rst_n(rst_n_pcu),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t),
        .br_target(pcu_br_tgt), .br_pc(pcu_pc),
        .redirect_valid(redir_v), .redirect_pc(redir_pc)
    );

    // === AO-Core ===
    ao_core_pace u_ao (
        .clk(clk), .rst_n(rst_n_ao),
        .pc_out(ao_pc), .instr_in(ao_instr),
        .shadow_rd_data(shdw_rd_data),
        .shadow_rd_valid(shdw_rd_valid),
        .shadow_rd_en(shdw_rd_en),
        .pcu_stalled(1'b0),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en)
    );

    // === Arch RF ===
    register_file #(.DATA_WIDTH(64), .ADDR_WIDTH(5)) u_arf (
        .clk(clk), .rst_n(rst_n_ao),
        .we(rf_wr_en), .rd(rf_wr_addr), .wd(rf_wr_data),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_arch_rd)
    );

endmodule
