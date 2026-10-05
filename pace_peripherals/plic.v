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
module plic #(parameter N_SRC = 32, parameter N_CTX = 2) (
    input  wire clk, rst_n,
    input  wire req, we,
    input  wire [63:0] addr, wdata,
    output reg  [63:0] rdata,
    output reg         ready,
    input  wire [N_SRC-1:0] irq_sources,
    output reg  [N_CTX-1:0] ctx_irq
);
    reg [2:0]       prio    [1:N_SRC-1];
    reg [N_SRC-1:0] pending;
    reg [N_SRC-1:0] enabled [0:N_CTX-1];
    reg [2:0]       thr     [0:N_CTX-1];
    reg [5:0]       claimed [0:N_CTX-1];

    wire [31:0] a32 = addr[31:0];

    // Address regions
    wire in_prio  = (a32 < 32'h1000);
    wire in_pend  = (a32 >= 32'h1000) && (a32 < 32'h2000);
    wire in_en    = (a32 >= 32'h2000) && (a32 < 32'h20_0000);
    wire in_thr   = (a32 >= 32'h20_0000) && (a32[2] == 1'b0);
    wire in_claim = (a32 >= 32'h20_0000) && (a32[2] == 1'b1);

    wire [7:0] src_idx = a32[9:2];
    wire [3:0] en_ctx  = (a32 - 32'h2000) >> 7;
    wire [3:0] thr_ctx = (a32 - 32'h20_0000) >> 12;

    // pending update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pending <= 0;
        else        pending <= pending | irq_sources;
    end

    // Best IRQ per context
    integer c, s;
    reg [5:0] best [0:N_CTX-1];
    reg       has  [0:N_CTX-1];
    always @(*) begin
        for (c = 0; c < N_CTX; c = c + 1) begin
            best[c] = 0;
            has[c]  = 0;
            for (s = 1; s < N_SRC; s = s + 1) begin
                if (pending[s] && enabled[c][s] && prio[s] > thr[c]) begin
                    if (!has[c] || prio[s] > prio[best[c]])
                        begin best[c] = s[5:0]; has[c] = 1; end
                end
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < N_CTX; g = g + 1)
            always @(*) ctx_irq[g] = has[g];
    endgenerate

    integer r, s3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 0; rdata <= 0;
            for (s3 = 1; s3 < N_SRC; s3 = s3 + 1) prio[s3] <= 0;
            for (r = 0; r < N_CTX; r = r + 1) begin
                enabled[r] <= 0; thr[r] <= 0; claimed[r] <= 0;
            end
        end else begin
            ready <= 0;
            if (req) begin
                if (we) begin
                    if (in_prio) begin
                        if (src_idx >= 1 && src_idx < N_SRC)
                            prio[src_idx] <= wdata[2:0];
                    end else if (in_en) begin
                        if (en_ctx < N_CTX)
                            enabled[en_ctx] <= wdata[N_SRC-1:0];
                    end else if (in_thr) begin
                        if (thr_ctx < N_CTX)
                            thr[thr_ctx] <= wdata[2:0];
                    end else if (in_claim) begin
                        // Complete: limpa pending do que foi claimed
                        if (thr_ctx < N_CTX && claimed[thr_ctx] != 0) begin
                            pending <= pending & ~(32'b1 << claimed[thr_ctx][4:0]);
                            claimed[thr_ctx] <= 0;
                        end
                    end
                end else begin
                    if (in_prio) begin
                        if (src_idx >= 1 && src_idx < N_SRC)
                            rdata <= {61'b0, prio[src_idx]};
                        else rdata <= 0;
                    end else if (in_pend) begin
                        rdata <= {32'b0, pending};
                    end else if (in_en) begin
                        if (en_ctx < N_CTX)
                            rdata <= {32'b0, enabled[en_ctx]};
                    end else if (in_thr) begin
                        if (thr_ctx < N_CTX)
                            rdata <= {61'b0, thr[thr_ctx]};
                    end else if (in_claim) begin
                        // Claim: retorna o melhor IRQ E captura pra complete
                        if (thr_ctx < N_CTX) begin
                            rdata <= {58'b0, best[thr_ctx]};
                            if (has[thr_ctx]) begin
                                pending <= pending & ~(32'b1 << best[thr_ctx][4:0]);
                                claimed[thr_ctx] <= best[thr_ctx];
                            end
                        end
                    end else rdata <= 0;
                end
                ready <= 1;
            end
        end
    end
endmodule
