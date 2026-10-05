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
// Vector CSRs: vstart, vxsat, vxrm, vcsr, vl, vtype
// Endereços RISC-V:
//   vstart = 0x008
//   vxsat  = 0x009
//   vxrm   = 0x00A
//   vcsr   = 0x00F
//   vl     = 0xC20
//   vtype  = 0xC21
module v_csr (
    input  wire        clk, rst_n,
    // Access from CSR instructions
    input  wire        csr_access,
    input  wire        csr_we,
    input  wire [11:0] csr_addr,
    input  wire [63:0] csr_wdata,
    input  wire [1:0]  csr_op,
    output reg  [63:0] csr_rdata,
    // Outputs to pipeline
    output reg  [7:0]  vl,
    output reg  [63:0] vtype
);
    reg [5:0]  vstart;
    reg        vxsat;
    reg  [1:0] vxrm;

    // vtype layout (simplified): 
    // bits[2:0] = vsew (0=8, 1=16, 2=32, 3=64)
    // bits[5:3] = vlmul (0=1, 1=2, 2=4, 3=8, 5=1/2, 6=1/4, 7=1/8)
    // bits[6]   = vta
    // bits[7]   = vma

    wire [2:0] vsew  = vtype[2:0];
    wire [2:0] vlmul = vtype[5:3];

    function [63:0] apply_op;
        input [63:0] old_v;
        input [63:0] wd;
        input [1:0]  o;
        begin
            case (o)
                2'b01: apply_op = wd;
                2'b10: apply_op = old_v | wd;
                2'b11: apply_op = old_v & ~wd;
                default: apply_op = old_v;
            endcase
        end
    endfunction

    always @(*) begin
        csr_rdata = 0;
        case (csr_addr)
            12'h008: csr_rdata = {58'b0, vstart};
            12'h009: csr_rdata = {63'b0, vxsat};
            12'h00A: csr_rdata = {62'b0, vxrm};
            12'h00F: csr_rdata = {61'b0, vxrm, vxsat};
            12'hC20: csr_rdata = {56'b0, vl};
            12'hC21: csr_rdata = vtype;
            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vstart <= 0;
            vxsat  <= 0;
            vxrm   <= 0;
            vl     <= 0;
            vtype  <= 64'h0000_0000_0000_0003;   // SEW=64, LMUL=1
        end else if (csr_access && csr_we) begin
            case (csr_addr)
                12'h008: vstart <= apply_op({58'b0, vstart}, csr_wdata, csr_op)[5:0];
                12'h009: vxsat  <= apply_op({63'b0, vxsat}, csr_wdata, csr_op)[0];
                12'h00A: vxrm   <= apply_op({62'b0, vxrm}, csr_wdata, csr_op)[1:0];
                12'h00F: begin
                    vxsat <= apply_op({61'b0, vxrm, vxsat}, csr_wdata, csr_op)[0];
                    vxrm  <= apply_op({61'b0, vxrm, vxsat}, csr_wdata, csr_op)[2:1];
                end
                12'hC20: vl    <= apply_op({56'b0, vl}, csr_wdata, csr_op)[7:0];
                12'hC21: vtype <= apply_op(vtype, csr_wdata, csr_op);
                default: ;
            endcase
        end
    end
endmodule
