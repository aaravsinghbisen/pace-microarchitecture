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
// Runahead control: quando um miss longo ocorre, PCU entra em modo
// especulativo (prefetch-only). Sai quando o miss resolve.
module runahead_ctrl (
    input  wire clk, rst_n,
    input  wire enable,          // habilitar runahead
    input  wire stall_long,      // sinal de miss longo (ex: L2 miss, MMU walk)
    input  wire stall_cleared,   // memória chegou
    input  wire sb_full,         // store buffer cheio (não dá pra rodar)
    output reg  runahead_active,
    output reg  discard_writes,  // 1 = não escreve no Shadow RF nem Arch RF
    output reg  [31:0] rh_steps,
    output reg  enter_pulse,
    output reg  exit_pulse
);
    localparam S_NORMAL = 0, S_RUNAHEAD = 1, S_DRAIN = 2;
    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_NORMAL;
            runahead_active <= 0;
            discard_writes  <= 0;
            rh_steps        <= 0;
            enter_pulse     <= 0;
            exit_pulse      <= 0;
        end else begin
            enter_pulse <= 0;
            exit_pulse  <= 0;

            case (state)
                S_NORMAL: begin
                    runahead_active <= 0;
                    discard_writes  <= 0;
                    rh_steps        <= 0;
                    if (enable && stall_long && !sb_full) begin
                        state           <= S_RUNAHEAD;
                        runahead_active <= 1;
                        discard_writes  <= 1;
                        enter_pulse     <= 1;
                    end
                end
                S_RUNAHEAD: begin
                    rh_steps <= rh_steps + 1;
                    // Prefetch continua até a memória chegar
                    if (stall_cleared) begin
                        state       <= S_DRAIN;
                        exit_pulse  <= 1;
                    end
                end
                S_DRAIN: begin
                    // Descarta os writes especulativos e reinicia
                    runahead_active <= 0;
                    discard_writes  <= 0;
                    state           <= S_NORMAL;
                end
            endcase
        end
    end
endmodule
