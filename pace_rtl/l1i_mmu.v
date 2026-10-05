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
// L1i com MMU Sv39 pré-instalada. Endereço de entrada é VIRTUAL.
module l1i_mmu #(
    parameter ADDR_W=64, parameter INSTR_W=32,
    parameter SETS=128, parameter WAYS=4, parameter LINE_INSTR=8
)(
    input  wire clk, rst_n,
    input  wire [ADDR_W-1:0] fetch_pc_va,
    output wire [INSTR_W-1:0] fetch_instr,
    output wire stall,             // freeze PCU (miss OR translation pending)
    // MMU config
    input  wire flush,
    input  wire [1:0] priv,
    input  wire [8:0] asid,
    input  wire [43:0] satp_ppn,
    input  wire satp_enable,
    // L2 (para linhas de instrução)
    output wire        l2_req,
    output wire [ADDR_W-1:0] l2_addr,
    input  wire [LINE_INSTR*INSTR_W-1:0] l2_data,
    input  wire        l2_ready,
    // PTE memory (vai pro top, roteado pra DRAM)
    output wire        pte_req,
    output wire [ADDR_W-1:0] pte_addr,
    input  wire [63:0] pte_rdata,
    input  wire        pte_ready,
    // Page fault
    output wire        page_fault,
    output wire [63:0] fault_cause,
    output wire [63:0] fault_va
);

    wire [63:0] phys_pc;
    wire        mdone, mfault;
    wire [63:0] mc, mva;

    // MMU req: pede tradução sempre que há um fetch
    wire mmu_req = 1'b1;

    mmu_sv39 u_mmu (
        .clk(clk), .rst_n(rst_n),
        .flush(flush),
        .req(mmu_req),
        .va(fetch_pc_va), .priv(priv),
        .is_fetch(1'b1), .is_store(1'b0), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .done(mdone), .fault(mfault),
        .fault_cause(mc), .fault_va(mva), .pa(phys_pc)
    );

    assign page_fault = mfault;
    assign fault_cause = mc;
    assign fault_va = mva;

    wire stall_l1i;

    l1i #(.ADDR_W(ADDR_W), .INSTR_W(INSTR_W), .SETS(SETS), .WAYS(WAYS), .LINE_INSTR(LINE_INSTR))
    u_l1i (
        .clk(clk), .rst_n(rst_n),
        .fetch_pc(satp_enable ? phys_pc : fetch_pc_va),
        .fetch_instr(fetch_instr),
        .stall(stall_l1i),
        .l2_req(l2_req), .l2_addr(l2_addr),
        .l2_data(l2_data), .l2_ready(l2_ready)
    );

    // stall se: (a) L1i miss, OR (b) translation pendente
    assign stall = stall_l1i || (satp_enable && !mdone && !mfault);
endmodule
