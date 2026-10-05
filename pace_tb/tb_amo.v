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
module tb_amo;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire        dbg_satp_en;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    wire        dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata;
    reg         dmem_ready;
    wire        vmem_req, vmem_we;
    wire [63:0] vmem_addr, vmem_wdata;
    reg  [63:0] vmem_rdata;
    reg         vmem_ready;
    wire        pte_req;
    wire [63:0] pte_addr;
    reg  [63:0] pte_rdata;
    reg         pte_ready;
    wire        dmmu_page_fault;
    wire [63:0] dmmu_fault_cause, dmmu_fault_va;
    wire        mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];
    reg [63:0] pmem [0:8191];
    integer i, t_run=0, t_pass=0, t_fail=0;

    top_pace_imem dut (
        .clk(clk), .rst_n(rst_n),
        .i_instr_count(4'd1),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .vmem_req(vmem_req), .vmem_we(vmem_we),
        .vmem_addr(vmem_addr), .vmem_wdata(vmem_wdata),
        .vmem_rdata(vmem_rdata), .vmem_ready(vmem_ready),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .dmmu_page_fault(dmmu_page_fault),
        .dmmu_fault_cause(dmmu_fault_cause), .dmmu_fault_va(dmmu_fault_va),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en)
    );

    always #5 clk = ~clk;

    wire [31:0] i0 = imem[imem_pc[9:2] + 0];
    wire [31:0] i1 = imem[imem_pc[9:2] + 1];
    wire [31:0] i2 = imem[imem_pc[9:2] + 2];
    wire [31:0] i3 = imem[imem_pc[9:2] + 3];
    wire [31:0] i4 = imem[imem_pc[9:2] + 4];
    wire [31:0] i5 = imem[imem_pc[9:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    always @(posedge clk) begin
        dmem_ready <= 0;
        vmem_ready <= 0;
        if (dmem_req) begin
            if (dmem_we) dmem[dmem_addr[8:3]] <= dmem_wdata;
            else         dmem_rdata <= dmem[dmem_addr[8:3]];
            dmem_ready <= 1;
        end
        if (vmem_req) begin
            if (vmem_we) dmem[vmem_addr[8:3]] <= vmem_wdata;
            else         vmem_rdata <= dmem[vmem_addr[8:3]];
            vmem_ready <= 1;
        end
    end

    reg pte_delay;
    always @(posedge clk) begin
        pte_ready <= 0;
        if (pte_req && !pte_delay) pte_delay <= 1;
        else if (pte_delay) begin
            pte_delay <= 0;
            pte_rdata <= pmem[pte_addr[14:3]];
            pte_ready <= 1;
        end
    end

    task check_arch;
        input [4:0] r; input [63:0] e; input [255:0] n;
        begin
            dbg_rs = r; #1; t_run = t_run + 1;
            if (dbg_arch_rd === e) begin t_pass = t_pass + 1; $display("[PASS] %0s : x%0d = %0d", n, r, dbg_arch_rd); end
            else begin t_fail = t_fail + 1; $display("[FAIL] %0s : x%0d = %0d (exp %0d)", n, r, dbg_arch_rd, e); end
        end
    endtask

    // Encoding helpers
    function [31:0] addi; input [4:0] rd, rs1; input [11:0] imm;
        begin addi = {imm, rs1, 3'b000, rd, 7'b0010011}; end
    endfunction

    always @(posedge clk) begin
        if (rst_n && dut.mc_shdw_we)
            $display("t=%0t MC shadow write: rd=x%0d data=%h",
                $time, dut.mc_shdw_rd, dut.mc_shdw_data);
    end

    always @(posedge clk) begin
        if (rst_n && (dut.u_mc.shadow_we || dut.mq_push_en))
            $display("t=%0t MC.shadow_we=%b rd=x%0d data=%h | push=%b op=%0d addr=%0d rs2=%0d",
                $time, dut.u_mc.shadow_we, dut.u_mc.shadow_rd, dut.u_mc.shadow_data,
                dut.mq_push_en, dut.mq_push_op, dut.mq_push_addr, dut.mq_push_rs2);
    end

    initial begin


        for (i=0;i<256;i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end
        for (i=0;i<8192;i=i+1) pmem[i] = 0;

        // Programa (todas em M-mode, sem MMU):
        //  addi x1, x0, 64      ; x1 = 64 = dmem[8]
        //  addi x2, x0, 10
        //  sw x2, 0(x1)         ; dmem[8] = 10
        //  addi x3, x0, 5
        //  amoadd.d x4, x3, (x1) ; x4 = old (10), dmem[8] = 15
        //  addi x5, x0, 100
        //  amoswap.d x6, x5, (x1) ; x6 = 15, dmem[8] = 100
        //  jal x0, 0
        imem[0] = addi(5'd1, 5'd0, 12'd64);
        imem[1] = addi(5'd2, 5'd0, 12'd10);
        imem[2] = {12'b0, 5'd2, 5'd1, 3'b011, 12'b0, 7'b0100011};   // sw x2, 0(x1)
        // sw encoding: imm[11:5]=0, rs2=2, rs1=1, funct3=011, imm[4:0]=0, opcode=0100011
        // = 0000000_00010_00001_011_00000_0100011 = 0x0020B023
        imem[2] = 32'h0020B023;
        imem[3] = addi(5'd3, 5'd0, 12'd5);
        // amoadd.d x4, x3, (x1): funct5=00000, aq=0, rl=0, rs2=3, rs1=1, funct3=011, rd=4, opcode=0101111
        // = 00000_0_0_00011_00001_011_00100_0101111 = 0x0030B22F
        imem[4] = 32'h0030B22F;
        imem[5] = addi(5'd5, 5'd0, 12'd100);
        // amoswap.d x6, x5, (x1): funct5=00001 = 0x0052B32F
        imem[6] = 32'h0052B32F;
        imem[7] = 32'h0000006F;

        mmio_rdata = 0; mmio_ready = 0; pte_delay = 0;
        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  A extension (AMO) end-to-end");
        $display("========================================");

        repeat(200) @(posedge clk);
        @(negedge clk);

        $display("  dmem[8] = %0d (exp 100)", dmem[8]);
        check_arch(5'd4, 64'd10, "x4 = amoadd old value (10)");
        check_arch(5'd6, 64'd15, "x6 = amoswap old value (15)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
