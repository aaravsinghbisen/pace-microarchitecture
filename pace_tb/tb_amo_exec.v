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
module tb_amo_exec;
    reg clk=0, rst_n=0;
    integer i, t_run=0, t_pass=0, t_fail=0;
    reg [4:0] dbg_rs=0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire dbg_satp_en;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    wire dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata;
    reg         dmem_ready;
    wire vmem_req, vmem_we;
    wire [63:0] vmem_addr, vmem_wdata;
    reg  [63:0] vmem_rdata; reg vmem_ready;
    wire pte_req; wire [63:0] pte_addr;
    reg [63:0] pte_rdata; reg pte_ready;
    wire dmmu_pf; wire [63:0] dmmu_fc, dmmu_fv;
    wire mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];

    top_pace_imem #(.HART_ID(0)) dut (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .vmem_req(vmem_req), .vmem_we(vmem_we),
        .vmem_addr(vmem_addr), .vmem_wdata(vmem_wdata),
        .vmem_rdata(vmem_rdata), .vmem_ready(vmem_ready),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .dmmu_page_fault(dmmu_pf),
        .dmmu_fault_cause(dmmu_fc), .dmmu_fault_va(dmmu_fv),
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

    // DRAM 1-cycle com trace completo
    always @(posedge clk) begin
        if (rst_n && dmem_req)
            $display("t=%0t SLAVE: we=%b addr=%h wdata=%h MEM_ATUAL=%h",
                $time, dmem_we, dmem_addr, dmem_wdata, dmem[dmem_addr[8:3]]);
        dmem_ready <= 0;
        if (dmem_req) begin
            if (dmem_we) dmem[dmem_addr[8:3]] <= dmem_wdata;
            else         dmem_rdata <= dmem[dmem_addr[8:3]];
            dmem_ready <= 1;
        end
    end

    task check;
        input cond; input [255:0] name;
        begin
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task check_arch;
        input [4:0] r; input [63:0] e; input [255:0] n;
        begin
            dbg_rs = r; #1; t_run = t_run + 1;
            if (dbg_arch_rd === e) begin t_pass = t_pass + 1; $display("[PASS] %0s : x%0d = %0d", n, r, dbg_arch_rd); end
            else begin t_fail = t_fail + 1; $display("[FAIL] %0s : x%0d = %0d (exp %0d)", n, r, dbg_arch_rd, e); end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && dut.u_mc.shadow_we)
            $display("t=%0t SHADOW WR: rd=x%0d data=%h",
                $time, dut.u_mc.shadow_rd, dut.u_mc.shadow_data);
    end

    reg [2:0] last_state = 7;
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_mc.state !== last_state || dut.u_mc.mem_req)
                $display("t=%0t MC: state=%0d mem_req=%b we=%b addr=%h wdata=%h rdata=%h ready=%b | pcu_pc=%h",
                    $time, dut.u_mc.state, dut.u_mc.mem_req, dut.u_mc.mem_we,
                    dut.u_mc.mem_addr, dut.u_mc.mem_wdata, dut.mc_rdata, dut.mc_ready,
                    dbg_pcu_pc);
            last_state <= dut.u_mc.state;
        end
    end

    initial begin

        for (i=0; i<256; i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end
        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // dmem[8] = 10 (PA 64)
        dmem[8] = 64'd10;

        // Programa:
        //  addi x1, x0, 64         ; endereço
        //  addi x2, x0, 5          ; valor a somar
        //  amoadd.d x3, x2, (x1)   ; x3 = old (10), dmem[8] = 15
        //  lw   x4, 0(x1)          ; x4 = 15 (confirma)
        //  jal x0, 0
        imem[0] = 32'h04000093;
        imem[1] = 32'h00500113;
        imem[2] = 32'h0020B1AF;   // amoadd.d x3, x2, (x1)
        imem[3] = 32'h0000A203;   // lw x4, 0(x1)
        imem[4] = 32'h0000006F;

        #20 rst_n = 1;

        $display("========================================");
        $display("  A extension EXECUTANDO");
        $display("========================================");

        repeat(300) @(posedge clk);
        @(negedge clk);

        $display("  dmem[8] = %0d (exp 15)", dmem[8]);

        check(dmem[8] === 64'd15, "AMOADD alterou memória (10 + 5 = 15)");
        check_arch(5'd3, 64'd10, "x3 = valor antigo (10)");
        check_arch(5'd4, 64'd15, "x4 = lw confirma 15");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — A extension EXECUTA");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
