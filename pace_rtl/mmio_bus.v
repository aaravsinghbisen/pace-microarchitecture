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
// MMIO Bus: routes M-Core accesses to CLINT / PLIC / UART / DRAM based on address
module mmio_bus (
    input  wire        clk, rst_n,
    // From M-Core (via L1d for DRAM, direct for MMIO)
    input  wire        req,
    input  wire        we,
    input  wire [63:0] addr,
    input  wire [63:0] wdata,
    output reg  [63:0] rdata,
    output reg         ready,
    // To CLINT
    output wire        clint_req, clint_we,
    output wire [63:0] clint_addr, clint_wdata,
    input  wire [63:0] clint_rdata,
    input  wire        clint_ready,
    // To UART (stub for now)
    output wire        uart_req, uart_we,
    output wire [63:0] uart_addr, uart_wdata,
    input  wire [63:0] uart_rdata,
    input  wire        uart_ready,
    // To PLIC (stub for now)
    output wire        plic_req, plic_we,
    output wire [63:0] plic_addr, plic_wdata,
    input  wire [63:0] plic_rdata,
    input  wire        plic_ready
);
    // Address decoder
    wire sel_clint = (addr[31:16] == 16'h0200);   // 0x0200_xxxx
    wire sel_plic  = (addr[31:24] == 8'h0C);      // 0x0C00_0000
    wire sel_uart  = (addr[31:16] == 16'h1000);   // 0x1000_xxxx

    // CLINT
    assign clint_req   = req && sel_clint;
    assign clint_we    = we;
    assign clint_addr  = addr;
    assign clint_wdata = wdata;

    // UART
    assign uart_req   = req && sel_uart;
    assign uart_we    = we;
    assign uart_addr  = addr;
    assign uart_wdata = wdata;

    // PLIC
    assign plic_req   = req && sel_plic;
    assign plic_we    = we;
    assign plic_addr  = addr;
    assign plic_wdata = wdata;

    // Response mux
    always @(*) begin
        if (sel_clint) begin rdata = clint_rdata; ready = clint_ready; end
        else if (sel_plic) begin rdata = plic_rdata; ready = plic_ready; end
        else if (sel_uart) begin rdata = uart_rdata; ready = uart_ready; end
        else begin rdata = 64'd0; ready = 1'b1; end   // unmapped = 0
    end
endmodule
