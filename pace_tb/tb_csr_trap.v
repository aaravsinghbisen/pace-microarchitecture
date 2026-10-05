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
module tb_csr_trap;
    reg clk = 0, rst_n;

    // CSR access
    reg  [11:0] csr_addr;
    reg         csr_we;
    reg  [1:0]  csr_op;
    reg  [63:0] csr_wdata;
    wire [63:0] csr_rdata;

    // Trap control
    reg         trap_enter;
    reg  [1:0]  trap_to_priv;
    reg         mret, sret;
    reg         update_mepc, update_mcause, update_mtval;
    reg         update_sepc, update_scause, update_stval;
    reg  [63:0] pc_val, cause_val, tval_val;
    reg         deleg_to_s;

    // Interrupts
    reg i_mtip, i_msip, i_meip, i_seip, i_stip, i_ssip;

    // Outputs
    wire [63:0] mstatus_o, mie_o, mip_o, mtvec_o, stvec_o;
    wire [63:0] medeleg_o, mideleg_o, mepc_o, sepc_o, mcause_o, scause_o;
    wire [1:0]  cur_priv_o;

    // Trap unit signals
    reg         exc_valid = 0;
    reg  [63:0] exc_cause = 0, exc_tval = 0, cur_pc = 0;
    wire        trap_taken;
    wire [63:0] trap_pc, trap_cause, trap_tval;
    wire [1:0]  trap_priv;
    wire        trap_deleg;

    csr_file u_csr (
        .clk(clk), .rst_n(rst_n),
        .csr_addr(csr_addr), .csr_we(csr_we), .csr_op(csr_op),
        .csr_wdata(csr_wdata), .csr_rdata(csr_rdata),
        .priv_mode(cur_priv_o),
        .trap_enter(trap_enter), .trap_to_priv(trap_to_priv),
        .mret(mret), .sret(sret),
        .update_mepc(update_mepc), .update_mcause(update_mcause), .update_mtval(update_mtval),
        .update_sepc(update_sepc), .update_scause(update_scause), .update_stval(update_stval),
        .pc_val(pc_val), .cause_val(cause_val), .tval_val(tval_val),
        .deleg_to_s(deleg_to_s),
        .i_mtip(i_mtip), .i_msip(i_msip), .i_meip(i_meip),
        .i_seip(i_seip), .i_stip(i_stip), .i_ssip(i_ssip),
        .mstatus_o(mstatus_o), .mie_o(mie_o), .mip_o(mip_o),
        .mtvec_o(mtvec_o), .stvec_o(stvec_o),
        .medeleg_o(medeleg_o), .mideleg_o(mideleg_o),
        .mepc_o(mepc_o), .sepc_o(sepc_o),
        .mcause_o(mcause_o), .scause_o(scause_o),
        .cur_priv_o(cur_priv_o)
    );

    trap_unit u_trap (
        .cur_priv(cur_priv_o), .mstatus(mstatus_o), .mie(mie_o), .mip(mip_o),
        .medeleg(medeleg_o), .mideleg(mideleg_o), .mtvec(mtvec_o), .stvec(stvec_o),
        .exc_valid(exc_valid), .exc_cause(exc_cause), .exc_tval(exc_tval), .cur_pc(cur_pc),
        .trap_taken(trap_taken), .trap_pc(trap_pc), .trap_cause(trap_cause),
        .trap_tval(trap_tval), .trap_to_priv(trap_priv), .deleg_to_s(trap_deleg)
    );

    always #5 clk = ~clk;

    integer tests_run=0, tests_passed=0, tests_failed=0;
    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task csr_write;
        input [11:0] a; input [63:0] d; input [1:0] op;
        begin
            @(negedge clk);
            csr_addr=a; csr_wdata=d; csr_op=op; csr_we=1;
            @(posedge clk); @(negedge clk);
            csr_we=0;
        end
    endtask

    task csr_read;
        input [11:0] a;
        begin
            @(negedge clk);
            csr_addr=a; csr_we=0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n=0;
        csr_addr=0; csr_we=0; csr_op=0; csr_wdata=0;
        trap_enter=0; trap_to_priv=0; mret=0; sret=0;
        update_mepc=0; update_mcause=0; update_mtval=0;
        update_sepc=0; update_scause=0; update_stval=0;
        pc_val=0; cause_val=0; tval_val=0; deleg_to_s=0;
        i_mtip=0; i_msip=0; i_meip=0; i_seip=0; i_stip=0; i_ssip=0;
        #20 rst_n=1; #5;

        $display("========================================");
        $display("  CSR + Trap Testbench");
        $display("========================================");

        check(cur_priv_o === 2'b11, "reset: in M-mode");

        // --- Read/write mtvec ---
        csr_write(12'h305, 64'h8000_1234, 2'b01);  // W
        csr_read(12'h305);
        check(csr_rdata === 64'h8000_1234, "mtvec write/read");

        // --- Set/clear bits ---
        csr_write(12'h304, 64'h0000_0088, 2'b01);  // mie = bits 7 (MTI), 3 (MSI)
        csr_read(12'h304);
        check(csr_rdata === 64'h0000_0088, "mie set");
        csr_write(12'h304, 64'h0000_0008, 2'b11);  // clear bit 7
        csr_read(12'h304);
        check(csr_rdata === 64'h0000_0080, "mie clear bit 7");

        // --- Trap entry to M-mode ---
        pc_val = 64'h8000_0100; cause_val = 64'd11; tval_val = 64'h1234;
        @(negedge clk); trap_enter=1; trap_to_priv=2'b11; deleg_to_s=0;
        @(posedge clk); @(negedge clk); trap_enter=0;
        #1;
        csr_read(12'h341); check(csr_rdata === 64'h8000_0100, "mepc = trapped PC");
        csr_read(12'h342); check(csr_rdata === 64'd11, "mcause = 11 (ecall_M)");
        csr_read(12'h343); check(csr_rdata === 64'h1234, "mtval = 0x1234");
        check(cur_priv_o === 2'b11, "still in M-mode after M-trap");

        // --- Trap entry to S-mode (delegated) ---
        pc_val = 64'h8000_0200; cause_val = 64'd9;   // ecall_S
        @(negedge clk); trap_enter=1; trap_to_priv=2'b01; deleg_to_s=1;
        @(posedge clk); @(negedge clk); trap_enter=0;
        #1;
        csr_read(12'h141); check(csr_rdata === 64'h8000_0200, "sepc = trapped PC");
        csr_read(12'h142); check(csr_rdata === 64'd9, "scause = 9 (ecall_S)");
        check(cur_priv_o === 2'b01, "switched to S-mode after delegated trap");

        // --- sret back to U-mode ---
        @(negedge clk); sret=1;
        @(posedge clk); @(negedge clk); sret=0;
        #1;
        check(cur_priv_o === 2'b01, "sret -> S-mode (SPP was 1)");

        // --- Interrupt: M-timer fires in M-mode with MIE=1 ---
        // First return to M-mode via trap
        pc_val = 64'h8000_0300; cause_val = 64'd11;
        @(negedge clk); trap_enter=1; trap_to_priv=2'b11; deleg_to_s=0;
        @(posedge clk); @(negedge clk); trap_enter=0;
        #1;
        // Enable MTI (bit 7) + MIE (bit 3 of mstatus)
        csr_write(12'h304, 64'h0000_0080, 2'b01);   // mie.MTIE
        csr_write(12'h300, 64'h0000_0008, 2'b01);   // mstatus.MIE
        // Raise MTIP
        i_mtip = 1;
        #10;
        check(trap_taken === 1'b1, "MTIP triggers trap");
        check(trap_cause === {1'b1, 57'b0, 6'd7}, "trap cause = MTI");
        check(trap_pc === {mtvec_o[63:2], 2'b00}, "trap target = mtvec");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
