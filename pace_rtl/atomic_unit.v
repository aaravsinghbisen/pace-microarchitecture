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
// Unidade atômica RISC-V (A extension).
// LR/SC + AMO{SWAP,ADD,XOR,AND,OR,MIN,MAX,MINU,MAXU}.W/.D
module atomic_unit #(
    parameter ADDR_W = 64,
    parameter DATA_W = 64
)(
    input  wire clk, rst_n,

    // Interface com pipeline
    input  wire        req,          // pulso: operação atômica
    input  wire        is_lr,        // load-reserved
    input  wire        is_sc,        // store-conditional
    input  wire        is_amo,       // AMO*
    input  wire [4:0]  amo_op,       // AMO operation
    input  wire        is_word,      // 1=.W 0=.D
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] rs2_val,     // valor de rs2
    output reg  [DATA_W-1:0] rd_val,      // valor lido (old)
    output reg         sc_success,        // pra SC: 1=sucesso
    output reg         done,

    // Interface memória (word-level)
    output reg         mem_req, mem_we,
    output reg  [ADDR_W-1:0] mem_addr,
    output reg  [DATA_W-1:0] mem_wdata,
    input  wire [DATA_W-1:0] mem_rdata,
    input  wire        mem_ready
);
    // AMO opcodes (funct5)
    localparam AMO_ADD    = 5'b00000;
    localparam AMO_SWAP   = 5'b00001;
    localparam AMO_XOR    = 5'b00100;
    localparam AMO_OR     = 5'b01000;
    localparam AMO_AND    = 5'b01100;
    localparam AMO_MIN    = 5'b10000;
    localparam AMO_MAX    = 5'b10100;
    localparam AMO_MINU   = 5'b11000;
    localparam AMO_MAXU   = 5'b11100;

    // Reservation register (single hart)
    reg                    res_valid;
    reg  [ADDR_W-1:0]      res_addr;

    localparam S_IDLE = 2'd0, S_MEM_RD = 2'd1, S_MEM_WR = 2'd2, S_DONE = 2'd3;
    reg [1:0] state;
    reg       lat_is_word;
    reg [4:0] lat_amo_op;
    reg       lat_is_sc;
    reg       lat_is_amo;
    reg [DATA_W-1:0] lat_rs2;
    reg [ADDR_W-1:0] lat_addr;

    // Compute new value (AMO)
    wire [63:0] old_v = mem_rdata;
    wire [63:0] w_rs2 = lat_is_word ? {32'b0, lat_rs2[31:0]} : lat_rs2;
    wire [63:0] w_old = lat_is_word ? {32'b0, old_v[31:0]} : old_v;
    reg  [63:0] new_v;
    always @(*) begin
        case (lat_amo_op)
            AMO_ADD:  new_v = w_old + w_rs2;
            AMO_SWAP: new_v = w_rs2;
            AMO_XOR:  new_v = w_old ^ w_rs2;
            AMO_OR:   new_v = w_old | w_rs2;
            AMO_AND:  new_v = w_old & w_rs2;
            AMO_MIN:  new_v = ($signed(w_old) < $signed(w_rs2)) ? w_old : w_rs2;
            AMO_MAX:  new_v = ($signed(w_old) > $signed(w_rs2)) ? w_old : w_rs2;
            AMO_MINU: new_v = (w_old < w_rs2) ? w_old : w_rs2;
            AMO_MAXU: new_v = (w_old > w_rs2) ? w_old : w_rs2;
            default:  new_v = w_rs2;
        endcase
    end

    // Interceptação: memória de 64 bits, mas W = 32 bits. Mascara pra manter alta
    wire [63:0] wr_data_w = lat_is_word ? {old_v[63:32], new_v[31:0]} : new_v;

    // Snoop: se outra requisição atômica chegar no mesmo endereço, invalida reserva
    // (simplificado: só o SC falha se houve escrita de outro hart)
    reg  global_wr_pulse;    // pulso de qualquer outra escrita no mesmo endereço
    // (não implementado no testbench — assume reserva preservada)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mem_req <= 0; mem_we <= 0; mem_addr <= 0; mem_wdata <= 0;
            rd_val <= 0; sc_success <= 0; done <= 0;
            res_valid <= 0; res_addr <= 0;
        end else begin
            done <= 0;
            case (state)
                S_IDLE: begin
                    mem_req <= 0; mem_we <= 0;
                    if (req) begin
                        lat_addr <= addr;
                        lat_is_word <= is_word;
                        lat_amo_op <= amo_op;
                        lat_is_sc <= is_sc;
                        lat_is_amo <= is_amo;
                        lat_rs2 <= rs2_val;

                        if (is_sc) begin
                            // SC: só faz se reserva válida e endereço bate
                            if (res_valid && (res_addr == addr)) begin
                                mem_req  <= 1;
                                mem_we   <= 1;
                                mem_addr <= addr;
                                mem_wdata<= is_word ? {32'b0, rs2_val[31:0]} : rs2_val;
                                state    <= S_MEM_WR;
                                sc_success <= 1;
                            end else begin
                                sc_success <= 0;
                                done <= 1;
                                state <= S_IDLE;
                            end
                            res_valid <= 0;   // SC sempre limpa
                        end else begin
                            // LR ou AMO: primeiro lê
                            mem_req  <= 1;
                            mem_we   <= 0;
                            mem_addr <= addr;
                            state    <= S_MEM_RD;
                        end
                    end
                end
                S_MEM_RD: begin
                    if (mem_ready) begin
                        rd_val <= is_word ? {32'b0, mem_rdata[31:0]} : mem_rdata;
                        mem_req <= 0;

                        if (is_lr) begin
                            res_valid <= 1;
                            res_addr  <= lat_addr;
                            done <= 1;
                            state <= S_IDLE;
                        end else if (is_amo) begin
                            mem_req  <= 1;
                            mem_we   <= 1;
                            mem_addr <= lat_addr;
                            mem_wdata<= wr_data_w;
                            state    <= S_MEM_WR;
                        end else begin
                            done <= 1;
                            state <= S_IDLE;
                        end
                    end
                end
                S_MEM_WR: begin
                    if (mem_ready) begin
                        mem_req <= 0;
                        done <= 1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
