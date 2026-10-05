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
module l1d_mmu #(
    parameter ADDR_W=64, parameter DATA_W=64,
    parameter SETS=128, parameter WAYS=4, parameter LINE_WORDS=8
)(
    input  wire clk, rst_n,
    input  wire                 cpu_req,
    input  wire                 cpu_we,
    input  wire [ADDR_W-1:0]    cpu_addr_va,
    input  wire [DATA_W-1:0]    cpu_wdata,
    output wire [DATA_W-1:0]    cpu_rdata,
    output wire                 cpu_ready,
    input  wire flush,
    input  wire [1:0] priv,
    input  wire [8:0] asid,
    input  wire [43:0] satp_ppn,
    input  wire satp_enable,
    output wire        l2_req, l2_we,
    output wire [ADDR_W-1:0] l2_addr,
    output wire [DATA_W-1:0] l2_wdata,
    input  wire [LINE_WORDS*DATA_W-1:0] l2_rdata,
    input  wire        l2_ready,
    output wire        mmio_req, mmio_we,
    output wire [ADDR_W-1:0] mmio_addr,
    output wire [DATA_W-1:0] mmio_wdata,
    input  wire [DATA_W-1:0] mmio_rdata,
    input  wire        mmio_ready,
    output wire        pte_req,
    output wire [ADDR_W-1:0] pte_addr,
    input  wire [63:0] pte_rdata,
    input  wire        pte_ready,
    output wire        page_fault,
    output wire [63:0] fault_cause,
    output wire [63:0] fault_va
);
    // ===== FSM =====
    localparam S_IDLE=0, S_MMU=1, S_L1D=2, S_WAIT_DROP=3, S_FAULT=4;
    reg [2:0] state;

    // ===== Latch =====
    reg [63:0] pa_used;
    reg        mmu_fault_r;
    reg [63:0] latched_cause, latched_va;

    // ===== MMU control =====
    wire satp_active = satp_enable && (priv != 2'b11);
    reg  mmu_req;
    wire mdone, mfault;
    wire [63:0] mc, mva, phys_addr;

    // ===== L1d control =====
    reg  l1d_req;
    wire l1d_ready;

    // ===== MMU instance =====
    mmu_sv39 u_mmu (
        .clk(clk), .rst_n(rst_n),
        .flush(flush),
        .req(mmu_req),
        .va(cpu_addr_va), .priv(priv),
        .is_fetch(1'b0), .is_store(cpu_we), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_active),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .done(mdone), .fault(mfault),
        .fault_cause(mc), .fault_va(mva), .pa(phys_addr)
    );

    // ===== L1d instance =====
    l1d #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .SETS(SETS), .WAYS(WAYS), .LINE_WORDS(LINE_WORDS))
    u_l1d (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(l1d_req), .cpu_we(cpu_we),
        .cpu_addr(pa_used), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(l1d_ready),
        .l2_req(l2_req), .l2_we(l2_we),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .snp_valid(1'b0), .snp_we(1'b0), .snp_addr(64'd0), .snp_wdata(64'd0)
    );

    // ===== FSM =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mmu_req <= 0;
            l1d_req <= 0;
            pa_used <= 0;
            mmu_fault_r <= 0;
            latched_cause <= 0;
            latched_va <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    mmu_req <= 0;
                    l1d_req <= 0;
                    if (cpu_req) begin
                        if (!satp_active) begin
                            // Bare mode: skip MMU
                            pa_used <= cpu_addr_va;
                            l1d_req <= 1;
                            state   <= S_L1D;
                        end else begin
                            mmu_req <= 1;
                            state   <= S_MMU;
                        end
                    end
                end
                S_MMU: begin
                    mmu_req <= 0;
                    if (mdone) begin
                        pa_used <= phys_addr;
                        l1d_req <= 1;
                        state   <= S_L1D;
                    end else if (mfault) begin
                        latched_cause <= mc;
                        latched_va    <= mva;
                        mmu_fault_r   <= 1;
                        state         <= S_FAULT;
                    end
                end
                S_L1D: begin
                    if (l1d_ready) begin
                        l1d_req <= 0;
                        state   <= S_WAIT_DROP;
                    end
                end
                S_WAIT_DROP: begin
                    if (!cpu_req) state <= S_IDLE;
                end
                S_FAULT: begin
                    if (!cpu_req) begin
                        mmu_fault_r <= 0;
                        state       <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // ===== Outputs =====
    assign cpu_ready  = l1d_ready;
    assign page_fault = mmu_fault_r;
    assign fault_cause= latched_cause;
    assign fault_va   = latched_va;
endmodule
