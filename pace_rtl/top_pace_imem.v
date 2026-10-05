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
module top_pace_imem #(parameter HART_ID = 0) (
    input  wire clk, rst_n,
    // IMem: 6 instr/ciclo, endereço alinhado com pcu_pc
    output wire [63:0] imem_pc,
    input  wire [6*32-1:0] imem_instr,
    // DMem: word-level (MC saída)
    output wire        dmem_req, dmem_we,
    output wire [63:0] dmem_addr, dmem_wdata,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_ready,
    // Vector memory port (vle.v/vse.v) — same DMem, no MMU for now
    output wire        vmem_req, vmem_we,
    output wire [63:0] vmem_addr, vmem_wdata,
    input  wire [63:0] vmem_rdata,
    input  wire        vmem_ready,
    // PTE memory (Sv39 page table walker)
    output wire        pte_req,
    output wire [63:0] pte_addr,
    input  wire [63:0] pte_rdata,
    input  wire        pte_ready,
    // Page fault status
    output wire        dmmu_page_fault,
    output wire [63:0] dmmu_fault_cause, dmmu_fault_va,
    // MMIO
    output wire        mmio_req, mmio_we,
    output wire [63:0] mmio_addr, mmio_wdata,
    input  wire [63:0] mmio_rdata,
    input  wire        mmio_ready,
    // Interrupts
    input  wire        i_mtip, i_msip, i_meip, i_seip, i_stip, i_ssip,
    // Debug
    input  wire [3:0]  i_instr_count,   // 1 = single-issue, 6 = 6-wide
    // Extension port (AMO/LR/SC)
    output wire        amo_ext_req,
    output wire [2:0]  amo_ext_op,
    output wire [2:0]  amo_ext_funct3,
    output wire [4:0]  amo_ext_funct5,
    output wire [63:0] amo_ext_addr,
    output wire [63:0] amo_ext_rs2,
    output wire [4:0]  amo_ext_rd,
    input  wire        amo_ext_ack,
    input  wire [63:0] amo_ext_result,
    // ===== Runahead extension ports =====
    input  wire        rh_discard,        // 1 = PCU executes but discards shadow writes
    output wire        rh_stall_long,     // 1 = long stall detected (consumer feeds to runahead_ctrl)
    output wire        rh_stall_cleared,  // 1 = stall resolved
    output wire        rh_sb_full,        // 1 = store buffer / mem queue full
    // ===== Debug =====
    input  wire [4:0]  dbg_rs,
    output wire [63:0] dbg_arch_rd,
    output wire [63:0] dbg_pcu_pc,
    output wire [63:0] dbg_satp,
    output wire        dbg_satp_en
);
    // Boot
    wire rst_n_pcu, rst_n_ao, boot_done;
    boot_sequencer #(.SCOUT_AHEAD_CYCLES(16)) u_boot (
        .clk(clk), .rst_n(rst_n),
        .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao), .boot_done(boot_done)
    );

    // PCU I/O
    wire [63:0] pcu_pc;
    wire [5:0]  pcu_shdw_we;
    wire [6*5-1:0] pcu_shdw_rd;
    wire [6*64-1:0] pcu_shdw_data;
    wire        pcu_br_v, pcu_br_t;
    wire [63:0] pcu_br_tgt;
    wire        redir_v;
    wire [63:0] redir_pc;
    wire [7:0]  pcu_vl;
    wire [63:0] pcu_vtype;
    wire [1:0]  priv_mode;
    wire [63:0] satp_w;
    wire        satp_en_w;
    wire        flush_tlb;
    wire        trap_taken_w;
    wire [2:0]  adv;
    wire        flush_fetch;
    wire [63:0] new_pc;

    // Memory queue: PCU -> MC
    wire        mq_push_en, mq_full;
    wire [2:0]  mq_push_op;
    wire [63:0] mq_push_addr, mq_push_rs2;
    wire [4:0]  mq_push_rd, mq_push_amo_f5;
    wire [2:0]  mq_push_funct3;
    wire        mq_pop_en, mq_pop_valid;
    wire [2:0]  mq_op;
    wire [63:0] mq_addr, mq_rs2;
    wire [4:0]  mq_rd, mq_amo_f5;
    wire [2:0]  mq_funct3;

    mem_queue #(.DEPTH(8)) u_mq (
        .clk(clk), .rst_n(rst_n_pcu),
        .push_en(mq_push_en), .push_op(mq_push_op),
        .push_addr(mq_push_addr), .push_rs2(mq_push_rs2),
        .push_rd(mq_push_rd), .push_funct3(mq_push_funct3),
        .push_amo_f5(mq_push_amo_f5),
        .push_ready(), .full(mq_full),
        .pop_en(mq_pop_en),
        .pop_op(mq_op), .pop_addr(mq_addr), .pop_rs2(mq_rs2),
        .pop_rd(mq_rd), .pop_funct3(mq_funct3), .pop_amo_f5(mq_amo_f5),
        .pop_valid(mq_pop_valid)
    );

    // MC interface
    wire        mc_shdw_we, mc_shdw_exc;
    wire [4:0]  mc_shdw_rd;
    wire [63:0] mc_shdw_data;
    wire        mc_busy;
    wire        mc_req, mc_we;
    wire [63:0] mc_addr, mc_wdata, mc_rdata;
    wire        mc_ready;


    // ===== RVC decompress: 6 lanes em paralelo =====
    wire [5:0]        rvc_is_c;
    wire [6*32-1:0]   rvc_decompressed;
    wire [6*32-1:0]   imem_instr_eff;

    genvar grvc;
    generate
        for (grvc = 0; grvc < 6; grvc = grvc + 1) begin : g_rvc
            rvc_decompress u_rvc (
                .instr16(imem_instr[grvc*32 +: 16]),
                .instr32(rvc_decompressed[grvc*32 +: 32]),
                .is_compressed(rvc_is_c[grvc]),
                .illegal()
            );
        end
    endgenerate

    generate
        for (grvc = 0; grvc < 6; grvc = grvc + 1) begin : g_mux_rvc
            assign imem_instr_eff[grvc*32 +: 32] = rvc_is_c[grvc] ?
                                                    rvc_decompressed[grvc*32 +: 32] :
                                                    imem_instr[grvc*32 +: 32];
        end
    endgenerate

    pcu6_v #(.HART_ID(HART_ID)) u_pcu (
        .clk(clk), .rst_n(rst_n_pcu),
        .stall(mc_busy), .fetch_stall(1'b0), .shdw_wr_ready(4'd6),
        .instr_count(i_instr_count),
        .instr_in(imem_instr_eff),
        .pc_out(pcu_pc),
        .shadow_we(pcu_shdw_we), .shadow_rd(pcu_shdw_rd),
        .shadow_data(pcu_shdw_data), .num_writes(),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t), .br_target(pcu_br_tgt),
        .redirect_valid(redir_v), .redirect_pc(redir_pc),
        .ext_wr_en(mc_ext_wr_en), .ext_wr_addr(mc_ext_wr_addr), .ext_wr_data(mc_ext_wr_data),
        .dbg_priv(priv_mode),
        .dbg_satp(satp_w), .dbg_satp_enable(satp_en_w),
        .dbg_flush_tlb(flush_tlb), .dbg_trap_taken(trap_taken_w),
        .mq_push_en(mq_push_en), .mq_push_op(mq_push_op),
        .mq_push_addr(mq_push_addr), .mq_push_rs2(mq_push_rs2),
        .mq_push_rd(mq_push_rd), .mq_push_funct3(mq_push_funct3),
        .mq_push_amo_f5(mq_push_amo_f5), .mq_full(mq_full),
        .vmem_req(vmem_req), .vmem_we(vmem_we),
        .vmem_addr(vmem_addr), .vmem_wdata(vmem_wdata),
        .vmem_rdata(vmem_rdata), .vmem_ready(vmem_ready),
        .dbg_advance(adv), .dbg_flush_fetch(flush_fetch), .dbg_new_pc(new_pc),
        .rh_discard(rh_discard),
        .i_mtip(i_mtip), .i_msip(i_msip), .i_meip(i_meip),
        .i_seip(i_seip), .i_stip(i_stip), .i_ssip(i_ssip),
        .dbg_vl(pcu_vl), .dbg_vtype(pcu_vtype),
        .dbg_vrs(5'd0), .dbg_vrd()
    );
    assign imem_pc = pcu_pc;
    assign dbg_pcu_pc = pcu_pc;
    assign dbg_satp = satp_w;
    assign dbg_satp_en = satp_en_w;

    // B-Core
    b_core u_bc (
        .clk(clk), .rst_n(rst_n_pcu),
        .br_valid(pcu_br_v), .br_taken(pcu_br_t),
        .br_target(pcu_br_tgt), .br_pc(pcu_pc),
        .redirect_valid(redir_v), .redirect_pc(redir_pc)
    );

    // Shadow RF multi (mescla PCU 6 + MC 1)
    wire        shdw_wr_full;
    wire [3:0]  shdw_wr_ready;
    wire [4*72-1:0] shdw_rd_data;
    wire [3:0]  shdw_rd_valid;
    wire        shdw_rd_empty;
    wire [9:0]  shdw_wr_ptr, shdw_rd_ptr;

    wire [6*72-1:0] pcu_shdw_pack;
    genvar gk;
    generate
        for (gk = 0; gk < 6; gk = gk + 1) begin : g_pack
            assign pcu_shdw_pack[gk*72 +: 72] =
                {3'b0, pcu_shdw_rd[gk*5 +: 5], pcu_shdw_data[gk*64 +: 64]};
        end
    endgenerate

    // PCU injeta ext_wr do MC nas lanes dele
    wire [5:0] final_wr_en = pcu_shdw_we;
    wire [6*72-1:0] final_wr_data = pcu_shdw_pack;

    wire [3:0] ao_rd_en;

    shadow_rf_multi #(.DEPTH(32), .DATA_WIDTH(72), .N_READ(4), .N_WRITE(6)) u_shdw (
        .clk(clk), .rst_n(rst_n_pcu),
        .wr_en(final_wr_en), .wr_data(final_wr_data),
        .wr_exception(6'b0),
        .wr_ready(shdw_wr_ready), .wr_full(shdw_wr_full),
        .rd_en(ao_rd_en), .rd_data(shdw_rd_data),
        .rd_valid(shdw_rd_valid), .rd_empty(shdw_rd_empty),
        .dbg_wr_ptr(shdw_wr_ptr), .dbg_rd_ptr(shdw_rd_ptr)
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

    // MC
    wire mc_ext_wr_en;
    wire [4:0] mc_ext_wr_addr;
    wire [63:0] mc_ext_wr_data;

    m_core u_mc (
        .clk(clk), .rst_n(rst_n_pcu),
        .mq_full(mq_full), .mq_pop_valid(mq_pop_valid), .mq_pop_en(mq_pop_en),
        .mq_op(mq_op), .mq_addr(mq_addr), .mq_rs2(mq_rs2),
        .mq_rd(mq_rd), .mq_funct3(mq_funct3), .mq_amo_f5(mq_amo_f5),
        .shadow_we(mc_shdw_we), .shadow_rd(mc_shdw_rd),
        .shadow_data(mc_shdw_data), .shadow_exc(mc_shdw_exc),
        .ext_wr_en(mc_ext_wr_en), .ext_wr_addr(mc_ext_wr_addr),
        .ext_wr_data(mc_ext_wr_data),
        .mem_req(mc_req), .mem_we(mc_we),
        .mem_addr(mc_addr), .mem_wdata(mc_wdata),
        .mem_rdata(mc_rdata), .mem_ready(mc_ready),
        .dbg_rs(5'd0), .dbg_rd(),
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
    assign mc_busy = 1'b0;   // MC não pede stall pro PCU

    // DMem via MMU wrapper (VA → PA)
    dmem_mmu_wrap u_dmmu (
        .clk(clk), .rst_n(rst_n_pcu),
        .mc_req(mc_req), .mc_we(mc_we),
        .mc_addr_va(mc_addr), .mc_wdata(mc_wdata),
        .mc_rdata(mc_rdata), .mc_ready(mc_ready),
        .mc_page_fault(dmmu_page_fault),
        .mc_fault_cause(dmmu_fault_cause), .mc_fault_va(dmmu_fault_va),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .flush_tlb(flush_tlb), .priv(priv_mode), .asid(9'd0),
        .satp_ppn(satp_w[43:0]), .satp_enable(satp_en_w),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready)
    );

    // MMIO: não usado neste top (MC só acessa DRAM)
    assign mmio_req   = 1'b0;
    assign mmio_we    = 1'b0;
    assign mmio_addr  = 64'd0;
    assign mmio_wdata = 64'd0;

    // ===== Runahead stall detector =====
    reg [7:0] rh_stall_cnt;
    always @(posedge clk or negedge rst_n_pcu) begin
        if (!rst_n_pcu) rh_stall_cnt <= 8'd0;
        else if (mc_busy) begin
            if (rh_stall_cnt != 8'hFF) rh_stall_cnt <= rh_stall_cnt + 1'b1;
        end else rh_stall_cnt <= 8'd0;
    end

    assign rh_stall_long    = (rh_stall_cnt >= 8'd32);
    assign rh_stall_cleared = !mc_busy;
    assign rh_sb_full       = mq_full;

endmodule
