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
// Prova que PCU aceita TODAS as instruções vetoriais sem travar.
module tb_vec_accept;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];
    integer i, t_run=0, t_pass=0, t_fail=0;

    wire dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata;
    reg         dmem_ready;
    wire vmem_req, vmem_we;
    wire [63:0] vmem_addr, vmem_wdata;
    reg  [63:0] vmem_rdata;
    reg         vmem_ready;
    wire pte_req;
    wire [63:0] pte_addr;
    reg  [63:0] pte_rdata;
    reg         pte_ready;
    wire dmmu_pf;
    wire [63:0] dmmu_fc, dmmu_fv;
    wire mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;
    wire [63:0] dbg_satp;
    wire        dbg_satp_en;

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

    always @(posedge clk) begin
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

    initial begin
        for (i=0; i<256; i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end

        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // Programa intercalando vetorial com ALU.
        // Se PCU aceitar vetorial sem travar, tudo avança.
        //  0x00  addi x1, x0, 11          ; x1 = 11
        //  0x04  addi x5, x0, 64          ; base
        //  0x08  vsetvli x0, x0, 0        ; VL = 2
        //  0x0C  vle.v v1, (x5)           ; ACEITA (não executa)
        //  0x10  addi x2, x0, 22          ; x2 = 22 — deve rodar
        //  0x14  vadd.vv v3, v1, v1       ; ACEITA (executa em vector_rf)
        //  0x18  add x3, x1, x2           ; x3 = 33 — deve rodar
        //  0x1C  vse.v v3, (x5)           ; ACEITA
        //  0x20  addi x7, x0, 99          ; x7 = 99 — deve rodar
        //  0x24  jal x0, 0
        imem[0] = 32'h00B00093;   // addi x1, x0, 11
        imem[1] = 32'h04000293;   // addi x5, x0, 64
        imem[2] = 32'h00007057;   // vsetvli x0, x0, 0
        imem[3] = 32'h0202E087;   // vle.v v1, (x5)
        imem[4] = 32'h01600113;   // addi x2, x0, 22
        imem[5] = 32'h020081D7;   // vadd.vv v3, v1, v1
        imem[6] = 32'h002081B3;   // add x3, x1, x2
        imem[7] = 32'h0202E1A7;   // vse.v v3, (x5)
        imem[8] = 32'h06300393;   // addi x7, x0, 99
        imem[9] = 32'h0000006F;   // jal x0, 0

        #20 rst_n = 1;

        $display("========================================");
        $display("  PCU accepts vector (VLE=128)");
        $display("========================================");

        repeat(100) @(posedge clk);
        @(negedge clk);

        $display("  PC final = %h", dbg_pcu_pc);

        check_arch(5'd1, 64'd11, "x1 = 11");
        check_arch(5'd2, 64'd22, "x2 = 22 (após vle.v)");
        check_arch(5'd3, 64'd33, "x3 = 33 (após vadd.vv)");
        check_arch(5'd7, 64'd99, "x7 = 99 (após vse.v)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — PCU aceita RVV sem travar");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
