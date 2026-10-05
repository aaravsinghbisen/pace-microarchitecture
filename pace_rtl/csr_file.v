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
// CSR File - RV64 privileged architecture (M/S/U modes)
// Supports: mstatus, misa, mie, mtvec, mscratch, mepc, mcause, mtval, mip,
//           medeleg, mideleg, mhartid, mvendorid, marchid, mimpid,
//           sstatus, sie, stvec, sscratch, sepc, scause, stval, sip, satp
module csr_file #(parameter HART_ID = 0) (
    input  wire        clk, rst_n,

    // CPU access port
    input  wire [11:0] csr_addr,
    input  wire        csr_we,
    input  wire [1:0]  csr_op,      // 00=R, 01=W, 10=set, 11=clear
    input  wire [63:0] csr_wdata,
    output reg  [63:0] csr_rdata,
    input  wire [1:0]  priv_mode,   // 00=U, 01=S, 11=M

    // Interrupt/trap state inputs (from trap_unit)
    input  wire        trap_enter,  // updating mstatus on trap entry
    input  wire [1:0]  trap_to_priv,
    input  wire        mret, sret,  // return instructions
    input  wire        update_mepc, update_mcause, update_mtval,
    input  wire        update_sepc, update_scause, update_stval,
    input  wire [63:0] pc_val,
    input  wire [63:0] cause_val,
    input  wire [63:0] tval_val,
    input  wire        deleg_to_s,  // if set, use S-mode CSRs instead of M

    // Interrupt pending inputs
    input  wire        i_mtip, i_msip, i_meip, i_seip, i_stip, i_ssip,

    // Outputs to trap_unit
    output wire [63:0] mstatus_o,
    output wire [63:0] mie_o,
    output wire [63:0] mip_o,
    output wire [63:0] mtvec_o,
    output wire [63:0] stvec_o,
    output wire [63:0] medeleg_o,
    output wire [63:0] mideleg_o,
    output wire [63:0] mepc_o,
    output wire [63:0] sepc_o,
    output wire [63:0] mcause_o,
    output wire [63:0] scause_o,
    output wire [1:0]  cur_priv_o,
    output wire [63:0] satp_o
);

    // ==== Privilege ====
    reg [1:0] cur_priv;
    assign cur_priv_o = cur_priv;

    // ==== CSR registers ====
    reg [63:0] mstatus,  misa,      mie,      mtvec,  mscratch;
    reg [63:0] mepc,     mcause,    mtval,    mip,    medeleg, mideleg;
    reg [63:0] stvec,    sscratch,  sepc,     scause, stval,   satp;
    wire [63:0] mhartid = HART_ID;

    assign mstatus_o = mstatus;
    assign mie_o     = mie;
    assign mip_o     = mip;
    assign mtvec_o   = mtvec;
    assign stvec_o   = stvec;
    assign medeleg_o = medeleg;
    assign mideleg_o = mideleg;
    assign mepc_o    = mepc;
    assign sepc_o    = sepc;
    assign mcause_o  = mcause;
    assign satp_o    = satp;
    assign scause_o  = scause;

    // sstatus is a view of mstatus (subset of bits)
    wire [63:0] sstatus_view = mstatus;
    wire [63:0] sie_view     = mie  & mideleg;   // S-mode visible interrupts
    wire [63:0] sip_view     = mip  & mideleg;

    // ==== Privilege check for CSR access ====
    // CSR addr bits [9:8] = minimum privilege required
    wire [1:0] csr_min_priv = csr_addr[9:8];
    wire csr_read_only     = csr_addr[11:10] == 2'b11;
    wire csr_priv_ok       = (cur_priv >= csr_min_priv);
    wire csr_write_ok      = csr_priv_ok && !csr_read_only;

    // ==== CSR read (combinational) ====
    always @(*) begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h301: csr_rdata = misa;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'h344: csr_rdata = mip;
            12'h302: csr_rdata = medeleg;
            12'h303: csr_rdata = mideleg;
            12'h100: csr_rdata = sstatus_view;
            12'h104: csr_rdata = sie_view;
            12'h105: csr_rdata = stvec;
            12'h140: csr_rdata = sscratch;
            12'h141: csr_rdata = sepc;
            12'h142: csr_rdata = scause;
            12'h143: csr_rdata = stval;
            12'h144: csr_rdata = sip_view;
            12'h180: csr_rdata = satp;
            12'hF14: csr_rdata = mhartid;
            default: csr_rdata = 64'd0;
        endcase
    end

    // ==== CSR write helpers ====
    function [63:0] apply_op;
        input [63:0] old_val;
        input [63:0] wdata;
        input [1:0]  op;
        begin
            case (op)
                2'b01: apply_op = wdata;              // write
                2'b10: apply_op = old_val | wdata;    // set
                2'b11: apply_op = old_val & ~wdata;   // clear
                default: apply_op = old_val;
            endcase
        end
    endfunction

    // ==== Privilege transitions ====
    // mret: new priv = mstatus.MPP, then MPP <- U (or lowest supported)
    // sret: new priv = mstatus.SPP, then SPP <- U
    wire [1:0] mstatus_MPP = mstatus[12:11];
    wire       mstatus_SPP = mstatus[8];
    wire [1:0] mret_target_priv = mstatus_MPP;
    wire [1:0] sret_target_priv = {1'b0, mstatus_SPP};

    // ==== Sequential updates ====
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_priv  <= 2'b11;   // start in M-mode
            mstatus   <= 64'd0;
            misa      <= 64'h8000_0000_0014_1100;  // RV64IMAFD + S + U
            mie       <= 64'd0;
            mtvec     <= 64'd0;
            mscratch  <= 64'd0;
            mepc      <= 64'd0;
            mcause    <= 64'd0;
            mtval     <= 64'd0;
            mip       <= 64'd0;
            medeleg   <= 64'd0;
            mideleg   <= 64'd0;
            stvec     <= 64'd0;
            sscratch  <= 64'd0;
            sepc      <= 64'd0;
            scause    <= 64'd0;
            stval     <= 64'd0;
            satp      <= 64'd0;
        end else begin
            // ---- Trap entry ----
            if (trap_enter) begin
                if (deleg_to_s) begin
                    // S-mode trap
                    sepc    <= pc_val;
                    scause  <= cause_val;
                    stval   <= tval_val;
                    mstatus[5]    <= mstatus[1];  // SPIE <- SIE
                    mstatus[1]    <= 1'b0;        // SIE <- 0
                    mstatus[8]    <= cur_priv[0]; // SPP <- prev priv
                    cur_priv <= 2'b01;            // go S-mode
                end else begin
                    // M-mode trap
                    mepc    <= pc_val;
                    mcause  <= cause_val;
                    mtval   <= tval_val;
                    mstatus[7]    <= mstatus[3];  // MPIE <- MIE
                    mstatus[3]    <= 1'b0;        // MIE <- 0
                    mstatus[12:11]<= cur_priv;    // MPP <- prev priv
                    cur_priv <= 2'b11;            // go M-mode
                end
            end

            // ---- mret ----
            if (mret) begin
                mstatus[3]    <= mstatus[7];  // MIE <- MPIE
                mstatus[7]    <= 1'b1;        // MPIE <- 1
                mstatus[12:11]<= 2'b00;       // MPP <- U
                cur_priv <= mret_target_priv;
            end

            // ---- sret ----
            if (sret) begin
                mstatus[1] <= mstatus[5];   // SIE <- SPIE
                mstatus[5] <= 1'b1;         // SPIE <- 1
                mstatus[8] <= 1'b0;         // SPP <- U
                cur_priv <= sret_target_priv;
            end

            // ---- Update epc/cause/tval from trap_unit ----
            if (update_mepc)   mepc   <= pc_val;
            if (update_mcause) mcause <= cause_val;
            if (update_mtval)  mtval  <= tval_val;
            if (update_sepc)   sepc   <= pc_val;
            if (update_scause) scause <= cause_val;
            if (update_stval)  stval  <= tval_val;

            // ---- CSR writes from CPU ----
            if (csr_we && csr_write_ok) begin
                case (csr_addr)
                    12'h300: mstatus   <= apply_op(mstatus, csr_wdata, csr_op);
                    12'h304: mie       <= apply_op(mie, csr_wdata, csr_op);
                    12'h305: mtvec     <= apply_op(mtvec, csr_wdata, csr_op);
                    12'h340: mscratch  <= apply_op(mscratch, csr_wdata, csr_op);
                    12'h341: mepc      <= apply_op(mepc, csr_wdata, csr_op);
                    12'h342: mcause    <= apply_op(mcause, csr_wdata, csr_op);
                    12'h343: mtval     <= apply_op(mtval, csr_wdata, csr_op);
                    12'h344: mip       <= apply_op(mip, csr_wdata, csr_op);
                    12'h302: medeleg   <= apply_op(medeleg, csr_wdata, csr_op);
                    12'h303: mideleg   <= apply_op(mideleg, csr_wdata, csr_op);
                    12'h100: begin
                        // sstatus: only certain bits writable
                        mstatus[1]    <= apply_op(mstatus, csr_wdata, csr_op) & (1<<1);
                        mstatus[5]    <= apply_op(mstatus, csr_wdata, csr_op) & (1<<5);
                        mstatus[8]    <= apply_op(mstatus, csr_wdata, csr_op) & (1<<8);
                        mstatus[18]   <= apply_op(mstatus, csr_wdata, csr_op) & (1<<18);
                        mstatus[19]   <= apply_op(mstatus, csr_wdata, csr_op) & (1<<19);
                    end
                    12'h104: mie       <= apply_op(mie, csr_wdata, csr_op) & mideleg;
                    12'h105: stvec     <= apply_op(stvec, csr_wdata, csr_op);
                    12'h140: sscratch  <= apply_op(sscratch, csr_wdata, csr_op);
                    12'h141: sepc      <= apply_op(sepc, csr_wdata, csr_op);
                    12'h142: scause    <= apply_op(scause, csr_wdata, csr_op);
                    12'h143: stval     <= apply_op(stval, csr_wdata, csr_op);
                    12'h144: mip       <= apply_op(mip, csr_wdata, csr_op) & mideleg;
                    12'h180: satp      <= apply_op(satp, csr_wdata, csr_op);
                    default: ;
                endcase
            end

            // ---- Live interrupt pending bits ----
            mip[7] <= i_mtip;
            mip[3] <= i_msip;
            mip[11]<= i_meip;
            mip[9] <= i_seip;
            mip[5] <= i_stip;
            mip[1] <= i_ssip;
        end
    end

endmodule
