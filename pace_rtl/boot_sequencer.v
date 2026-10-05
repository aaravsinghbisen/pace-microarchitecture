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
module boot_sequencer #(
    parameter SCOUT_AHEAD_CYCLES = 2*32
)(
    input  wire clk, rst_n,
    output reg  rst_n_pcu,   // scouts enabled
    output reg  rst_n_ao,    // AO-Core enabled
    output reg  boot_done
);
    localparam S_RESET       = 0;
    localparam S_SCOUT_START = 1;
    localparam S_SCOUT_AHEAD = 2;
    localparam S_AO_START    = 3;
    localparam S_STEADY      = 4;

    reg [2:0]  state;
    reg [15:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_RESET;
            counter   <= 0;
            rst_n_pcu <= 0;
            rst_n_ao  <= 0;
            boot_done <= 0;
        end else begin
            case (state)
                S_RESET: begin
                    rst_n_pcu <= 0;
                    rst_n_ao  <= 0;
                    if (counter == 5) begin
                        counter <= 0;
                        state   <= S_SCOUT_START;
                    end else counter <= counter + 1;
                end
                S_SCOUT_START: begin
                    rst_n_pcu <= 1;              // turn scouts ON
                    rst_n_ao  <= 0;              // AO still OFF
                    counter   <= 0;
                    state     <= S_SCOUT_AHEAD;
                end
                S_SCOUT_AHEAD: begin
                    // Scouts run ahead, filling shadow RF
                    if (counter == SCOUT_AHEAD_CYCLES) begin
                        counter <= 0;
                        state   <= S_AO_START;
                    end else counter <= counter + 1;
                end
                S_AO_START: begin
                    rst_n_ao <= 1;               // turn AO-Cores ON
                    state    <= S_STEADY;
                end
                S_STEADY: begin
                    boot_done <= 1;
                end
            endcase
        end
    end
endmodule
