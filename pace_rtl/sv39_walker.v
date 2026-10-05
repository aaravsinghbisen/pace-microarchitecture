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
module sv39_walker (
    input  wire        clk, rst_n,
    input  wire        req,
    input  wire [63:0] va,
    input  wire [1:0]  priv,
    input  wire        is_fetch,
    input  wire        is_store,
    input  wire [43:0] satp_ppn,
    output reg         mem_req,
    output reg  [63:0] mem_addr,
    input  wire [63:0] mem_rdata,
    input  wire        mem_ready,
    output reg         done,
    output reg         fault,
    output reg  [63:0] fault_cause,
    output reg  [63:0] fault_va,
    output reg  [63:0] pa,
    // Leaf PTE permissions (valid when done)
    output reg         leaf_r, leaf_w, leaf_x, leaf_u
);
    localparam CAUSE_FETCH = 64'd12;
    localparam CAUSE_LOAD  = 64'd13;
    localparam CAUSE_STORE = 64'd15;

    reg [63:0] lat_va;
    reg [1:0]  lat_priv;
    reg        lat_is_fetch, lat_is_store;
    reg [43:0] lat_base_ppn;
    reg [1:0]  lat_level;
    reg [63:0] lat_pte;

    localparam S_IDLE=3'd0, S_REQ=3'd1, S_WAIT=3'd2, S_CHECK=3'd3, S_DONE=3'd4, S_FAULT=3'd5;
    reg [2:0] state;

    wire [8:0] vpn_sel = (lat_level == 2'd2) ? lat_va[38:30] :
                         (lat_level == 2'd1) ? lat_va[29:21] : lat_va[20:12];

    wire va_sign_ok = (va[63:39] == {25{va[38]}});

    wire        pte_v = lat_pte[0];
    wire        pte_r = lat_pte[1];
    wire        pte_w = lat_pte[2];
    wire        pte_x = lat_pte[3];
    wire        pte_u = lat_pte[4];
    wire [43:0] pte_ppn = lat_pte[53:10];
    wire        pte_leaf = pte_r || pte_x;

    wire perm_fail = (lat_is_fetch && !pte_x) ||
                     (!lat_is_fetch && !lat_is_store && !pte_r) ||
                     (lat_is_store && !pte_w);
    wire u_fail = (lat_priv == 2'b00) && !pte_u;

    wire superpage_fail = pte_leaf && (
        (lat_level == 2'd2 && pte_ppn[17:0] != 0) ||
        (lat_level == 2'd1 && pte_ppn[8:0]  != 0));

    wire [63:0] this_cause = lat_is_fetch ? CAUSE_FETCH :
                             lat_is_store ? CAUSE_STORE : CAUSE_LOAD;

    reg [63:0] pa_calc;
    always @(*) begin
        case (lat_level)
            2'd2: pa_calc = {8'b0, pte_ppn, 12'b0} | {34'b0, lat_va[29:0]};
            2'd1: pa_calc = {8'b0, pte_ppn, 12'b0} | {43'b0, lat_va[20:0]};
            default: pa_calc = {8'b0, pte_ppn, 12'b0} | {52'b0, lat_va[11:0]};
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mem_req <= 0; mem_addr <= 0;
            done <= 0; fault <= 0;
            fault_cause <= 0; fault_va <= 0; pa <= 0;
            leaf_r <= 0; leaf_w <= 0; leaf_x <= 0; leaf_u <= 0;
            lat_va <= 0; lat_priv <= 0; lat_is_fetch <= 0; lat_is_store <= 0;
            lat_base_ppn <= 0; lat_level <= 0; lat_pte <= 0;
        end else begin
            done <= 0;
            fault <= 0;
            case (state)
                S_IDLE: begin
                    mem_req <= 0;
                    if (req) begin
                        lat_va <= va; lat_priv <= priv;
                        lat_is_fetch <= is_fetch; lat_is_store <= is_store;
                        lat_base_ppn <= satp_ppn;
                        lat_level <= 2'd2;
                        fault_va <= va; fault_cause <= this_cause;
                        state <= va_sign_ok ? S_REQ : S_FAULT;
                    end
                end
                S_REQ: begin
                    mem_req <= 1;
                    mem_addr <= {8'b0, lat_base_ppn, 12'b0} + ({55'b0, vpn_sel} << 3);
                    state <= S_WAIT;
                end
                S_WAIT: begin
                    if (mem_ready) begin
                        mem_req <= 0;
                        lat_pte <= mem_rdata;
                        state <= S_CHECK;
                    end
                end
                S_CHECK: begin
                    if (!pte_v || (!pte_r && pte_w))          state <= S_FAULT;
                    else if (!pte_leaf) begin
                        if (lat_level == 2'd0)                state <= S_FAULT;
                        else begin
                            lat_base_ppn <= pte_ppn;
                            lat_level <= lat_level - 1'b1;
                            state <= S_REQ;
                        end
                    end else begin
                        if (perm_fail || u_fail || superpage_fail) state <= S_FAULT;
                        else begin
                            pa <= pa_calc;
                            leaf_r <= pte_r;
                            leaf_w <= pte_w;
                            leaf_x <= pte_x;
                            leaf_u <= pte_u;
                            state <= S_DONE;
                        end
                    end
                end
                S_DONE:  begin done <= 1;  state <= S_IDLE; end
                S_FAULT: begin fault <= 1; state <= S_IDLE; end
            endcase
        end
    end
endmodule
