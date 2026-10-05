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
module mmu_sv39 (
    input  wire        clk, rst_n,
    input  wire        flush,
    input  wire        req,
    input  wire [63:0] va,
    input  wire [1:0]  priv,
    input  wire        is_fetch,
    input  wire        is_store,
    input  wire [8:0]  asid,
    input  wire [43:0] satp_ppn,
    input  wire        satp_enable,
    output wire        pte_req,
    output wire [63:0] pte_addr,
    input  wire [63:0] pte_rdata,
    input  wire        pte_ready,
    output reg         done,
    output reg         fault,
    output reg  [63:0] fault_cause,
    output reg  [63:0] fault_va,
    output reg  [63:0] pa
);
    // ==== Signals ====
    reg         l1_upd_en, l2_upd_en;
    reg  [63:0] l1_upd_va, l1_upd_pa, l2_upd_va, l2_upd_pa;
    reg  [8:0]  l1_upd_asid, l2_upd_asid;
    reg         l1_upd_r, l1_upd_w, l1_upd_x, l1_upd_u;
    reg         l2_upd_r, l2_upd_w, l2_upd_x, l2_upd_u;

    wire        l1_hit;
    wire [63:0] l1_pa;
    wire        l1_r, l1_w, l1_x, l1_u;

    reg         l2_lookup_req;
    wire        l2_hit, l2_ready;
    wire [63:0] l2_pa;
    wire        l2_r, l2_w, l2_x, l2_u;

    reg         wlk_req;
    wire        wlk_done, wlk_fault;
    wire [63:0] wlk_cause, wlk_pa;
    wire        wlk_r, wlk_w, wlk_x, wlk_u;

    // ==== L1 TLB ====
    tlb_l1 u_l1 (
        .clk(clk), .rst_n(rst_n),
        .lookup_req(req),
        .lookup_va(va),
        .lookup_asid(asid),
        .hit(l1_hit), .pa(l1_pa),
        .perm_r(l1_r), .perm_w(l1_w), .perm_x(l1_x), .perm_u(l1_u),
        .upd_en(l1_upd_en),
        .upd_va(l1_upd_va), .upd_pa(l1_upd_pa), .upd_asid(l1_upd_asid),
        .upd_r(l1_upd_r), .upd_w(l1_upd_w), .upd_x(l1_upd_x), .upd_u(l1_upd_u),
        .flush(flush)
    );

    // ==== L2 TLB ====
    tlb_l2 u_l2 (
        .clk(clk), .rst_n(rst_n),
        .lookup_req(l2_lookup_req),
        .lookup_va(lat_va),
        .lookup_asid(lat_asid),
        .hit(l2_hit), .pa(l2_pa),
        .perm_r(l2_r), .perm_w(l2_w), .perm_x(l2_x), .perm_u(l2_u),
        .ready(l2_ready),
        .upd_en(l2_upd_en),
        .upd_va(l2_upd_va), .upd_pa(l2_upd_pa), .upd_asid(l2_upd_asid),
        .upd_r(l2_upd_r), .upd_w(l2_upd_w), .upd_x(l2_upd_x), .upd_u(l2_upd_u),
        .flush(flush)
    );

    // ==== Walker ====
    sv39_walker u_wlk (
        .clk(clk), .rst_n(rst_n),
        .req(wlk_req), .va(lat_va), .priv(lat_priv),
        .is_fetch(lat_is_fetch), .is_store(lat_is_store),
        .satp_ppn(satp_ppn),
        .mem_req(pte_req), .mem_addr(pte_addr),
        .mem_rdata(pte_rdata), .mem_ready(pte_ready),
        .done(wlk_done), .fault(wlk_fault),
        .fault_cause(wlk_cause), .fault_va(), .pa(wlk_pa),
        .leaf_r(wlk_r), .leaf_w(wlk_w), .leaf_x(wlk_x), .leaf_u(wlk_u)
    );

    // ==== FSM ====
    localparam S_IDLE=0, S_L2=2, S_WLK=3;
    reg [2:0] state;
    reg [63:0] lat_va;
    reg [1:0]  lat_priv;
    reg        lat_is_fetch, lat_is_store;
    reg [8:0]  lat_asid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 0; fault <= 0;
            fault_cause <= 0; fault_va <= 0; pa <= 0;
            lat_va <= 0; lat_priv <= 0;
            lat_is_fetch <= 0; lat_is_store <= 0; lat_asid <= 0;
            l2_lookup_req <= 0;
            wlk_req <= 0;
            l1_upd_en <= 0; l2_upd_en <= 0;
            l1_upd_va <= 0; l1_upd_pa <= 0; l1_upd_asid <= 0;
            l2_upd_va <= 0; l2_upd_pa <= 0; l2_upd_asid <= 0;
            l1_upd_r <= 0; l1_upd_w <= 0; l1_upd_x <= 0; l1_upd_u <= 0;
            l2_upd_r <= 0; l2_upd_w <= 0; l2_upd_x <= 0; l2_upd_u <= 0;
        end else begin
            done       <= 0;
            fault      <= 0;
            l1_upd_en  <= 0;
            l2_upd_en  <= 0;

            case (state)
                S_IDLE: begin
                    if (req) begin
                        if (!satp_enable) begin
                            pa   <= va;
                            done <= 1;
                        end else if (l1_hit) begin
                            pa   <= l1_pa;
                            done <= 1;
                        end else begin
                            lat_va        <= va;
                            lat_priv      <= priv;
                            lat_is_fetch  <= is_fetch;
                            lat_is_store  <= is_store;
                            lat_asid      <= asid;
                            l2_lookup_req <= 1;
                            state         <= S_L2;
                        end
                    end
                end
                S_L2: begin
                    l2_lookup_req <= 0;
                    if (l2_ready) begin
                        if (l2_hit) begin
                            // Populate L1 from L2 hit
                            l1_upd_en   <= 1;
                            l1_upd_va   <= lat_va;
                            l1_upd_pa   <= l2_pa;
                            l1_upd_asid <= lat_asid;
                            l1_upd_r    <= l2_r;
                            l1_upd_w    <= l2_w;
                            l1_upd_x    <= l2_x;
                            l1_upd_u    <= l2_u;
                            pa          <= l2_pa;
                            done        <= 1;
                            state       <= S_IDLE;
                        end else begin
                            wlk_req <= 1;
                            state   <= S_WLK;
                        end
                    end
                end
                S_WLK: begin
                    wlk_req <= 0;
                    if (wlk_done) begin
                        // Populate both TLBs from walker
                        l1_upd_en   <= 1;
                        l1_upd_va   <= lat_va;
                        l1_upd_pa   <= wlk_pa;
                        l1_upd_asid <= lat_asid;
                        l1_upd_r    <= wlk_r;
                        l1_upd_w    <= wlk_w;
                        l1_upd_x    <= wlk_x;
                        l1_upd_u    <= wlk_u;
                        l2_upd_en   <= 1;
                        l2_upd_va   <= lat_va;
                        l2_upd_pa   <= wlk_pa;
                        l2_upd_asid <= lat_asid;
                        l2_upd_r    <= wlk_r;
                        l2_upd_w    <= wlk_w;
                        l2_upd_x    <= wlk_x;
                        l2_upd_u    <= wlk_u;
                        pa          <= wlk_pa;
                        done        <= 1;
                        state       <= S_IDLE;
                    end else if (wlk_fault) begin
                        fault_cause <= wlk_cause;
                        fault_va    <= lat_va;
                        fault       <= 1;
                        state       <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
