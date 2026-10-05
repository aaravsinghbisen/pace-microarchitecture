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
module dmem_mmu_wrap (
    input  wire clk, rst_n,
    input  wire        mc_req, mc_we,
    input  wire [63:0] mc_addr_va, mc_wdata,
    output reg  [63:0] mc_rdata,
    output reg         mc_ready,
    output reg         mc_page_fault,
    output reg  [63:0] mc_fault_cause, mc_fault_va,
    output reg         dmem_req, dmem_we,
    output reg  [63:0] dmem_addr, dmem_wdata,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_ready,
    input  wire        flush_tlb,
    input  wire [1:0]  priv,
    input  wire [8:0]  asid,
    input  wire [43:0] satp_ppn,
    input  wire        satp_enable,
    output wire        pte_req,
    output wire [63:0] pte_addr,
    input  wire [63:0] pte_rdata,
    input  wire        pte_ready
);
    localparam S_IDLE=0, S_MMU=1, S_DMEM=2, S_DONE=3;
    reg [1:0] state;
    reg [63:0] lat_va, lat_wdata;
    reg        lat_we;
    reg        mmu_req;

    wire        mdone, mfault;
    wire [63:0] mc_cause, mva, phys_addr;

    mmu_sv39 u_mmu (
        .clk(clk), .rst_n(rst_n), .flush(flush_tlb),
        .req(mmu_req), .va(lat_va), .priv(priv),
        .is_fetch(1'b0), .is_store(lat_we), .asid(asid),
        .satp_ppn(satp_ppn), .satp_enable(satp_enable),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .done(mdone), .fault(mfault),
        .fault_cause(mc_cause), .fault_va(mva), .pa(phys_addr)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mmu_req <= 0;
            lat_va <= 0; lat_we <= 0; lat_wdata <= 0;
            mc_rdata <= 0; mc_ready <= 0;
            mc_page_fault <= 0; mc_fault_cause <= 0; mc_fault_va <= 0;
            dmem_req <= 0; dmem_we <= 0; dmem_addr <= 0; dmem_wdata <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    mc_ready      <= 0;
                    mc_page_fault <= 0;
                    dmem_req      <= 0;
                    if (mc_req) begin
                        lat_va    <= mc_addr_va;
                        lat_we    <= mc_we;
                        lat_wdata <= mc_wdata;
                        if (satp_enable) begin
                            mmu_req <= 1;    // pulso 1 ciclo
                            state   <= S_MMU;
                        end else begin
                            dmem_req   <= 1;
                            dmem_we    <= mc_we;
                            dmem_addr  <= mc_addr_va;
                            dmem_wdata <= mc_wdata;
                            state      <= S_DMEM;
                        end
                    end
                end
                S_MMU: begin
                    mmu_req <= 0;        // zera logo após o pulso
                    if (mdone) begin
                        dmem_req   <= 1;
                        dmem_we    <= lat_we;
                        dmem_addr  <= phys_addr;
                        dmem_wdata <= lat_wdata;
                        state      <= S_DMEM;
                    end else if (mfault) begin
                        mc_page_fault  <= 1;
                        mc_fault_cause <= mc_cause;
                        mc_fault_va    <= mva;
                        mc_ready       <= 1;
                        state          <= S_DONE;
                    end
                end
                S_DMEM: begin
                    if (dmem_ready) begin
                        dmem_req <= 0;
                        mc_rdata <= dmem_rdata;
                        mc_ready <= 1;
                        state    <= S_DONE;
                    end
                end
                S_DONE: begin
                    if (!mc_req) state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
