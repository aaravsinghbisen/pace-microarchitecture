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
module mesi_ctrl (
    input  wire clk, rst_n,
    input  wire local_req, local_write, local_hit,
    output wire need_bus_rd, need_bus_rdx, need_bus_upgr,
    output reg  local_done,
    output reg  flush_data_valid,
    output reg  [63:0] flush_data,
    input  wire bus_rd, bus_rdx, bus_upgr,
    input  wire [31:0] bus_addr, my_addr,
    output reg  [1:0] state,
    input  wire [63:0] write_data_in,
    output reg  [63:0] data_out,
    input  wire [63:0] data_in_local
);
    localparam I = 2'b00, S = 2'b01, E = 2'b10, M = 2'b11;

    // Pulsos registrados (durável no ciclo seguinte ao request)
    reg rd_pulse, rdx_pulse, upgr_pulse;
    assign need_bus_rd   = rd_pulse;
    assign need_bus_rdx  = rdx_pulse;
    assign need_bus_upgr = upgr_pulse;

    wire addr_match = (bus_addr == my_addr);
    reg  pending_rd;   // aguardando resposta do bus

    // local_done combinacional (mesmo ciclo da requisição)
    always @(*) begin
        local_done = 0;
        if (local_req) begin
            case (state)
                S: if (!local_write) local_done = 1;
                E, M: local_done = 1;
                default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= I;
            data_out <= 0;
            rd_pulse <= 0; rdx_pulse <= 0; upgr_pulse <= 0;
            flush_data_valid <= 0;
            flush_data <= 0;
            pending_rd <= 0;
        end else begin
            // Defaults
            rd_pulse <= 0;
            rdx_pulse <= 0;
            upgr_pulse <= 0;
            flush_data_valid <= 0;

            // ============ Local requests ============
            if (local_req) begin
                case (state)
                    I: begin
                        if (local_write) begin
                            rdx_pulse <= 1;
                            state <= M;
                            data_out <= data_in_local;
                        end else begin
                            rd_pulse <= 1;
                            pending_rd <= 1;   // aguarda dado do bus
                        end
                    end
                    S: begin
                        if (local_write) begin
                            upgr_pulse <= 1;
                            state <= M;
                            data_out <= data_in_local;
                        end
                    end
                    E: begin
                        if (local_write) begin
                            state <= M;
                            data_out <= data_in_local;
                        end
                    end
                    M: begin
                        if (local_write) data_out <= data_in_local;
                    end
                endcase
            end

            // ============ Bus read response (1 ciclo depois) ============
            if (pending_rd) begin
                state     <= E;   // (assume sem sharers; senão seria S)
                data_out  <= write_data_in;
                pending_rd <= 0;
            end

            // ============ Snoop (último, vence) ============
            if (addr_match && (bus_rd || bus_rdx || bus_upgr)) begin
                case (state)
                    M: begin
                        if (bus_rdx || bus_upgr) state <= I;
                        else begin
                            state            <= S;
                            flush_data_valid <= 1;
                            flush_data       <= data_out;
                        end
                    end
                    E: begin
                        if (bus_rdx || bus_upgr) state <= I;
                        else                     state <= S;
                    end
                    S: begin
                        if (bus_rdx || bus_upgr) state <= I;
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
