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
// Trap Unit - detects exceptions/interrupts and controls mode transitions
module trap_unit (
    input  wire [1:0]  cur_priv,
    input  wire [63:0] mstatus,
    input  wire [63:0] mie,
    input  wire [63:0] mip,
    input  wire [63:0] medeleg,
    input  wire [63:0] mideleg,
    input  wire [63:0] mtvec,
    input  wire [63:0] stvec,

    // Exceptions raised by the pipeline this cycle
    input  wire        exc_valid,
    input  wire [63:0] exc_cause,   // e.g., 8=ecall_U, 9=ecall_S, 11=ecall_M, 2=illegal
    input  wire [63:0] exc_tval,
    input  wire [63:0] cur_pc,

    // Trap output
    output reg         trap_taken,
    output reg  [63:0] trap_pc,     // PC to jump to
    output reg  [63:0] trap_cause,
    output reg  [63:0] trap_tval,
    output reg  [1:0]  trap_to_priv,
    output reg         deleg_to_s
);
    // Interrupt enable priority (machine has priority)
    wire mstatus_MIE = mstatus[3];
    wire mstatus_SIE = mstatus[1];

    // Enabled interrupts (mip & mie)
    wire [63:0] pending = mip & mie;

    // M-level interrupts: bits not delegated
    wire [63:0] m_pending = pending & ~mideleg;
    // S-level interrupts: bits delegated
    wire [63:0] s_pending = pending & mideleg;

    // Priority encoder: highest bit wins (MEI > MSI > MTI > SEI > SSI > STI in spec order)
    // Simplified: we pick the highest set bit in m_pending (M-side) first
    reg  [5:0]  m_irq_idx;
    reg         m_irq_valid;
    reg  [5:0]  s_irq_idx;
    reg         s_irq_valid;

    integer i;
    always @(*) begin
        m_irq_valid = 0;
        m_irq_idx   = 6'd0;
        for (i = 63; i >= 0; i = i - 1) begin
            if (m_pending[i] && !m_irq_valid) begin
                m_irq_valid = 1;
                m_irq_idx   = i[5:0];
            end
        end
    end
    always @(*) begin
        s_irq_valid = 0;
        s_irq_idx   = 6'd0;
        for (i = 63; i >= 0; i = i - 1) begin
            if (s_pending[i] && !s_irq_valid) begin
                s_irq_valid = 1;
                s_irq_idx   = i[5:0];
            end
        end
    end

    // Take an M-mode interrupt if in M-mode with MIE=1, OR in S/U-mode
    wire take_m_irq = m_irq_valid &&
                      ((cur_priv == 2'b11) ? mstatus_MIE : 1'b1);
    // Take an S-mode interrupt if in S-mode with SIE=1, or in U-mode
    wire take_s_irq = s_irq_valid &&
                      ((cur_priv == 2'b01) ? mstatus_SIE :
                       (cur_priv == 2'b00) ? 1'b1 : 1'b0);

    // Exception delegation: medeleg bit[cause] decides M vs S
    wire exc_delegatable = (exc_cause < 64'd64) && medeleg[exc_cause[5:0]];
    // Only delegate to S if current priv <= S (cannot delegate when in M)
    wire exc_deleg_to_s  = exc_delegatable && (cur_priv != 2'b11);

    // Priority: M-interrupt > S-interrupt > exception (spec: interrupts before exceptions
    // when both can be taken at same priority level; but exceptions have higher priority
    // than same-level interrupts. We simplify: M-irq > S-irq > exception.)
    always @(*) begin
        trap_taken  = 1'b0;
        trap_pc     = 64'd0;
        trap_cause  = 64'd0;
        trap_tval   = 64'd0;
        trap_to_priv= 2'b11;
        deleg_to_s  = 1'b0;

        if (take_m_irq) begin
            trap_taken  = 1'b1;
            trap_pc     = {mtvec[63:2], 2'b00};   // direct mode
            trap_cause  = {1'b1, 57'b0, m_irq_idx}; // MSB=1 for interrupt
            trap_tval   = 64'd0;
            trap_to_priv= 2'b11;
            deleg_to_s  = 1'b0;
        end else if (take_s_irq) begin
            trap_taken  = 1'b1;
            trap_pc     = {stvec[63:2], 2'b00};
            trap_cause  = {1'b1, 57'b0, s_irq_idx};
            trap_tval   = 64'd0;
            trap_to_priv= 2'b01;
            deleg_to_s  = 1'b1;
        end else if (exc_valid) begin
            trap_taken  = 1'b1;
            trap_cause  = exc_cause;
            trap_tval   = exc_tval;
            if (exc_deleg_to_s) begin
                trap_pc     = {stvec[63:2], 2'b00};
                trap_to_priv= 2'b01;
                deleg_to_s  = 1'b1;
            end else begin
                trap_pc     = {mtvec[63:2], 2'b00};
                trap_to_priv= 2'b11;
                deleg_to_s  = 1'b0;
            end
        end
    end

endmodule
