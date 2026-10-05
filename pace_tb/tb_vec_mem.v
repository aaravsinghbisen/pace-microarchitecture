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
module tb_vec_mem;
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

    function [63:0] pte_ptr; input [43:0] ppn;
        begin pte_ptr = {10'b0, ppn, 2'b0, 8'b0100_0001}; end
    endfunction
    function [63:0] pte_leaf; input [43:0] ppn;
        begin pte_leaf = {10'b0, ppn, 2'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1}; end
    endfunction

    task check;
        input cond; input [255:0] name;
        begin
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        for (i=0;i<256;i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end
        for (i=0;i<8192;i=i+1) pmem[i] = 0;

        // Vetor na memória: dmem[10]=11, dmem[11]=22, dmem[12]=33, dmem[13]=44
        dmem[10] = 64'd1111;
        dmem[11] = 64'd2222;

        // Programa:
        //  addi x1, x0, 80       ; x1 = 80 = PA (endereço byte de dmem[10] = 10*8)
        //  vsetvli x0, x0, 0     ; VL = 2
        //  vle.v v1, (x1)        ; v1 = [1111, 2222]
        //  addi x2, x0, 112      ; x2 = 112 (dmem[14])
        //  vse.v v1, (x2)        ; dmem[14] = 1111, dmem[15] = 2222
        //  jal x0, 0
        imem[0] = 32'h05000093;  // addi x1, x0, 80
        imem[1] = 32'h00007057;  // vsetvli x0, x0, 0
        imem[2] = 32'h0200E087;  // vle.v v1, (x1)
        imem[3] = 32'h07000113;  // addi x2, x0, 112
        imem[4] = 32'h020170A7;  // vse.v v1, (x2)
        imem[5] = 32'h0000006F;

        mmio_rdata = 0; mmio_ready = 0; pte_delay = 0;
        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  Vector load/store test");
        $display("========================================");

        repeat(300) @(posedge clk);
        @(negedge clk);

        $display("  PCU pc = %h", dbg_pcu_pc);
        $display("  dmem[14] = %0d (exp 1111)", dmem[14]);
        $display("  dmem[15] = %0d (exp 2222)", dmem[15]);
        check(dmem[14] === 64'd1111, "vle.v + vse.v: dmem[14] = 1111");
        check(dmem[15] === 64'd2222, "vle.v + vse.v: dmem[15] = 2222");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
