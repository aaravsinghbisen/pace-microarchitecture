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
// Wrapper: CSR file + Trap unit + IRQ handling.
// Integrado com PCU 6-wide (lane 0 é quem faz CSR/system instructions).
module csr_trap_unit #(parameter HART_ID = 0) (
    input  wire clk, rst_n,

    // ===== Interface com PCU =====
    input  wire        csr_req,       // 1 ciclo: lane 0 é CSR/system instr
    input  wire        is_system,     // 1 se opcode SYSTEM
    input  wire        is_csr,        // 1 se CSRxx
    input  wire        is_ecall,
    input  wire        is_ebreak,
    input  wire        is_mret,
    input  wire        is_sret,
    input  wire [11:0] csr_addr,
    input  wire [1:0]  csr_op,        // 00=R, 01=W, 10=set, 11=clear
    input  wire [63:0] csr_wdata,
    input  wire [63:0] cur_pc,
    output wire [63:0] csr_rdata,

    // Trap reativo (exceções da pipeline) — gera trap
    input  wire        exc_valid,
    input  wire [63:0] exc_cause,
    input  wire [63:0] exc_tval,

    // Saídas pro PCU
    output wire [63:0] trap_pc,
    output wire        trap_taken,
    output wire [1:0]  cur_priv,
    output wire [63:0] satp,
    output wire        satp_enable,
    output wire        flush_tlb,
    output wire [63:0] mepc_o,
    output wire [63:0] sepc_o,

    // Interrupts externos
    input  wire        i_mtip, i_msip, i_meip,
    input  wire        i_seip, i_stip, i_ssip
);
    // ===== CSR file =====
    wire [63:0] mstatus_o, mie_o, mip_o, mtvec_o, stvec_o;
    wire [63:0] medeleg_o, mideleg_o, mepc_o_csr, sepc_o_csr;
    wire [63:0] mcause_o, scause_o;

    wire [1:0]  cur_priv_int;
    assign cur_priv = cur_priv_int;

    wire        trap_taken_w;
    wire [63:0] trap_pc_w, trap_cause_w, trap_tval_w;
    wire [1:0]  trap_priv_w;
    wire        trap_deleg_w;

    // Precisamos de um PC que "entra" no trap
    // Quando trap_taken, csr_file precisa escrever mepc = PC da instrução que falhou
    // Pra exceção síncrona: PC = cur_pc
    // Pra interrupção: PC = cur_pc (instrução que não foi executada)

    csr_file #(.HART_ID(HART_ID)) u_csr (
        .clk(clk), .rst_n(rst_n),
        .csr_addr(csr_addr),
        .csr_we(is_csr && csr_req),
        .csr_op(csr_op),
        .csr_wdata(csr_wdata),
        .csr_rdata(csr_rdata),
        .priv_mode(cur_priv_int),
        .trap_enter(trap_taken_w),
        .trap_to_priv(trap_priv_w),
        .mret(is_mret && csr_req),
        .sret(is_sret && csr_req),
        .update_mepc(1'b0), .update_mcause(1'b0), .update_mtval(1'b0),
        .update_sepc(1'b0), .update_scause(1'b0), .update_stval(1'b0),
        .pc_val(cur_pc),
        .cause_val(trap_cause_w),
        .tval_val(trap_tval_w),
        .deleg_to_s(trap_deleg_w),
        .i_mtip(i_mtip), .i_msip(i_msip), .i_meip(i_meip),
        .i_seip(i_seip), .i_stip(i_stip), .i_ssip(i_ssip),
        .mstatus_o(mstatus_o), .mie_o(mie_o), .mip_o(mip_o),
        .mtvec_o(mtvec_o), .stvec_o(stvec_o),
        .medeleg_o(medeleg_o), .mideleg_o(mideleg_o),
        .mepc_o(mepc_o_csr), .sepc_o(sepc_o_csr),
        .mcause_o(mcause_o), .scause_o(scause_o),
        .cur_priv_o(cur_priv_int)
    );

    // ===== Trap unit =====
    trap_unit u_trap (
        .cur_priv(cur_priv),
        .mstatus(mstatus_o),
        .mie(mie_o),
        .mip(mip_o),
        .medeleg(medeleg_o),
        .mideleg(mideleg_o),
        .mtvec(mtvec_o),
        .stvec(stvec_o),
        .exc_valid(exc_valid),
        .exc_cause(exc_cause),
        .exc_tval(exc_tval),
        .cur_pc(cur_pc),
        .trap_taken(trap_taken_w),
        .trap_pc(trap_pc_w),
        .trap_cause(trap_cause_w),
        .trap_tval(trap_tval_w),
        .trap_to_priv(trap_priv_w),
        .deleg_to_s(trap_deleg_w)
    );

    assign trap_taken = trap_taken_w;
    assign mepc_o = mepc_o_csr;
    assign sepc_o = sepc_o_csr;
    assign trap_pc    = trap_pc_w;

    // ===== satp / MMU =====
    // satp[63] = MODE (Sv39 = 8)
    // satp[43:0] = PPN
    // satp[59:44] = ASID
    // u_csr não expõe satp diretamente; precisamos adicionar. Por ora,
    // verificamos se satp é escrito pelo CSR e mantemos um registrador local.
    reg [63:0] satp_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            satp_r <= 0;
        end else if (is_csr && csr_req && (csr_addr == 12'h180)) begin
            case (csr_op)
                2'b01: satp_r <= csr_wdata;
                2'b10: satp_r <= satp_r | csr_wdata;
                2'b11: satp_r <= satp_r & ~csr_wdata;
            endcase
        end
    end
    assign satp = satp_r;
    assign satp_enable = (satp_r[63:60] == 4'd8);  // Sv39 = MODE 8

    // ===== flush TLB em SFENCE.VMA =====
    // SFENCE.VMA: opcode=1110011, funct3=000, csr_addr=0x120
    assign flush_tlb = (is_system && csr_req && csr_addr == 12'h120);
endmodule
