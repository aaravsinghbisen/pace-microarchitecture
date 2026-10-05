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
module top_pace_full (
    input  wire clk,
    input  wire rst_n_in,
    // MMIO (uncached, para o SoC)
    output wire        mmio_req, mmio_we,
    output wire [63:0] mmio_addr, mmio_wdata,
    input  wire [63:0] mmio_rdata,
    input  wire        mmio_ready,
    // DRAM
    output wire        dram_req, dram_we,
    output wire [63:0] dram_addr,
    output wire [511:0] dram_wdata,
    input  wire [511:0] dram_rdata,
    input  wire        dram_ready,
    // Interrupts
    input  wire        i_mtip, i_msip, i_meip, i_seip, i_stip, i_ssip,
    // Debug
    output wire [63:0] dbg_pcu_pc,
    output wire [7:0]  dbg_vl,
    output wire [63:0] dbg_vtype,
    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_arch_rd,
    output wire [63:0] dbg_instr_count,
    output wire [31:0] dbg_ipc_x1000
);
    // ===== Boot =====
    wire rst_n_pcu, rst_n_ao, boot_done;
    boot_sequencer #(.SCOUT_AHEAD_CYCLES(64)) u_boot (
        .clk(clk), .rst_n(rst_n_in),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao), .boot_done(boot_done)
    );

    // ===== MMU config =====
    wire        satp_enable;
    wire [63:0] satp_w;
    wire [43:0] satp_ppn    = satp_w[43:0];
    wire [8:0]  asid        = satp_w[59:44];
    wire        flush_tlb;
    wire [1:0]  priv_mode;

    // ===== PCU 6-wide + vector =====
    wire [63:0] pcu_pc;
    wire [6*32-1:0] pcu_instr_bus;
    wire [31:0] pcu_instr_0 = pcu_instr_bus[31:0];   // lane 0 (para MC)
    wire        pcu_fetch_stall;
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
    wire        pcu_trap_taken;

    // Fetch 6 instruções: pega 192 bits da L1i (6 × 32 bits)
    wire [31:0]  l1i_instr_out;  // 1 instr/ciclo (simplificação atual)

    // ===== MC =====
    wire        mc_shdw_we, mc_shdw_exc;
    wire [4:0]  mc_shdw_rd;
    wire [63:0] mc_shdw_data;
    wire        mc_busy;
    wire        mc_req, mc_we;
    wire [63:0] mc_addr, mc_wdata, mc_rdata;
    wire        mc_ready;

    // ===== Shadow RF multi =====
    // 6 writes: 5 do PCU + 1 do MC (lane 5 é preterida se MC estiver ativo)
    wire [3:0]  shdw_wr_ready;
    wire        shdw_wr_full;
    wire [3:0]  shdw_wr_ready_v;
    wire [4*72-1:0] shdw_rd_data;
    wire [3:0]  shdw_rd_valid;
    wire        shdw_rd_empty;
    wire [9:0]  shdw_wr_ptr, shdw_rd_ptr;

    // Pack das 6 escritas do PCU (72 bits cada)
    wire [6*72-1:0] pcu_shdw_pack;
    genvar gk;
    generate
        for (gk = 0; gk < 6; gk = gk + 1) begin : g_pack
            assign pcu_shdw_pack[gk*72 +: 72] =
                {3'b0, pcu_shdw_rd[gk*5 +: 5], pcu_shdw_data[gk*64 +: 64]};
        end
    endgenerate

    // MC entra como 7ª escrita, ocupa lane 0 se ativo (prioridade)
    wire [5:0] final_wr_en = mc_shdw_we ? {pcu_shdw_we[5:1], 1'b1}
                                        : pcu_shdw_we;
    wire [6*72-1:0] final_wr_data = mc_shdw_we
        ? {pcu_shdw_pack[6*72-1:1*72], {3'b0, mc_shdw_rd, mc_shdw_data}}
        : pcu_shdw_pack;

    // ===== B-Core =====
    b_core u_bc (
        .clk(clk), .rst_n(rst_n_pcu),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t),
        .br_target(pcu_br_tgt), .br_pc(pcu_pc),
        .redirect_valid(redir_v), .redirect_pc(redir_pc)
    );

    // ===== 4 AO-Cores =====
    wire [3:0]  ao_rd_en;
    wire [3:0]  rf_we;
    wire [3*5-1:0] rf_rd;
    wire [4*64-1:0] rf_wd;

    ao_core_multi #(.N_AO(4)) u_ao (
        .clk(clk), .rst_n(rst_n_ao),
        .shdw_data(shdw_rd_data), .shdw_valid(shdw_rd_valid),
        .shdw_rd_en(ao_rd_en),
        .rf_we(rf_we), .rf_rd(rf_rd), .rf_wd(rf_wd)
    );

    // ===== Arch RF 4-port =====
    register_file_multi #(.N_WRITE(4)) u_arf (
        .clk(clk), .rst_n(rst_n_ao),
        .we(rf_we), .rd(rf_rd), .wd(rf_wd),
        .rs1(5'd0), .rs2(5'd0), .rd1(), .rd2(),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_arch_rd)
    );

    // ===== L1i com MMU =====
    wire        l1i_l2_req, l1i_l2_ready;
    wire [63:0] l1i_l2_addr;
    wire        l1i_pte_req, l1i_pte_ready;
    wire [63:0] l1i_pte_addr, l1i_pte_rdata;

    wire [255:0] l1i_l2_data_from_l2 = l2_p0_rdata[255:0];
    l1i_mmu u_l1i (
        .clk(clk), .rst_n(rst_n_pcu),
        .fetch_pc_va(fbuf_fetch_pc),
        .fetch_instr(l1i_instr_out),
        .stall(pcu_fetch_stall),
        .flush(flush_tlb), .priv(priv_mode), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .l2_req(l1i_l2_req), .l2_addr(l1i_l2_addr),
        .l2_data(l1i_l2_data_from_l2), .l2_ready(l1i_l2_ready),
        .pte_req(l1i_pte_req), .pte_addr(l1i_pte_addr),
        .pte_rdata(l1i_pte_rdata), .pte_ready(l1i_pte_ready),
        .page_fault(), .fault_cause(), .fault_va()
    );

    // Fetch buffer: acumula 6 instrs da L1i (1/ciclo), libera 6 pro PCU
    wire [6*32-1:0] fbuf_instrs;
    wire [63:0]     fbuf_pc;
    wire            fbuf_valid;
    wire [63:0]     fbuf_fetch_pc;
    wire            pcu_consume = !pcu_fetch_stall && !mc_busy;

    wire [2:0]  pcu_advance;
    wire        pcu_flush_fetch;
    wire [63:0] pcu_new_pc;

    fetch_buffer u_fbuf (
        .clk(clk), .rst_n(rst_n_pcu),
        .in_instr(l1i_instr_out), .in_valid(!pcu_fetch_stall),
        .flush(pcu_flush_fetch), .flush_pc(pcu_new_pc),
        .consume_count(pcu_advance),
        .out_instrs(fbuf_instrs), .out_pc(), .out_valid(fbuf_valid),
        .next_fetch_pc(fbuf_fetch_pc)
    );
    assign pcu_instr_bus = fbuf_instrs;

    // ===== L1d com MMU =====
    wire        l1d_l2_req, l1d_l2_we, l1d_l2_ready;
    wire [63:0] l1d_l2_addr, l1d_l2_wdata;
    wire [511:0] l1d_l2_rdata;
    wire        l1d_pte_req, l1d_pte_ready;
    wire [63:0] l1d_pte_addr, l1d_pte_rdata;

    l1d_mmu u_l1d (
        .clk(clk), .rst_n(rst_n_pcu),
        .cpu_req(mc_req), .cpu_we(mc_we),
        .cpu_addr_va(mc_addr), .cpu_wdata(mc_wdata),
        .cpu_rdata(mc_rdata), .cpu_ready(mc_ready),
        .flush(flush_tlb), .priv(priv_mode), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .l2_req(l1d_l2_req), .l2_we(l1d_l2_we),
        .l2_addr(l1d_l2_addr), .l2_wdata(l1d_l2_wdata),
        .l2_rdata(l1d_l2_rdata), .l2_ready(l1d_l2_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .pte_req(l1d_pte_req), .pte_addr(l1d_pte_addr),
        .pte_rdata(l1d_pte_rdata), .pte_ready(l1d_pte_ready),
        .page_fault(), .fault_cause(), .fault_va()
    );

    // ===== L2 (arbitragem simples: L1i + PTE têm prioridade) =====
    wire [511:0] l2_p0_rdata, l2_p1_rdata;
    wire        l2_p0_ready, l2_p1_ready;

    wire p0_sel_pte = l1d_pte_req | l1i_pte_req;
    wire [63:0] p0_addr = l1d_pte_req ? l1d_pte_addr :
                          l1i_pte_req ? l1i_pte_addr : l1i_l2_addr;

    l2 u_l2 (
        .clk(clk), .rst_n(rst_n_pcu),
        .p0_req(l1i_l2_req | p0_sel_pte),
        .p0_addr(p0_addr),
        .p0_rdata(l2_p0_rdata), .p0_ready(l2_p0_ready),
        .p1_req(l1d_l2_req), .p1_we(l1d_l2_we),
        .p1_addr(l1d_l2_addr), .p1_wdata({448'b0, l1d_l2_wdata[63:0]}),
        .p1_rdata(l2_p1_rdata), .p1_ready(l2_p1_ready),
        .mem_req(dram_req), .mem_we(dram_we),
        .mem_addr(dram_addr), .mem_wdata(dram_wdata),
        .mem_rdata(dram_rdata), .mem_ready(dram_ready)
    );

    assign l1i_l2_ready  = l1i_l2_req ? l2_p0_ready : 1'b0;
    assign l1i_pte_rdata = l1i_pte_req ? l2_p0_rdata[63:0] : 64'd0;
    assign l1i_pte_ready = l1i_pte_req ? l2_p0_ready : 1'b0;
    assign l1d_pte_rdata = l1d_pte_req ? l2_p0_rdata[63:0] : 64'd0;
    assign l1d_pte_ready = l1d_pte_req ? l2_p0_ready : 1'b0;
    assign l1d_l2_rdata  = l2_p1_rdata;
    assign l1d_l2_ready  = l2_p1_ready;

    // ===== Shadow RF multi-read (4 heads) =====
    shadow_rf_multi #(.DEPTH(32), .DATA_WIDTH(72), .N_READ(4), .N_WRITE(6)) u_shdw (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(final_wr_en), .wr_data(final_wr_data),
        .wr_exception(6'b0),
        .wr_ready(shdw_wr_ready_v), .wr_full(shdw_wr_full),
        .rd_en(ao_rd_en), .rd_data(shdw_rd_data),
        .rd_valid(shdw_rd_valid), .rd_empty(shdw_rd_empty),
        .dbg_wr_ptr(shdw_wr_ptr), .dbg_rd_ptr(shdw_rd_ptr)
    );
    assign shdw_wr_ready = shdw_wr_ready_v[3:0];

    // ===== PCU 6-wide =====
    pcu6_v u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .stall(mc_busy), .fetch_stall(pcu_fetch_stall),
        .shdw_wr_ready(shdw_wr_ready),
        .instr_count(fbuf_valid ? 4'd6 : 4'd1),
        .instr_in(pcu_instr_bus),
        .pc_out(pcu_pc),
        .shadow_we(pcu_shdw_we), .shadow_rd(pcu_shdw_rd),
        .shadow_data(pcu_shdw_data), .num_writes(pcu_num_writes),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t), .br_target(pcu_br_tgt),
        .redirect_valid(redir_v), .redirect_pc(redir_pc),
        .ext_wr_en(mc_shdw_we), .ext_wr_addr(mc_shdw_rd), .ext_wr_data(mc_shdw_data),
        .dbg_priv(priv_mode),
        .dbg_satp(satp_w),
        .dbg_satp_enable(satp_enable),
        .dbg_flush_tlb(flush_tlb),
        .dbg_trap_taken(pcu_trap_taken),
        .dbg_advance(pcu_advance),
        .dbg_flush_fetch(pcu_flush_fetch),
        .dbg_new_pc(pcu_new_pc),
        .i_mtip(i_mtip), .i_msip(i_msip), .i_meip(i_meip),
        .i_seip(i_seip), .i_stip(i_stip), .i_ssip(i_ssip),
        .dbg_vl(pcu_vl), .dbg_vtype(pcu_vtype),
        .dbg_vrs(5'd0), .dbg_vrd()
    );

    // ===== MC =====
    m_core u_mc (
        .clk(clk), .rst_n(rst_n_pcu),
        .pcu_valid(1'b1), .instr_in(pcu_instr_0),
        .shdw_wr_ready(shdw_wr_ready[0]),
        .stall_pcu(mc_busy),
        .shadow_we(mc_shdw_we), .shadow_rd(mc_shdw_rd),
        .shadow_data(mc_shdw_data), .shadow_exc(mc_shdw_exc),
        .ext_wr_en(1'b0), .ext_wr_addr(5'd0), .ext_wr_data(64'd0),
        .mem_req(mc_req), .mem_we(mc_we),
        .mem_addr(mc_addr), .mem_wdata(mc_wdata),
        .mem_rdata(mc_rdata), .mem_ready(mc_ready),
        .dbg_rs(5'd0), .dbg_rd()
    );

    // ===== Perf counters =====
    perf_counters u_perf (
        .clk(clk), .rst_n(rst_n_ao), .enable(boot_done),
        .commit_en(rf_we != 0),
        .shdw_wr_en(|final_wr_en), .shdw_rd_en(1'b1),
        .shdw_empty(shdw_rd_empty), .shdw_full(shdw_wr_full),
        .shdw_count({2'b0, shdw_wr_ptr[3:0]} - {2'b0, shdw_rd_ptr[3:0]}),
        .sb_push(1'b0), .sb_hit(1'b0), .sb_miss(1'b0),
        .l1i_hit(1'b0), .l1i_miss(1'b0),
        .l1d_hit(1'b0), .l1d_miss(1'b0),
        .l2_hit(1'b0), .l2_miss(1'b0),
        .tlb_l1_hit(1'b0), .tlb_l1_miss(1'b0),
        .tlb_l2_hit(1'b0), .tlb_l2_miss(1'b0),
        .runahead_active(1'b0), .runahead_enter(1'b0), .runahead_exit(1'b0),
        .cycles(), .instr_retired(dbg_instr_count),
        .shdw_writes(), .shdw_reads(), .shdw_stall_cycles(),
        .sb_pushes(), .sb_forward_hits(),
        .l1i_hit_cnt(), .l1i_miss_cnt(),
        .l1d_hit_cnt(), .l1d_miss_cnt(),
        .l2_hit_cnt(), .l2_miss_cnt(),
        .tlb_l1_hit_cnt(), .tlb_l1_miss_cnt(),
        .tlb_l2_hit_cnt(), .tlb_l2_miss_cnt(),
        .runahead_cycles(), .runahead_entries(),
        .ipc_x1000(dbg_ipc_x1000),
        .l1d_hit_rate_x1000(), .l1i_hit_rate_x1000()
    );

    // Debug
    assign dbg_pcu_pc = pcu_pc;
    assign dbg_vl     = pcu_vl;
    assign dbg_vtype  = pcu_vtype;

    // Interrupts (não usados por enquanto no top — hook futura)
endmodule
