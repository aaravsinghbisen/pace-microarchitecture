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
// Top minimalista: PCU 6-wide + Shadow multi + 4 AO + IMem combinacional
module top_simple (
    input  wire clk,
    input  wire rst_n,
    // IMem combinacional (gerenciado pelo testbench)
    output wire [63:0] imem_addr,
    input  wire [31:0] imem_rdata,
    // Debug
    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_arch_rd,
    output wire [63:0] dbg_pcu_pc
);
    // Boot seq: 5 reset + scout-ahead (10 ciclos só pra testar)
    wire rst_n_pcu, rst_n_ao, boot_done;
    boot_sequencer #(.SCOUT_AHEAD_CYCLES(16)) u_boot (
        .clk(clk), .rst_n(rst_n),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao), .boot_done(boot_done)
    );

    // PCU 6-wide
    wire [63:0] pcu_pc;
    wire [5:0]  pcu_shdw_we;
    wire [6*5-1:0] pcu_shdw_rd;
    wire [6*64-1:0] pcu_shdw_data;
    wire [5:0]  pcu_num_writes;
    wire        pcu_br_v, pcu_br_t;
    wire [63:0] pcu_br_tgt;
    wire        redir_v;
    wire [63:0] redir_pc;
    wire [7:0]  pcu_vl;
    wire [63:0] pcu_vtype;

    // Só lane 0 ativa, resto NOP
    localparam NOP32 = 32'h00000013;
    wire [6*32-1:0] pcu_instr_bus = {{5{NOP32}}, imem_rdata};

    // Shadow RF multi
    wire        shdw_wr_full;
    wire [3:0]  shdw_wr_ready;
    wire [4*72-1:0] shdw_rd_data;
    wire [3:0]  shdw_rd_valid;
    wire        shdw_rd_empty;
    wire [9:0]  shdw_wr_ptr, shdw_rd_ptr;

    // Pack das 6 escritas
    wire [6*72-1:0] pcu_shdw_pack;
    genvar gk;
    generate
        for (gk = 0; gk < 6; gk = gk + 1) begin : g_pack
            assign pcu_shdw_pack[gk*72 +: 72] =
                {3'b0, pcu_shdw_rd[gk*5 +: 5], pcu_shdw_data[gk*64 +: 64]};
        end
    endgenerate

    // AO rd_en
    wire [3:0] ao_rd_en;

    shadow_rf_multi #(.DEPTH(32), .DATA_WIDTH(72), .N_READ(4), .N_WRITE(6)) u_shdw (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(pcu_shdw_we), .wr_data(pcu_shdw_pack),
        .wr_exception(6'b0),
        .wr_ready(shdw_wr_ready), .wr_full(shdw_wr_full),
        .rd_en(ao_rd_en), .rd_data(shdw_rd_data),
        .rd_valid(shdw_rd_valid), .rd_empty(shdw_rd_empty),
        .dbg_wr_ptr(shdw_wr_ptr), .dbg_rd_ptr(shdw_rd_ptr)
    );

    // B-Core
    wire redir_v_unused;
    b_core u_bc (
        .clk(clk), .rst_n(rst_n_pcu),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t),
        .br_target(pcu_br_tgt), .br_pc(pcu_pc),
        .redirect_valid(redir_v), .redirect_pc(redir_pc)
    );

    // AO + Arch RF
    wire [3:0]  rf_we;
    wire [4*5-1:0]  rf_rd;
    wire [4*64-1:0] rf_wd;

    ao_core_multi #(.N_AO(4)) u_ao (
        .clk(clk), .rst_n(rst_n_ao),
        .shdw_data(shdw_rd_data), .shdw_valid(shdw_rd_valid),
        .shdw_rd_en(ao_rd_en),
        .rf_we(rf_we), .rf_rd(rf_rd), .rf_wd(rf_wd)
    );

    register_file_multi #(.N_WRITE(4)) u_arf (
        .clk(clk), .rst_n(rst_n_ao),
        .we(rf_we), .rd(rf_rd), .wd(rf_wd),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_arch_rd)
    );

    // PCU 6-wide
    pcu6_v u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .stall(1'b0), .fetch_stall(1'b0),
        .shdw_wr_ready(shdw_wr_ready),
        .instr_in(pcu_instr_bus),
        .pc_out(pcu_pc),
        .shadow_we(pcu_shdw_we), .shadow_rd(pcu_shdw_rd),
        .shadow_data(pcu_shdw_data), .num_writes(pcu_num_writes),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t), .br_target(pcu_br_tgt),
        .redirect_valid(redir_v), .redirect_pc(redir_pc),
        .ext_wr_en(1'b0), .ext_wr_addr(5'd0), .ext_wr_data(64'd0),
        .dbg_priv(),
        .dbg_vl(pcu_vl), .dbg_vtype(pcu_vtype)
    );

    assign imem_addr = pcu_pc;
    assign dbg_pcu_pc = pcu_pc;
endmodule
